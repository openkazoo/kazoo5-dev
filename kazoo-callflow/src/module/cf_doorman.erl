%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc Doorman for a user or device
%%%
%%% 1. Have caller record their name
%%% 2. Originate to callee
%%% 3. Play prompt + recording for callee
%%%   Press 1, connect caller to callee
%%%   Press 2, lookup callee's voicemail and send caller to voicemail
%%%   Press 3, reject caller
%%%
%%% Data:
%%%   id                | {ID}       | User or device Id
%%%   recording_limit   |  8s        | Caller's time limit for the recording
%%%   tones             | [ToneJObj] | The ring tone to play to the caller after recording
%%%   caller_id_name    | "Doorman"  | The caller ID name to be displayed to the callee
%%%   call_timeout      | 30s        | How long to ring the callee
%%%   caller_greeting   | "Hi. Please state your name after the tone." | The greeting to play to the caller
%%%   failover_strategy | "hangup"   | What to do if the callee doesn't answer or is busy
%%%   vmbox_id          | {ID}       | The voicemail box to send the caller to if the callee doesn't answer or is busy
%%%   max_menu_attempts | 3          | How many times to allow the callee to choose from the menu
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_doorman).

-behaviour(gen_cf_action).

-include("callflow.hrl").

-export([handle/2]).

-define(DTMF_CONNECT_CALL, <<"1">>).
-define(DTMF_VM, <<"2">>).
-define(DTMF_HANGUP, <<"3">>).

-type failure_reason() ::
        'callee_endpoint_fail' |
        'callee_busy' |
        'callee_no_answer' |
        'callee_error' |
        'callee_hungup' |
        'caller_timeout'.

-type contact_callee_return() ::
        {'error', failure_reason()} |
        {'error', 'caller_hungup', kapps_call:call()} |
        {'ok', binary(), kapps_call:call()}.

%%------------------------------------------------------------------------------
%% @doc Doorman entry point
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    kapps_call_command:answer(Call),
    CallerCall = get_caller_recording(Data, Call),
    play_ringtone_to_caller(Data, CallerCall),
    lager:info("caller has recorded message (~s) and is ringing now", [kapps_call:kvs_fetch('caller_recording_id', CallerCall)]),
    _ = case contact_callee(Data, CallerCall) of
            {'ok', Choice, CalleeCall} ->
                handle_choice(Choice, Data, CallerCall, CalleeCall);
            {'error', 'callee_endpoint_fail'} ->
                lager:info("failed to build callee endpoint"),
                hangup_caller(CallerCall);
            {'error', 'callee_busy'} ->
                lager:info("callee is busy"),
                handle_failover(Data, CallerCall);
            {'error', 'callee_no_answer'} ->
                lager:info("callee did not answer"),
                handle_failover(Data, CallerCall);
            {'error', 'callee_error'} ->
                lager:info("callee is unreachable"),
                handle_failover(Data, CallerCall);
            {'error', 'callee_hungup'} ->
                handle_failover(Data, CallerCall);
            {'error', 'caller_hungup', CalleeCall} ->
                handle_caller_termination(CallerCall, CalleeCall);
            {'error', 'caller_timeout'} ->
                lager:info("caller waiting timeout expired"),
                hangup_caller(CallerCall)
        end,
    cf_exe:continue(Call).

-spec get_caller_recording(kz_json:object(), kapps_call:call()) -> kapps_call:call().
get_caller_recording(Data, Call) ->
    prompt_caller(Data, Call),
    RecordingId = record_caller(Data, Call),
    UpdatedCall = kapps_call:kvs_store('caller_recording_id', RecordingId, Call),
    thank_caller(UpdatedCall),
    UpdatedCall.

-spec record_caller(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
record_caller(Data, Call) ->
    RecordingId = <<(kz_binary:rand_hex(16))/binary, ".mp3">>,
    {'ok', JObj} = kapps_call_command:b_record(RecordingId
                                              ,?ANY_DIGIT
                                              ,recording_limit(Data)
                                              ,Call
                                              ),
    case kz_json:get_binary_value(<<"Channel-Answer-State">>, JObj) of
        <<"answered">> -> <<"/tmp/", RecordingId/binary>>;
        <<"hangup">> ->
            lager:info("caller hung up during message recording"),
            exit('normal');
        Other ->
            lager:error("unhandled channel answer state: ~p", [Other]),
            exit('normal')
    end.

-spec recording_limit(kz_json:object()) -> number().
recording_limit(Data) ->
    Limit = kz_json:get_integer_value(<<"recording_limit">>, Data, 8),
    lager:debug("recording limit: ~p", [Limit]),
    kz_math:clamp(16, 2, Limit).

prompt_caller(Data, Call) ->
    Beep = kz_json:from_list([{<<"Frequencies">>, [<<"440">>]}
                             ,{<<"Duration-ON">>, <<"500">>}
                             ,{<<"Duration-OFF">>, <<"100">>}
                             ]),
    Greeting = case kz_json:get_ne_binary_value(<<"caller_greeting">>, Data) of
                   'undefined' -> {'prompt', <<"cf-doorman_greeting">>};
                   GreetingText -> {'tts', GreetingText}
               end,
    AudioMacro = [Greeting
                 ,{'tones', [Beep]}
                 ],
    NoopId = kapps_call_command:audio_macro(AudioMacro, Call),
    case kapps_call_command:wait_for_noop(Call, NoopId) of
        {'ok', _} -> 'ok';
        {'error', 'channel_hungup'} ->
            lager:debug("caller hung up during doorman's prompt"),
            exit('normal')
    end.

thank_caller(Call) ->
    case kapps_call_command:b_prompt(<<"general-thank_you">>, Call) of
        {'ok', _} -> 'ok';
        {'error', 'channel_hungup'} ->
            lager:debug("caller hung up during doorman's thank message"),
            exit('normal')
    end.

play_ringtone_to_caller(Data, Call) ->
    Tones = cf_tones:convert_tones(tones(Data)),
    kapps_call_command:tones(Tones, Call).

tones(Data) ->
    % number of repetitions set high enough to make sure that the ringtone
    % is played until the callee eventually answers the call and makes his choice
    [kz_json:set_value(<<"repeat">>, 600, Tone)
     || Tone <- kz_json:get_list_value(<<"tones">>, Data, [us_tone()])
    ].

-spec us_tone() -> kz_json:object().
us_tone() ->
    kz_json:from_list([{<<"duration_on">>, 2000}
                      ,{<<"duration_off">>, 4000}
                      ,{<<"frequencies">>, [440,480]}
                      ]).

hangup_caller(Call) ->
    {'ok', _} = kapps_call_command:b_flush(Call),
    {'ok', _} = kapps_call_command:b_prompt(<<"cf-doorman_unreachable">>, Call),
    'ok' = kapps_call_command:hangup(Call),
    cf_exe:hard_stop(Call).

handle_failover(Data, CallerCall) ->
    case kz_json:get_ne_binary_value(<<"failover_strategy">>, Data) of
        <<"hangup">> ->
            lager:info("failing over to hangup"),
            hangup_caller(CallerCall);
        <<"voicemail">> ->
            lager:info("failing over to voicemail"),
            case get_vmbox(Data, CallerCall) of
                'undefined' ->
                    lager:info("no voicemail box specified, hanging up"),
                    hangup_caller(CallerCall);
                VMBoxId ->
                    lager:info("sending caller to voicemail box ~s", [VMBoxId]),
                    VMData = kz_json:from_list([{<<"action">>, <<"compose">>}
                                               ,{<<"id">>, VMBoxId}
                                               ]),
                    {'ok', _} = kapps_call_command:b_flush(CallerCall),
                    cf_voicemail:handle(VMData, CallerCall)
            end
    end.

%% If 1 is pressed the call is connected
%% If 2 is pressed the caller is sent to voicemail
%% If 3 is pressed call is ended
handle_choice(?DTMF_CONNECT_CALL, _Data, CallerCall, CalleeCall) ->
    TargetCallId = kapps_call:call_id(CallerCall),
    lager:info("callee has chosen to accept call ~s", [TargetCallId]),
    pickup_caller(TargetCallId, CalleeCall),
    {'ok', CalleeCall};
handle_choice(?DTMF_VM, Data, CallerCall, CalleeCall) ->
    VMBoxId = get_vmbox(Data, CalleeCall),
    lager:info("callee has chosen to send caller to voicemail box ~s", [VMBoxId]),

    kapps_call_command:hangup(CalleeCall),

    VMData = kz_json:from_list([{<<"action">>, <<"compose">>}
                               ,{<<"id">>, VMBoxId}
                               ]),
    {'ok', _} = kapps_call_command:b_flush(CallerCall),
    cf_voicemail:handle(VMData, CallerCall);
handle_choice(?DTMF_HANGUP, _Data, CallerCall, _CalleeCall) ->
    lager:info("callee has chosen to reject incoming call ~s", [kapps_call:call_id(CallerCall)]),
    hangup_caller(CallerCall).

get_vmbox(Data, Call) ->
    case kz_json:get_ne_binary_value(<<"vmbox_id">>, Data) of
        'undefined' ->
            AccountId = kapps_call:account_id(Call),
            OwnerId = kz_doc:id(Data),
            lager:debug("no vmbox_id specified in callflow data, trying to find vmbox for ~p", [OwnerId]),
            {'ok', Doc} = kz_datamgr:open_cache_doc(AccountId, OwnerId),
            case kz_doc:type(Doc) of
                <<"user">> ->
                    get_vmbox_from_user(AccountId, OwnerId);
                <<"device">> ->
                    get_vmbox_from_device(AccountId, Doc)
            end;
        VMBoxId -> VMBoxId
    end.

get_vmbox_from_device(AccountId, Device) ->
    UserId = kzd_devices:owner_id(Device),
    get_vmbox_from_user(AccountId, UserId).

get_vmbox_from_user(AccountId, OwnerId) ->
    case kz_datamgr:get_results(AccountId
                               ,<<"attributes/owned">>
                               ,[{'key', [OwnerId, <<"vmbox">>]}])
    of
        {'ok', [JObj]} ->
            lager:debug("found vmbox owned by user: ~s", [OwnerId]),
            kz_json:get_value(<<"id">>, JObj);
        {'error', _R} ->
            lager:debug("unable to fetch vmbox: ~p", [_R]),
            'undefined'
    end.

-spec wait_for_calee(kz_term:pid_ref(), 'undefined' | kapps_call:call(), kapps_call:call()) -> contact_callee_return().
wait_for_calee({CalleePid, CalleeRef}=CalleeProc, CalleeCall, CallerCall) ->
    receive
        {_Pid, 'update_callee', UpdatedCalleeCall} ->
            lager:debug("callee call updated: ~p", [kapps_call:to_json(UpdatedCalleeCall)]),
            wait_for_calee(CalleeProc, UpdatedCalleeCall, CallerCall);
        {CalleePid, CalleeResponse} ->
            erlang:demonitor(CalleeRef, ['flush']),
            CalleeResponse;
        {'DOWN', CalleeRef, 'process', _Pid, 'normal'} ->
            lager:info("callee process ended normally"),
            erlang:demonitor(CalleeRef, ['flush']),
            {'ok', 'callee_process_ended'};
        {'DOWN', CalleeRef, 'process', Pid, _Reason} ->
            lager:error("callee proces ~p exited abnormally: ~p", [Pid, _Reason]),
            erlang:demonitor(CalleeRef, ['flush']),
            {'error', 'callee_process_error'};
        {'amqp_msg', JObj} ->
            CallerCallID = kapps_call:call_id(CallerCall),
            case {kz_api:event_type(JObj), kz_call_event:call_id(JObj)} of
                {{<<"call_event">>, <<"CHANNEL_DESTROY">>}, CallerCallID} ->
                    {'error', 'caller_hungup', CalleeCall};
                {{<<"call_event">>, <<"CHANNEL_DISCONNECTED">>}, CallerCallID} ->
                    {'error', 'caller_hungup', CalleeCall};
                {_Evt, _CallId} ->
                    lager:debug("ignoring event: ~p", [JObj]),
                    wait_for_calee(CalleeProc, CalleeCall, CallerCall)
            end;
        _Other ->
            lager:debug("ignoring event: ~p", [_Other]),
            wait_for_calee(CalleeProc, CalleeCall, CallerCall)
    end.

-spec contact_callee(kz_json:object(), kapps_call:call()) -> contact_callee_return().
contact_callee(Data, Call) ->
    EndpointId = kz_doc:id(Data),
    Props = kz_json:from_list([{<<"source">>, <<?MODULE_STRING>>}]),

    case kz_endpoint:build(EndpointId, Props, Call) of
        {'ok', Endpoints} ->
            contact_callee(Data, Call, Endpoints);
        {'error', _E} ->
            lager:error("failed to build endpoint for ~p with error ~p", [EndpointId, _E]),
            {'error', 'callee_endpoint_fail'}
    end.

-spec contact_callee(kz_json:object(), kapps_call:call(), kz_json:objects()) -> contact_callee_return().
contact_callee(Data, CallerCall, Endpoints) ->
    AMQPConsumer = kz_amqp_channel:consumer_pid(),
    AMQPChannel = kz_amqp_channel:consumer_channel(),
    CalleeProc = kz_process:spawn_monitor(fun contact_callee/6, [Data, CallerCall, Endpoints, self(), AMQPConsumer, AMQPChannel]),
    wait_for_calee(CalleeProc, 'undefined', CallerCall).

contact_callee(Data, CallerCall, Endpoints, DoormanProc, AMQPConsumer, AMQPChannel) ->
    _ = kz_amqp_channel:consumer_channel(AMQPChannel),
    _ = kz_amqp_channel:consumer_pid(AMQPConsumer),

    CalleeCall = create_callee_call(Data, CallerCall, Endpoints),
    Request = build_originate_request(Data, CalleeCall, Endpoints, CallerCall),
    Validator = fun(Resp) -> validate_originate_resp(Resp, CalleeCall, DoormanProc) end,
    lager:info("originate callee call on: ~s", [kz_json:get_ne_binary_value(<<"Switch-Nodename">>, Request)]),

    _ = case kz_amqp_worker:call_collect(
               Request
              ,fun kapi_resource:publish_originate_req/1
              ,Validator
              ,300 * ?MILLISECONDS_IN_SECOND)
        of
            {'ok', [OriginateResp|_]} ->
                case kz_json:get_value(<<"Event-Category">>, OriginateResp) of
                    <<"resource">> ->
                        lager:info("callee answered the call ~p", [OriginateResp]),
                        UpdatedCallee = kapps_call:from_originate_resp(OriginateResp, CalleeCall),
                        DoormanProc ! {self(), 'update_callee', UpdatedCallee},
                        update_logging_id(CallerCall, UpdatedCallee),
                        kz_events:bind_call_id(kapps_call:call_id(UpdatedCallee)),
                        Resp = doorman_menu(UpdatedCallee),
                        kz_events:unbind_call_id(kapps_call:call_id(UpdatedCallee)),
                        DoormanProc ! {self(), Resp};
                    <<"error">> ->
                        case kz_json:get_value(<<"Error-Message">>, OriginateResp) of
                            <<"USER_BUSY">> ->
                                DoormanProc ! {self(), {'error', 'callee_busy'}};
                            <<"ORIGINATOR_CANCEL">> ->
                                lager:info("caller has canceled the call");
                            <<"NO_ANSWER">> ->
                                DoormanProc ! {self(), {'error', 'callee_no_answer'}};
                            _Reason ->
                                lager:debug("failed to contact callee: ~p", [_Reason]),
                                DoormanProc ! {self(), {'error', 'callee_error'}}
                        end
                end;
            {'error', _E} ->
                lager:debug("failed to contact callee: ~p", [_E]),
                DoormanProc ! {self(), {'error', 'callee_error'}}
        end,
    lager:debug("callee helper process exiting normally"),
    'ok'.

%% custom validator for two reasons:
%% 1. we want to process originate ready response, but not finish collecting responses
%% 2. we want to process error responses immediately and not wait for timeout
-spec validate_originate_resp(kz_term:api_terms(), kapps_call:call(), pid()) -> boolean().
validate_originate_resp([Resp|_], CalleeCall, DoormanProc) ->
    validate_originate_resp(kz_json:get_value(<<"Event-Name">>, Resp), Resp, CalleeCall, DoormanProc).

-spec validate_originate_resp(kz_json:api_json_term(), kz_term:api_terms(), kapps_call:call(), pid()) -> boolean().
validate_originate_resp(<<"originate_resp">>, Resp, _CalleeCall, _DoormanProc) ->
    kapi_resource:originate_resp_v(Resp)
        orelse kz_api:error_resp_v(Resp);
validate_originate_resp(<<"originate_ready">>, Resp, CalleeCall, DoormanProc) ->
    case kapi_resource:originate_ready_v(Resp) of
        'true' ->
            lager:debug("received originate ready response: ~p", [Resp]),
            OriginateUUID = kz_json:get_ne_binary_value(<<"Originate-UUID">>, Resp),
            OriginateQueue = kz_json:get_ne_binary_value(<<"Originate-Queue">>, Resp),
            ServerId = kz_json:get_value(<<"Server-ID">>, Resp),
            Routines = [
                        {fun kapps_call:from_originate_ready/2, Resp}
                       ,{fun kapps_call:kvs_store/3, 'Server-ID', ServerId}
                       ,{fun kapps_call:kvs_store/3, 'Originate-UUID', OriginateUUID}
                       ,{fun kapps_call:kvs_store/3, 'Originate-Queue', OriginateQueue}
                       ],
            UpdatedCallee = kapps_call:exec(Routines, kapps_call:from_originate_ready(Resp, CalleeCall)),
            lager:info("updated callee call: ~p, DoormanProc: ~p", [UpdatedCallee, DoormanProc]),
            DoormanProc ! {self(), 'update_callee', UpdatedCallee},
            Request = [
                       {<<"Originate-UUID">>, OriginateUUID}
                      | kz_api:default_headers(ServerId, ?APP_NAME, ?APP_VERSION)
                      ],
            Publisher = fun(P) -> kapi_dialplan:publish_originate_execute(ServerId, P) end,
            _ = kz_amqp_worker:cast(Request, Publisher),
            'false';
        'false' ->
            'true'
    end;
validate_originate_resp(_Event, Resp, _CalleeCall, _DoormanProc) ->
    kz_api:error_resp_v(Resp).

-type doorman_menu_return() :: {'ok', binary(), kapps_call:call()} | {'error', 'callee_hungup' | 'callee_error'}.

-spec doorman_menu(kapps_call:call()) -> doorman_menu_return().
doorman_menu(CalleeCall) ->
    case doorman_prompt(CalleeCall) of
        {'ok', <<>>} ->
            lager:info("doorman menu timeout expired, callee didn't make choice, going to hangup"),
            kapps_call_command:hangup(CalleeCall),
            {'error', 'callee_hungup'};
        {'ok', ?DTMF_HANGUP} ->
            kapps_call_command:hangup(CalleeCall),
            {'ok', ?DTMF_HANGUP, CalleeCall};
        {'ok', Option} -> {'ok', Option, CalleeCall};
        {'error', 'channel_hungup'} ->
            lager:info("callee hungup during doorman prompt"),
            {'error', 'callee_hungup'};
        {'error', 'callee_hungup_max_attempts'} ->
            lager:info("callee has reached max number of attempts to chose from the menu, going to hangup"),
            kapps_call_command:hangup(CalleeCall),
            {'error', 'callee_hungup'};
        {'error', _E} ->
            lager:error("error waiting for callee to choose: ~p", [_E]),
            {'error', 'callee_error'}
    end.

-spec doorman_prompt(kapps_call:call()) ->
          {'error', 'channel_hungup' | 'callee_hungup_max_attempts' | kz_json:object()} |
          {'ok', binary()}.
doorman_prompt(CalleeCall) ->
    lager:info("introducing caller to callee"),
    CallerIntro = [{'tts', <<"Call from">>}
                  ,{'play', kapps_call:kvs_fetch('caller_recording_id', CalleeCall), [<<"#">>], <<"both">> }
                  ],
    NoopId = kapps_call_command:audio_macro(CallerIntro, CalleeCall),
    case cf_util:wait_for_noop(CalleeCall, NoopId) of
        {'ok', _} -> doorman_options(CalleeCall, 0);
        {'error', _} = R -> R
    end.

doorman_options(CalleeCall, Counter) ->
    lager:info("playing doorman options to callee"),
    Options = erlang:iolist_to_binary(["Press ", ?DTMF_CONNECT_CALL, " to answer. ",
                                       "Press ", ?DTMF_VM, " to send call to voicemail. ",
                                       "Press ", ?DTMF_HANGUP, " to reject."
                                      ]),

    NoopId = kapps_call_command:tts(Options, CalleeCall),
    Choice = kapps_call_command:collect_digits(1
                                              ,kapps_call_command:default_collect_timeout()
                                              ,2 * ?MILLISECONDS_IN_SECOND
                                              ,NoopId
                                              ,CalleeCall
                                              ),
    case Choice of
        {'ok', ?DTMF_CONNECT_CALL} ->
            callee_announcement(CalleeCall);
        {'ok', Option} = R when Option =:= ?DTMF_VM; Option =:= ?DTMF_HANGUP -> R;
        {'ok', BadChoice} ->
            bad_choice(BadChoice, CalleeCall, Counter + 1);
        R -> R
    end.

callee_announcement(CalleeCall) ->
    Beep = kz_json:from_list([{<<"Frequencies">>, [<<"440">>]}
                             ,{<<"Duration-ON">>, <<"500">>}
                             ,{<<"Duration-OFF">>, <<"100">>}
                             ]),
    Announcement = <<"Your call is being connected.">>,

    AudioMacro = [{'tts', Announcement}
                 ,{'tones', [Beep]}
                 ],
    NoopId = kapps_call_command:audio_macro(AudioMacro, CalleeCall),
    case kapps_call_command:wait_for_noop(CalleeCall, NoopId) of
        {'ok', _} -> {'ok', ?DTMF_CONNECT_CALL};
        {'error', 'channel_hungup'} = R ->
            lager:debug("callee hung up during callee announcement"),
            R
    end.

bad_choice(BadChoice, CalleeCall, Counter) ->
    MaxAttempts = kapps_call:kvs_fetch('max_menu_attempts', CalleeCall),
    case Counter < MaxAttempts of
        'true' ->
            lager:info("callee has selected option which doesn't exist - (pressed ~p)", [BadChoice]),
            Text = <<"Wrong option, please, try again.">>,
            case kapps_call_command:b_tts(Text, CalleeCall) of
                {'ok', _} -> doorman_options(CalleeCall, Counter);
                {'error', 'channel_hungup'} = R -> R;
                {'error', _E} ->
                    lager:error("error playing tts: ~p", [_E]),
                    exit('normal')
            end;
        'false' ->
            Text = <<"Wrong option, Good bye.">>,
            _ = kapps_call_command:b_tts(Text, CalleeCall),
            {'error', 'callee_hungup_max_attempts'}
    end.

pickup_caller(TargetCallId, CalleeCall) ->
    kapps_call_command:connect_leg(TargetCallId, CalleeCall).

-spec update_logging_id(kapps_call:call(), kapps_call:call()) -> any().
update_logging_id(CallerCall, CalleeCall) ->
    LogId = iolist_to_binary([kapps_call:call_id(CallerCall)
                             ,"-"
                             ,kapps_call:call_id(CalleeCall)
                             ]),
    kz_log:put_callid(LogId).

build_originate_request(Data, CalleeCall, Endpoints, CallerCall) ->
    CCVs = [{<<"Account-ID">>, kapps_call:account_id(CalleeCall)}
           ,{<<"Inherit-Codec">>, <<"false">>}
           ,{<<"Authorizing-Type">>, kapps_call:authorizing_type(CalleeCall)}
           ,{<<"Authorizing-ID">>, kapps_call:authorizing_id(CalleeCall)}
           ],
    MsgId = kz_binary:rand_hex(16),
    CallTimeoutS = kz_json:get_integer_value(<<"call_timeout">>, Data, 30),

    kz_json:from_list(
      [{<<"Application-Name">>, <<"park">>}
      ,{<<"Application-Data">>, kz_json:new()}
      ,{<<"Continue-On-Fail">>, 'false'}
      ,{<<"Custom-Channel-Vars">>, kz_json:from_list(CCVs)}
      ,{<<"Dial-Endpoint-Method">>, <<"simultaneous">>}
      ,{<<"Endpoints">>, Endpoints}
      ,{<<"Export-Custom-Channel-Vars">>, [<<"Account-ID">>
                                          ,<<"Authorizing-ID">>
                                          ,<<"Authorizing-Type">>
                                          ,<<"Outbound-Callee-ID-Name">>
                                          ,<<"Outbound-Callee-ID-Number">>
                                          ,<<"Retain-CID">>
                                          ]}
      ,{<<"Ignore-Early-Media">>, 'true'}
      ,{<<"Originate-Immediate">>, 'false'}
      ,{<<"Switch-Nodename">>, kapps_call:switch_nodename(CallerCall)}
      ,{<<"Media">>, <<"process">>}
      ,{<<"Msg-ID">>, MsgId}
      ,{<<"Outbound-Caller-ID-Name">>, kapps_call:caller_id_name(CalleeCall)}
      ,{<<"Outbound-Caller-ID-Number">>, kapps_call:caller_id_number(CalleeCall)}
      ,{<<"Timeout">>, CallTimeoutS}
      | kz_api:default_headers(<<"resource">>, <<"originate_req">>, ?APP_NAME, ?APP_VERSION)
      ]).

-spec create_callee_call(kz_json:object(), kapps_call:call(), kz_json:objects()) ->
          kapps_call:call().
create_callee_call(Data, CallerCall, Endpoints) ->
    Routines = [{fun kapps_call:set_account_db/2, kapps_call:account_db(CallerCall)}
               ,{fun kapps_call:set_account_id/2, kapps_call:account_id(CallerCall)}
               ,{fun kapps_call:set_authorizing_id/2, kz_json:find(<<"Endpoint-ID">>, Endpoints)}
               ,{fun kapps_call:set_caller_id_name/2, kz_json:get_ne_binary_value(<<"caller_id_name">>, Data, <<"Doorman">>)}
               ,{fun kapps_call:set_caller_id_number/2, kapps_call:caller_id_number(CallerCall)}
               ,{fun kapps_call:set_custom_channel_var/3, <<"Retain-CID">>, <<"true">>}
               ,{fun kapps_call:set_resource_type/2, <<"audio">>}
               ,{fun kapps_call:kvs_store/3, 'caller_recording_id', kapps_call:kvs_fetch('caller_recording_id', CallerCall)}
               ,{fun kapps_call:kvs_store/3, 'max_menu_attempts', kz_json:get_integer_value(<<"max_menu_attempts">>, Data, 3)}
               ],
    kapps_call:exec(Routines, kapps_call:new()).

-spec handle_caller_termination(kapps_call:call(), kapps_call:call()) -> 'ok'.
handle_caller_termination(CallerCall, CalleeCall) ->
    lager:info("premature termination of caller (A-leg) ~s prior to bridge", [kapps_call:call_id_direct(CallerCall)]),

    case kapps_call:call_id(CalleeCall) of
        'undefined' ->
            lager:debug("callee (B-leg) was not answered yet. Cancelling originate request"),
            cancel_callee_call(CalleeCall);
        CalleeCallID ->
            lager:debug("callee (B-leg) ~s has already answered. Terminating it.", [CalleeCallID]),
            kapps_call_command:hangup(CalleeCall)
    end,
    'ok'.

cancel_callee_call(CalleeCall) ->
    Payload = [{<<"Originate-UUID">>, kapps_call:kvs_fetch(<<"Originate-UUID">>, CalleeCall)}
              | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
              ],
    kapi_dialplan:publish_originate_cancel(kapps_call:kvs_fetch(<<"Originate-Queue">>, CalleeCall), Payload).
