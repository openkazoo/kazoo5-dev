%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2025, 2600Hz
%%% @doc
%%% @author Karl Anderson
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_park).

-behaviour(gen_cf_action).

-include("callflow.hrl").

-export([handle/2]).
-export([update_presence/3]).
-export([maybe_cleanup_slot/3]).

-define(PARKED_CALL_DOC_TYPE, <<"parked_call">>).
-define(PARKED_CALLS_VIEW, <<"parking/parked_calls">>).
-define(PARKED_CALL_VIEW, <<"parking/parked_call">>).

-define(SLOT_DOC_ID(A), <<"parking-slot-", A/binary>>).

-define(MOD_CONFIG_CAT, <<(?CF_CONFIG_CAT)/binary, ".park">>).

-define(DEFAULT_RINGBACK_TM, kapps_config:get_integer(?MOD_CONFIG_CAT, <<"default_ringback_timeout">>, 2 * ?MILLISECONDS_IN_MINUTE)).
-define(DEFAULT_CALLBACK_TM, kapps_config:get_integer(?MOD_CONFIG_CAT, <<"default_callback_timeout">>, 30 * ?MILLISECONDS_IN_SECOND)).

-define(DEFAULT_PARKED_TYPE, <<"early">>).
-define(SYSTEM_PARKED_TYPE, kapps_config:get_ne_binary(?MOD_CONFIG_CAT, <<"parked_presence_type">>, ?DEFAULT_PARKED_TYPE)).
-define(ACCOUNT_PARKED_TYPE(A), kapps_account_config:get(A, ?MOD_CONFIG_CAT, <<"parked_presence_type">>, ?SYSTEM_PARKED_TYPE)).
-define(PRESENCE_TYPE_KEY, <<"Presence-Type">>).
-define(PARK_DELAY_CHECK_TIME_KEY, <<"valet_reservation_cleanup_time_ms">>).
-define(PARK_DELAY_CHECK_TIME, kapps_config:get_integer(?MOD_CONFIG_CAT, ?PARK_DELAY_CHECK_TIME_KEY, ?MILLISECONDS_IN_SECOND * 3)).
-define(PARKING_APP_NAME, <<"park">>).
-define(MAX_SLOT_NUMBER_KEY, <<"max_slot_number">>).
-define(MAX_SLOT_EXCEEDED, 'max_slot_exceeded').

%%------------------------------------------------------------------------------
%% @doc Entry point for this module sends an arbitrary response back to the
%% call originator.
%% @end
%%------------------------------------------------------------------------------
-spec update_presence(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
update_presence(SlotNumber, _PresenceId, AccountDb) ->
    case get_slot(SlotNumber, AccountDb) of
        {'ok', Slot} -> update_presence(Slot);
        _ -> 'ok'
    end.

%%------------------------------------------------------------------------------
%% @doc Entry point for this module sends an arbitrary response back to the
%% call originator.
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> any().
handle(Data, Call) ->
    ParkedCalls = get_parked_calls(Call),
    AutoSlotNumber = get_slot_number(ParkedCalls, kapps_call:kvs_fetch('cf_capture_group', Call)),
    SlotNumber = kz_json:get_ne_binary_value(<<"slot">>, Data, AutoSlotNumber),
    ReferredTo = kapps_call:custom_channel_var(<<"Referred-To">>, <<>>, Call),
    PresenceType = presence_type(SlotNumber, Data, Call),

    case re:run(ReferredTo, "Replaces=([^;]*)", [{'capture', [1], 'binary'}]) of
        'nomatch' when ReferredTo =:= <<>> ->
            handle_nomatch_with_empty_referred_to(Data, Call, PresenceType, ParkedCalls, SlotNumber);
        'nomatch' ->
            handle_nomatch(Data, Call, PresenceType, ParkedCalls, SlotNumber, ReferredTo);
        {'match', [Replaces]} ->
            handle_replaces(Data, Call, Replaces)
    end.

-spec handle_replaces(kz_json:object(), kapps_call:call(), kz_term:ne_binary()) ->
          'ok' |
          {'error', 'timeout' | 'failed'}.
handle_replaces(Data, Call, Replaces) ->
    lager:info("call was the result of an attended-transfer completion, updating call id"),
    {'ok', FoundInSlotNumber, Slot} = update_call_id(Replaces, Call),
    wait_for_pickup(FoundInSlotNumber, Slot, Data, Call).

-spec handle_nomatch(kz_json:object(), kapps_call:call(), kz_term:ne_binary(), kz_json:object(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
handle_nomatch(Data, Call, PresenceType, ParkedCalls, SlotNumber, ReferredTo) ->
    lager:info("call was the result of a blind transfer, assuming intention was to park"),
    Slot = create_slot('undefined', PresenceType, SlotNumber, Data, 'false', Call),
    park_call(SlotNumber, Slot, ParkedCalls, ReferredTo, Data, Call).

-spec handle_nomatch_with_empty_referred_to(kz_json:object(), kapps_call:call(), kz_term:ne_binary(), kz_json:object(), kz_term:ne_binary()) -> 'ok'.
handle_nomatch_with_empty_referred_to(Data, Call, PresenceType, ParkedCalls, SlotNumber) ->
    lager:info("call was the result of a direct dial"),
    case kz_json:get_ne_binary_value(<<"action">>, Data, <<"park">>) of
        <<"direct_park">> ->
            lager:info("action is to directly park the call"),
            Slot = create_slot(cf_exe:callid(Call), PresenceType, SlotNumber, Data, 'false', Call),
            direct_park(SlotNumber, Slot, ParkedCalls, Data, Call);
        <<"park">> ->
            lager:info("action is to park the call"),
            Slot = create_slot('undefined', PresenceType, SlotNumber, Data, 'true', Call),
            park_call(SlotNumber, Slot, ParkedCalls, 'undefined', Data, Call);
        <<"retrieve">> ->
            lager:info("action is to retrieve a parked call"),
            case retrieve(SlotNumber, Call) of
                {'ok', _} ->
                    cf_exe:transfer(maybe_record_call(Call));
                _Else ->
                    _ = kapps_call_command:b_answer(Call),
                    _ = kapps_call_command:b_prompt(<<"park-no_caller">>, Call),
                    cf_exe:stop(Call)
            end;
        <<"auto">> ->
            lager:info("action is to automatically determine if we should retrieve or park"),
            case retrieve(SlotNumber, Call) of
                {'error', 'attended'} ->
                    error_occupied_slot(Call);
                {'error', _} ->
                    Slot = create_slot(cf_exe:callid(Call), PresenceType, SlotNumber, Data, 'true', Call),
                    park_call(SlotNumber, Slot, ParkedCalls, 'undefined', Data, Call);
                {'ok', _} ->
                    cf_exe:transfer(maybe_record_call(Call))
            end
    end.

-spec maybe_record_call(kapps_call:call()) -> kapps_call:call().
maybe_record_call(Call) ->
    %% Using kzd_devices:fetch/2 here instead of kz_endpoint:get/1 because the latter adds default
    %% values when endpoint's call_recording is not configured and in this case that scenario needs
    %% to be handle different.
    do_maybe_record_call(Call
                        ,kzd_devices:fetch(kapps_call:account_id(Call)
                                          ,kapps_call:authorizing_id(Call)
                                          )
                        ).

-spec do_maybe_record_call(kapps_call:call(), {'ok', kzd_devices:doc()} | {'error', any()}) ->
          kapps_call:call().
do_maybe_record_call(Call, {'ok', Endpoint}) ->
    AccountId = kapps_call:account_id(Call),
    {'ok', User} = case kapps_call:owner_id(Call) of
                       'undefined' -> {'ok', kz_json:new()}; %% Unassigned device.
                       OwnerId -> kzd_users:fetch(AccountId, OwnerId)
                   end,
    {'ok', Account} = kzd_accounts:fetch(AccountId),
    EndpointRec = add_debug_info(kzd_devices:call_recording(Endpoint, kz_json:new()), Endpoint),
    UserRec = add_debug_info(kzd_users:call_recording(User, kz_json:new()), User),
    AccountRec = add_debug_info(kzd_accounts:call_recording_account(Account, kz_json:new()), Account),
    case maybe_record_call([EndpointRec, UserRec, AccountRec], Call) of
        {'true', Data} ->
            lager:debug("recording because device, user, or account is configured to record calls"),
            kapps_call:start_recording(Data, Call);
        'false' ->
            lager:debug("not recording this time"),
            Call
    end;
do_maybe_record_call(Call, {'error', _}=_Err) ->
    %% Known to happen with commland when retrieving parked call.
    lager:debug("not recording this time. Failed to fetch auth endpoint: ~p", [_Err]),
    Call.

%%------------------------------------------------------------------------------
%% @doc This function adds debugging information that will later be used within
%% `maybe_record_call/3' function to tell whether the given JObj has call_recording
%% enabled or not. That should ease debugging call_recording issues in the future.
%% @end
%%------------------------------------------------------------------------------
-spec add_debug_info(kz_json:object(), kz_doc:doc()) -> kz_json:object().
add_debug_info(RecJObj, Doc) ->
    kz_doc:setters(RecJObj
                  ,[{fun kz_doc:set_id/2, kz_doc:id(Doc)}
                   ,{fun kz_doc:set_type/2, kz_doc:type(Doc)}
                   ]
                  ).

%%------------------------------------------------------------------------------
%% @doc The logic implemented on this function is like this: device > user > account. Which means,
%% device takes precedence over user and user takes precedence over account. In this order of ideas,
%% the code only checks user's configuration if device's configuration is not set, same logic for user.
%% For example:
%% - If device is NOT configured to record calls, check user, if user is NOT configured to record
%%   calls, check account.
%% - If device has call_recording configuration and call recording is disabled, do not record call.
%%   If it is enabled, then record the call. Same logic for user up to account.
%% @end
%%------------------------------------------------------------------------------
-spec maybe_record_call(kz_json:objects(), kapps_call:call()) ->
          'false' |
          {'true', kz_json:object()}.
maybe_record_call(RecJObjs, Call) ->
    InceptionType = kapps_call:inception_type(Call),
    AnyKey = [<<"any">>, InceptionType], %% any
    DirKey = [kapps_call:direction(Call), InceptionType], %% inbound, outbound
    maybe_record_call(RecJObjs, AnyKey, DirKey).

-spec maybe_record_call(kz_json:objects(), kz_json:path(), kz_json:path()) ->
          'false' |
          {'true', kz_json:object()}.
maybe_record_call([], _AnyKey, _DirKey) ->
    lager:debug("none of the provided objects have call_recording configured"),
    'false';
maybe_record_call([RecJObj | RecJObjs], AnyKey, DirKey) ->
    DocType = kz_doc:type(RecJObj),
    DocId = kz_doc:id(RecJObj),
    case get_recording_settings(AnyKey, DirKey, RecJObj) of
        'undefined' ->
            lager:debug("call recording not configured for ~s ~s", [DocType, DocId]),
            maybe_record_call(RecJObjs, AnyKey, DirKey);
        RecordingSettings ->
            case kz_json:is_true(<<"enabled">>, RecordingSettings) of
                'false' -> 'false';
                'true' ->
                    lager:info("call recording is enabled from doc ~s: ~s", [DocType, DocId]),
                    {'true', RecordingSettings}
            end
    end.

-spec get_recording_settings(kz_json:path(), kz_json:path(), kz_json:object()) -> kz_term:api_object().
get_recording_settings(AnyKey, DirKey, RecJObj) ->
    kz_json:get_first_defined([AnyKey, DirKey], RecJObj).

-spec direct_park(kz_term:ne_binary(), kz_json:object(), kz_json:object(), kz_json:object(), kapps_call:call()) -> 'ok'.
direct_park(SlotNumber, Slot, ParkedCalls, Data, Call) ->
    MaxSlotNumber = kz_json:get_integer_value(?MAX_SLOT_NUMBER_KEY, Data),
    case save_slot(SlotNumber, MaxSlotNumber, Slot, ParkedCalls, Call) of
        {'ok', _} -> parked_call(SlotNumber, Slot, Data, Call);
        {'error', ?MAX_SLOT_EXCEEDED} ->
            cf_exe:continue(kz_term:to_upper_binary(?MAX_SLOT_EXCEEDED), Call);
        {'error', _Reason} ->
            lager:info("unable to save direct park slot: ~p", [_Reason]),
            cf_exe:stop(Call)
    end.

%%------------------------------------------------------------------------------
%% @doc Determine the appropriate action to retrieve a parked call
%% @end
%%------------------------------------------------------------------------------
-spec retrieve(kz_term:ne_binary(), kapps_call:call()) ->
          {'ok', 'retrieved'} |
          {'error', 'slot_empty' | 'timeout' | 'failed' | 'attended'}.
retrieve(SlotNumber, Call) ->
    SlotReturn = get_slot(SlotNumber, kapps_call:account_db(Call)),
    retrieve(SlotNumber, SlotReturn, 1, Call).

-spec retrieve(kz_term:ne_binary(), {'ok', kz_json:object()} | kz_datamgr:data_error(), 1..3, kapps_call:call()) ->
          {'ok', 'retrieved'} |
          {'error', 'slot_empty' | 'timeout' | 'failed' | 'attended'}.
retrieve(SlotNumber, {'error', 'not_found'}, _Try, _Call) ->
    lager:info("the parking slot ~s is empty, unable to retrieve caller", [SlotNumber]),
    {'error', 'slot_empty'};
retrieve(SlotNumber, {'error', _E}, _Try, _Call) ->
    lager:info("getting the parking slot ~s errored, unable to retrieve caller: ~p", [SlotNumber, _E]),
    {'error', 'slot_empty'};
retrieve(SlotNumber, {'ok', Slot}, 3, Call) ->
    retrieve_after_retries(SlotNumber, Slot, Call);
retrieve(SlotNumber, {'ok', Slot}, Try, Call) ->
    maybe_attempt_retrieve(SlotNumber, Slot, Try, Call).

maybe_attempt_retrieve(SlotNumber, Slot, Try, Call) ->
    maybe_attempt_retrieve(SlotNumber, Slot, Try, Call, maybe_retrieve_slot(Slot)).

maybe_attempt_retrieve(_SlotNumber, _Slot, _Try, _Call, {'error', _}=E) -> E;
maybe_attempt_retrieve(SlotNumber, _Slot, Try, Call, {'retry', ParkedCallId}) ->
    lager:info("the parking slot ~s currently has a pending attended parked call ~s, retrying in 1 sec"
              ,[SlotNumber, ParkedCallId]
              ),
    timer:sleep(?MILLISECONDS_IN_SECOND),
    retrieve(SlotNumber, get_slot(SlotNumber, kapps_call:account_db(Call)), Try + 1, Call);
maybe_attempt_retrieve(SlotNumber, _Slot, _Try, Call, {'ok', ParkedCallId}) ->
    lager:info("the parking slot ~s currently has a parked call ~s, attempting to retrieve caller"
              ,[SlotNumber, ParkedCallId]
              ),
    case retrieve_slot(ParkedCallId, Call) of
        'ok' ->
            _ = publish_retrieved(Call, SlotNumber),
            _ = cleanup_slot(SlotNumber, ParkedCallId, kapps_call:account_db(Call)),
            {'ok', 'retrieved'};
        {'error', _E}=E ->
            lager:debug("failed to retrieve slot: ~p", [_E]),
            _ = cleanup_slot(SlotNumber, ParkedCallId, kapps_call:account_db(Call)),
            E
    end.

retrieve_after_retries(SlotNumber, Slot, Call) ->
    retrieve_after_retries(SlotNumber, Slot, Call, kz_json:is_true(<<"Attended">>, Slot)).

retrieve_after_retries(SlotNumber, Slot, _Call, 'true') ->
    AttendedCallId = kz_json:get_ne_binary_value(<<"Call-ID">>, Slot),
    lager:info("the parking slot ~s currently has a pending attended parked call ~s after 3 tries, play occupied and exit"
              ,[SlotNumber, AttendedCallId]
              ),
    {'error', 'attended'};
retrieve_after_retries(SlotNumber, Slot, Call, 'false') ->
    ParkedCallId = kz_json:get_ne_binary_value(<<"Call-ID">>, Slot),
    lager:info("the parking slot ~s currently has a parked call ~s after 3 tries, attempting to retrieve caller"
              ,[SlotNumber, ParkedCallId]
              ),
    case retrieve_slot(ParkedCallId, Call) of
        'ok' -> {'ok', 'retrieved'};
        Error -> Error
    end.

-spec maybe_retrieve_slot(kz_json:object()) -> {'retry' | 'ok', kz_term:ne_binary()} | {'error', 'slot_empty'}.
maybe_retrieve_slot(Slot) ->
    ParkedCallId = kz_json:get_ne_binary_value(<<"Call-ID">>, Slot),
    case kz_json:is_true(<<"Attended">>, Slot) of
        'true' -> {'retry', ParkedCallId};
        'false' when ParkedCallId =/= 'undefined' -> {'ok', ParkedCallId};
        'false' -> {'error', 'slot_empty'}
    end.

-spec retrieve_slot(kz_term:ne_binary(), kapps_call:call()) ->
          'ok' |
          {'error', 'timeout' | 'failed'}.
retrieve_slot(ParkedCallId, Call) ->
    lager:info("retrieved parked call from slot, maybe bridging to caller ~s", [ParkedCallId]),
    _ = send_pickup(ParkedCallId, Call),
    wait_for_pickup(Call).

-spec send_pickup(kz_term:ne_binary(), kapps_call:call()) -> 'ok'.
send_pickup(ParkedCallId, Call) ->
    Req = [{<<"Unbridged-Only">>, 'true'}
          ,{<<"Application-Name">>, <<"call_pickup">>}
          ,{<<"Target-Call-ID">>, ParkedCallId}
          ,{<<"Continue-On-Fail">>, 'false'}
          ,{<<"Continue-On-Cancel">>, 'true'}
          ,{<<"Park-After-Pickup">>, 'false'}
          ],
    kapps_call_command:send_command(Req, Call).

-spec wait_for_pickup(kapps_call:call()) ->
          'ok' |
          {'error', 'timeout' | 'failed'}.
wait_for_pickup(Call) ->
    case kapps_call_command:receive_event(10 * ?MILLISECONDS_IN_SECOND) of
        {'ok', Evt} ->
            pickup_event(Call, kz_api:event_type(Evt), Evt);
        {'error', 'timeout'}=E ->
            lager:debug("timed out"),
            E
    end.

-spec pickup_event(kapps_call:call(), {kz_term:ne_binary(), kz_term:ne_binary()}, kz_call_event:payload()) ->
          'ok' |
          {'error', 'failed'}.
pickup_event(_Call, {<<"error">>, <<"dialplan">>}, _Evt) ->
    lager:debug("error in dialplan: ~s", [kz_call_event:error_message(_Evt)]),
    {'error', 'failed'};
pickup_event(_Call, {<<"call_event">>,<<"CHANNEL_BRIDGE">>}, _Evt) ->
    'ok' = lager:debug("channel bridged to ~s", [kz_call_event:other_leg_call_id(_Evt)]);
pickup_event(Call, _Type, _Evt) ->
    lager:debug("pickup event not handled : ~p", [_Type]),
    wait_for_pickup(Call).

%%------------------------------------------------------------------------------
%% @doc Determine the appropriate action to park the current call scenario
%% @end
%%------------------------------------------------------------------------------
-spec park_call(kz_term:ne_binary(), kz_json:object(), kz_json:object(), kz_term:api_binary(), kz_json:object(), kapps_call:call()) -> 'ok'.
park_call(SlotNumber, Slot, ParkedCalls, ReferredTo, Data, Call) ->
    lager:info("attempting to park call in slot ~s", [SlotNumber]),
    MaxSlotNumber = kz_json:get_integer_value(?MAX_SLOT_NUMBER_KEY, Data),
    case {ReferredTo, save_slot(SlotNumber, MaxSlotNumber, Slot, ParkedCalls, Call)} of
        %% attended transfer but the provided slot number is occupied, we are still connected to the 'parker'
        %% not the 'parkee'
        {'undefined', {'error', 'occupied'}} ->
            error_occupied_slot(Call);
        %% attended transfer and allowed to update the provided slot number, we are still connected to the 'parker'
        %% not the 'parkee'
        {'undefined', _} ->
            lager:info("playback slot number ~s to caller", [SlotNumber]),
            %% Update screen with new slot number
            _ = kapps_call_command:b_answer(Call),
            %% Caller parked in slot number...
            _ = kapps_call_command:b_prompt(<<"park-call_placed_in_spot">>, Call),
            _ = kapps_call_command:b_say(kz_term:to_binary(SlotNumber), Call),
            _ = wait_for_hangup(Call),
            _ = timer:apply_after(?PARK_DELAY_CHECK_TIME, ?MODULE, 'maybe_cleanup_slot', [SlotNumber, Call, cf_exe:callid(Call)]),
            cf_exe:transfer(Call);
        %% blind transfer but the provided slot number is occupied
        {_, {'error', 'occupied'}} ->
            lager:info("blind transfer to a occupied slot, call the parker back.."),
            case ringback_parker(kz_json:get_ne_binary_value(<<"Ringback-ID">>, Slot), SlotNumber, Slot, Data, Call) of
                'answered' -> cf_exe:transfer(Call);
                'intercepted' -> cf_exe:transfer(Call);
                'channel_hungup' -> cf_exe:stop(Call);
                'failed' ->
                    kapps_call_command:hangup(Call),
                    cf_exe:stop(Call)
            end,
            'ok';
        %% blind transfer and allowed to update the provided slot number
        {_, {'ok', _}} -> parked_call(SlotNumber, Slot, Data, Call)
    end.

-spec parked_call(kz_term:ne_binary(), kz_json:object(), kz_json:object(), kapps_call:call()) -> 'ok'.
parked_call(SlotNumber, Slot, Data, Call) ->
    ParkedCallId = kz_json:get_ne_binary_value(<<"Call-ID">>, Slot),
    lager:info("call ~s parked in slot ~s", [ParkedCallId, SlotNumber]),
    _ = publish_parked(Call, SlotNumber),
    update_presence(Slot),
    wait_for_pickup(SlotNumber, Slot, Data, Call).

-spec wait_for_hangup(kapps_call:call()) -> {'ok', 'channel_hungup'} | {'error', 'timeout'}.
wait_for_hangup(Call) ->
    case cf_exe:is_channel_destroyed(Call) of
        'false' -> kapps_call_command:wait_for_hangup(?MILLISECONDS_IN_SECOND * 30);
        'true' -> {'ok', 'channel_hungup'}
    end.

%%------------------------------------------------------------------------------
%% @doc Builds the json object representing the call in the parking slot
%% @end
%%------------------------------------------------------------------------------
-spec create_slot(kz_term:api_ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object(), boolean(), kapps_call:call()) -> kz_json:object().
create_slot(ParkerCallId, PresenceType, SlotNumber, Data, Attended, Call) ->
    CallId = cf_exe:callid(Call),
    RingbackId = ringback_endpoint_id(Call),
    SlotCallId = kz_binary:rand_hex(16),
    User = slot_presence_id(SlotNumber, Data, Call),
    Realm = kapps_call:account_realm(Call),
    kz_json:from_list([{<<"Call-ID">>, CallId}
                      ,{<<"Attended">>, Attended}
                      ,{<<"Slot-Call-ID">>, SlotCallId}
                      ,{<<"Switch-URI">>, kapps_call:switch_uri(Call)}
                      ,{<<"From-Tag">>, kapps_call:from_tag(Call)}
                      ,{<<"To-Tag">>, kapps_call:to_tag(Call)}
                      ,{<<"Parker-Call-ID">>, ParkerCallId}
                      ,{<<"Ringback-ID">>, RingbackId}
                      ,{<<"Presence-User">>, User}
                      ,{<<"Presence-Realm">>, Realm}
                      ,{<<"Presence-ID">>, <<User/binary, "@", Realm/binary>>}
                      ,{<<"Node">>, kapps_call:switch_nodename(Call)}
                      ,{<<"CID-Number">>, kapps_call:caller_id_number(Call)}
                      ,{<<"CID-Name">>, kapps_call:caller_id_name(Call)}
                      ,{<<"CID-URI">>, kapps_call:from(Call)}
                      ,{<<"Hold-Media">>, kz_attributes:moh_attributes(RingbackId, <<"media_id">>, Call)}
                      ,{<<"Parked-Number">>, parked_num(Call)}
                      ,{<<"Timestamp">>, kz_time:now_s()}
                      ,{?PRESENCE_TYPE_KEY, PresenceType}
                      ]
                     ).

-spec slot_presence_id(kz_term:ne_binary(), kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
slot_presence_id(SlotNumber, Data, Call) ->
    case kz_json:is_true(<<"custom_presence_id">>, Data, 'false') of
        'true' -> maybe_custom_slot_presence_id(SlotNumber, Data, Call);
        'false' -> slot_presence_user(SlotNumber, Data, Call)
    end.

-spec slot_presence_user(kz_term:ne_binary(), kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
slot_presence_user(SlotNumber, Data, Call) ->
    PresenceUser = slot_presence_user(SlotNumber, Call),
    case should_force_presence_user(Data, Call) of
        'true' -> force_presence_user(PresenceUser);
        'false' -> PresenceUser
    end.

-spec slot_presence_user(kz_term:ne_binary(), kapps_call:call()) -> kz_term:ne_binary().
slot_presence_user(SlotNumber, Call) ->
    User = kapps_call:request_user(Call),
    case kapps_call:kvs_fetch('cf_capture_group', <<>>, Call) of
        _ = ?NE_BINARY -> User;
        _Other -> <<User/binary, SlotNumber/binary>>
    end.

should_force_presence_user(Data, Call) ->
    kz_app_config:is_true({?APP, kapps_call:account_id(Call)}, <<"park.force_presence_user">>, 'true')
        orelse kz_json:is_true(<<"force_presence_user">>, Data).

force_presence_user(<<"*3", _/binary>> = User) -> User;
force_presence_user(<<"*4", SlotId/binary>>) -> <<"*3", SlotId/binary>>;
force_presence_user(<<"*", _Key, SlotId/binary>>) -> <<"*3", SlotId/binary>>;
force_presence_user(SlotId) -> <<"*3", SlotId/binary>>.

-spec maybe_custom_slot_presence_id(kz_term:ne_binary(), kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
maybe_custom_slot_presence_id(SlotNumber, Data, Call) ->
    case kz_json:get_ne_binary_value(<<"presence_id">>, slot_configuration(Data, SlotNumber)) of
        'undefined' -> maybe_custom_presence_id(Data, Call);
        PresenceId -> PresenceId
    end.

-spec maybe_custom_presence_id(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
maybe_custom_presence_id(Data, Call) ->
    case kz_json:get_ne_binary_value(<<"presence_id">>, Data) of
        'undefined' -> kapps_call:request_user(Call);
        PresenceId -> PresenceId
    end.

%%------------------------------------------------------------------------------
%% @doc Returns the provided slot number or the next available if none
%% was provided
%% @end
%%------------------------------------------------------------------------------
-spec get_slot_number(kz_json:object(), kz_term:api_binary()) -> kz_term:ne_binary().
get_slot_number(_, ?NE_BINARY=CaptureGroup) ->
    CaptureGroup;
get_slot_number(ParkedCalls, _) ->
    Slots = [kz_term:to_integer(Slot)
             || Slot <- kz_json:get_keys(<<"slots">>, ParkedCalls)
            ],
    Sorted = ordsets:to_list(ordsets:from_list([100|Slots])),
    kz_term:to_binary(find_slot_number(Sorted)).

-spec find_slot_number([integer(),...]) -> integer().
find_slot_number([A]) -> A + 1;
find_slot_number([A|[B|_]=Slots]) ->
    case B =:= A + 1 of
        'false' -> A + 1;
        'true' -> find_slot_number(Slots)
    end.

%%------------------------------------------------------------------------------
%% @doc Save the slot data in the parked calls object at the slot number.
%% If, on save, it conflicts then it gets the new instance
%% and tries again, determining the new slot.
%% @end
%%------------------------------------------------------------------------------
-spec save_slot(kz_term:ne_binary(), kz_term:api_integer(), kz_json:object(), kz_json:object(), kapps_call:call()) ->
          {'ok', kz_json:object()} |
          {'error', atom()}.
save_slot(SlotNumber, MaxSlotNumber, Slot, ParkedCalls, Call) ->
    try kz_term:to_integer(SlotNumber) of
        SlotNumberInt ->
            MaxExceeded = MaxSlotNumber =/= 'undefined'
                andalso SlotNumberInt > MaxSlotNumber,
            MaxExceeded
                andalso lager:info("no more slots available - max_slot_number (~b) has been exceeded", [MaxSlotNumber]),
            save_slot_check_max_slot_exceeded(SlotNumber, MaxExceeded, Slot, ParkedCalls, Call)
    catch
        'error':'badarg' ->
            save_slot(SlotNumber, Slot, ParkedCalls, Call)
    end.

-spec save_slot_check_max_slot_exceeded(kz_term:ne_binary(), boolean(), kz_json:object(), kz_json:object(), kapps_call:call()) ->
          {'ok', kz_json:object()} |
          {'error', atom()}.
save_slot_check_max_slot_exceeded(_, 'true', _, _, _) ->
    {'error', ?MAX_SLOT_EXCEEDED};
save_slot_check_max_slot_exceeded(SlotNumber, 'false', Slot, ParkedCalls, Call) ->
    save_slot(SlotNumber, Slot, ParkedCalls, Call).

-spec save_slot(kz_term:ne_binary(), kz_json:object(), kz_json:object(), kapps_call:call()) ->
          {'ok', kz_json:object()} |
          {'error', atom()}.
save_slot(SlotNumber, Slot, ParkedCalls, Call) ->
    ParkedCallId = kz_json:get_ne_binary_value([<<"slots">>, SlotNumber, <<"Call-ID">>], ParkedCalls),
    ParkerCallId = kz_json:get_ne_binary_value([<<"slots">>, SlotNumber, <<"Parker-Call-ID">>], ParkedCalls),
    case kz_term:is_empty(ParkedCallId)
        orelse ParkedCallId =:= ParkerCallId
    of
        'true' ->
            lager:info("slot has parked call '~s' by parker '~s', it is available", [ParkedCallId, ParkerCallId]),
            do_save_slot(SlotNumber, Slot, Call);
        'false' ->
            case kapps_call_command:b_channel_status(ParkedCallId) of
                {'ok', _} ->
                    lager:info("slot has active call '~s' in it, denying use of slot", [ParkedCallId]),
                    {'error', 'occupied'};
                _Else ->
                    lager:info("slot is availabled because parked call '~s' no longer exists: ~p", [ParkedCallId, _Else]),
                    do_save_slot(SlotNumber, Slot, Call)
            end
    end.

-spec do_save_slot(kz_term:ne_binary(), kz_json:object(), kapps_call:call()) ->
          {'ok', kz_json:object()} |
          {'error', atom()}.
do_save_slot(SlotNumber, Slot, Call) ->
    Doc = slot_doc(SlotNumber, Slot, Call),
    AccountDb = kapps_call:account_db(Call),
    CallId = kz_json:get_ne_binary_value(<<"Call-ID">>, Slot),
    lager:debug("attempting to update parked call document for slot ~s with call ~s", [SlotNumber, CallId]),
    case kz_datamgr:save_doc(AccountDb, Doc) of
        {'ok', _}=Ok ->
            lager:info("saved call parking data for slot ~s", [SlotNumber]),
            Ok;
        {'error', _Error} ->
            lager:info("error when attempting to store call parking data for slot ~s : ~p", [SlotNumber, _Error]),
            {'error', 'occupied'}
    end.

-spec slot_doc(kz_term:ne_binary(), kz_json:object(), kapps_call:call()) -> kz_json:object().
slot_doc(SlotNumber, Slot, Call) ->
    AccountDb = kapps_call:account_db(Call),
    Doc = case kz_json:get_json_value(<<"pvt_fields">>, Slot) of
              'undefined' -> kz_json:set_value(<<"slot">>, Slot, kz_json:new());
              Pvt -> kz_json:set_value(<<"slot">>, kz_doc:public_fields(Slot), Pvt)
          end,
    Options = [{'type', ?PARKED_CALL_DOC_TYPE}
              ,{'account_id', kapps_call:account_id(Call)}
              ,{'id', ?SLOT_DOC_ID(SlotNumber)}
              ],
    maybe_add_slot_doc_rev(kz_doc:update_pvt_parameters(Doc, AccountDb, Options), AccountDb).

-spec maybe_add_slot_doc_rev(kz_json:object(), kz_term:ne_binary()) -> kz_json:object().
maybe_add_slot_doc_rev(JObj, AccountDb) ->
    case kz_datamgr:lookup_doc_rev(AccountDb, kz_doc:id(JObj)) of
        {'ok', Rev} -> kz_json:set_value(<<"_rev">>, Rev, JObj);
        {'error', _} -> JObj
    end.

%%------------------------------------------------------------------------------
%% @doc After an attended transfer we need to find the callid that we stored
%% because it was the "C-Leg" of a transfer and now we have the
%% actual "A-Leg".  Find the old callid and update it with the new one.
%% @end
%%------------------------------------------------------------------------------
-spec update_call_id(kz_term:ne_binary(), kapps_call:call()) ->
          {'ok', kz_term:ne_binary(), kz_json:object()}.
update_call_id(Replaces, Call) ->
    CallId = cf_exe:callid(Call),
    lager:info("update parked call id ~s with new call id ~s", [Replaces, CallId]),
    AccountDb = kapps_call:account_db(Call),
    case kz_datamgr:get_result_doc(AccountDb, ?PARKED_CALL_VIEW, Replaces) of
        {'ok', Doc} ->
            ?SLOT_DOC_ID(SlotNumber) = kz_doc:id(Doc),
            lager:info("found parked call id ~s in slot ~s", [Replaces, SlotNumber]),
            _ = publish_parked(Call, SlotNumber),
            CallerNode = kapps_call:switch_nodename(Call),
            Updaters = [fun(J) -> kz_json:set_value(<<"Call-ID">>, CallId, J) end
                       ,fun(J) -> kz_json:set_value(<<"Node">>, CallerNode, J) end
                       ,fun(J) -> kz_json:set_value(<<"CID-Number">>, kapps_call:caller_id_number(Call), J) end
                       ,fun(J) -> kz_json:set_value(<<"CID-Name">>, kapps_call:caller_id_name(Call), J) end
                       ,fun(J) -> kz_json:set_value(<<"CID-URI">>, kapps_call:from(Call), J) end
                       ,fun(J) -> kz_json:set_value(<<"Attended">>, 'false', J) end
                       ,fun(J) -> maybe_set_hold_media(J, Call) end
                       ,fun(J) -> kz_json:set_value(<<"Parked-Number">>, parked_num(Call), J) end
                       ],
            Slot = kz_json:get_json_value(<<"slot">>, Doc),
            UpdatedSlot = lists:foldr(fun(F, J) -> F(J) end, Slot, Updaters),
            JObj = kz_json:set_value(<<"slot">>, UpdatedSlot, Doc),
            case kz_datamgr:save_doc(AccountDb, JObj) of
                {'ok', _} ->
                    update_presence(UpdatedSlot),
                    {'ok', SlotNumber, UpdatedSlot};
                {'error', _R} = E -> E
            end;
        {'error', _R} = E ->
            lager:info("failed to find parking slot with call id ~s: ~p", [Replaces, _R]),
            E
    end.

-spec maybe_set_hold_media(kz_json:object(), kapps_call:call()) -> kz_json:object().
maybe_set_hold_media(JObj, Call) ->
    RingbackId = kz_json:get_ne_binary_value(<<"Ringback-ID">>, JObj),
    HoldMedia = kz_json:get_ne_binary_value(<<"Hold-Media">>, JObj),
    case RingbackId =/= 'undefined'
        andalso HoldMedia =:= 'undefined'
    of
        'false' -> JObj;
        'true' ->
            maybe_set_hold_media_from_ringback(JObj, Call, RingbackId)
    end.

-spec maybe_set_hold_media_from_ringback(kz_json:object(), kapps_call:call(), kz_term:ne_binary()) -> kz_json:object().
maybe_set_hold_media_from_ringback(JObj, Call, RingbackId) ->
    case kz_attributes:moh_attributes(RingbackId, <<"media_id">>, Call) of
        'undefined' -> JObj;
        RingbackHoldMedia ->
            kz_json:set_value(<<"Hold-Media">>, RingbackHoldMedia, JObj)
    end.

%%------------------------------------------------------------------------------
%% @doc Attempts to retrieve the parked calls list from the datastore, if
%% the list does not exist then it returns an new empty instance
%% @end
%%------------------------------------------------------------------------------
-spec get_parked_calls(kapps_call:call() | kz_term:ne_binary()) -> kz_json:object().
get_parked_calls(?NE_BINARY = AccountDb) ->
    Options = ['include_docs'
              ,{'doc_type', ?PARKED_CALL_DOC_TYPE}
              ],
    case kz_datamgr:get_results(AccountDb, ?PARKED_CALLS_VIEW, Options) of
        {'error', _} -> load_parked_calls([]);
        {'ok', JObjs} -> load_parked_calls(JObjs)
    end;
get_parked_calls(Call) ->
    get_parked_calls(kapps_call:account_db(Call)).

-spec load_parked_calls(kz_json:objects()) -> kz_json:object().
load_parked_calls(JObjs) ->
    Slots = [load_parked_call(JObj) || JObj <- JObjs],
    kz_json:from_list([{<<"slots">>, kz_json:from_list(Slots)}]).

-spec load_parked_call(kz_json:object()) -> {kz_term:ne_binary(), kz_json:object()}.
load_parked_call(JObj) ->
    Doc = kz_json:get_json_value(<<"doc">>, JObj),
    <<"parking-slot-", SlotNumber/binary>> = kz_doc:id(Doc),
    case kz_json:get_json_value(<<"slot">>, Doc) of
        'undefined' -> 'undefined';
        Slot -> {SlotNumber, kz_json:set_value(<<"pvt_fields">>, kz_doc:private_fields(Doc), Slot)}
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec maybe_cleanup_slot(kz_term:ne_binary(), kapps_call:call(), kz_term:ne_binary()) -> 'ok'.
maybe_cleanup_slot(SlotNumber, Call, OldCallId) ->
    _ = kz_log:put_callid(OldCallId),
    ParkedCalls = get_parked_calls(Call),
    AccountDb   = kapps_call:account_db(Call),

    lager:info("maybe cleaning up parking slot ~p with old call-id ~p", [SlotNumber, OldCallId]),
    case kz_json:get_json_value([<<"slots">>, SlotNumber], ParkedCalls) of
        'undefined' ->
            lager:info("slot not found, not doing anything");
        Slot ->
            ParkedCallId = kz_json:get_ne_binary_value(<<"Call-ID">>, Slot),
            maybe_cleanup_slot(SlotNumber, OldCallId, ParkedCallId, AccountDb)
    end.

-spec maybe_cleanup_slot(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
maybe_cleanup_slot(SlotNumber, CallId, CallId, AccountDb) ->
    lager:info("callid (~p) in parking slot ~p has not changed, cleaning up...", [CallId, SlotNumber]),
    cleanup_slot(SlotNumber, CallId, AccountDb);

maybe_cleanup_slot(_SlotNumber, _OldCallId, _NewCallId, _AccountDb) ->
    lager:info("parking slot ~p call-id changed from ~p to ~p, not cleaning.", [_SlotNumber, _OldCallId, _NewCallId]).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec cleanup_slot(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          {'ok', kz_json:object()} |
          {'error', any()}.
cleanup_slot(SlotNumber, ParkedCallId, AccountDb) ->
    case kz_datamgr:open_doc(AccountDb, ?SLOT_DOC_ID(SlotNumber)) of
        {'ok', JObj} ->
            case kz_json:get_ne_binary_value([<<"slot">>, <<"Call-ID">>], JObj) of
                ParkedCallId ->
                    lager:info("delete parked call ~s in slot ~s", [ParkedCallId, SlotNumber]),
                    delete_slot(AccountDb, JObj);
                _Else ->
                    lager:info("call ~s is parked in slot ~s and we expected ~s", [_Else, SlotNumber, ParkedCallId]),
                    {'error', 'unexpected_callid'}
            end;
        {'error', _R}=E ->
            lager:info("failed to open the parked call doc ~s : ~p", [SlotNumber, _R]),
            E
    end.

-spec delete_slot(kz_term:ne_binary(), kz_json:object()) ->
          {'ok', kz_json:object()} |
          {'error', any()}.
delete_slot(AccountDb, JObj) ->
    case kz_datamgr:save_doc(AccountDb, kz_json:delete_key(<<"slot">>, JObj)) of
        {'ok', _}=Ok ->
            Slot = kz_json:get_json_value(<<"slot">>, JObj),
            update_presence(<<"terminated">>, Slot),
            Ok;
        {'error', _R}=E ->
            lager:info("failed to delete slot ~s : ~p", [kz_doc:id(JObj), _R]),
            E
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec wait_for_pickup(kz_term:ne_binary(), kz_json:object(), kz_json:object(), kapps_call:call()) -> 'ok'.
wait_for_pickup(SlotNumber, Slot, Data, Call) ->
    RingbackId = kz_json:get_ne_binary_value(<<"Ringback-ID">>, Slot),
    HoldMedia = kz_json:get_ne_binary_value(<<"Hold-Media">>, Slot),
    Timeout = case kz_term:is_empty(RingbackId) of
                  'true' -> 'infinity';
                  'false' -> ringback_timeout(Data, SlotNumber)
              end,
    lager:info("waiting '~p' for parked caller to be picked up or hangup", [Timeout]),
    kapps_call_command:hold(HoldMedia, Call),
    case kapps_call_command:wait_for_unparked_call(Call, Timeout) of
        {'error', 'timeout'} ->
            ChannelUp = case kapps_call_command:b_channel_status(Call) of
                            {'ok', _} -> 'true';
                            {'error', _} -> 'false'
                        end,
            case ChannelUp
                andalso ringback_parker(RingbackId, SlotNumber, Slot, Data, Call)
            of
                'false' ->
                    lager:info("parked call does not exist anymore, hangup"),
                    _ = cleanup_slot(SlotNumber, cf_exe:callid(Call), kapps_call:account_db(Call)),
                    cf_exe:stop(Call);
                'intercepted' ->
                    lager:info("parked caller ringback was intercepted"),
                    _ = cleanup_slot(SlotNumber, cf_exe:callid(Call), kapps_call:account_db(Call)),
                    _ = publish_retrieved(Call, SlotNumber),
                    Call1 = cf_util:maybe_start_recording_to(Call, <<"onnet">>),
                    cf_exe:transfer(Call1);
                'answered' ->
                    lager:info("parked caller ringback was answered"),
                    _ = cleanup_slot(SlotNumber, cf_exe:callid(Call), kapps_call:account_db(Call)),
                    _ = publish_retrieved(Call, SlotNumber),
                    wait_for_bridge(Call);
                'failed' ->
                    unanswered_action(SlotNumber, Slot, Data, Call);
                'channel_hungup' ->
                    lager:info("parked call does not exist anymore, hangup"),
                    _ = cleanup_slot(SlotNumber, cf_exe:callid(Call), kapps_call:account_db(Call)),
                    cf_exe:stop(Call)
            end;
        {'error', 'channel_disconnected'} ->
            lager:info("parked caller has disconnected, checking status"),
            case kapps_call_command:b_channel_status(cf_exe:callid(Call)) of
                {'ok', _} ->
                    lager:info("call '~s' is still active", [cf_exe:callid(Call)]),
                    wait_for_pickup(SlotNumber, Slot, Data, Call);
                _Else ->
                    lager:info("call '~s' is no longer active, ", [cf_exe:callid(Call)]),
                    _ = cleanup_slot(SlotNumber, cf_exe:callid(Call), kapps_call:account_db(Call)),
                    cf_exe:stop(Call)
            end;
        {'error', 'channel_hungup'} ->
            lager:info("parked caller hangup"),
            _ = publish_abandoned(Call, SlotNumber),
            _ = cleanup_slot(SlotNumber, cf_exe:callid(Call), kapps_call:account_db(Call)),
            cf_exe:stop(Call);
        {'ok', JObj} ->
            case {kz_call_event:event_name(JObj), kz_call_event:application_name(JObj), kz_call_event:channel_state(JObj)} of
                %% fast pickup scenario
                {<<"CHANNEL_INTERCEPTED">>, _AppName, _ChannelState} ->
                    lager:info("parked call intercepted, handling fast pickup"),
                    handle_fast_pickup(JObj, Call, SlotNumber);
                %% FS application hold completed due to parked call hangup
                {<<"CHANNEL_EXECUTE_COMPLETE">>, <<"hold">>, <<"HANGUP">>}->
                    lager:info("parked caller hangup"),
                    _ = publish_abandoned(Call, SlotNumber),
                    _ = cleanup_slot(SlotNumber, cf_exe:callid(Call), kapps_call:account_db(Call)),
                    cf_exe:stop(Call);
                %% FS application hold completed, indicating parked call pickup
                {<<"CHANNEL_EXECUTE_COMPLETE">>, <<"hold">>, _} ->
                    lager:info("parked caller has been picked up"),
                    _ = publish_retrieved(Call, SlotNumber),
                    _ = cleanup_slot(SlotNumber, cf_exe:callid(Call), kapps_call:account_db(Call)),
                    cf_exe:transfer(Call)
            end;
        _Else ->
            lager:info("unhandled case waiting for call pickup"),
            _ = publish_abandoned(Call, SlotNumber),
            _ = cleanup_slot(SlotNumber, cf_exe:callid(Call), kapps_call:account_db(Call)),
            cf_exe:stop(Call)
    end.

handle_fast_pickup(JObj, Call, SlotNumber) ->
    PickerCallID = kz_json:get_ne_value(<<"Intercepted-By">>, JObj),
    ParkedCallID = cf_exe:callid(Call),
    AMQPConsumer = kz_amqp_channel:consumer_pid(),
    AMQPChannel = kz_amqp_channel:consumer_channel(),
    AccountDb = kapps_call:account_db(Call),
    kz_process:spawn(fun fast_picker_leg_handler/3, [PickerCallID, AMQPConsumer, AMQPChannel]),
    %% wait for bridge with picker leg
    case kapps_call_command:wait_for_channel_bridge() of
        {'ok', Evt} ->
            case kz_api:event_type(Evt) of
                {<<"call_event">>, <<"CHANNEL_BRIDGE">>} ->
                    lager:info("fast pickup: parked call bridged with picker leg ~s", [PickerCallID]),
                    _ = publish_retrieved(Call, SlotNumber),
                    _ = cleanup_slot(SlotNumber, ParkedCallID, AccountDb),
                    cf_exe:transfer(Call);
                _ ->
                    lager:info("fast pickup: parked call: ~s was disconnected", [ParkedCallID]),
                    _ = publish_abandoned(Call, SlotNumber),
                    _ = cleanup_slot(SlotNumber, ParkedCallID, AccountDb),
                    cf_exe:stop(Call)
            end
    end.

fast_picker_leg_handler(PickerCallID, AMQPConsumer, AMQPChannel) ->
    _ = kz_amqp_channel:consumer_channel(AMQPChannel),
    _ = kz_amqp_channel:consumer_pid(AMQPConsumer),
    kz_events:bind_call_id(PickerCallID),
    %% wait for bridge with parked leg
    case kapps_call_command:wait_for_channel_bridge() of
        {'ok', Evt} ->
            case kz_api:event_type(Evt) of
                {<<"call_event">>, <<"CHANNEL_BRIDGE">>} ->
                    PickerCall = build_call_from_event(Evt),
                    lager:debug("fast pickup: processing recording settings for picker call: ~s", [PickerCallID]),
                    maybe_record_call(PickerCall);
                _ ->
                    lager:info("fast pickup: picker call: ~s was disconnected", [PickerCallID])
            end
    end.

build_call_from_event(Event) ->
    CCVs = kz_json:get_value(<<"Custom-Channel-Vars">>, Event),
    CallCtlQ = kz_json:get_ne_binary_value([<<"Call-Control">>, <<"Queue">>], Event),
    CallCtlPid = kz_json:get_ne_binary_value([<<"Call-Control">>, <<"PID">>], Event),
    Routines = [
                {fun kapps_call:from_json/2, Event}
               ,{fun kapps_call:set_account_id/2, kz_json:get_binary_value(<<"Account-ID">>, CCVs)}
               ,{fun kapps_call:set_authorizing_id/2, kz_json:get_binary_value(<<"Authorizing-ID">>, CCVs)}
               ,{fun kapps_call:set_authorizing_type/2, kz_json:get_binary_value(<<"Authorizing-Type">>, CCVs)}
               ,{fun kapps_call:set_control_queue/2, kapi:encode_pid(CallCtlQ, kz_term:to_pid(CallCtlPid))}
               ],
    kapps_call:exec(Routines, kapps_call:new()).

-spec ringback_timeout(kz_json:object(), kz_term:ne_binary()) -> integer().
ringback_timeout(Data, SlotNumber) ->
    JObj = slot_configuration(Data, SlotNumber),
    DefaultRingbackTime = kz_json:get_integer_value(<<"default_ringback_timeout">>, Data, ?DEFAULT_RINGBACK_TM),
    kz_json:get_integer_value(<<"ringback_timeout">>, JObj, DefaultRingbackTime).

-spec callback_timeout(kz_json:object(), kz_term:ne_binary()) -> integer().
callback_timeout(Data, SlotNumber) ->
    JObj = slot_configuration(Data, SlotNumber),
    DefaultCallbackTime = kz_json:get_integer_value(<<"default_callback_timeout">>, Data, ?DEFAULT_CALLBACK_TM),
    kz_json:get_integer_value(<<"callback_timeout">>, JObj, DefaultCallbackTime).

-spec unanswered_action(kz_term:ne_binary(), kz_json:object(), kz_json:object(), kapps_call:call()) -> 'ok'.
unanswered_action(SlotNumber, Slot, Data, Call) ->
    case cf_exe:next(SlotNumber, Call) of
        'undefined' ->
            update_presence(Slot),
            wait_for_pickup(SlotNumber, Slot, Data, Call);
        _ ->
            _ = publish_abandoned(Call, SlotNumber),
            _ = cleanup_slot(SlotNumber, cf_exe:callid(Call), kapps_call:account_db(Call)),
            cf_exe:continue(SlotNumber, Call)
    end.

-spec presence_type(kz_term:ne_binary(), kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
presence_type(SlotNumber, Data, Call) ->
    JObj = slot_configuration(Data, SlotNumber),
    DefaultPresenceType =
        kz_json:get_ne_binary_value(<<"default_presence_type">>
                                   ,Data
                                   ,?ACCOUNT_PARKED_TYPE(kapps_call:account_id(Call))
                                   ),
    kz_json:get_ne_binary_value(<<"presence_type">>, JObj, DefaultPresenceType).

-spec slots_configuration(kz_json:object()) -> kz_json:object().
slots_configuration(Data) ->
    kz_json:get_json_value(<<"slots">>, Data, kz_json:new()).

-spec slot_configuration(kz_json:object(), kz_term:ne_binary()) -> kz_json:object().
slot_configuration(Data, SlotNumber) ->
    kz_json:get_json_value(SlotNumber, slots_configuration(Data), kz_json:new()).

%%------------------------------------------------------------------------------
%% @doc Ringback the device that parked the call
%% @end
%%------------------------------------------------------------------------------
-type ringback_parker_result() :: 'answered' | 'intercepted' | 'failed' | 'channel_hungup'.

-spec ringback_parker(kz_term:api_binary(), kz_term:ne_binary(), kz_json:object(), kz_json:object(), kapps_call:call()) -> ringback_parker_result().
ringback_parker('undefined', _, _, _, _) -> 'failed';
ringback_parker(EndpointId, SlotNumber, Slot, Data, Call0) ->
    CalleeNumber = kz_json:get_value(<<"CID-Number">>, Slot),
    CalleeName = kz_json:get_value(<<"CID-Name">>, Slot),
    TmpCID = <<"Parking slot ", SlotNumber/binary, " - ", CalleeName/binary>>,

    Routines = [{fun kapps_call:kvs_store/3, 'dynamic_cid', {'undefined', TmpCID}}
               ,{fun kapps_call:kvs_store/3, 'force_dynamic_cid', 'true'}
               ,{fun kapps_call:set_callee_id_number/2, CalleeNumber}
               ,{fun kapps_call:set_callee_id_name/2, CalleeName}
               ],
    Call = kapps_call:exec(Routines, Call0),
    Timeout = callback_timeout(Data, SlotNumber),
    CVars = kz_json:from_list([{<<"Caller-ID-Name">>, CalleeName}]),
    case kz_endpoint:build(EndpointId, kz_json:from_list([{<<"can_call_self">>, 'true'}]), Call) of
        {'ok', [Endpoint]} ->
            lager:info("attempting to ringback endpoint ~s", [EndpointId]),
            EP = kz_json:set_value([<<"Endpoint-Actions">>
                                   ,<<"Execute-On-Answer">>
                                   ,<<"Set-Caller-ID">>
                                   ]
                                  ,set_command(CVars)
                                  ,Endpoint
                                  ),
            kapps_call_command:break(Call),
            kapps_call_command:bridge([EP], Call),
            wait_for_ringback(Timeout, Call);
        _ -> 'failed'
    end.

-spec set_command(kz_json:object()) -> kz_json:object().
set_command(ChannelVars) ->
    Command = [{<<"Application-Name">>, <<"set">>}
              ,{<<"Custom-Channel-Vars">>, ChannelVars}
              ,{<<"Custom-Call-Vars">>, kz_json:new()}
              ,{<<"Call-ID">>, kz_binary:rand_hex(16)}
              ,{<<"Msg-ID">>, kz_binary:rand_hex(16)}
              | kz_api:default_headers(<<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    kz_json:from_list(Command).

-spec wait_for_ringback(timeout(), kapps_call:call()) -> ringback_parker_result().
wait_for_ringback(Timeout, Call) ->
    case wait_for_parker(Timeout, Call) of
        {'ok', JObj} ->
            case kz_api:event_name(JObj) of
                <<"CHANNEL_INTERCEPTED">> ->
                    lager:info("channel intercepted during ringback"),
                    'intercepted';
                _Else ->
                    lager:info("completed successful bridge to the ringback device"),
                    'answered'
            end;
        {'fail', JObj} ->
            case kz_api:event_name(JObj) of
                <<"CHANNEL_DESTROY">> ->
                    lager:info("channel hungup during ringback"),
                    'channel_hungup';
                _Else ->
                    lager:info("ringback failed, returning caller to parking slot: ~p", [_Else]),
                    'failed'
            end;
        _Else ->
            lager:info("ringback failed, returning caller to parking slot: ~p" , [_Else]),
            'failed'
    end.

-type wait_for_parker_result() :: {'ok' | 'fail' | 'error', kz_json:object()}.
-type receive_event_result() :: {'ok', kz_json:object()} | {'error', 'timeout'}.

-spec wait_for_parker(timeout(), kapps_call:call()) -> wait_for_parker_result().
wait_for_parker(Timeout, Call) ->
    Start = kz_time:start_time(),
    lager:debug("waiting for parker for ~p ms", [Timeout]),
    wait_for_parker(Timeout, Call, Start, kapps_call_command:receive_event(Timeout)).

-spec wait_for_parker(timeout(), kapps_call:call(), kz_time:start_time(), receive_event_result()) -> wait_for_parker_result().
wait_for_parker(_Timeout, _Call, _Start, {'error', 'timeout'}=E) -> E;
wait_for_parker(Timeout, Call, Start, {'ok', JObj}) ->
    Disposition = kz_json:get_value(<<"Disposition">>, JObj),
    Cause = kz_json:get_first_defined([<<"Application-Response">>
                                      ,<<"Hangup-Cause">>
                                      ], JObj, <<"UNSPECIFIED">>),
    Result = case Disposition =:= <<"SUCCESS">>
                 orelse Cause =:= <<"SUCCESS">>
             of
                 'true' -> 'ok';
                 'false' -> 'fail'
             end,
    case kapps_call_command:get_event_type(JObj) of
        {<<"error">>, _, <<"bridge">>} ->
            lager:debug("channel execution error while waiting for bridge: ~s", [kz_json:encode(JObj)]),
            {'error', JObj};
        {<<"call_event">>, <<"CHANNEL_DESTROY">>, _} ->
            lager:info("bridge channel destroy completed with result ~s(~s)", [Disposition, Result]),
            {Result, JObj};
        {<<"call_event">>, <<"CHANNEL_INTERCEPTED">>, _} ->
            lager:debug("ringback channel intercepted"),
            {'ok', JObj};
        {<<"call_event">>, <<"CHANNEL_BRIDGE">>, _} ->
            lager:debug("ringback channel bridged"),
            {'ok', JObj};
        {<<"call_event">>, <<"CHANNEL_EXECUTE_COMPLETE">>, <<"bridge">>} ->
            lager:info("bridge execute completed with result ~s(~s)", [Disposition, Result]),
            {Result, JObj};
        _E ->
            NewTimeout = kz_time:decr_timeout(Timeout, Start),
            NewStart = kz_time:start_time(),
            wait_for_parker(NewTimeout, Call, NewStart, kapps_call_command:receive_event(NewTimeout))
    end.

expires(<<"early">>) -> 3600;
expires(<<"confirmed">>) -> 3600;
expires(<<"terminated">>) -> 10.

-spec update_presence(kz_term:api_object()) -> 'ok'.
update_presence('undefined') -> 'ok';
update_presence(Slot) ->
    update_presence(kz_json:get_ne_binary_value(?PRESENCE_TYPE_KEY, Slot, <<"early">>), Slot).

-spec update_presence(kz_term:ne_binary(), kz_term:api_object()) -> 'ok'.
update_presence(_State, 'undefined') -> 'ok';
update_presence(State, Slot) ->
    PresenceUser = kz_json:get_ne_binary_value(<<"Presence-User">>, Slot),
    PresenceRealm = kz_json:get_ne_binary_value(<<"Presence-Realm">>, Slot),
    PresenceId = <<PresenceUser/binary, "@", PresenceRealm/binary>>,
    PresenceURI = <<"sip:", PresenceId/binary>>,

    SwitchURI = kz_json:get_ne_binary_value(<<"Switch-URI">>, Slot),
    CallId = kz_json:get_ne_binary_value(<<"Call-ID">>, Slot),
    _SlotCallId = kz_json:get_ne_binary_value(<<"Slot-Call-ID">>, Slot),
    ToUser = kz_json:get_ne_binary_value(<<"CID-Name">>, Slot),
    To = kz_json:get_ne_binary_value(<<"CID-URI">>, Slot),
    Expires = expires(State),

    Command = props:filter_undefined(
                [{<<"Presence-ID">>, PresenceId}
                ,{<<"From">>, PresenceURI}
                ,{<<"From-User">>, PresenceUser}
                ,{<<"From-Realm">>, PresenceRealm}
                ,{<<"From-Tag">>, <<"A">>}

                ,{<<"To">>, To}
                ,{<<"To-User">>, ToUser}
                ,{<<"To-Realm">>, PresenceRealm}
                ,{<<"To-Tag">>, <<"B">>}
                ,{<<"To-URI">>, PresenceURI}

                ,{<<"State">>, State}
                ,{<<"Call-ID">>, CallId}
                ,{<<"Switch-URI">>, SwitchURI}
                ,{<<"Direction">>, <<"recipient">>}

                ,{<<"Expires">>, Expires}
                ,{<<"Event-Package">>, <<"dialog">>}

                | kz_api:default_headers(?PARKING_APP_NAME, ?APP_VERSION)
                ]),
    lager:info("update presence-id '~s' with state: ~s", [PresenceId, State]),
    kz_amqp_worker:cast(Command, fun kapi_presence:publish_dialog/1).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec publish_parked(kapps_call:call(), kz_term:ne_binary()) -> 'ok'.
publish_parked(Call, SlotNumber) ->
    publish_event(Call, SlotNumber, <<"PARK_PARKED">>).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec publish_retrieved(kapps_call:call(), kz_term:ne_binary()) -> 'ok'.
publish_retrieved(Call, SlotNumber) ->
    publish_event(Call, SlotNumber, <<"PARK_RETRIEVED">>).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec publish_abandoned(kapps_call:call(), kz_term:ne_binary()) -> 'ok'.
publish_abandoned(Call, Slot) ->
    publish_event(Call, Slot, <<"PARK_ABANDONED">>).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec publish_event(kapps_call:call(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
publish_event(Call, SlotNumber, Event) ->
    Cmd = [{<<"Call-ID">>, kapps_call:call_id(Call)}
          ,{<<"Callee-ID-Name">>, kapps_call:callee_id_name(Call)}
          ,{<<"Callee-ID-Number">>, kapps_call:callee_id_number(Call)}
          ,{<<"Caller-ID-Name">>, kapps_call:caller_id_name(Call)}
          ,{<<"Caller-ID-Number">>, kapps_call:caller_id_number(Call)}
          ,{<<"Custom-Channel-Vars">>, custom_channel_vars(Call)}
          ,{<<"Event-Name">>, Event}
          ,{<<"Parking-Slot">>, kz_term:to_binary(SlotNumber)}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    kapi_call:publish_event(Cmd).

-spec custom_channel_vars(kapps_call:call()) -> kz_json:object().
custom_channel_vars(Call) ->
    JObj = kapps_call:custom_channel_vars(Call),
    Realm = kapps_call:account_realm(Call),
    kz_json:set_value(<<"Realm">>, Realm, JObj).

-spec get_slot(kz_term:ne_binary(), kz_term:ne_binary()) ->
          {'ok', kz_json:object()} |
          kz_datamgr:data_error() |
          {'error', 'not_occupied'}.
get_slot(SlotNumber, AccountDb) ->
    DocId = ?SLOT_DOC_ID(SlotNumber),
    case kz_datamgr:open_doc(AccountDb, {?PARKED_CALL_DOC_TYPE, DocId}) of
        {'ok', JObj} -> maybe_empty_slot(JObj);
        {'error', _} = E -> E
    end.

-spec maybe_empty_slot(kz_json:object()) -> {'ok', kz_json:object()} |
          {'error', 'not_occupied'}.
maybe_empty_slot(JObj) ->
    case kz_json:get_json_value(<<"slot">>, JObj) of
        'undefined' -> {'error', 'not_occupied'};
        Slot ->
            {'ok', kz_json:set_value(<<"pvt_fields">>
                                    ,kz_doc:private_fields(JObj)
                                    ,Slot
                                    )
            }
    end.

-spec error_occupied_slot(kapps_call:call()) -> 'ok'.
error_occupied_slot(Call) ->
    lager:info("selected slot is occupied"),
    %% Update screen with error that the slot is occupied
    _ = case kapps_call_command:b_answer(Call) of
            {'error', 'timeout'} ->
                lager:info("timed out waiting for the answer to complete");
            {'error', 'channel_hungup'} ->
                lager:info("channel hungup while answering");
            _ ->
                lager:debug("channel answered, prompting of the slot being in use"),
                %% playback message that caller will have to try a different slot
                kapps_call_command:b_prompt(<<"park-already_in_use">>, Call)
        end,
    cf_exe:stop(Call).

-spec wait_for_bridge(kapps_call:call()) -> 'ok'.
wait_for_bridge(Call) ->
    Call1 = cf_util:maybe_start_recording_to(Call, <<"onnet">>),
    _ = kapps_call_command:wait_for_bridge('infinity', Call1),
    cf_exe:continue(Call1).


-spec ringback_endpoint_id(kapps_call:call()) -> kz_term:api_binary().
ringback_endpoint_id(Call) ->
    case kapps_call:restricted_endpoint_id(Call) of
        'undefined' ->
            kapps_call:authorizing_id(Call);
        EndpointId ->
            lager:debug("call was referred by endpoint id  => ~s / ~s", [kapps_call:account_id(Call), EndpointId]),
            EndpointId
    end.

-spec parked_num(kapps_call:call()) -> kz_term:api_binary().
parked_num(Call) ->
    case kapps_call:direction(Call) of
        <<"outbound">> -> kapps_call:callee_id_number(Call);
        _ -> kapps_call:caller_id_number(Call)
    end.
