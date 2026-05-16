%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2020-2025, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_webhooks).

-export([user_webhook/0, user_webhook/2]).

%% Manual test functions
-export([seq/0
        ,cleanup/0

        ,seq_cp_29/0
        ,seq_include_meta/0
        ,seq_mweh_3/0
        ,seq_recv_events/0
        ,seq_resp_envelope/0
        ,seq_samples/0
        ,seq_security/0
        ,seq_url/0
        ]).

-include("properly.hrl").

-properly({standalone, [seq_recv_events/0
                       ,seq_include_meta/0
                       ,seq_url/0
                       ]}).

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-define(PORT(API), kz_json:get_integer_value([<<"default">>, <<"port">>]
                                            ,kz_json:decode(pqc_cb_system_configs:get_default_config(API, <<"blackhole">>))
                                            ,5555
                                            )
       ).

-define(CUSTOM_REQUEST_HEADERS, {<<"x-custom-webhook-header">>, <<?MODULE_STRING>>}).

-spec seq() -> 'ok'.
seq() ->
    properly_util:run_seq(?MODULE).

-spec seq_recv_events() -> 'ok'.
seq_recv_events() ->
    API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    ?INFO("created account: ~s", [AccountResp]),
    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    AuthAccountId = pqc_cb_api:auth_account_id(API),

    WHConfig = pqc_cb_system_configs:get_default_config(API, <<"webhooks.object">>),
    lager:info("get webhooks.object system config: ~s", [WHConfig]),
    WHData = pqc_cb_response:data(WHConfig),

    IncludeFields = kz_json:get_list_value([<<"default">>, <<"include_fields">>, <<"default">>], WHData),

    'true' = lists:all(fun(Fields) -> lists:member(Fields, IncludeFields) end
                      ,[<<"pvt_auth_user_id">>
                       ,<<"pvt_auth_account_id">>
                       ]
                      ),
    %% just a note, since properly uses API auth, no auth_user_id is on the doc

    EmptySummaryResp = pqc_cb_webhooks:summary(API, AccountId),
    lager:info("empty summary: ~s", [EmptySummaryResp]),
    'true' = ([] =:= kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryResp))),

    [Verb | _] = kz_term:shuffle_list([<<"put">>, <<"post">>]),
    Version = <<"v1">>,
    CreateResp = pqc_cb_webhooks:create(API, AccountId, user_webhook(Verb, Version)),
    lager:info("created hook: ~s", [CreateResp]),
    WebhookId = kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(CreateResp)),

    SummaryResp = pqc_cb_webhooks:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [WebhookSummary] = kz_json:get_list_value([<<"data">>], kz_json:decode(SummaryResp)),
    WebhookId = kz_doc:id(WebhookSummary),

    PatchKit = kz_json:from_list([{<<?MODULE_STRING>>, kz_binary:rand_hex(5)}]),
    PatchResp = pqc_cb_webhooks:patch(API, AccountId, WebhookId, PatchKit),
    lager:info("patch resp: ~s", [PatchResp]),
    'true' = kz_json:get_value(<<?MODULE_STRING>>, PatchKit)
        =:= kz_json:get_value([<<"data">>, <<?MODULE_STRING>>], kz_json:decode(PatchResp)),

    {UserPid, _Ref} = kz_process:spawn_monitor(fun create_user_and_wait/3, [self(), API, AccountId]),
    lager:info("managing user CRUD in ~p", [UserPid]),

    UserId = receive {UserPid, 'user_id', UID} -> UID end,
    lager:info("user ID is ~s", [UserId]),

    {_, CreatedHookQS} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("created event: ~s", [CreatedHookQS]),

    CreatedHookProps = kz_http_util:parse_query_string(CreatedHookQS),
    _ = validate_received_webhook(CreatedHookProps, AuthAccountId, UserId, AccountId, <<"doc_created">>),

    UserPid ! {'patch', kz_json:from_list([{<<"patch">>, kz_binary:rand_hex(4)}])},
    lager:info("patching user"),

    {_, PatchedHookQS} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("update event: ~s", [PatchedHookQS]),
    PatchedHookProps = kz_http_util:parse_query_string(PatchedHookQS),

    _ = validate_received_webhook(PatchedHookProps, AuthAccountId, UserId, AccountId, <<"doc_edited">>),

    UserPid ! 'delete',
    lager:info("deleting user"),

    {_, DeletedHookQS} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("delete event: ~s", [DeletedHookQS]),
    DeletedHookProps = kz_http_util:parse_query_string(DeletedHookQS),

    _ = validate_received_webhook(DeletedHookProps, AuthAccountId, UserId, AccountId, <<"doc_deleted">>),

    DeleteResp = pqc_cb_webhooks:delete(API, AccountId, WebhookId),
    lager:info("delete webhook: ~s", [DeleteResp]),

    EmptyAgainResp = pqc_cb_webhooks:summary(API, AccountId),

    lager:info("empty again summary: ~s", [EmptyAgainResp]),
    'true' = ([] =:= kz_json:get_list_value([<<"data">>], kz_json:decode(EmptyAgainResp))),
    cleanup(API, [AccountId]).

validate_received_webhook(HookProps, AuthAccountId, UserId, AccountId, Action) ->
    UserId = props:get_value(<<"id">>, HookProps),
    AccountId = props:get_value(<<"account_id">>, HookProps),
    AuthAccountId = props:get_value(<<"auth_account_id">>, HookProps),
    <<"user">> = props:get_value(<<"type">>, HookProps),
    Action = props:get_value(<<"action">>, HookProps).

-spec seq_samples() -> 'ok'.
seq_samples() ->
    API = initial_state(),

    AvailableResp = pqc_cb_webhooks:list_available(API),
    lager:info("available: ~s", [AvailableResp]),
    Available = kz_json:get_list_value(<<"data">>, kz_json:decode(AvailableResp)),
    'true' = ([] =/= Available),

    SamplesResp = pqc_cb_webhooks:samples(API),
    lager:info("samples: ~s", [SamplesResp]),
    Samples = [_|_] = kz_json:get_list_value(<<"data">>, kz_json:decode(SamplesResp)),

    lists:all(fun(SampleId) -> can_fetch_sample(API, SampleId) end, Samples),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    ?INFO("created account: ~s", [AccountResp]),
    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    SummaryResp = pqc_cb_webhooks:summary(API, AccountId),
    lager:info("summary: ~s", [SummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),

    cleanup(API, [AccountId]),
    lager:info("finished").

%% @doc disabling webhook should not fire event
-spec seq_mweh_3() -> 'ok'.
seq_mweh_3() ->
    API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    ?INFO("created account: ~s", [AccountResp]),
    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    AuthAccountId = pqc_cb_api:auth_account_id(API),

    EmptySummaryResp = pqc_cb_webhooks:summary(API, AccountId),
    lager:info("empty summary: ~s", [EmptySummaryResp]),
    'true' = ([] =:= kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryResp))),

    [Verb | _] = kz_term:shuffle_list([<<"put">>, <<"post">>]),
    Version = <<"v1">>,
    CreateResp = pqc_cb_webhooks:create(API, AccountId, user_webhook(Verb, Version)),
    lager:info("created hook: ~s", [CreateResp]),
    WebhookId = kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(CreateResp)),

    SummaryResp = pqc_cb_webhooks:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [WebhookSummary] = kz_json:get_list_value([<<"data">>], kz_json:decode(SummaryResp)),
    WebhookId = kz_doc:id(WebhookSummary),

    {UserPid, _Ref} = kz_process:spawn_monitor(fun create_user_and_wait/3, [self(), API, AccountId]),
    lager:info("managing user CRUD in ~p", [UserPid]),

    UserId = receive {UserPid, 'user_id', UID} -> UID end,
    lager:info("user ID is ~s", [UserId]),

    {_, CreatedHookQS} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("created event: ~s", [CreatedHookQS]),

    CreatedHookProps = kz_http_util:parse_query_string(CreatedHookQS),
    _ = validate_received_webhook(CreatedHookProps, AuthAccountId, UserId, AccountId, <<"doc_created">>),

    %% Now disable the webhook, then edit the user to generate a new webhook event
    PatchResp = pqc_cb_webhooks:patch(API, AccountId, WebhookId, kzd_webhooks:set_enabled(kz_json:new(), 'false')),
    lager:info("disabled via PATCH: ~s", [PatchResp]),

    UserPid ! {'patch', kz_json:from_list([{<<"patch">>, kz_binary:rand_hex(4)}])},
    lager:info("patching user"),
    receive {UserPid, 'patched', _Rev1} -> 'ok' end,

    {'error', 'timeout'} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 1200),
    lager:info("timed out, as expected"),

    %% Now re-enable the webhook, then edit the user to generate a new webhook event
    RePatchResp = pqc_cb_webhooks:patch(API, AccountId, WebhookId, kzd_webhooks:set_enabled(kz_json:new(), 'true')),
    lager:info("re-enabled via PATCH: ~s", [RePatchResp]),

    UserPid ! {'patch', kz_json:from_list([{<<"patch">>, kz_binary:rand_hex(4)}])},
    lager:info("re-patching user"),
    receive {UserPid, 'patched', _Rev2} -> 'ok' end,

    {_, PatchedHookQS} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("patched event: ~s", [PatchedHookQS]),

    %% Let's publish a conf change AMQP from a "remote" zone that disables the webhook again
    _ = publish_disabled(AccountId, WebhookId),

    UserPid ! {'patch', kz_json:from_list([{<<"patch">>, kz_binary:rand_hex(4)}])},
    lager:info("re-patching user to not recv event"),
    receive {UserPid, 'patched', _Rev3} -> 'ok' end,

    {'error', 'timeout'} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("timed out again, as expected"),

    ReRePatchResp = pqc_cb_webhooks:patch(API, AccountId, WebhookId, kzd_webhooks:set_enabled(kz_json:new(), 'true')),
    lager:info("re-re-enabled via PATCH: ~s", [ReRePatchResp]),

    UserPid ! 'delete',
    lager:info("deleting user"),
    receive {UserPid, 'deleted', _Rev4} -> 'ok' end,

    {_, DeletedHookQS} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("delete event: ~s", [DeletedHookQS]),
    DeletedHookProps = kz_http_util:parse_query_string(DeletedHookQS),

    _ = validate_received_webhook(DeletedHookProps, AuthAccountId, UserId, AccountId, <<"doc_deleted">>),

    DeleteResp = pqc_cb_webhooks:delete(API, AccountId, WebhookId),
    lager:info("delete webhook: ~s", [DeleteResp]),

    EmptyAgainResp = pqc_cb_webhooks:summary(API, AccountId),

    lager:info("empty again summary: ~s", [EmptyAgainResp]),
    'true' = ([] =:= kz_json:get_list_value([<<"data">>], kz_json:decode(EmptyAgainResp))),

    cleanup(API, [AccountId]).

-spec seq_cp_29() -> 'ok'.
seq_cp_29() ->
    API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    ?INFO("created account: ~s", [AccountResp]),
    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    test_channel_event_v1(<<"CHANNEL_CREATE">>, API, AccountId),

    test_channel_event_v2(<<"CHANNEL_CREATE">>, API, AccountId),

    test_user_events_v1(API, AccountId),

    test_user_events_v2(API, AccountId),

    cleanup(API, [AccountId]).

publish_channel_event(Event, AccountId) ->
    %% emit the call event on the account
    CallId = kz_binary:rand_hex(4),
    CallProps = [{<<"Event-Name">>, <<Event/binary>>}
                ,{<<"Call-ID">>, CallId}
                ,{<<"variable_sip_req_uri">>, <<"request@domain.com">>}
                ,{<<"variable_sip_to_uri">>, <<"to@domain.com">>}
                ,{<<"variable_sip_from_uri">>, <<"from@domain.com">>}
                ,{<<"Call-Direction">>, <<"inbound">>}
                ,{<<"Custom-Channel-Vars">>, kz_json:from_list([{<<"Account-ID">>, AccountId}])}
                | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
                ],
    lager:info("publishing call event ~s", [CallId]),
    'ok' = kz_amqp_worker:cast(CallProps, fun kapi_call:publish_event/1).

test_channel_event_v1(Event, API, AccountId) ->
    WebhookId = create_channel_event(Event, API, AccountId),
    timer:sleep(150), % let it get to webhooks

    publish_channel_event(Event, AccountId),

    %% receive the webhook call event
    {ReqHeaders, WebhookCallEvent} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),

    'true' = lists:member(?CUSTOM_REQUEST_HEADERS, kz_json:to_proplist(ReqHeaders)),

    lager:info("recv webhook call event: ~s", [WebhookCallEvent]),
    WebhookCallEventString = kz_http_util:parse_query_string(WebhookCallEvent),
    lager:info("webhook call event string: ~p", [WebhookCallEventString]),

    %% Delete a webhook
    DeleteResp = pqc_cb_webhooks:delete(API, AccountId, WebhookId),
    lager:info("delete call event webhook: ~s", [DeleteResp]).

create_channel_event(Event, API, AccountId) ->
    create_channel_event(Event, API, AccountId, 'undefined').

create_channel_event(Event, API, AccountId, Version) ->
    %% Create webhook
    URL = <<(pqc_httpd:base_url(kz_log:get_callid()))/binary, ?MODULE_STRING>>,
    Verb = <<"post">>,
    ModifiedUserDocs = [],

    Webhook = kz_json:exec_first([{fun kzd_webhooks:set_uri/2, URL}
                                 ,{fun kzd_webhooks:set_name/2, <<?MODULE_STRING, "_user">>}
                                 ,{fun kzd_webhooks:set_http_verb/2, Verb}
                                 ,{fun kzd_webhooks:set_hook/2, kz_term:to_lower_binary(Event)}
                                 ,{fun kzd_webhooks:set_custom_data/2, kz_json:from_list(ModifiedUserDocs)}
                                 ,{fun kzd_webhooks:set_version/2, Version}
                                 ,{fun kzd_webhooks:set_custom_request_headers/2, kz_json:from_list([?CUSTOM_REQUEST_HEADERS])}
                                 ]
                                ,kzd_webhooks:new()
                                ),
    CreateResp = pqc_cb_webhooks:create(API, AccountId, Webhook),
    lager:info("created call event hook: ~s", [CreateResp]),
    kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(CreateResp)).

bind_for_wss(Event, #{'auth_token' := AuthToken} = API, AccountId) ->
    %% Open websocket connection
    {'ok', WSConn} = pqc_ws_client:connect("localhost", ?PORT(API)),
    lager:info("connected to websocket: ~p", [WSConn]),

    %% bind on account and auth-account
    BindReqId = kz_binary:rand_hex(4),
    BindReq = kz_json:from_list([{<<"action">>, <<"subscribe">>}
                                ,{<<"auth_token">>, AuthToken}
                                ,{<<"request_id">>, BindReqId}
                                ,{<<"data">>
                                 ,kz_json:from_list([{<<"account_id">>, AccountId}
                                                    ,{<<"binding">>, (<<"call.", Event/binary, ".*">>)}
                                                    ])
                                 }
                                ]),
    _Send = pqc_ws_client:send(WSConn, kz_json:encode(BindReq)),
    {'json', BindReplyJObj} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("bind reply: ~p", [BindReplyJObj]),
    WSConn.

unbind_for_wss(Event, #{'auth_token' := AuthToken}, AccountId, WSConn) ->
    %% unbind on auth-account
    UnbindReqId = kz_binary:rand_hex(4),
    UnbindReq = kz_json:from_list([{<<"action">>, <<"unsubscribe">>}
                                  ,{<<"auth_token">>, AuthToken}
                                  ,{<<"request_id">>, UnbindReqId}
                                  ,{<<"data">>
                                   ,kz_json:from_list([{<<"account_id">>, AccountId}
                                                      ,{<<"binding">>, (<<"call.", Event/binary, ".*">>)}
                                                      ])
                                   }
                                  ]),
    _ = pqc_ws_client:send(WSConn, kz_json:encode(UnbindReq)),
    {'json', UnbindReplyJObj} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("unbind reply: ~p", [UnbindReplyJObj]).

test_channel_event_v2(Event, API, AccountId) ->
    WebhookId = create_channel_event(Event, API, AccountId, <<"v2">>),

    WSConn = bind_for_wss(Event, API, AccountId),

    publish_channel_event(Event, AccountId),

    %% receive the webhook call event
    {_, WebhookCallEvent} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv webhook call event: ~s", [WebhookCallEvent]),
    WebhookCallEventString = kz_http_util:parse_query_string(WebhookCallEvent),
    WebhookCallEventArrays = kz_http_util:parse_query_arrays(WebhookCallEventString),
    WebhookCallEventJObj = kz_json:from_list(WebhookCallEventArrays),
    lager:info("webhook call event JObj: ~p", [WebhookCallEventJObj]),

    %% receive the websocket call event
    {'json', WebsocketCallEvent} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv websocket call event: ~p", [WebsocketCallEvent]),

    %% compare call event webhook vs websocket
    'true' = test_v2_events(WebhookCallEventJObj, WebsocketCallEvent),

    %% Delete a webhook
    DeleteResp = pqc_cb_webhooks:delete(API, AccountId, WebhookId),
    lager:info("delete call event webhook: ~s", [DeleteResp]),

    unbind_for_wss(Event, API, AccountId, WSConn),

    %% Close connection
    pqc_ws_client:close(WSConn).

%% KWEB-15, v2 format for webhooks object is changed. Blackhole should be updated to match,
%% But in the meantime, this test case is alterted to reflect the de-snyc.
-define(PRIVATE_AMQP_FIELDS,
        [[<<"data">>, <<"node">>]
        ,[<<"data">>, <<"message_id">>]
        ,[<<"data">>, <<"server_id">>]
        ,[<<"data">>, <<"origin_cache">>]
        ,[<<"data">>, <<"app_name">>]
        ,[<<"data">>, <<"app_version">>]
        ,[<<"data">>, <<"event_name">>]
        ,[<<"data">>, <<"event_category">>]
        ,[<<"data">>, <<"msg_id">>]
        ]).

test_v2_events(WebhookEvent, WebsocketEvent) ->
    WebEvent = kz_json:delete_keys([<<"timestamp">>, <<"hmac">>
                                   ,[<<"data">>, <<"is_soft_deleted">>]
                                   ,[<<"data">>, <<"date_modified">>]
                                   ,[<<"data">>, <<"date_created">>]
                                   ,[<<"data">>, <<"doc">>]
                                   ,[<<"data">>, <<"metadata">>]
                                   ]
                                  ,WebhookEvent
                                  ),
    SockEvent = kz_json:delete_keys([<<"routing_key">>
                                    ,<<"subscription_key">>
                                    ,<<"subscribed_key">>
                                    ,[<<"data">>, <<"is_soft_deleted">>]
                                    ,[<<"data">>, <<"date_modified">>]
                                    ,[<<"data">>, <<"date_created">>]
                                    ] ++ ?PRIVATE_AMQP_FIELDS
                                   ,WebsocketEvent
                                   ),

    ?DEV_LOG("~n Webhook Event: ~p ~n Socket Event: ~p ~n", [WebEvent, SockEvent]),

    kz_json:are_equal(WebEvent, SockEvent).

test_user_events_v1(API, AccountId) ->
    %% Create webhook
    Verb = <<"post">>,
    CreateResp = pqc_cb_webhooks:create(API, AccountId, user_webhook(Verb, <<"v1">>)),
    lager:info("created user event hook: ~s", [CreateResp]),
    WebhookId = kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(CreateResp)),

    %% somewhere there's a delay between the webhooks app
    %% recv/processing this webhook, and the user being created below
    timer:sleep(100),

    %% emit the create user event
    {UserPid, _Ref} = kz_process:spawn_monitor(fun create_user_and_wait/3, [self(), API, AccountId]),
    lager:info("managing user CRUD in ~p", [UserPid]),
    UserId = receive {UserPid, 'user_id', UID} -> UID end,
    lager:info("user ID is ~s", [UserId]),

    %% receive the webhook create user event
    {_, WebhookCreateUserEvent} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv webhook create user event: ~s", [WebhookCreateUserEvent]),
    WebhookCreateUserEventString = kz_http_util:parse_query_string(WebhookCreateUserEvent),
    lager:info("webhook create user event: ~p", [WebhookCreateUserEventString]),

    %% emit the patch user event
    UserPid ! {'patch', kz_json:from_list([{<<"patch">>, kz_binary:rand_hex(4)}])},
    lager:info("patching user"),
    receive {UserPid, 'patched', _Rev1} -> 'ok' end,

    %% receive the webhook update user event
    {_, WebhookUpdateUserEvent} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv webhook update user event: ~s", [WebhookUpdateUserEvent]),
    WebhookUpdateUserEventString = kz_http_util:parse_query_string(WebhookUpdateUserEvent),
    lager:info("webhook update user event: ~p", [WebhookUpdateUserEventString]),

    %% emit the delete user event
    UserPid ! 'delete',
    lager:info("deleting user"),
    receive {UserPid, 'deleted', _Rev2} -> 'ok' end,

    %% receive the webhook delete user event
    {_, WebhookDeleteUserEvent} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv webhook delete user event: ~s", [WebhookDeleteUserEvent]),
    WebhookDeleteUserEventString = kz_http_util:parse_query_string(WebhookDeleteUserEvent),
    lager:info("webhook delete user event: ~p", [WebhookDeleteUserEventString]),

    %% Delete a webhook
    DeleteResp = pqc_cb_webhooks:delete(API, AccountId, WebhookId),
    lager:info("delete user event webhook: ~s", [DeleteResp]).

test_user_events_v2(#{'auth_token' := AuthToken} = API, AccountId) ->
    %% Create webhook
    Verb = <<"post">>,
    CreateResp = pqc_cb_webhooks:create(API, AccountId, user_webhook(Verb, <<"v2">>)),
    lager:info("created user event hook: ~s", [CreateResp]),
    WebhookId = kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(CreateResp)),

    %% Open websocket connection
    {'ok', WSConn} = pqc_ws_client:connect("localhost", ?PORT(API)),
    lager:info("connected to websocket: ~p", [WSConn]),

    %% bind on account and auth-account
    BindReqId = kz_binary:rand_hex(4),
    Binding = <<"object.*.user">>,
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

    %% emit the create user event
    {UserPid, _Ref} = kz_process:spawn_monitor(fun create_user_and_wait/3, [self(), API, AccountId]),
    lager:info("managing user CRUD in ~p", [UserPid]),
    UserId = receive {UserPid, 'user_id', UID} -> UID end,
    lager:info("user ID is ~s", [UserId]),

    %% receive the webhook create user event
    {_, WebhookCreateUserEvent} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv webhook create user event: ~s", [WebhookCreateUserEvent]),
    WebhookCreateUserEventString = kz_http_util:parse_query_string(WebhookCreateUserEvent),
    WebhookCreateUserEventArrays = kz_http_util:parse_query_arrays(WebhookCreateUserEventString),
    WebhookCreateUserEventJObj = kz_json:from_list(WebhookCreateUserEventArrays),
    lager:info("webhook create user event JObj: ~p", [WebhookCreateUserEventJObj]),

    %% receive the websocket create user event
    {'json', WebsocketCreateUserEvent} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv websocket create user event: ~p", [WebsocketCreateUserEvent]),

    'true' = test_v2_events(WebhookCreateUserEventJObj, WebsocketCreateUserEvent),

    %% emit the patch user event
    UserPid ! {'patch', kz_json:from_list([{<<"patch">>, kz_binary:rand_hex(4)}])},
    lager:info("patching user"),
    receive {UserPid, 'patched', _Rev1} -> 'ok' end,

    %% receive the webhook update user event
    {_, WebhookUpdateUserEvent} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv webhook update user event: ~s", [WebhookUpdateUserEvent]),
    WebhookUpdateUserEventString = kz_http_util:parse_query_string(WebhookUpdateUserEvent),
    WebhookUpdateUserEventArrays = kz_http_util:parse_query_arrays(WebhookUpdateUserEventString),
    WebhookUpdateUserEventJObj = kz_json:from_list(WebhookUpdateUserEventArrays),
    lager:info("webhook update user event JObj: ~p", [WebhookUpdateUserEventJObj]),

    %% receive the websocket update user event
    {'json', WebsocketUpdateUserEvent} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv websocket update user event: ~p", [WebsocketUpdateUserEvent]),

    'true' = test_v2_events(WebhookUpdateUserEventJObj, WebsocketUpdateUserEvent),

    %% emit the delete user event
    UserPid ! 'delete',
    lager:info("deleting user"),
    receive {UserPid, 'deleted', _Rev2} -> 'ok' end,

    %% receive the webhook delete user event
    {_, WebhookDeleteUserEvent} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv webhook delete user event: ~s", [WebhookDeleteUserEvent]),
    WebhookDeleteUserEventString = kz_http_util:parse_query_string(WebhookDeleteUserEvent),
    WebhookDeleteUserEventArrays = kz_http_util:parse_query_arrays(WebhookDeleteUserEventString),
    WebhookDeleteUserEventJObj = kz_json:from_list(WebhookDeleteUserEventArrays),
    lager:info("webhook delete user event JObj: ~p", [WebhookDeleteUserEventJObj]),

    %% receive the websocket delete user event
    {'json', WebsocketDeleteUserEvent} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv websocket delete user event: ~p", [WebsocketDeleteUserEvent]),

    'true' = test_v2_events(WebhookDeleteUserEventJObj, WebsocketDeleteUserEvent),

    %% Delete a webhook
    DeleteResp = pqc_cb_webhooks:delete(API, AccountId, WebhookId),
    lager:info("delete user event webhook: ~s", [DeleteResp]),

    %% unbind on auth-account
    UnbindReqId = kz_binary:rand_hex(4),
    UnbindReq = kz_json:from_list([{<<"action">>, <<"unsubscribe">>}
                                  ,{<<"auth_token">>, AuthToken}
                                  ,{<<"request_id">>, UnbindReqId}
                                  ,{<<"data">>
                                   ,kz_json:from_list([{<<"account_id">>, AccountId}
                                                      ,{<<"binding">>, Binding}
                                                      ])
                                   }
                                  ]),
    _ = pqc_ws_client:send(WSConn, kz_json:encode(UnbindReq)),
    {'json', UnbindReplyJObj} = pqc_ws_client:recv(WSConn, 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("unbind reply: ~p", [UnbindReplyJObj]),

    %% Close connection
    pqc_ws_client:close(WSConn).

-spec initial_state() -> pqc_cb_api:state().
initial_state() ->
    API = pqc_cb_api:init_api(['crossbar', 'webhooks']
                             ,['cb_webhooks', 'cb_users', 'cb_system_configs']
                             ),

    patch_validate_dns(API, 'false'),

    {'ok', HTTPD} = pqc_httpd:start_link(kz_log:get_callid()),
    ?INFO("HTTPD started: ~p", [HTTPD]),
    API#{httpd => HTTPD}.

patch_validate_dns(API, PatchValue) ->
    Config = pqc_cb_system_configs:patch_default_config(API
                                                       ,<<"kazoo_web">>
                                                       ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"should_validate_dns">>, PatchValue}])}])
                                                       ),
    lager:info("patched should_validate_dns ~p: ~s", [PatchValue, Config]).

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = properly_maintenance:cleanup_module_accounts(?MODULE),
    API = pqc_cb_api:init_api(['crossbar'], ['cb_system_configs']),
    patch_validate_dns(API, 'true').

cleanup(API, Accounts) ->
    lager:info("cleanup time, everybody helps"),
    _ = seq_accounts:cleanup_accounts(API, Accounts),
    patch_to_allow_restricted_ips(API),
    _ = pqc_cb_api:cleanup(API),

    kz_process:flush_mailbox('true'),
    patch_validate_dns(API, 'true').

can_fetch_sample(API, SampleId) ->
    SampleResp = pqc_cb_webhooks:sample(API, SampleId),
    lager:info("sample for ~s: ~s", [SampleId, SampleResp]),
    [] =/= kz_json:get_list_value(<<"data">>, kz_json:decode(SampleResp)).

-spec user_webhook() -> kzd_webhooks:doc().
user_webhook() ->
    user_webhook(<<"post">>, <<"v1">>).

-spec user_webhook(kz_term:ne_binary(), kz_term:ne_binary()) -> kzd_webhooks:doc().
user_webhook(Verb, Version) ->
    user_webhook(Verb, Version, 'null').

user_webhook(Verb, Version, SecurityKey) ->
    user_webhook(Verb, Version, SecurityKey, <<"form-data">>).

user_webhook(Verb, Version, SecurityKey, Format) ->
    URL = <<(pqc_httpd:base_url(kz_log:get_callid()))/binary, ?MODULE_STRING>>,

    ModifiedUserDocs = [{<<"type">>, kzd_users:type()}
                       ,{<<"action">>, <<"all">>}
                       ],

    Webhook = kz_json:exec_first([{fun kzd_webhooks:set_uri/2, URL}
                                 ,{fun kzd_webhooks:set_name/2, <<?MODULE_STRING, "_user">>}
                                 ,{fun kzd_webhooks:set_http_verb/2, Verb}
                                 ,{fun kzd_webhooks:set_hook/2, <<"object">>}
                                 ,{fun kzd_webhooks:set_custom_data/2, kz_json:from_list(ModifiedUserDocs)}
                                 ,{fun kzd_webhooks:set_version/2, Version}
                                 ,{fun kzd_webhooks:set_format/2, Format}
                                 ,{fun kzd_webhooks:set_security_settings_sha256_key/2, SecurityKey}

                                 ]
                                ,kzd_webhooks:new()
                                ),
    kz_doc:public_fields(Webhook).

create_user_and_wait(ParentPid, API, AccountId) ->
    kz_log:put_callid(kz_term:to_binary(ParentPid)),
    UserDoc = seq_users:new_user(),
    UserResp = pqc_cb_users:create(API, AccountId, UserDoc),
    lager:info("~p: ~p ! user resp: ~s", [self(), ParentPid, UserResp]),

    UserId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(UserResp)),

    ParentPid ! {self(), 'user_id', UserId},
    wait_for_instructions(ParentPid, API, AccountId, UserId).

wait_for_instructions(ParentPid, API, AccountId, UserId) ->
    receive
        {'patch', PatchJObj} ->
            PatchResp = pqc_cb_users:patch(API, AccountId, UserId, PatchJObj),
            lager:info("~p: tell parent:~p ! patched: ~s", [self(), ParentPid, PatchResp]),
            ParentPid ! {self(), 'patched', kz_json:get_ne_binary_value(<<"revision">>, kz_json:decode(PatchResp))},
            wait_for_instructions(ParentPid, API, AccountId, UserId);
        'delete' ->
            DeleteResp = pqc_cb_users:delete(API, AccountId, UserId),
            lager:info("~p: ~p ! deleted: ~s", [self(), ParentPid, DeleteResp]),
            ParentPid ! {self(), 'deleted', kz_json:get_ne_binary_value(<<"revision">>, kz_json:decode(DeleteResp))},
            lager:info("and now my watch has ended")
    end.

-spec seq_url() -> any().
seq_url() ->
    API = initial_state(),

    patch_to_disallow_restricted_ips(API),
    patch_validate_dns(API, 'true'),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    ?INFO("created account: ~s", [AccountResp]),
    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    _ = [try_bad_url(API, AccountId, URL) || URL <- bad_urls()],

    lager:info("completed successfully!"),
    _ = cleanup(API, [AccountId]).

try_bad_url(API, AccountId, URL) ->
    CreateResp = pqc_cb_webhooks:create(API, AccountId, bad_url_webhook(URL)),
    lager:info("should fail create: ~p", [CreateResp]),
    {'error', ErrorResp} = CreateResp,
    lager:info("create resp failed with url ~s: ~s", [URL, ErrorResp]),

    Error = kz_json:decode(ErrorResp),
    400 = kz_json:get_integer_value(<<"error">>, Error),
    URL = kz_json:get_ne_binary_value([<<"data">>, <<"uri">>, <<"error">>, <<"value">>], Error),
    <<"error">> = kz_json:get_ne_binary_value(<<"status">>, Error).

%% @doc test "version" in auth'd req but not in unauth'd
-spec seq_resp_envelope() -> 'ok'.
seq_resp_envelope() ->
    API = initial_state(),

    AuthdResp = pqc_cb_webhooks:list_available(API),
    AuthdJObj = kz_json:decode(AuthdResp),
    'true' = kz_json:is_defined(<<"version">>, AuthdJObj),

    UnAuthdResp = pqc_cb_webhooks:list_available(API#{auth_token => 'undefined'}),
    UnAuthdJObj = kz_json:decode(UnAuthdResp),
    'false' = kz_json:is_defined(<<"version">>, UnAuthdJObj),
    lager:info("version doesn't appear in un-authenticated request"),

    cleanup(API, []).

bad_urls() ->
    [<<"https://localhost:345/webhook">>, <<"https://username@password:localhost:345/webhook">>
    ,<<"http://0:5984/_replicate//">>, <<"http://username@password:0:5984/_replicate//">>
    ,<<"https://192.168.6.8:0/">>, <<"https://username@password:192.168.6.8:0/">>

         %% resolves to localhost
         %% https://gist.github.com/tinogomes/c425aa2a56d289f16a1f4fcb8a65ea65
    ,<<"http://thisia.localtest.me/">>
    ,<<"http://domaincontrol.com:20548/">>
    ].

bad_url_webhook(URI) ->
    kz_doc:setters(kzd_webhooks:new()
                  ,[{fun kzd_webhooks:set_name/2, <<?MODULE_STRING>>}
                   ,{fun kzd_webhooks:set_hook/2, <<"channel_destroy">>}
                   ,{fun kzd_webhooks:set_uri/2, URI}
                   ]).

%% @doc set doc keys for user docs in system_config, generate user and
%% check that expected keys are present in the webhook data received
-spec seq_include_meta() -> 'ok'.
seq_include_meta() ->
    API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    ?INFO("created account: ~s", [AccountResp]),
    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    Settings = kz_json:set_value([<<"include_fields">>, kzd_users:type()]
                                ,[<<"first_name">>, <<"last_name">>]
                                ,kz_json:new()
                                ),
    PatchConfig = pqc_cb_system_configs:set_default_config(API
                                                          ,kz_json:from_list([{<<"default">>, Settings}
                                                                             ,{<<"id">>, <<"webhooks.object">>}
                                                                             ])
                                                          ),
    lager:info("patched system config: ~s", [PatchConfig]),

    EmptySummaryResp = pqc_cb_webhooks:summary(API, AccountId),
    lager:info("empty summary: ~s", [EmptySummaryResp]),
    'true' = ([] =:= kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryResp))),

    [Verb | _] = kz_term:shuffle_list([<<"put">>, <<"post">>]),
    Version = <<"v1">>,
    CreateResp = pqc_cb_webhooks:create(API, AccountId, user_webhook(Verb, Version)),
    lager:info("created hook: ~s", [CreateResp]),
    WebhookId = kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(CreateResp)),

    SummaryResp = pqc_cb_webhooks:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [WebhookSummary] = kz_json:get_list_value([<<"data">>], kz_json:decode(SummaryResp)),
    WebhookId = kz_doc:id(WebhookSummary),

    {UserPid, _Ref} = kz_process:spawn_monitor(fun create_user_and_wait/3, [self(), API, AccountId]),
    lager:info("managing user CRUD in ~p", [UserPid]),
    UserId = receive {UserPid, 'user_id', UID} -> UID end,
    lager:info("user ID is ~s", [UserId]),

    {_, CreatedHookQS} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("created event: ~s", [CreatedHookQS]),

    CreatedHookProps = kz_http_util:parse_query_string(CreatedHookQS),
    'true' = <<"user">> =:= props:get_value(<<"type">>, CreatedHookProps),
    'true' = <<"doc_created">> =:= props:get_value(<<"action">>, CreatedHookProps),
    <<FirstName/binary>> = props:get_value(<<"first_name">>, CreatedHookProps),
    <<LastName/binary>> = props:get_value(<<"last_name">>, CreatedHookProps),

    lager:info("expected extra values are present: ~s ~s", [FirstName, LastName]),

    UnSettings = kz_json:set_value([<<"include_fields">>, kzd_users:type()], [], kz_json:new()),
    UnPatchConfig = pqc_cb_system_configs:patch_default_config(API
                                                              ,<<"webhooks.object">>
                                                              ,kz_json:from_list([{<<"default">>, UnSettings}])
                                                              ),
    lager:info("unpatched system config: ~s", [UnPatchConfig]),

    cleanup(API, [AccountId]).

%% test HMAC hash inclusion on webhooks with security settings
-spec seq_security() -> 'ok'.
seq_security() ->
    API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    ?INFO("created account: ~s", [AccountResp]),
    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    SharedKey = kz_binary:rand_hex(8),

    Webhook = user_webhook(<<"post">>, <<"v2">>, SharedKey, <<"json">>),
    CreateResp = pqc_cb_webhooks:create(API, AccountId, Webhook),
    lager:info("created webhook: ~s", [CreateResp]),
    WebhookId = kz_doc:id(kz_json:get_json_value(<<"metadata">>, kz_json:decode(CreateResp))),
    lager:info("created webhook ~s with key ~s", [WebhookId, SharedKey]),

    %% emit the create user event
    {UserPid, _Ref} = kz_process:spawn_monitor(fun create_user_and_wait/3, [self(), API, AccountId]),
    lager:info("managing user CRUD in ~p", [UserPid]),
    UserId = receive {UserPid, 'user_id', UID} -> UID end,
    lager:info("user ID is ~s", [UserId]),

    %% receive the webhook create user event
    {_, WebhookEvent} = pqc_httpd:fetch_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("recv webhook event: ~s", [WebhookEvent]),
    WebhookEventJObj = kz_json:decode(WebhookEvent),

    <<"event">> = kz_json:get_ne_binary_value(<<"action">>, WebhookEventJObj),
    <<"doc_created">> = kz_json:get_ne_binary_value(<<"name">>, WebhookEventJObj),
    <<"user">> = kz_json:get_ne_binary_value([<<"data">>, <<"type">>], WebhookEventJObj),
    AccountId = kz_json:get_ne_binary_value([<<"data">>, <<"account_id">>], WebhookEventJObj),
    UserId = kz_json:get_ne_binary_value([<<"data">>, <<"id">>], WebhookEventJObj),

    Data = kz_json:get_json_value(<<"data">>, WebhookEventJObj),
    <<Timestamp/binary>> = kz_json:get_ne_binary_value([<<"timestamp">>], WebhookEventJObj),
    <<HMAC/binary>> = kz_json:get_ne_binary_value(<<"hmac">>, WebhookEventJObj),

    lager:info("hmac: ~s", [HMAC]),
    lager:info("hash ~s, ~s ~s", [SharedKey, Timestamp, kz_json:encode(Data, ['canonical'])]),

    HMAC = base64:encode(crypto:mac('hmac', 'sha256', SharedKey, <<Timestamp/binary, (kz_json:encode(Data, ['canonical']))/binary>>)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED SEQ_SECURITY").

publish_disabled(AccountId, WebhookId) ->
    %% First, disable the webhook but suppress the change notice
    {'ok', Webhook} = kz_datamgr:open_cache_doc(?KZ_WEBHOOKS_DB, WebhookId),
    {'ok', Saved} = kz_datamgr:save_doc(?KZ_WEBHOOKS_DB
                                       ,kzd_webhooks:set_enabled(Webhook, 'false')
                                       ,[{'publish_change_notice', 'false'}]
                                       ),
    lager:info("disabling webhook ~s (~s) but not publishing the change", [WebhookId, kz_doc:revision(Saved)]),

    EventName = <<"doc_edited">>,
    Type = kzd_webhooks:type(),

    Props = props:filter_undefined(
              [{<<"ID">>, WebhookId}
              ,{<<"Origin-Cache">>, <<?MODULE_STRING>>}
              ,{<<"Type">>, Type}
              ,{<<"Database">>, ?KZ_WEBHOOKS_DB}
              ,{<<"Rev">>, kz_doc:revision(Saved)}
              ,{<<"Account-ID">>, AccountId}
              ,{<<"Date-Modified">>, kz_time:now_s()}
              ,{<<"Date-Created">>, kz_time:now_s()}
              ,{<<"Is-Soft-Deleted">>, 'false'}
              ,{<<"Node">>, <<?MODULE_STRING"@some.host">>}
              | kz_api:default_headers(<<"configuration">>
                                      ,EventName
                                      ,?APP_NAME
                                      ,?APP_VERSION
                                      )
              ]),
    Fun = fun(P) -> kapi_conf:publish_doc_update('edited', ?KZ_WEBHOOKS_DB, kzd_webhooks:type(), WebhookId, P) end,
    lager:info("publishing change from a different node ~p", [Props]),
    'ok' = kz_amqp_worker:cast(Props, Fun),
    %% let the message percolate through KAZOO
    timer:sleep(100).

patch_to_disallow_restricted_ips(API) ->
    patch_restricted_ips(API, 'false').

patch_to_allow_restricted_ips(API) ->
    patch_restricted_ips(API, 'true').

patch_restricted_ips(API, ShouldAllow) ->
    CBConfig = pqc_cb_system_configs:patch_default_config(API
                                                         ,<<"kazoo_web">>
                                                         ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"allow_restricted_ips">>, ShouldAllow}])}])
                                                         ),
    lager:info("patched restricted ips ~p: ~s", [ShouldAllow, CBConfig]).
