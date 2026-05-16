%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2025, 2600Hz
%%% @doc Test the directories API endpoint
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_blackhole).

-export([seq/0
        ,seq_api/0
        ,seq_max_conn/0
        ,amqp_disconnect/0
        ,seq_count_bindings/0
        ,cleanup/0
        ]).

-include("properly.hrl").
-include_lib("kazoo_amqp/include/kz_amqp.hrl").
-include_lib("kazoo_stdlib/include/kz_types.hrl").


-properly({standalone, [seq_count_bindings/0 % this one may run in parallel with tweaking
                       ,seq_max_conn/0 % needed because it kicks other tests off
                       ]}).

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-define(PORT(API), kz_json:get_integer_value([<<"default">>, <<"port">>]
                                            ,kz_json:decode(pqc_cb_system_configs:get_default_config(API, <<"blackhole">>))
                                            ,5555
                                            )
       ).

-spec seq() -> 'ok'.
seq() ->
    _ = [seq_ping()
        ,seq_max_conn()
        ,seq_api()
         %% not running this during CI as it causes error.log CRASH REPORT
         %% when the AMQP connection is torn down
         %%,amqp_disconnect()
        ,seq_count_bindings()
        ],
    'ok'.

seq_ping() ->
    #{'auth_token' := AuthToken} = API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account: ~s", [AccountResp]),

    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    {'ok', WSConn} = pqc_ws_client:connect(?BASE_URL, ?PORT(API)),
    lager:info("connected to websocket: ~p", [WSConn]),

    PingReqId = kz_binary:rand_hex(4),
    Ping = kz_json:from_list([{<<"request_id">>, PingReqId}
                             ,{<<"action">>, <<"ping">>}
                             ,{<<"auth_token">>, AuthToken}
                             ]),
    _ = pqc_ws_client:send(WSConn, kz_json:encode(Ping)),
    {'json', ReplyJObj} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("pong: ~p", [ReplyJObj]),
    PingReqId = kz_json:get_ne_binary_value(<<"request_id">>, ReplyJObj),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, ReplyJObj),

    timer:sleep(2 * ?MILLISECONDS_IN_SECOND),

    _ = pqc_ws_client:send(WSConn, kz_json:encode(Ping)),
    {'json', Reply2JObj} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("pong2: ~p", [Reply2JObj]),

    pqc_ws_client:close(WSConn),

    cleanup(API, [AccountId]),
    lager:info("finished ping seq").

-spec seq_max_conn() -> 'ok'.
seq_max_conn() ->
    #{'auth_token' := AuthToken} = API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account: ~s", [AccountResp]),

    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    ConfigResp = pqc_cb_system_configs:get_default_config(API, <<"blackhole">>),
    PrevMaxConn = kz_json:get_integer_value([<<"default">>, <<"max_connections_per_ip">>]
                                           ,kz_json:decode(ConfigResp)
                                           ),
    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"blackhole">>
                                                  ,kz_json:from_list([{<<"default">>
                                                                      ,kz_json:from_list([{<<"max_connections_per_ip">>, 1}])
                                                                      }])
                                                  ),

    {'ok', WSConn} = pqc_ws_client:connect(?BASE_URL, ?PORT(API)),
    lager:info("connected to websocket: ~p", [WSConn]),

    PingReqId = kz_binary:rand_hex(4),
    Ping = kz_json:from_list([{<<"request_id">>, PingReqId}
                             ,{<<"action">>, <<"ping">>}
                             ,{<<"auth_token">>, AuthToken}
                             ]),
    _ = pqc_ws_client:send(WSConn, kz_json:encode(Ping)),
    {'json', ReplyJObj} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("pong: ~p", [ReplyJObj]),
    PingReqId = kz_json:get_ne_binary_value(<<"request_id">>, ReplyJObj),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, ReplyJObj),

    {'error', {'ws_upgrade_failed', {429, _WSHeaders}}} = pqc_ws_client:connect(?BASE_URL, ?PORT(API)),
    lager:info("failed to connect a second time"),

    pqc_ws_client:close(WSConn),

    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"blackhole">>
                                                  ,kz_json:from_list([{<<"default">>
                                                                      ,kz_json:from_list([{<<"max_connections_per_ip">>, PrevMaxConn}])
                                                                      }])
                                                  ),

    cleanup(API, [AccountId]),
    lager:info("finished max_conn seq").

-spec seq_api() -> 'ok'.
seq_api() ->
    API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account: ~s", [AccountResp]),

    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    AvailableBindings = pqc_cb_websockets:available(API),
    lager:info("available: ~s", [AvailableBindings]),
    'true' = ([] =/= kz_json:is_json_object([<<"data">>, <<"call">>], kz_json:decode(AvailableBindings))),

    test_empty_active_connections(API, AccountId),

    {'ok', WSConn} = pqc_ws_client:connect(?BASE_URL, ?PORT(API)),
    lager:info("connected to websocket: ~p", [WSConn]),

    %% test pinging the websocket
    _ = test_ws_ping(API, WSConn),

    Binding = <<"object.*.user">>,

    %% test using the API to list ws connections
    {SocketId, BindReq} = test_ws_api_listing(API, WSConn, AccountId, Binding),

    %% test receiving events over the ws
    _ = test_crud_user_events(WSConn, API, AccountId),

    %% test receiving call events over the ws
    _ = test_channel_create(WSConn, API, AccountId),

    %% test unbinding for events
    _ = test_ws_unbind(API, WSConn, AccountId, SocketId, BindReq, Binding),

    pqc_ws_client:close(WSConn),

    test_empty_active_connections(API, AccountId),

    cleanup(API, [AccountId]),
    lager:info("finished api seq").

%% test that shouldn't be run as part of CI
-spec amqp_disconnect() -> 'ok'.
amqp_disconnect() ->
    API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account: ~s", [AccountResp]),

    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    AvailableBindings = pqc_cb_websockets:available(API),
    lager:info("available: ~s", [AvailableBindings]),
    'true' = ([] =/= kz_json:is_json_object([<<"data">>, <<"call">>], kz_json:decode(AvailableBindings))),

    test_empty_active_connections(API, AccountId),

    {'ok', WSConn} = pqc_ws_client:connect(?BASE_URL, ?PORT(API)),
    lager:info("connected to websocket: ~p", [WSConn]),

    %% test pinging the websocket
    _ = test_ws_ping(API, WSConn),

    Binding = <<"object.*.user">>,

    %% test using the API to list ws connections
    {SocketId, BindReq} = test_ws_api_listing(API, WSConn, AccountId, Binding),
    lager:info("socket ~p bind ~p", [SocketId, BindReq]),

    %% test receiving events over the ws
    _ = test_crud_user_events(WSConn, API, AccountId),

    %% test receiving call events over the ws
    _ = test_channel_create(WSConn, API, AccountId),

    _ = disconnect_reconnect_amqp(),

    %% test receiving events over the ws
    _ = test_crud_user_events(WSConn, API, AccountId),

    %% test receiving call events over the ws
    _ = test_channel_create(WSConn, API, AccountId),

    pqc_ws_client:close(WSConn),

    test_empty_active_connections(API, AccountId),

    cleanup(API, [AccountId]),
    lager:info("finished amqp disconnect").

-spec seq_count_bindings() -> 'ok'.
seq_count_bindings() ->
    API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account: ~s", [AccountResp]),

    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    AvailableBindings = pqc_cb_websockets:available(API),
    lager:info("available: ~s", [AvailableBindings]),
    'true' = ([] =/= kz_json:is_json_object([<<"data">>, <<"call">>], kz_json:decode(AvailableBindings))),

    lager:info("active connections should be empty"),
    test_empty_active_connections(API, AccountId),

    {'ok', WSConn} = pqc_ws_client:connect(?BASE_URL, ?PORT(API)),
    lager:info("connected to websocket: ~p", [WSConn]),

    %% test pinging the websocket
    _ = test_ws_ping(API, WSConn),

    %% bind for CHANNEL_CREATE on account and auth-account
    bind_for_channel_events(WSConn, API, AccountId),
    bind_for_channel_events(WSConn, API, pqc_cb_api:auth_account_id(API)),

    %% emit the call event on the account and receive it
    CallId = emit_channel_event(AccountId),
    _ = recv_channel_event(WSConn, CallId, AccountId),

    %% unbind for CHANNEL_CREATE on auth-account
    _ = unbind_for_channel_events(WSConn, API, pqc_cb_api:auth_account_id(API)),

    %% emit the call event on the account and should still receive it
    SecondCallId = emit_channel_event(AccountId),
    recv_channel_event(WSConn, SecondCallId, AccountId),

    lager:info("shutting down WS conn ~p", [WSConn]),
    pqc_ws_client:close(WSConn),
    timer:sleep(100),

    lager:info("active connections should be empty again"),
    test_empty_active_connections(API, AccountId),

    cleanup(API, [AccountId]),
    lager:info("finished count bindings").

-spec initial_state() -> pqc_cb_api:state().
initial_state() ->
    _ = init_system(),
    pqc_cb_api:authenticate().

init_system() ->
    TestId = kz_binary:rand_hex(5),
    kz_log:put_callid(TestId),

    _ = kz_data_tracing:clear_all_traces(),
    _ = [kapps_controller:start_app(App) ||
            App <- ['crossbar', 'blackhole']
        ],
    _ = [crossbar_maintenance:start_module(Mod) ||
            Mod <- ['cb_websockets']
        ],

    blackhole_listener:flush(),

    lager:info("init finished").

-spec cleanup() -> 'ok'.
cleanup() ->
    cleanup(pqc_cb_api:authenticate()).

-spec cleanup(pqc_cb_api:state()) -> 'ok'.
cleanup(API) ->
    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"blackhole">>
                                                  ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"max_connections_per_ip">>, 'null'}])}])
                                                  ),
    _ = properly_maintenance:cleanup_module_accounts(?MODULE).

cleanup(API, AccountIds) ->
    lager:info("cleanup time, everybody helps"),
    _ = seq_accounts:cleanup_accounts(API, AccountIds),
    _ = pqc_cb_api:cleanup(API).

test_ws_ping(#{auth_token := AuthToken}, WSConn) ->
    PingReqId = kz_binary:rand_hex(4),
    Ping = kz_json:from_list([{<<"request_id">>, PingReqId}
                             ,{<<"action">>, <<"ping">>}
                             ,{<<"auth_token">>, AuthToken}
                             ]),
    _Send = pqc_ws_client:send(WSConn, kz_json:encode(Ping)),
    {'json', ReplyJObj} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("pong: ~p", [ReplyJObj]),
    PingReqId = kz_json:get_ne_binary_value(<<"request_id">>, ReplyJObj),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, ReplyJObj).

test_ws_api_listing(#{auth_token := AuthToken}=API, WSConn, AccountId, Binding) ->
    WithSocket = pqc_cb_websockets:summary(API, AccountId),
    lager:info("with socket: ~s", [WithSocket]),
    [SocketDetails] = kz_json:get_list_value(<<"data">>, kz_json:decode(WithSocket)),
    [] = kz_json:get_list_value(<<"bindings">>, SocketDetails),
    SocketId = kz_json:get_ne_binary_value(<<"websocket_session_id">>, SocketDetails),

    BindReqId = kz_binary:rand_hex(4),
    BindReq = kz_json:from_list([{<<"action">>, <<"subscribe">>}
                                ,{<<"auth_token">>, AuthToken}
                                ,{<<"request_id">>, BindReqId}
                                ,{<<"data">>
                                 ,kz_json:from_list([{<<"account_id">>, AccountId}
                                                    ,{<<"binding">>, Binding}
                                                    ])
                                 }
                                ]),
    _Send = pqc_ws_client:send(WSConn, kz_json:encode(BindReq)),
    {'json', BindReplyJObj} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("bind reply: ~p", [BindReplyJObj]),
    <<"reply">> = kz_json:get_ne_binary_value(<<"action">>, BindReplyJObj),
    BindReqId = kz_json:get_ne_binary_value(<<"request_id">>, BindReplyJObj),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, BindReplyJObj),
    [Binding] = kz_json:get_list_value([<<"data">>, <<"subscribed">>], BindReplyJObj),

    DetailsResp = pqc_cb_websockets:details(API, AccountId, SocketId),
    lager:info("details: ~s", [DetailsResp]),
    DetailsJObj = kz_json:decode(DetailsResp),
    [Binding] = kz_json:get_list_value([<<"data">>, <<"bindings">>], DetailsJObj),

    MyIP = my_ip(),

    MyIP = kz_json:get_ne_binary_value([<<"data">>, <<"source">>], DetailsJObj),
    SocketId = kz_json:get_ne_binary_value([<<"data">>, <<"websocket_session_id">>], DetailsJObj),

    {SocketId, BindReq}.

test_crud_user_events(WSConn, API, AccountId) ->
    UserDoc = seq_users:new_user(),
    Create = pqc_cb_users:create(API, AccountId, UserDoc),
    lager:info("created user ~s", [Create]),
    UserId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(Create)),

    {'json', CreateEvent} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("create event: ~p", [CreateEvent]),

    <<"event">> = kz_json:get_ne_binary_value(<<"action">>, CreateEvent),
    <<"object.*.user">> = kz_json:get_ne_binary_value(<<"subscribed_key">>, CreateEvent),
    <<"doc_created">> = kz_json:get_ne_binary_value(<<"name">>, CreateEvent),

    CreateJObj = kz_json:get_json_value(<<"data">>, CreateEvent),
    <<"user">> = kz_json:get_ne_binary_value(<<"type">>, CreateJObj),
    AccountId = kz_json:get_ne_binary_value(<<"account_id">>, CreateJObj),
    UserId = kz_json:get_ne_binary_value(<<"id">>, CreateJObj),

    Delete = pqc_cb_users:delete(API, AccountId, UserId),
    lager:info("deleted user ~s", [Delete]),

    {'json', DeleteEvent} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("delete event: ~p", [DeleteEvent]),

    <<"event">> = kz_json:get_ne_binary_value(<<"action">>, DeleteEvent),
    <<"object.*.user">> = kz_json:get_ne_binary_value(<<"subscribed_key">>, DeleteEvent),
    <<"doc_deleted">> = kz_json:get_ne_binary_value(<<"name">>, DeleteEvent),

    DeleteJObj = kz_json:get_json_value(<<"data">>, DeleteEvent),
    <<"user">> = kz_json:get_ne_binary_value(<<"type">>, DeleteJObj),
    'true' = kz_json:is_true(<<"is_soft_deleted">>, DeleteJObj),
    AccountId = kz_json:get_ne_binary_value(<<"account_id">>, DeleteJObj),
    UserId = kz_json:get_ne_binary_value(<<"id">>, DeleteJObj).

test_ws_unbind(API, WSConn, AccountId, SocketId, BindReq, Binding) ->
    UnbindReqId = kz_binary:rand_hex(4),
    UnbindReq = kz_json:set_values([{<<"action">>, <<"unsubscribe">>}
                                   ,{<<"request_id">>, UnbindReqId}
                                   ]
                                  ,BindReq
                                  ),
    _Send = pqc_ws_client:send(WSConn, kz_json:encode(UnbindReq)),
    {'json', UnbindReplyJObj} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("unbind reply: ~p", [UnbindReplyJObj]),
    <<"reply">> = kz_json:get_ne_binary_value(<<"action">>, UnbindReplyJObj),
    UnbindReqId = kz_json:get_ne_binary_value(<<"request_id">>, UnbindReplyJObj),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, UnbindReplyJObj),
    [Binding] = kz_json:get_list_value([<<"data">>, <<"unsubscribed">>], UnbindReplyJObj),

    NoDetailsResp = pqc_cb_websockets:details(API, AccountId, SocketId),
    lager:info("no details: ~s", [NoDetailsResp]),
    NoDetailsJObj = kz_json:decode(NoDetailsResp),
    [] = kz_json:get_list_value([<<"data">>, <<"bindings">>], NoDetailsJObj),

    MyIP = my_ip(),

    MyIP = kz_json:get_ne_binary_value([<<"data">>, <<"source">>], NoDetailsJObj),
    SocketId = kz_json:get_ne_binary_value([<<"data">>, <<"websocket_session_id">>], NoDetailsJObj).

test_empty_active_connections(API, AccountId) ->
    EmptySockets = pqc_cb_websockets:summary(API, AccountId),
    lager:info("empty summary: ~s", [EmptySockets]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySockets)).

test_channel_create(WSConn, API, AccountId) ->
    bind_for_channel_events(WSConn, API, AccountId),

    CallId = emit_channel_event(AccountId),

    recv_channel_event(WSConn, CallId, AccountId),

    OtherAccountId = kz_binary:rand_hex(16),
    OtherCallId = emit_channel_event(OtherAccountId),
    no_recv_channel_event(WSConn, OtherCallId, OtherAccountId),

    unbind_for_channel_events(WSConn, API, AccountId).

recv_channel_event(WSConn, CallId, AccountId) ->
    lager:info("recv event for call ~s in account ~s", [CallId, AccountId]),
    {'json', CallEvent} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("call event: ~p", [CallEvent]),
    CallId = kz_json:get_ne_binary_value([<<"data">>, <<"call_id">>], CallEvent),
    AccountId = kz_json:get_ne_binary_value([<<"data">>, <<"custom_channel_vars">>, <<"account_id">>], CallEvent),
    <<"CHANNEL_CREATE">> = kz_json:get_ne_binary_value([<<"name">>], CallEvent),
    <<"event">> = kz_json:get_ne_binary_value([<<"action">>], CallEvent),
    'ok'.

no_recv_channel_event(WSConn, CallId, AccountId) ->
    lager:info("recv event for call ~s in other account ~s", [CallId, AccountId]),
    {'error', 'timeout'} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("timed out waiting for ~s in ~s, as expected", [CallId, AccountId]).

unbind_for_channel_events(WSConn, #{auth_token := AuthToken}, AccountId) ->
    UnbindReqId = kz_binary:rand_hex(4),
    UnbindReq = kz_json:from_list([{<<"action">>, <<"unsubscribe">>}
                                  ,{<<"auth_token">>, AuthToken}
                                  ,{<<"request_id">>, UnbindReqId}
                                  ,{<<"data">>
                                   ,kz_json:from_list([{<<"account_id">>, AccountId}
                                                      ,{<<"binding">>, (Binding = <<"call.CHANNEL_CREATE.*">>)}
                                                      ])
                                   }
                                  ]),
    _Send = pqc_ws_client:send(WSConn, kz_json:encode(UnbindReq)),

    {'json', UnbindReplyJObj} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("unbind reply: ~p", [UnbindReplyJObj]),
    <<"reply">> = kz_json:get_ne_binary_value(<<"action">>, UnbindReplyJObj),
    UnbindReqId = kz_json:get_ne_binary_value(<<"request_id">>, UnbindReplyJObj),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, UnbindReplyJObj),
    [Binding] = kz_json:get_list_value([<<"data">>, <<"unsubscribed">>], UnbindReplyJObj),
    'ok'.

bind_for_channel_events(WSConn, #{auth_token := AuthToken}, AccountId) ->
    BindReqId = kz_binary:rand_hex(4),
    BindReq = kz_json:from_list([{<<"action">>, <<"subscribe">>}
                                ,{<<"auth_token">>, AuthToken}
                                ,{<<"request_id">>, BindReqId}
                                ,{<<"data">>
                                 ,kz_json:from_list([{<<"account_id">>, AccountId}
                                                    ,{<<"binding">>, (Binding = <<"call.CHANNEL_CREATE.*">>)}
                                                    ])
                                 }
                                ]),
    _Send = pqc_ws_client:send(WSConn, kz_json:encode(BindReq)),
    {'json', BindReplyJObj} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("bind reply: ~p", [BindReplyJObj]),
    <<"reply">> = kz_json:get_ne_binary_value(<<"action">>, BindReplyJObj),
    BindReqId = kz_json:get_ne_binary_value(<<"request_id">>, BindReplyJObj),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, BindReplyJObj),
    Bindings = kz_json:get_list_value([<<"data">>, <<"subscribed">>], BindReplyJObj),
    'true' = lists:member(Binding, Bindings).

emit_channel_event(AccountId) ->
    CallId = kz_binary:rand_hex(4),
    CallProps = [{<<"Event-Name">>, <<"CHANNEL_CREATE">>}
                ,{<<"Call-ID">>, CallId}
                ,{<<"variable_sip_req_uri">>, <<"request@domain.com">>}
                ,{<<"variable_sip_to_uri">>, <<"to@domain.com">>}
                ,{<<"variable_sip_from_uri">>, <<"from@domain.com">>}
                ,{<<"Call-Direction">>, <<"inbound">>}
                ,{<<"Custom-Channel-Vars">>, kz_json:from_list([{<<"Account-ID">>, AccountId}])}
                | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
                ],
    lager:info("publishing call event ~s", [CallId]),
    'ok' = kz_amqp_worker:cast(CallProps, fun kapi_call:publish_event/1),
    CallId.

disconnect_reconnect_amqp() ->
    _Disconnected = [disconnect(Connection) || Connection <- kz_amqp_connections:connections()],
    lager:info("disconnected: ~p", [_Disconnected]),
    timer:sleep(100),
    kz_amqp_connections:wait_for_available(5 * ?MILLISECONDS_IN_SECOND),
    lager:info("connection reconnected"),
    _ = blackhole_listener:wait_until_consuming(5 * ?MILLISECONDS_IN_SECOND),
    _ = kz_hooks_listener:wait_until_consuming(5 * ?MILLISECONDS_IN_SECOND),
    _ = kz_hooks_shared_listener:wait_until_consuming(5 * ?MILLISECONDS_IN_SECOND),
    lager:info("channel and bindings should be available").

disconnect(#kz_amqp_connections{connection=KZConn}) ->
    #kz_amqp_connection{connection=AMQPConn} = kz_amqp_connection:get_connection(KZConn),
    lager:info("exiting amqp conn ~p", [AMQPConn]),
    exit(AMQPConn, 'heartbeat_timeout').

my_ip() ->
    {'ok', IPTuple} = inet:getaddr(net_adm:localhost(), 'inet'),
    kz_network_utils:iptuple_to_binary(IPTuple).
