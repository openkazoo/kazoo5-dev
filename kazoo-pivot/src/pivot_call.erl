%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2025, 2600Hz
%%% @doc Handle processing of the pivot call
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pivot_call).
-behaviour(gen_listener).

%% API
-export([start_link/2
        ,maybe_relay_event/2
        ,stop_call/2
        ,new_request/3, new_request/4
        ,updated_call/2
        ,usurp_executor/1
        ]).

%% gen_server callbacks
-export([init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_info/2
        ,handle_event/2
        ,terminate/2
        ,code_change/3
        ]).

-include("pivot.hrl").

-define(SERVER, ?MODULE).
-define(DEFAULT_REQ_TIMEOUT_MS
       ,kapps_config:get_integer(?APP_NAME, <<"request_timeout_ms">>, 5 * ?MILLISECONDS_IN_SECOND)
       ).

-type http_method() :: 'get' | 'post'.

-record(stream, {id = 'undefined' :: kz_term:api_ne_binary()
                ,name :: kz_term:ne_binary()
                ,pid :: kz_term:api_pid()
                ,ref :: kz_term:api_reference()
                ,req_ref :: kz_term:api_reference()
                ,node :: kz_term:api_atom()
                ,start_timeout_ref :: kz_term:api_reference()
                }).

-record(state, {voice_uri :: kz_term:api_ne_binary()
               ,cdr_uri :: kz_term:api_ne_binary()
               ,request_format = <<"kazoo">> :: kz_term:ne_binary()
               ,request_body_format = <<"form">> :: kz_term:ne_binary()
               ,request_timeout_ms :: pos_integer()
               ,custom_request_headers = [] :: kz_json:json_proplist()
               ,method = 'get' :: http_method()
               ,call :: kapps_call:call() | 'undefined'
               ,call_id :: kz_term:ne_binary()
               ,request_id :: kz_http:req_id() | 'undefined'
               ,request_params :: kz_term:api_object()
               ,response_headers :: kz_term:binaries() | kz_term:api_ne_binary()
               ,response_body = [] :: iodata()
               ,response_content_type :: kz_term:api_binary()
               ,response_pid :: kz_term:api_pid() %% pid of the processing of the response
               ,response_event_handlers = [] :: kz_term:pids()
               ,response_ref :: kz_term:api_reference() %% monitor ref for the pid
               ,debug = 'false' :: boolean()
               ,requester_queue :: kz_term:api_ne_binary()
               ,streams = [] :: [#stream{}]
               ,flow_doc :: kz_term:api_object()
               ,flow_type :: kz_term:ne_binary()
               }).
-type state() :: #state{}.

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Starts the server.
%% @end
%%------------------------------------------------------------------------------
-spec start_link(kapps_call:call(), kz_json:object()) -> kz_types:startlink_ret().
start_link(Call, JObj) ->
    CallId = kapps_call:call_id(Call),

    StreamBinding = {'stream', [{'account_id', kapps_call:account_id(Call)}
                               ,{'call_id', kapps_call:call_id(Call)}
                               ]
                    },
    Bindings = {'bindings', [{'self', []}
                            ,{'call', [{'callid', CallId}, 'pooled']}
                            ,{'pivot', [{'restrict_to', [StreamBinding]}]}
                            ]},
    Responders = {'responders', [{{?MODULE, 'maybe_relay_event'}
                                 ,[{<<"conference">>, <<"event">>}
                                  ,{<<"resource">>, <<"offnet_resp">>}
                                  ,{<<"call_event">>, <<"*">>}
                                  ,{<<"pivot">>, <<"*">>}
                                  ]
                                 }
                                ]},

    gen_listener:start_link(?SERVER
                           ,[Bindings, Responders]
                           ,[Call, JObj]
                           ).

-spec stop_call(pid(), kapps_call:call()) -> 'ok'.
stop_call(Srv, Call) -> gen_listener:cast(Srv, {'stop_call', Call}).

-spec new_request(pid(), kz_term:ne_binary(), http_method()) -> 'ok'.
new_request(Srv, Uri, Method) ->
    gen_listener:cast(Srv, {'request', Uri, Method}).

-spec new_request(pid(), kz_term:ne_binary(), http_method(), kz_term:proplist()) -> 'ok'.
new_request(Srv, Uri, Method, Params) ->
    gen_listener:cast(Srv, {'request', Uri, Method, Params}).

-spec updated_call(pid(), kapps_call:call()) -> 'ok'.
updated_call(Srv, Call) -> gen_listener:call(Srv, {'updated_call', Call}).

-spec usurp_executor(pid()) -> 'ok'.
usurp_executor(Srv) -> gen_listener:cast(Srv, 'usurp').

-spec maybe_relay_event(kz_json:object(), kz_term:proplist() | state()) -> 'ok'.
maybe_relay_event(JObj, #state{response_pid=Pid
                              ,response_event_handlers=Pids
                              ,call_id = CallId
                              ,streams = Streams
                              }) ->
    Props = [{'pid', Pid}
            ,{'pids', Pids}
            ,{'call_id', CallId}
            ,{'streams', Streams}
            ],
    maybe_relay_event(JObj, Props);
maybe_relay_event(JObj, Props) ->
    ServerPid = props:get_value('server', Props),
    Pids = response_handler_pids(Props),
    CallId = props:get_value('call_id', Props),
    case {kz_api:event_type(JObj), kz_call_event:call_id(JObj)} of
        {{<<"call_event">>, <<"CHANNEL_DESTROY">>}, CallId} ->
            lager:debug("caller channel destroyed, saving cdrs..."),
            _ = [kapps_call_command:relay_event(P, JObj) || P <- Pids],
            gen_listener:cast(ServerPid, {'cdr', JObj});
        {{<<"call_event">> = _Cat, <<"CHANNEL_EXECUTE_COMPLETE">> = _Evt}, CallId} ->
            case kz_call_event:application_name(JObj) of
                <<"stream">> ->
                    %% TODO: can we extract stream name from Raw-Application-Data?
                    Id = kz_call_event:application_response(JObj),
                    lager:debug("freeswitch connected to proxy for stream ~s", [Id]),
                    gen_listener:cast(ServerPid, {'set_stream_id', Id});
                _App ->
                    lager:debug("relaying event ~s/~s to ~p (original call-id ~s)", [_Cat, _Evt, Pids, CallId]),
                    [kapps_call_command:relay_event(P, JObj) || P <- Pids]
            end;
        {{_Cat, _Evt}, _EventCallId} ->
            lager:debug("relaying event ~s/~s to ~p (original call-id ~s)", [_Cat, _Evt, Pids, CallId]),
            [kapps_call_command:relay_event(P, JObj) || P <- Pids]
    end.

-spec response_handler_pids(kz_term:proplist()) -> [pid()].
response_handler_pids(Props) ->
    Pid = props:get_value('pid', Props),
    HandlerPids = [Pid | get_stream_pids(Props)],
    case props:get_value('pids', Props) of
        [_|_]=Pids -> [P || P <- HandlerPids ++ Pids, is_pid(P)];
        _ -> [P || P <- HandlerPids, is_pid(P)]
    end.

-spec get_stream_pids(kz_term:proplist()) -> [pid()].
get_stream_pids(Props) ->
    %% TODO: handle me rpc node?
    [Pid || #stream{pid = Pid} <- props:get_value('streams', Props, []), is_pid(Pid)].

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the server.
%% @end
%%------------------------------------------------------------------------------
-spec init([kapps_call:call() | kz_json:object()]) ->
          {'ok', state(), 'hibernate'} |
          {'stop', 'normal'}.
init([Call, JObj]) ->
    init(Call, JObj, kapps_call_events:is_destroyed(Call)).

-spec init(kapps_call:call(), kz_json:object(), boolean()) ->
          {'ok', state(), 'hibernate'} |
          {'stop', 'normal'}.
init(_Call, _JObj, 'true') ->
    lager:info("call has gone down while we started up"),
    {'stop', 'normal'};
init(Call, JObj, 'false') ->
    kz_log:put_callid(kapps_call:call_id(Call)),

    Method = kzt_util:http_method(kz_json:get_value(<<"HTTP-Method">>, JObj, 'get')),
    VoiceUri = kz_json:get_value(<<"Voice-URI">>, JObj),

    ReqFormat = kz_json:get_value(<<"Request-Format">>, JObj, <<"twiml">>),
    ReqBodyFormat = kz_json:get_value(<<"Request-Body-Format">>, JObj, <<"form">>),

    lager:debug("waiting on queue for pivot ~s request to ~s", [Method, VoiceUri]),

    {'ok'
    ,#state{voice_uri = VoiceUri
           ,method = Method
           ,cdr_uri=kz_json:get_value(<<"CDR-URI">>, JObj)
           ,call=kzt_util:increment_iteration(Call)
           ,call_id=kapps_call:call_id(Call)
           ,request_format=ReqFormat
           ,request_body_format=ReqBodyFormat
           ,request_timeout_ms=kz_json:get_integer_value(<<"Request-Timeout">>, JObj, ?DEFAULT_REQ_TIMEOUT_MS)
           ,debug=kz_json:is_true(<<"Debug">>, JObj, 'false')
           ,requester_queue = kapps_call:controller_queue(Call)
           ,custom_request_headers = format_request_headers(kz_json:get_json_value(<<"Custom-Request-Headers">>, JObj))
           ,flow_doc = kz_json:get_ne_binary_value(<<"Flow-Doc">>, JObj)
           ,flow_type = kz_json:get_ne_binary_value(<<"Flow-Type">>, JObj, <<"application/xml">>)
           }
    ,'hibernate'
    }.

-spec format_request_headers(kz_term:api_object()) -> kz_json:json_proplist().
format_request_headers('undefined') -> [];
format_request_headers(RequestHeaders) ->
    kz_json:foldl(fun format_request_header/3, [], RequestHeaders).

format_request_header(Key, Value, Acc) ->
    [{kz_term:to_list(Key), Value} | Acc].

%%------------------------------------------------------------------------------
%% @doc Handling call messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_call(any(), kz_term:pid_ref(), state()) -> {'reply', 'ok', state()}.
handle_call({'updated_call', Call}, _From, State) ->
    {'reply', 'ok', State#state{call=Call}};
handle_call(_Request, _From, State) ->
    {'reply', 'ok', State}.

%%------------------------------------------------------------------------------
%% @doc Handling cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_cast(any(), state()) ->
          {'noreply', state()} |
          {'noreply', state(), 'hibernate'} |
          {'stop', 'normal', state()}.
handle_cast('usurp', State) ->
    lager:debug("terminating pivot call because of usurp"),
    {'stop', 'normal', State#state{call='undefined'}};
handle_cast({'request', Uri, Method}
           ,#state{call=Call
                  ,request_format=ReqFormat
                  }=State) ->
    handle_cast({'request', Uri, Method, req_params(ReqFormat, Call)}, State);
handle_cast({'request', 'undefined', _Method, _Params}
           ,#state{call=Call
                  ,requester_queue=RequesterQ
                  }=State
           ) ->
    lager:debug("request uri is undefined, ending the call"),
    publish_failed_or_hangup(Call, RequesterQ),
    {'stop', 'normal', State};
handle_cast({'request', Uri, Method, Params}
           ,#state{call=Call
                  ,requester_queue=RequesterQ
                  }=State
           ) ->
    Call1 = kzt_util:set_voice_uri(Uri, Call),

    case send_req(Call1, Uri, Method, Params, State) of
        {'ok', ReqId, Call2} ->
            lager:debug("sent request ~p to '~s' via '~s'", [ReqId, Uri, Method]),
            {'noreply'
            ,State#state{request_id=ReqId
                        ,request_params=kz_json:from_list(Params)
                        ,response_content_type = <<>>
                        ,response_body = []
                        ,method=Method
                        ,voice_uri=Uri
                        ,call=Call2
                        }
            };
        _ ->
            publish_failed_or_hangup(Call, RequesterQ),
            {'stop', 'normal', State}
    end;

handle_cast({'gen_listener', {'created_queue', Q}}, #state{call=Call}=State) ->
    lager:debug("acquired queue ~s", [Q]),
    NewState = State#state{call=kapps_call:set_controller_queue(Q, Call)},
    maybe_exec_flow_doc_or_new_request(NewState);

handle_cast({'stream_start', From, Data}, State) ->
    NewState = maybe_limit_stream(Data, From, State),
    {'noreply', NewState};
handle_cast({'stream_stop', Id, Name}, State) ->
    NewState = stream_stop(Id, Name, State),
    {'noreply', NewState};

handle_cast({'set_stream_id', Id}, #state{streams=Streams, call=Call}=State) ->
    case lists:partition(fun(#stream{start_timeout_ref=TRef}) when is_reference(TRef) -> 'true';
                            (_) -> 'false'
                         end
                        ,Streams
                        )
    of
        {[], _} ->
            {'noreply', State};
        {[#stream{start_timeout_ref = TRef, pid='undefined'}=Stream|_], NewStreams} ->
            _ = erlang:cancel_timer(TRef),
            {'noreply', State#state{streams=[Stream#stream{id=Id, start_timeout_ref='undefined'} | NewStreams]}};
        {[#stream{start_timeout_ref = TRef, pid=From, req_ref=Ref}=Stream|_], NewStreams} ->
            _ = erlang:cancel_timer(TRef),
            From ! {'get_call', From, Ref, {Call, Id}},
            {'noreply', State#state{streams=[Stream#stream{id=Id, start_timeout_ref='undefined', req_ref='undefined'} | NewStreams]}}
    end;

handle_cast({'stop_call', Call}
           ,#state{cdr_uri='undefined'}=State
           ) ->
    lager:debug("no cdr callback, terminating call"),
    kapps_call_command:queued_hangup(Call),
    {'stop', 'normal', State};

handle_cast({'stop_call', Call}, #state{}=State) ->
    lager:debug("requested to stop while CDR uri is defined, hanging call waiting for cdrs before going down, hard stopping in 30 seconds"),
    kapps_call_command:queued_hangup(Call),

    %% hard stop if hangup or cdr was unsuccessful.
    erlang:send_after(30 * ?MILLISECONDS_IN_SECOND, self(), {'hard_stop', Call}),
    {'noreply', State};

handle_cast({'cdr', _JObj}
           ,#state{cdr_uri='undefined'
                  ,call=Call
                  }=State
           ) ->
    lager:debug("recv cdr for call, no cdr uri though, hard stopping..."),
    erlang:send_after(3 * ?MILLISECONDS_IN_SECOND, self(), {'hard_stop', Call}),
    {'noreply', State};
handle_cast({'cdr', JObj}
           ,#state{cdr_uri=Url
                  ,call=Call
                  ,debug=Debug
                  }=State
           ) ->
    lager:debug("sending cdr to cdr_uri ~s", [kz_log:redactor(Url)]),

    JObj1 = kz_json:delete_key(<<"Custom-Channel-Vars">>, JObj),
    Body =  kz_http_util:json_to_querystring(kz_api:remove_defaults(JObj1)),
    Headers = [{"Content-Type", "application/x-www-form-urlencoded"}],

    maybe_debug_req(Call, Url, 'post', Headers, Body, Debug),

    case kz_http:post(kz_term:to_list(Url), Headers, Body) of
        {'ok', RespCode, RespHeaders, RespBody} ->
            maybe_debug_resp(Debug, Call, integer_to_binary(RespCode), RespHeaders, RespBody),
            lager:debug("got response code ~p from cdr_uri", [RespCode]);
        {'error', _E} ->
            lager:debug("failed to send CDR: ~p", [_E])
    end,

    erlang:send_after(3 * ?MILLISECONDS_IN_SECOND, self(), {'hard_stop', Call}),
    {'noreply', State#state{cdr_uri='undefined'}};

handle_cast({'add_event_handler', {Pid, _Ref}}
           ,#state{response_event_handlers=Pids}=State
           ) ->
    lager:debug("adding event handler ~p", [Pid]),
    {'noreply', State#state{response_event_handlers=[Pid | Pids]}};
handle_cast({'add_event_handler', Pid}
           ,#state{response_event_handlers=Pids}=State
           ) when is_pid(Pid) ->
    lager:debug("adding event handler ~p", [Pid]),
    {'noreply', State#state{response_event_handlers=[Pid | Pids]}};

handle_cast({'gen_listener',{'is_consuming',_IsConsuming}}, #state{call=Call}=State) ->
    case kapps_call_events:is_destroyed(Call) of
        'true' ->
            lager:info("channel was destroyed while AMQP started"),
            {'stop', 'normal', State};
        'false' ->
            {'noreply', State}
    end;
handle_cast({'gen_listener', {'pooled_binding', _B}}, State) ->
    {'noreply', State};
handle_cast(_Req, State) ->
    lager:debug("unhandled cast: ~p", [_Req]),
    {'noreply', State}.

%%------------------------------------------------------------------------------
%% @doc Handling all non call/cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_info(any(), state()) ->
          {'noreply', state()} |
          {'noreply', state(), 'hibernate'} |
          {'stop', any(), state()}.
handle_info({'hard_stop', _Call}, State) ->
    {'stop', 'normal', State};
handle_info({'get_call', From, Ref, Node, Name}, #state{streams=Streams, call=Call}=State) ->
    %% TODO: handle me rpc node?
    lager:debug("getting stream '~ts' info for proxy at ~p", [Name, From]),
    case lists:partition(fun(#stream{name = N}) -> N =:= Name; (_) -> 'false' end, Streams) of
        {[], _} ->
            From ! {'get_call', From, Ref, 'not_found'},
            {'noreply', State};
        {[#stream{id='undefined'}=Stream|_], NewStreams} ->
            lager:debug("still waiting for stream '~s' id from freeswitch", [Name]),
            From ! {'get_call', From, Ref, 'no_id'},
            Updated = Stream#stream{pid=From
                                   ,ref=erlang:monitor('process', From)
                                   ,req_ref=Ref
                                   ,node=Node
                                   },
            {'noreply', State#state{streams=[Updated | NewStreams]}};
        {[#stream{id=Id}=Stream|_], NewStreams} ->
            From ! {'get_call', From, Ref, {Call, Id}},
            Updated = Stream#stream{pid=From
                                   ,ref=erlang:monitor('process', From)
                                   ,node=Node
                                   },
            {'noreply', State#state{streams=[Updated | NewStreams]}}
    end;
handle_info({'stream_start', Name, 'timeout'}, #state{streams=Streams}=State) ->
    Data = kz_json:from_list([{<<"name">>, Name}]),
    case lists:partition(fun(#stream{name=N}) when N =:= Name -> 'true'; (_) -> 'false' end, Streams) of
        {[], _} ->
            {'noreply', State};
        {[#stream{pid=Pid}=Stream|_], NewStreams} when is_pid(Pid) ->
            lager:debug("timeout waiting for stream-id for ~s from freeswitch", [Name]),
            send_stream_error(Data, <<"internal connection timeout">>, State),
            {'noreply', State#state{streams=[Stream#stream{start_timeout_ref='undefined'} | NewStreams]}};
        {_, NewStreams} ->
            lager:debug("timeout waiting for stream-id for ~s from freeswitch", [Name]),
            {'noreply', State#state{streams=NewStreams}}
    end;

handle_info({'http', {ReqId, 'stream_start', Hdrs}}
           ,#state{request_id=ReqId}=State
           ) ->
    RespHeaders = normalize_resp_headers(Hdrs),
    lager:debug("recv resp headers"),
    {'noreply', State#state{response_headers=RespHeaders}};

handle_info({'http', {ReqId, {'error', Error}}}
           ,#state{call=Call
                  ,request_id=ReqId
                  ,response_body=_RespBody
                  ,requester_queue=RequesterQ
                  }=State
           ) ->
    lager:info("recv error ~p : collected: ~s", [Error, lists:reverse(_RespBody)]),
    publish_failed_or_hangup(Call, RequesterQ),
    {'stop', 'normal', State};

handle_info({'http', {ReqId, 'stream', Chunk}}
           ,#state{request_id=ReqId
                  ,response_body=RespBody
                  }=State
           ) ->
    lager:info("adding response chunk: '~ts'", [Chunk]),

    {'noreply', State#state{response_body = [Chunk | RespBody]}};

handle_info({'http', {ReqId, 'stream_end', FinalHeaders}}
           ,#state{request_id=ReqId
                  ,response_body=RevBody
                  ,call=Call
                  ,debug=Debug
                  ,requester_queue=RequesterQ
                  }=State
           ) ->
    RespHeaders = normalize_resp_headers(FinalHeaders),
    Body = unicode:characters_to_binary(lists:reverse(RevBody)),
    maybe_debug_resp(Debug, Call, <<"200">>, RespHeaders, Body),

    AMQPConsumer = kz_amqp_channel:consumer_pid(),
    HandleArgs = [RequesterQ
                 ,kzt_util:set_amqp_listener(self(), Call)
                 ,props:get_value(<<"content-type">>, RespHeaders)
                 ,Body
                 ,AMQPConsumer
                 ],
    {Pid, Ref} = kz_process:spawn_monitor(fun handle_resp/5, HandleArgs),
    lager:debug("processing resp with ~p(~p)", [Pid, Ref]),
    {'noreply'
    ,State#state{request_id = 'undefined'
                ,request_params = kz_json:new()
                ,response_body = []
                ,response_content_type = <<>>
                ,response_pid = Pid
                ,response_ref = Ref
                }
    ,'hibernate'
    };

handle_info({'http', {ReqId, {{_, StatusCode, _}, RespHeaders, RespBody}}}
           ,#state{request_id=ReqId
                  ,requester_queue=RequesterQ
                  ,call=Call
                  ,debug=ShouldDebug
                  }=State
           )
  when (StatusCode - 400) < 100 ->
    lager:info("recv client failure status code ~p", [StatusCode]),
    publish_failed_or_hangup(Call, RequesterQ),
    maybe_debug_resp(ShouldDebug, Call, kz_term:to_binary(StatusCode), RespHeaders, RespBody),
    {'stop', 'normal', State};
handle_info({'http', {ReqId, {{_, StatusCode, _}, RespHeaders, RespBody}}}
           ,#state{request_id=ReqId
                  ,requester_queue=RequesterQ
                  ,call=Call
                  ,debug=ShouldDebug
                  }=State
           )
  when (StatusCode - 500) < 100 ->
    lager:info("recv server failure status code ~p", [StatusCode]),
    publish_failed_or_hangup(Call, RequesterQ),
    maybe_debug_resp(ShouldDebug, Call, kz_term:to_binary(StatusCode), RespHeaders, RespBody),
    {'stop', 'normal', State};

handle_info({'DOWN', Ref, 'process', Pid, 'normal'}
           ,#state{response_pid=Pid
                  ,response_ref=Ref
                  }=State
           ) ->
    lager:debug("response processing finished for ~p(~p)", [Pid, Ref]),
    {'noreply', State#state{response_pid='undefined', response_ref = 'undefined'}, 'hibernate'};
handle_info({'DOWN', Ref, 'process', Pid, Reason}
           ,#state{response_pid=Pid
                  ,response_ref=Ref
                  ,call=Call
                  ,requester_queue=RequesterQ
                  }=State
           ) ->
    lager:info("response pid ~p(~p) down: ~p", [Pid, Ref, Reason]),
    publish_failed_or_hangup(Call, RequesterQ),
    {'stop', 'normal', State#state{response_pid = 'undefined', response_ref = 'undefined'}};
handle_info({'DOWN', Ref, 'process', Pid, 'normal'}=_Info, #state{streams=Streams}=State) ->
    case lists:partition(fun(Stream) -> is_stream_process(Stream, Pid, Ref) end, Streams) of
        {[], _} ->
            lager:debug("unhandled message: ~p", [_Info]),
            {'noreply', State};
        {[#stream{id=Id}|_], Ss} ->
            lager:debug("stream ~s proxy process ~p(~p) is down normally", [Id, Pid, Ref]),
            {'noreply', State#state{streams=Ss}}
    end;
handle_info({'DOWN', Ref, 'process', Pid, Reason}=_Info, #state{streams=Streams}=State) ->
    case lists:partition(fun(Stream) -> is_stream_process(Stream, Pid, Ref) end, Streams) of
        {[], _} ->
            lager:debug("unhandled message: ~p", [_Info]),
            {'noreply', State};
        {[#stream{name=Id}|_], Ss} ->
            lager:debug("stream ~s proxy process ~p died unexpectedly: ~p", [Id, Pid, Reason]),
            {'noreply', State#state{streams=Ss}}
    end;

handle_info(_Info, State) ->
    lager:debug("unhandled message: ~p", [_Info]),
    {'noreply', State}.

is_stream_process(#stream{pid=Pid, ref=Ref}, Pid, Ref) -> 'true';
is_stream_process(_, _, _) -> 'false'.

%%------------------------------------------------------------------------------
%% @doc Handling messaging bus events
%% @end
%%------------------------------------------------------------------------------
-spec handle_event(kz_json:object(), state()) -> gen_listener:handle_event_return().
handle_event(_JObj, #state{response_pid=Pid
                          ,response_event_handlers=Pids
                          ,call_id = CallId
                          ,streams = Streams
                          }
            ) ->
    {'reply', [{'pid', Pid}
              ,{'pids', Pids}
              ,{'call_id', CallId}
              ,{'streams', Streams}
              ]}.

%%------------------------------------------------------------------------------
%% @doc This function is called by a `gen_server' when it is about to
%% terminate. It should be the opposite of `Module:init/1' and do any
%% necessary cleaning up. When it returns, the `gen_server' terminates
%% with Reason. The return value is ignored.
%%
%% @end
%%------------------------------------------------------------------------------
-spec terminate(any(), state()) -> 'ok'.
terminate(_Reason, #state{response_pid=Pid}) ->
    lager:info("pivot call terminating: ~p", [_Reason]),
    _ = case is_pid(Pid)
            andalso erlang:is_process_alive(Pid)
        of
            'true' ->
                lager:debug("exiting response process ~p", [Pid]),
                exit(Pid, 'kill');
            'false' -> 'ok'
        end,
    'ok'.

%%------------------------------------------------------------------------------
%% @doc Convert process state when code is changed.
%% @end
%%------------------------------------------------------------------------------
-spec code_change(any(), state(), any()) -> {'ok', state()}.
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec maybe_exec_flow_doc_or_new_request(state()) ->
          {'noreply', state()} |
          {'noreply', state(), 'hibernate'} |
          {'stop', 'normal', state()}.
maybe_exec_flow_doc_or_new_request(#state{flow_doc='undefined'
                                         ,call=Call
                                         ,voice_uri = VoiceUri
                                         ,request_format = ReqFormat
                                         ,method = Method
                                         }=State
                                  ) ->
    BaseParams = req_params(ReqFormat, Call),
    new_request(self(), VoiceUri, Method, BaseParams),
    {'noreply', State};
maybe_exec_flow_doc_or_new_request(#state{flow_doc=FlowDoc
                                         ,flow_type=FlowType
                                         ,call=Call
                                         ,debug=Debug
                                         ,requester_queue=RequesterQ
                                         }=State
                                  ) ->
    maybe_debug_resp(Debug, Call, <<"PivotFlowDoc">>, [], kz_json:encode(FlowDoc)),

    AMQPConsumer = kz_amqp_channel:consumer_pid(),
    HandleArgs = [RequesterQ
                 ,kzt_util:set_amqp_listener(self(), Call)
                 ,FlowType
                 ,FlowDoc
                 ,AMQPConsumer
                 ],
    {Pid, Ref} = kz_process:spawn_monitor(fun handle_resp/5, HandleArgs),
    lager:debug("processing resp with ~p(~p)", [Pid, Ref]),
    {'noreply'
    ,State#state{request_id = 'undefined'
                ,request_params = kz_json:new()
                ,response_body = []
                ,response_content_type = <<>>
                ,response_pid = Pid
                ,response_ref = Ref
                ,flow_doc = 'undefined'
                }
    ,'hibernate'
    }.
%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec send_req(kapps_call:call(), kz_term:ne_binary(), http_method(), kz_term:proplist(), state()) ->
          {'ok', kz_http:req_id(), kapps_call:call()} |
          {'stop', kapps_call:call()}.
send_req(Call, Uri, 'get', BaseParams, #state{request_body_format=_ReqBodyFormat
                                             ,request_timeout_ms=TimeoutMs
                                             ,debug=Debug
                                             ,custom_request_headers=CustomReqHeaders
                                             }
        ) ->
    UserParams = kzt_translator:get_user_vars(Call),
    Params = kz_json:set_values(BaseParams, UserParams),
    UpdatedCall = kapps_call:kvs_erase(<<"digits_collected">>, Call),
    send(UpdatedCall, uri(Uri, format_request(Params, <<"form">>)), 'get', CustomReqHeaders, [], TimeoutMs, Debug);
send_req(Call, Uri, 'post', BaseParams, #state{request_body_format=ReqBodyFormat
                                              ,request_timeout_ms=TimeoutMs
                                              ,debug=Debug
                                              ,custom_request_headers=CustomReqHeaders
                                              }
        ) ->
    UserParams = kzt_translator:get_user_vars(Call),
    Params = kz_json:set_values(BaseParams, UserParams),
    UpdatedCall = kapps_call:kvs_erase(<<"digits_collected">>, Call),
    Headers = [{"Content-Type", req_content_type(ReqBodyFormat)} | CustomReqHeaders],
    send(UpdatedCall, Uri, 'post', Headers, format_request(Params, ReqBodyFormat), TimeoutMs, Debug).

-spec send(kapps_call:call(), kz_term:ne_binary(), http_method(), kz_term:proplist(), iolist(), pos_integer(), boolean()) ->
          {'ok', kz_http:req_id(), kapps_call:call()} |
          {'stop', kapps_call:call()}.
send(Call, Uri, Method, ReqHdrs, ReqBody, TimeoutMs, Debug) ->
    lager:info("sending req to ~s(~s): ~s", [Uri, Method, iolist_to_binary(ReqBody)]),

    maybe_debug_req(Call, Uri, Method, ReqHdrs, ReqBody, Debug),

    case kz_http:async_req(self(), Method, Uri, ReqHdrs, ReqBody, [{'timeout', TimeoutMs}]) of
        {'http_req_id', ReqId} ->
            lager:debug("response coming in asynchronously to ~p(max ~p ms)", [ReqId, TimeoutMs]),
            {'ok', ReqId, Call};
        {'error', _Reason} ->
            lager:debug("error with req: ~p", [_Reason]),
            {'stop', Call}
    end.

-spec normalize_resp_headers(kz_term:proplist()) -> kz_term:proplist().
normalize_resp_headers(Headers) ->
    [{kz_term:to_lower_binary(K), kz_term:to_binary(V)} || {K, V} <- Headers].

-spec handle_resp(kz_term:api_binary(), kapps_call:call(), kz_term:api_ne_binary(), binary(), pid()) -> 'ok'.
handle_resp(RequesterQ, Call, CT, <<_/binary>> = RespBody, AMQPConsumer) ->
    _ = kz_amqp_channel:consumer_pid(AMQPConsumer),

    kz_log:put_callid(kapps_call:call_id(Call)),
    Srv = kzt_util:get_amqp_listener(Call),

    case process_resp(RequesterQ, Call, CT, RespBody) of
        {'stop_call', Call1} ->
            stop_call_after(Srv, Call1);
        {'usurp', _Call1} ->
            usurp_executor(Srv);
        {'request', Call1} ->
            updated_call(Srv, kzt_util:increment_iteration(Call1)),
            new_request(Srv
                       ,kzt_util:get_voice_uri(Call1)
                       ,kzt_util:get_voice_uri_method(Call1)
                       )
    end.

-spec process_resp(kz_term:api_binary(), kapps_call:call(), kz_term:api_ne_binary(), binary()) ->
          {'stop_call', kapps_call:call()} |
          {'request', kapps_call:call()} |
          {'usurp', kapps_call:call()}.
process_resp(_, Call, _, <<>>) ->
    lager:debug("no response body, finishing up"),
    {'stop_call', Call};
process_resp(RequesterQ, Call, CT, RespBody) ->
    lager:info("finding translator for content type ~s", [CT]),
    try kzt_translator:exec(RequesterQ, Call, CT, RespBody) of
        {'stop', Call1} ->
            lager:debug("translator says stop"),
            {'stop_call', Call1};
        {'ok', Call1} ->
            lager:debug("translator rendered successfully, stopping pivot call"),
            {'stop_call', Call1};
        {'request', _Call1}=Req ->
            lager:debug("translator says make another request"),
            Req;
        {'usurp', _Call1}=Usurp ->
            lager:info("translator has been usurped"),
            Usurp;
        {'error', Call1} ->
            lager:debug("error in translator, FAIL"),
            {'stop_call', Call1};
        {'error', Call1, Errors} ->
            lager:error("validation errors in response, FAIL"),
            _ = debug_error(Call1, Errors, RespBody),
            {'stop_call', Call1}
    catch
        'throw':{'json', Msg, Before, After} ->
            debug_json_error(Call, Msg, Before, After, RespBody),
            {'stop_call', Call};
        'throw':{'error', 'unrecognized_cmds'} ->
            lager:info("no translators recognize the supplied commands: ~s", [RespBody]),
            {'stop_call', Call}
    end.

-spec uri(kz_term:ne_binary(), iolist()) -> kz_term:ne_binary().
uri(URI, QueryString) ->
    SuppliedQS = iolist_to_binary(QueryString),
    case kz_http_util:urlsplit(URI) of
        {Scheme, Host, Path, <<>>, Fragment} ->
            kz_http_util:urlunsplit({Scheme, Host, Path, SuppliedQS, Fragment});
        {Scheme, Host, Path, QS, Fragment} ->
            kz_http_util:urlunsplit({Scheme, Host, Path, <<QS/binary, "&", SuppliedQS/binary>>, Fragment})
    end.

-spec req_params(kz_term:ne_binary(), kapps_call:call()) -> kz_term:proplist().
req_params(Format, Call) ->
    FmtAtom = kz_term:to_atom(<<"kzt_", Format/binary>>, 'true'),
    try FmtAtom:req_params(Call) of
        Result ->
            lager:debug("get req params from ~s", [FmtAtom]),
            Result
    catch
        'error':'undef' -> []
    end.

-spec maybe_debug_req(kapps_call:call(), binary(), atom(), kz_term:proplist(), iolist(), boolean()) -> 'ok'.
maybe_debug_req(_Call, _Uri, _Method, _ReqHdrs, _ReqBody, 'false') -> 'ok';
maybe_debug_req(Call, Uri, Method, ReqHdrs, ReqBody, 'true') ->
    Headers = kz_json:from_list([{fix_value(K), fix_value(V)} || {K, V} <- ReqHdrs]),
    store_debug(Call, [{<<"uri">>, iolist_to_binary(Uri)}
                      ,{<<"method">>, kz_term:to_binary(Method)}
                      ,{<<"req_headers">>, Headers}
                      ,{<<"req_body">>, iolist_to_binary(ReqBody)}
                      ]).

-spec maybe_debug_resp(boolean(), kapps_call:call(), kz_term:ne_binary(), kz_term:proplist(), binary()) -> 'ok'.
maybe_debug_resp('false', _Call, _StatusCode, _RespHeaders, _RespBody) -> 'ok';
maybe_debug_resp('true', Call, StatusCode, RespHeaders, RespBody) ->
    Headers = kz_json:from_list([{fix_value(K), fix_value(V)} || {K, V} <- RespHeaders]),
    store_debug(Call
               ,[{<<"resp_status_code">>, StatusCode}
                ,{<<"resp_headers">>, Headers}
                ,{<<"resp_body">>, RespBody}
                ]
               ).

-spec debug_error(kapps_call:call(), [jesse_error:error_reason()], binary()) -> 'ok'.
debug_error(Call, Errors, RespBody) ->
    JObj = kz_json_schema:errors_to_jobj(Errors),
    store_debug(Call
               ,kz_json:from_list([{<<"schema_errors">>, JObj}
                                  ,{<<"resp_body">>, RespBody}
                                  ])
               ).

debug_json_error(Call, Msg, Before, After, RespBody) ->
    JObj = kz_json:from_list([{<<"resp_body">>, RespBody}
                             ,{<<"json_errors">>
                              ,kz_json:from_list([{<<"before">>, Before}
                                                 ,{<<"after">>, After}
                                                 ,{<<"message">>, Msg}
                                                 ])
                              }
                             ]),
    store_debug(Call, JObj).

-spec store_debug(kapps_call:call(), kz_term:proplist() | kz_json:object()) -> 'ok'.
store_debug(Call, Doc) when is_list(Doc) ->
    store_debug(Call, kz_json:from_list(Doc));
store_debug(Call, DebugJObj) ->
    AccountModDb = kzs_util:format_account_mod_id(kapps_call:account_id(Call)),
    JObj = debug_doc(Call, DebugJObj, AccountModDb),

    case kazoo_modb:save_doc(AccountModDb, JObj) of
        {'ok', _Saved} ->
            lager:debug("saved debug doc: ~p", [_Saved]);
        {'error', _E} ->
            lager:debug("failed to save debug doc: ~p", [_E])
    end.

-spec debug_doc(kapps_call:call(), kz_json:object(), kz_term:ne_binary()) ->
          kz_json:object().
debug_doc(Call, DebugJObj, AccountModDb) ->
    WithCallJObj = kz_json:set_values([{<<"call_id">>, kapps_call:call_id(Call)}
                                      ,{<<"iteration">>, kzt_util:iteration(Call)}
                                      ]
                                     ,DebugJObj
                                     ),
    kz_doc:update_pvt_parameters(WithCallJObj
                                ,AccountModDb
                                ,[{'account_id', kapps_call:account_id(Call)}
                                 ,{'account_db', AccountModDb}
                                 ,{'type', <<"pivot_debug">>}
                                 ,{'now', kz_time:now_s()}
                                 ]
                                ).

-spec fix_value(number() | list()) -> number() | kz_term:ne_binary().
fix_value(N) when is_number(N) -> N;
fix_value(O) -> kz_term:to_lower_binary(O).

-spec format_request(kz_json:object(), kz_term:ne_binary()) -> iolist().
format_request(Params, <<"form">>) ->
    kz_http_util:json_to_querystring(Params);
format_request(Params, <<"json">>) ->
    kz_json:encode(Params).

-spec req_content_type(kz_term:ne_binary()) -> kz_term:ne_binary().
req_content_type(<<"form">>) ->
    <<"application/x-www-form-urlencoded">>;
req_content_type(<<"json">>) ->
    <<"application/json">>.

-spec is_first_pivot_request(kapps_call:call()) -> boolean().
is_first_pivot_request(Call) ->
    1 =:= kzt_util:iteration(Call).

-spec publish_failed_or_hangup(kapps_call:call(), kz_term:ne_binary()) -> 'ok'.
publish_failed_or_hangup(Call, RequesterQ) ->
    case is_first_pivot_request(Call) of
        'true' -> publish_failed(Call, RequesterQ);
        'false' -> maybe_hangup(Call)
    end.

-spec maybe_hangup(kapps_call:call()) -> 'ok'.
maybe_hangup(Call) -> kapps_call_command:queued_hangup(Call).

-spec publish_failed(kapps_call:call(), kz_term:ne_binary()) -> 'ok'.
publish_failed(Call, RequesterQ) ->
    PubFun = fun(P) -> kapi_pivot:publish_failed(RequesterQ, P) end,
    _ = kz_amqp_worker:cast([{<<"Call-ID">>, kapps_call:call_id(Call)}
                            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
                            ]
                           ,PubFun
                           ),
    'ok'.

%% after 10ms, send stop_call to pivot_call process,
%% to avoid race condition between stop_call and DOWN message
%% of handle_resp process when it's done its task
-spec stop_call_after(kz_term:pid(), kapps_call:call()) -> {'ok', timer:tref()} | {'error', any()}.
stop_call_after(Srv, Call) ->
    timer:apply_after(?MILLISECONDS_IN_SECOND div 100
                     ,?MODULE
                     ,'stop_call'
                     ,[Srv, Call]).

-spec maybe_limit_stream(kz_json:object(), pid(), state()) -> state().
maybe_limit_stream(Data, From, #state{streams=[]}=State) ->
    handle_stream_start(Data, From, State);
maybe_limit_stream(Data, From, #state{streams=Streams}=State) ->
    Length = length(Streams),
    case kz_json:get_ne_binary_value(<<"type">>, Data, <<"unidirectional">>) of
        <<"unidirectional">> when Length < 4 ->
            lager:debug("reached to maximum supported stream per call"),
            send_stream_error(Data, <<"max unidirectional limit reached">>, State),
            State;
        <<"bidirectional">> when Length < 1 ->
            lager:debug("reached to maximum supported stream per call"),
            send_stream_error(Data, <<"max bidirectional limit reached">>, State),
            State;
        <<"raw">> ->
            lager:debug("reached to maximum supported stream per call"),
            send_stream_error(Data, <<"max unidirectional limit reached">>, State),
            State;
        _ ->
            handle_stream_start(Data, From, State)
    end.

-spec stream_stop(kz_term:api_ne_binary(), kz_term:api_ne_binary(), state()) -> state().
stream_stop('undefined', 'undefined', #state{call=Call}=State) ->
    kapps_call_command:stream_stop(Call),
    State;
stream_stop('undefined', Name, #state{call=Call, streams=Streams}=State) ->
    case [Stream || #stream{name=N}=Stream <- Streams, N =:= Name] of
        [] ->
            lager:debug("stream with name '~s' not found", [Name]),
            State;
        [#stream{id=Id}|_] ->
            kapps_call_command:stream_stop(Id, Call),
            State
    end;
stream_stop(Id, _, #state{call=Call, streams=Streams}=State) ->
    case [Stream || #stream{id=I}=Stream <- Streams, I =:= Id] of
        [] ->
            lager:debug("stream with id '~s' not found", [Id]),
            State;
        [#stream{}|_] ->
            kapps_call_command:stream_stop(Id, Call),
            State
    end.

-spec handle_stream_start(kz_json:object(), pid(), state()) -> state().
handle_stream_start(Data, From, #state{streams=Streams}=State) ->
    Name = kz_json:get_ne_binary_value(<<"name">>, Data),
    case lists:any(fun(#stream{name=N}) -> N =:= Name end, Streams) of
        'false' ->
            start_stream(Name, Data, From, State);
        'true' ->
            lager:debug("stream with name '~s' is already exists", [Name]),
            send_stream_error(Data, <<"stream name already exists">>, State),
            State
    end.

-spec start_stream(kz_term:ne_binary(), kz_json:object(), pid(), state()) -> state().
start_stream(Name, Data, RespPid, #state{call=Call, streams=Streams}=State) ->
    ProxyUrl = pivot_piper_init:websocket_proxy_url(kapps_call:account_id(Call), kapps_call:call_id(Call)),
    AudioCodec = get_stream_codec(Data),
    AudioTracks = get_stream_tracks(Data),
    AudioMix = get_stream_mix(Data),
    SampleRate = kz_json:get_ne_binary_value(<<"sample_rate">>, Data, <<"8000">>),
    Payload = stream_payload(Name, Data, self(), RespPid, State),

    lager:debug("sending stream command for ~s for proxy ~s", [Name, kz_log:redactor(ProxyUrl)]),

    kapps_call_command:stream_start(ProxyUrl, AudioCodec, AudioTracks, AudioMix, SampleRate, Payload, Call),
    Stream = #stream{name = Name
                    ,start_timeout_ref = erlang:send_after(5 * ?MILLISECONDS_IN_SECOND, self(), {'stream_start', Name, 'timeout'})
                    },
    State#state{streams=[Stream|Streams]}.

-spec get_stream_tracks(kz_json:object()) -> kz_term:ne_binary().
get_stream_tracks(Data) ->
    case kz_json:get_ne_binary_value(<<"track">>, Data, <<"inbound_track">>) of
        <<"outbound_track">> -> <<"outbound">>;
        <<"both_tracks">> -> <<"both">>;
        _ -> <<"inbound">>
    end.

-spec get_stream_mix(kz_json:object()) -> kz_term:ne_binary().
get_stream_mix(Data) ->
    case kz_json:get_ne_binary_value(<<"mix">>, Data, <<"mono">>) of
        <<"stereo">> -> <<"stereo">>;
        _ -> <<"mono">>
    end.

-spec get_stream_codec(kz_json:object()) -> kz_term:ne_binary().
get_stream_codec(Data) ->
    case kz_term:to_lower_binary(kz_json:get_ne_binary_value(<<"format">>, Data, <<"L16">>)) of
        <<"pcmu">> -> <<"PCMU">>;
        _ -> <<"L16">>
    end.

-spec stream_payload(kz_term:ne_binary(), kz_json:object(), pid(), pid(), state()) -> kz_json:object().
stream_payload(Name, Data, ListenerPid, From, _State) ->
    Prop = [{<<"amqp_listener">>, kz_term:to_binary(ListenerPid)}
           ,{<<"amqp_consumer">>, kz_term:to_binary(kz_amqp_channel:consumer_pid())}
           ,{<<"response_pid">>, kz_term:to_binary(From)}
           ,{<<"node">>, kz_term:to_binary(node())}
           ,{<<"name">>, Name}
           ],
    kz_json:set_values(Prop, Data).

send_stream_error(Data, Reason, #state{call=Call}) ->
    Props = [{<<"Stream-Name">>, kz_json:get_ne_binary_value(<<"name">>, Data)}
            ,{<<"Call-ID">>, kapps_call:call_id(Call)}
            ,{<<"Account-ID">>, kapps_call:account_id(Call)}
            ,{<<"Reason">>, <<"error">>}
            ,{<<"Error-Message">>, Reason}
            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
            ],
    _ = kz_amqp_worker:cast(Props, fun kapi_pivot:publish_stream_stop/1),
    'ok'.
