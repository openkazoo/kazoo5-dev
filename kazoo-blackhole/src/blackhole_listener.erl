%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(blackhole_listener).
-behaviour(gen_listener).

-export([start_link/0
        ,handle_amqp_event/3
        ,handle_call_event/1
        ,add_binding/1, remove_binding/1
        ,add_bindings/1, remove_bindings/1
        ,flush/0

        ,wait_until_consuming/1
        ]).

-export([init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_info/2
        ,handle_event/2
        ,terminate/2
        ,code_change/3
        ]).

-include("blackhole.hrl").
-include_lib("kazoo_amqp/src/api/kapi_websockets.hrl").

-define(SERVER, ?MODULE).

-record(state, {bindings :: ets:tid()}).
-type state() :: #state{}.

-type mod_inited() :: 'ok' | {'error', atom()} |
                      'stopped'. %% stopped instead of inited

%% By convention, we put the options here in macros, but not required.
-define(BINDINGS, [{'websockets', [{'restrict_to', ['get', 'module_req']}]}]).

-define(RESPONDERS, [{{?MODULE, 'handle_amqp_event'}
                     ,[{<<"*">>, <<"*">>}]
                     }
                    ]).
-define(QUEUE_NAME, <<>>).
-define(QUEUE_OPTIONS, []).
-define(CONSUME_OPTIONS, []).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Starts the server.
%% @end
%%------------------------------------------------------------------------------
-spec start_link() -> kz_types:startlink_ret().
start_link() ->
    gen_listener:start_link({'local', ?SERVER}
                           ,?MODULE
                           ,[{'bindings', ?BINDINGS}
                            ,{'responders', ?RESPONDERS}
                            ,{'queue_name', ?QUEUE_NAME}       % optional to include
                            ,{'queue_options', ?QUEUE_OPTIONS} % optional to include
                            ,{'consume_options', ?CONSUME_OPTIONS} % optional to include
                            ]
                           ,[]
                           ).

-spec wait_until_consuming(timeout()) -> 'ok' | {'error', 'timeout'}.
wait_until_consuming(Timeout) ->
    gen_listener:wait_until_consuming(?SERVER, Timeout).

-spec flush() -> 'ok'.
flush() ->
    gen_listener:cast(?SERVER, 'flush_bh_bindings').

-spec handle_amqp_event(kz_json:object(), kz_term:proplist(), gen_listener:basic_deliver() | kz_term:ne_binary()) -> 'ok'.
handle_amqp_event(EventJObj, _Props, ?MODULE_REQ_ROUTING_KEY) ->
    handle_module_req(EventJObj);
handle_amqp_event(EventJObj, _Props, <<RoutingKey/binary>>) ->
    Evt = kz_api:event_type(EventJObj),
    lager:debug("recv event ~p (~s)", [Evt, RoutingKey]),
    RK = <<"blackhole.event.", RoutingKey/binary>>,

    StartTime = kz_time:start_time(),
    Res = case lookup_bindings(EventJObj) of
              [] ->
                  blackhole_bindings:pmap(RK, [RoutingKey, EventJObj]);
              Bindings ->
                  blackhole_bindings:pmap(RK, [RoutingKey, EventJObj], Bindings)
          end,
    lager:debug("delivered the event ~p (~s) to ~b subscriptions in ~b ms (used bh rk ~s)"
               ,[Evt, RoutingKey, length(Res), kz_time:elapsed_ms(StartTime), RK]
               );
handle_amqp_event(EventJObj, Props, BasicDeliver) ->
    handle_amqp_event(EventJObj, Props, gen_listener:routing_key_used(BasicDeliver)).

-spec handle_module_req(kz_json:object()) -> 'ok'.
handle_module_req(EventJObj) ->
    'true' = kapi_websockets:module_req_v(EventJObj),
    lager:debug("recv module_req: ~p", [EventJObj]),
    handle_module_req(EventJObj
                     ,kz_json:get_atom_value(<<"Module">>, EventJObj)
                     ,kz_json:get_binary_value(<<"Action">>, EventJObj)
                     ,kz_json:is_true(<<"Persist">>, EventJObj, 'true')
                     ).

-spec handle_module_req(kz_json:object(), atom(), kz_term:ne_binary(), boolean()) -> 'ok'.
handle_module_req(EventJObj, BHModule, <<"start">>, Persist) ->
    case code:which(BHModule) of
        'non_existing' -> send_error_module_resp(EventJObj, <<"module doesn't exist">>);
        _Path ->
            Started = start_module(BHModule),
            Persisted = maybe_persist(BHModule, Persist, Started),
            send_module_resp(EventJObj, Started, Persisted)
    end;
handle_module_req(EventJObj, BHModule, <<"stop">>, Persist) ->
    'ok' = blackhole_bindings:flush_mod(BHModule),

    Persist
        andalso blackhole_config:set_default_autoload_modules(
                  lists:delete(kz_term:to_binary(BHModule)
                              ,blackhole_config:autoload_modules()
                              )
                 ),

    send_module_resp(EventJObj, 'stopped', 'true').

-spec start_module(atom()) -> mod_inited().
start_module(BHModule) ->
    blackhole_bindings:init_mod(BHModule).

-spec maybe_persist(atom(), boolean(), mod_inited()) -> boolean().
maybe_persist(_BHModule, 'false', _Started) -> 'false';
maybe_persist(_BHModule, 'true', {'error', _}) -> 'false';
maybe_persist(BHModule, 'true', 'ok') ->
    Mods = blackhole_config:autoload_modules(),
    case lists:member(kz_term:to_binary(BHModule), Mods) of
        'true' ->
            lager:debug("module ~s persisted~n", [BHModule]),
            'true';
        'false' ->
            persist_module(BHModule, Mods)
    end.

-spec persist_module(atom(), kz_term:ne_binaries()) -> boolean().
persist_module(Module, Mods) ->
    case blackhole_config:set_default_autoload_modules(
           [kz_term:to_binary(Module)
           | lists:delete(kz_term:to_binary(Module), Mods)
           ]
          )
    of
        {'ok', _} -> 'true';
        {'error', _} -> 'false'
    end.

-spec send_module_resp(kz_json:object(), mod_inited(), boolean()) -> 'ok'.
send_module_resp(EventJObj, Started, Persisted) ->
    Resp = [{<<"Persisted">>, Persisted}
           ,{<<"Started">>, Started =:= 'ok'}
           ,{<<"Error">>, maybe_start_error(Started)}
           ,{<<"Msg-ID">>, kz_api:msg_id(EventJObj)}
           | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
           ],
    ServerId = kz_api:server_id(EventJObj),
    kapi_websockets:publish_module_resp(ServerId, Resp).

-spec maybe_start_error(mod_inited()) -> kz_term:api_ne_binary().
maybe_start_error('ok') -> 'undefined';
maybe_start_error('stopped') -> 'undefined';
maybe_start_error({'error', E}) -> kz_term:to_binary(E).

-spec send_error_module_resp(kz_json:object(), kz_term:ne_binary()) -> 'ok'.
send_error_module_resp(EventJObj, Error) ->
    Resp = [{<<"Persisted">>, 'false'}
           ,{<<"Started">>, 'false'}
           ,{<<"Error">>, Error}
           ,{<<"Msg-ID">>, kz_api:msg_id(EventJObj)}
           | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
           ],
    ServerId = kz_api:server_id(EventJObj),
    kapi_websockets:publish_module_resp(ServerId, Resp).

-type bh_amqp_binding() :: {'amqp', atom(), kz_term:proplist()}.
-type bh_hook_binding() :: {'hook', kz_term:ne_binary()} |
                           {'hook', kz_term:ne_binary(), kz_term:ne_binary()}.
-type bh_event_binding() :: bh_amqp_binding() | bh_hook_binding().
-type bh_event_bindings() :: [bh_event_binding()].

-spec add_binding(bh_event_binding()) -> 'ok'.
add_binding(Binding) ->
    gen_listener:cast(?SERVER, {'add_bh_binding', Binding}).

-spec add_bindings(bh_event_bindings()) -> 'ok'.
add_bindings(Bindings) ->
    gen_listener:cast(?SERVER, {'add_bh_bindings', Bindings}).

-spec remove_binding(bh_event_binding()) -> 'ok'.
remove_binding(Binding) ->
    gen_listener:cast(?SERVER, {'remove_bh_binding', Binding}).

-spec remove_bindings(bh_event_bindings()) -> 'ok'.
remove_bindings(Bindings) ->
    gen_listener:cast(?SERVER, {'remove_bh_bindings', Bindings}).

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the server.
%% @end
%%------------------------------------------------------------------------------
-spec init(list()) -> {'ok', state()}.
init([]) ->
    kz_log:put_callid(?MODULE),

    %% bind for all accounts' call events, easier to discard events
    %% than adjust AMQP bindings dynamically
    kz_events:add_async_call_event_handler(<<"*">>, <<"*">>, fun handle_call_event/1),

    {'ok', #state{bindings=ets:new(?MODULE, [])}}.

%%------------------------------------------------------------------------------
%% @doc Handling call messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_call(any(), kz_term:pid_ref(), state()) -> kz_types:handle_call_ret_state(state()).
handle_call(_Request, _From, State) ->
    {'reply', {'error', 'not_implemented'}, State}.

%%------------------------------------------------------------------------------
%% @doc Handling cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_cast(any(), state()) -> kz_types:handle_cast_ret_state(state()).
handle_cast({'add_bh_bindings', Bindings}, #state{bindings=ETS}=State) ->
    _ = add_bh_bindings(ETS, Bindings),
    {'noreply', State};
handle_cast({'add_bh_binding', Binding}, #state{bindings=ETS}=State) ->
    _ = add_bh_binding(ETS, Binding),
    {'noreply', State};
handle_cast({'remove_bh_bindings', Bindings}, #state{bindings=ETS}=State) ->
    _ = remove_bh_bindings(ETS, Bindings),
    {'noreply', State};
handle_cast({'remove_bh_binding', Binding}, #state{bindings=ETS}=State) ->
    _ = remove_bh_binding(ETS, Binding),
    {'noreply', State};
handle_cast({'gen_listener', {'created_queue', _QueueNAme}}, State) ->
    {'noreply', State};
handle_cast({'gen_listener', {'is_consuming', _IsConsuming}}, State) ->
    {'noreply', State};
handle_cast('flush_bh_bindings', #state{bindings=ETS}=State) ->
    _ = flush_bh_bindings(ETS),
    {'noreply', State};
handle_cast(_Msg, State) ->
    {'noreply', State}.

%%------------------------------------------------------------------------------
%% @doc Handling all non call/cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_info(any(), state()) ->
          {'noreply', state()}.
handle_info({'kapi', {_, _, CallEvent}}, State) ->
    HookEvent = kz_api:event_name(CallEvent),
    AccountId = kz_call_event:account_id(CallEvent),
    _ = kz_process:spawn(fun handle_hook_event/3, [AccountId, HookEvent, CallEvent]),
    {'noreply', State};
handle_info(_Info, State) ->
    {'noreply', State}.

%%------------------------------------------------------------------------------
%% @doc Allows listener to pass options to handlers.
%% @end
%%------------------------------------------------------------------------------
-spec handle_event(kz_json:object(), kz_term:proplist()) -> gen_listener:handle_event_return().
handle_event(JObj, _State) ->
    maybe_handle_call_event(JObj).

-spec handle_call_event([kapi_call:event()] | kapi_call:event()) -> 'ok'.
handle_call_event([CallEvent]) ->
    handle_call_event(CallEvent);
handle_call_event(CallEvent) ->
    _ = maybe_handle_call_event(CallEvent),
    'ok'.

maybe_handle_call_event(JObj) ->
    maybe_handle_call_event(JObj, kz_api:event_category(JObj)).

%% delivered via kz_events
maybe_handle_call_event(CallEvent, <<"call_event">>) ->
    HookEvent = kz_api:event_name(CallEvent),
    AccountId = kz_call_event:account_id(CallEvent),
    _Pid = kz_process:spawn(fun handle_hook_event/3, [AccountId, HookEvent, CallEvent]),
    lager:info("handling call event ~s in ~p", [HookEvent, _Pid]),
    'ignore';
maybe_handle_call_event(_JObj, _Cat) ->
    lager:info("ignoring evt"),
    {'reply', []}.

%%------------------------------------------------------------------------------
%% @doc This function is called by a `gen_server' when it is about to
%% terminate. It should be the opposite of `Module:init/1' and do any
%% necessary cleaning up. When it returns, the `gen_server' terminates
%% with Reason. The return value is ignored.
%%
%% @end
%%------------------------------------------------------------------------------
-spec terminate(any(), state()) -> 'ok'.
terminate(_Reason, _State) ->
    lager:debug("listener terminating: ~p", [_Reason]).

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
-spec encode_call_id(kz_json:object()) -> kz_term:ne_binary().
encode_call_id(JObj) ->
    kz_amqp_util:encode(kz_call_event:call_id(JObj)).

-spec handle_hook_event(kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> any().
handle_hook_event(AccountId, EventType, JObj) ->
    RK = kz_binary:join([<<"call">>
                        ,AccountId
                        ,EventType
                        ,encode_call_id(JObj)
                        ]
                       ,<<".">>
                       ),
    lager:info("building call rk ~s", [RK]),
    handle_amqp_event(JObj, [], RK).

-spec binding_key(bh_event_binding()) -> binary().
binding_key(Binding) -> base64:encode(term_to_binary(Binding)).

-spec add_bh_binding(ets:tid(), bh_event_binding()) -> 'ok'.
add_bh_binding(ETS, Binding) ->
    Key = binding_key(Binding),
    case ets:update_counter(ETS, Key, 1, {Key, 0}) of
        1 ->
            lager:debug("blackhole is creating new binding to ~p", [Binding]),
            add_bh_binding(Binding);
        0 ->
            lager:debug("listener has 0 refs after updating ? not creating new binding for ~p"
                       ,[Binding]
                       );
        _Else ->
            lager:debug("listener has ~b refs, not creating new binding for ~p"
                       ,[_Else, Binding]
                       )
    end.

-spec remove_bh_binding(ets:tid(), bh_event_binding()) -> 'ok' | 'true'.
remove_bh_binding(ETS, Binding) ->
    Key = binding_key(Binding),
    remove_bh_binding(ETS, Binding, Key, ets:update_counter(ETS, Key, -1, {Key, 0})).

-spec remove_bh_binding(ets:tid(), bh_event_binding(), binary(), integer()) -> 'ok' | 'true'.
remove_bh_binding(ETS, Binding, Key, 0) ->
    lager:debug("blackhole is deleting binding for ~p", [Binding]),
    remove_bh_binding(Binding),
    ets:delete(ETS, Key);
remove_bh_binding(ETS, Binding, Key, Neg) when Neg < 0 ->
    lager:debug("listener have ~b negative references, removing binding for ~p"
               ,[Neg, Binding]
               ),
    remove_bh_binding(Binding),
    ets:delete(ETS, Key);
remove_bh_binding(_ETS, _Binding, _Key, _Else) ->
    lager:debug("listener still have ~b references, not removing binding for ~p"
               ,[_Else, _Binding]
               ).

%% {hook,...} is replaced with kz_events call event handler
add_bh_binding({'hook', _AccountId}) -> 'ok';
add_bh_binding({'hook', <<"*">>, _Event}) -> 'ok';
add_bh_binding({'hook', _AccountId, _Event}) -> 'ok';
add_bh_binding({'amqp', Wapi, Options}) ->
    gen_listener:add_binding(self(), Wapi, Options).

remove_bh_binding({'hook', _AccountId}) -> 'ok';
remove_bh_binding({'hook', <<"*">>, _Event}) -> 'ok';
remove_bh_binding({'hook', _AccountId, _Event}) -> 'ok';
remove_bh_binding({'amqp', Wapi, Options}) ->
    gen_listener:rm_binding(self(), Wapi, Options).

add_bh_bindings(ETS, Bindings) ->
    [add_bh_binding(ETS, Binding) || Binding <- Bindings].

remove_bh_bindings(ETS, Bindings) ->
    [remove_bh_binding(ETS, Binding) || Binding <- Bindings].

-spec flush_bh_bindings(ets:tid()) -> ets:tid().
flush_bh_bindings(ETS) ->
    ets:foldl(fun flush_bh_binding/2, ETS, ETS).

-spec flush_bh_binding({binary(), integer()}, ets:tid()) -> ets:tid().
flush_bh_binding({Key, _Counter}, ETS) ->
    Binding = binary_to_term(base64:decode(Key)),
    remove_bh_binding(ETS, Binding, Key, 0),
    ETS.

-spec lookup_bindings(kz_json:object()) -> list().
lookup_bindings(EventJObj) ->
    lookup_bindings(EventJObj, kz_api:event_type(EventJObj)).

-spec lookup_bindings(kz_json:object(), {kz_term:api_ne_binary(), kz_term:api_ne_binary()}) -> kazoo_bindings:kz_bindings().
lookup_bindings(EventJObj, {<<"call_event">>, _}) ->
    %% RK: call.{account_id}.{event}.{call_id}
    Event = kz_api:event_name(EventJObj),
    AccountId = kz_call_event:account_id(EventJObj, <<"*">>),
    CallId = encode_call_id(EventJObj),
    Base = <<"blackhole.event.call.", AccountId/binary, ".">>,

    Suffixes = [<<"*.*">>
               ,<<"*.", CallId/binary>>
               ,<<Event/binary, ".*">>
               ,<<Event/binary, ".", CallId/binary>>
               ],

    do_lookup(Base, Suffixes);
lookup_bindings(EventJObj, {<<"qubicle-session">>, _}) ->
    %% RK: qubicle.session.{account_id}.{session_id}.{event}
    SessionId = kz_json:get_ne_binary_value(<<"Session-ID">>, EventJObj, <<"*">>),
    AccountId = kz_json:get_ne_binary_value(<<"Account-ID">>, EventJObj, <<"*">>),
    EventName = kz_api:event_name(EventJObj),
    Base = <<"blackhole.event.qubicle.session.", AccountId/binary, ".">>,
    Suffixes = [<<"*.*">>
               ,<<SessionId/binary, ".*">>
               ,<<SessionId/binary, ".", EventName/binary>>
               ,<<"*.", EventName/binary>>
               ],
    do_lookup(Base, Suffixes);
lookup_bindings(EventJObj, {<<"qubicle-queue">>, _}) ->
    %% RK: qubicle.queue.{account_id}.{recipient_id}.{event}
    AccountId = kz_json:get_ne_binary_value(<<"Account-ID">>, EventJObj, <<"*">>),
    QueueId = kz_json:get_ne_binary_value(<<"Queue-ID">>, EventJObj, <<"*">>),
    EventName = kz_api:event_name(EventJObj),
    Base = <<"blackhole.event.qubicle.queue.", AccountId/binary, ".">>,
    Suffixes = [<<"*.*">>
               ,<<QueueId/binary, ".*">>
               ,<<QueueId/binary, ".", EventName/binary>>
               ,<<"*.", EventName/binary>>
               ],
    do_lookup(Base, Suffixes);
lookup_bindings(EventJObj, {<<"qubicle-recipient">>, _}) ->
    %% RK: qubicle.recipient.{account_id}.{recipient_id}.{event}
    AccountId = kz_json:get_ne_binary_value(<<"Account-ID">>, EventJObj, <<"*">>),
    RecipientId = kz_json:get_ne_binary_value(<<"Recipient-ID">>, EventJObj, <<"*">>),
    EventName = kz_api:event_name(EventJObj),
    Base = <<"blackhole.event.qubicle.recipient.", AccountId/binary, ".">>,
    Suffixes = [<<"*.*">>
               ,<<RecipientId/binary, ".*">>
               ,<<RecipientId/binary, ".", EventName/binary>>
               ,<<"*.", EventName/binary>>
               ],
    do_lookup(Base, Suffixes);
lookup_bindings(EventJObj, {<<"configuration">>, _}) ->
    %% RK: {doc_action}.{account_db}.{doc_type}.*
    AccountDb = kz_json:get_ne_binary_value(<<"Database">>, EventJObj, <<"*">>),
    Action = kz_json:get_ne_binary_value(<<"Event-Name">>, EventJObj, <<"*">>),
    Type = kz_json:get_ne_binary_value(<<"Type">>, EventJObj, <<"*">>),
    Base = <<"blackhole.event.">>,
    Suffixes = [<<"*.*.*.*">>
               ,<<Action/binary, ".*.*.*">>
               ,<<Action/binary, ".", AccountDb/binary, ".*.*">>
               ,<<Action/binary, ".", AccountDb/binary, ".", Type/binary, ".*">>
               ,<<Action/binary, ".*.", Type/binary, ".*">>
               ,<<"*.", AccountDb/binary, ".", Type/binary, ".*">>
               ,<<"*.", AccountDb/binary, ".*.*">>
               ,<<"*.*.", Type/binary, ".*">>
               ],

    do_lookup(Base, Suffixes);
lookup_bindings(EventJObj, {<<"fax">>, <<"status">>}) ->
    %% RK: fax.status.{account_id}.{job_id}
    AccountId = kz_json:get_ne_binary_value(<<"Account-ID">>, EventJObj, <<"*">>),
    FaxId = kz_json:get_first_defined([<<"Fax-ID">>,<<"Job-ID">>], EventJObj, <<"*">>),
    Base = <<"blackhole.event.fax.status.", AccountId/binary, ".">>,
    Suffixes = [<<"*">>
               ,FaxId
               ],
    do_lookup(Base, Suffixes);
lookup_bindings(_EventJObj, LookupType) ->
    lager:info("unsupported hook type: ~p", [LookupType]),
    [].

-spec do_lookup(kz_term:ne_binary(), kz_term:ne_binaries()) -> kazoo_bindings:kz_bindings().
do_lookup(Base, Suffixes) ->
    lists:usort(
      lists:flatmap(fun(Suffix) ->
                            Routing = <<Base/binary, Suffix/binary>>,
                            ets:lookup('kazoo_bindings', Routing)
                    end, Suffixes)
     ).
