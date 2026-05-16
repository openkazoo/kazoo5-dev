%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2025-, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_j5_channels).

-export([seq/0
        ,seq_limits/0
        ,seq_kjon_3/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-properly({standalone, [seq_kjon_3/0]}).

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-define(WAIT_AFTER_DELETE, 1500).
-define(WAIT_AFTER_UPDATE, 1500).

-spec seq() -> 'ok'.
seq() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun seq_limits/0
                  ,fun seq_kjon_3/0
                  ]).

-spec seq_limits() -> 'ok'.
seq_limits() ->
    API = pqc_cb_api:init_api(['crossbar', 'jonny5']
                             ,['cb_accounts', 'cb_limits']
                             ),
    AccountId = create_account(API, ?ACCOUNT_NAME),
    ResellerId = reseller_id(API, AccountId),

    _ = pqc_cb_phone_numbers:add_number(API
                                       ,AccountId
                                       ,<<"+14157900000">>
                                       ,kz_json:from_list([{<<"carrier_name">>, <<"knm_inventory">>}])
                                       ),
    _ = update_limits(API, pqc_cb_api:auth_account_id(API), 2),
    _ = update_limits(API, AccountId, 2),

    j5_channels:flush(),

    CallId1 = kz_binary:rand_hex(5),
    CallId2 = kz_binary:rand_hex(5),
    CallId3 = kz_binary:rand_hex(5),
    CallId4 = kz_binary:rand_hex(5),

    %% FIXME: previously authz was running on both directions
    %% then after a refactor the code was removed, then it was added back
    %% but only for inbound direction.
    %% Also code is update to skip authz for not billable number, currently again for
    %% inbound call only. changing the direction here to outbound so this test limits here.
    %% But when the j5_authz_req is adjusted for both dierction
    %% this test need to find a way to add numbers which are billable to make this
    %% test works.

    _ = send_channel_create(AccountId, ResellerId, CallId1, 'undefined', <<"outbound">>),
    {'ok', Resp1} = send_authz_req(AccountId, ResellerId, CallId1, 'undefined', <<"outbound">>),
    'true' = is_authorized(Resp1),
    1 = query_limits(AccountId),
    lager:info("first channel ~s authorized successfully", [CallId1]),

    _ = send_channel_create(AccountId, ResellerId, CallId2, 'undefined', <<"outbound">>),
    {'ok', Resp2} = send_authz_req(AccountId, ResellerId, CallId2, 'undefined', <<"outbound">>),
    'true' = is_authorized(Resp2),
    2 = query_limits(AccountId),
    lager:info("second channel ~s authorized successfully", [CallId2]),

    _ = send_channel_create(AccountId, ResellerId, CallId3, 'undefined', <<"outbound">>),
    {'ok', Resp3} = send_authz_req(AccountId, ResellerId, CallId3, 'undefined', <<"outbound">>),
    lager:info("should not be authz: ~p", [Resp3]),
    'false' = is_authorized(Resp3),
    3 = query_limits(AccountId),

    lager:info("third channel ~s failed to authorize", [CallId3]),

    _ = send_channel_destroy(AccountId, ResellerId, CallId3, 'undefined', <<"outbound">>),
    _ = timer:sleep(?WAIT_AFTER_DELETE),
    2 = query_limits(AccountId),
    _ = send_channel_destroy(AccountId, ResellerId, CallId1),
    _ = send_channel_destroy(AccountId, ResellerId, CallId2),
    _ = timer:sleep(?WAIT_AFTER_DELETE),
    0 = query_limits(AccountId),

    _ = update_limits(API, AccountId, 0),
    _ = timer:sleep(?WAIT_AFTER_UPDATE),

    _ = send_channel_create(AccountId, ResellerId, CallId4, 'undefined', <<"outbound">>),
    {'ok', Resp4} = send_authz_req(AccountId, ResellerId, CallId4, 'undefined', <<"outbound">>),
    'false' = is_authorized(Resp4),
    1 = query_limits(AccountId),
    _ = send_channel_destroy(AccountId, ResellerId, CallId4),
    _ = timer:sleep(?WAIT_AFTER_DELETE),

    0 = query_limits(AccountId),

    cleanup(API, [AccountId]).

-spec seq_kjon_3() -> 'ok'.
seq_kjon_3() ->
    API = pqc_cb_api:init_api(['crossbar', 'jonny5']
                             ,['cb_accounts', 'cb_limits']
                             ),
    AccountId = create_account(API, ?ACCOUNT_NAME),
    ResellerId = reseller_id(API, AccountId),

    %% Default bypass are for 'emergency' and 'tollfree_us' 'outbound'
    EmergencyCallId = kz_binary:rand_hex(4),
    TollFreeUSCallId = kz_binary:rand_hex(4),
    CaribbeanCallId = kz_binary:rand_hex(4),

    _ = send_channel_create(AccountId, ResellerId, EmergencyCallId, <<"emergency">>),
    {'ok', EmergencyResp} = send_authz_req(AccountId, ResellerId, EmergencyCallId, <<"emergency">>),
    lager:info("authz resp: ~p", [EmergencyResp]),
    _ = send_channel_destroy(AccountId, ResellerId, EmergencyCallId, <<"emergency">>),

    'true' = is_authorized(EmergencyResp),

    %% TODO: Create a call and authz request for tollfree_us outbound
    _ = send_channel_create(AccountId, ResellerId, TollFreeUSCallId, <<"tollfree_us">>, <<"outbound">>),
    {'ok', TollFreeUSResp} = send_authz_req(AccountId, ResellerId, TollFreeUSCallId, <<"tollfree_us">>, <<"outbound">>),
    lager:info("authz resp: ~p", [TollFreeUSResp]),
    _ = send_channel_destroy(AccountId, ResellerId, TollFreeUSCallId, <<"tollfree_us">>, <<"outbound">>),

    'true' = is_authorized(TollFreeUSResp),

    %% Patch system_config to add a carribiean classifier bypass
    FetchConfig = pqc_cb_system_configs:get_default_config(API, <<"jonny5">>),
    lager:info("fetched config: ~s", [FetchConfig]),

    J5Config = kz_json:decode(FetchConfig),

    BaseBypass = kz_json:get_list_value([<<"data">>, <<"default">>, <<"bypass_authz_classifiers">>]
                                       ,J5Config
                                       ),
    NewBypass = [kz_json:from_list([{<<"classifier">>, <<"caribbean">>}])
                | BaseBypass
                ],

    NewConfig = kz_json:from_list([{<<"default">>
                                   ,kz_json:from_list([{<<"bypass_authz_classifiers">>, NewBypass}])}
                                  ]
                                 ),

    _SavedConfig = pqc_cb_system_configs:patch_default_config(API
                                                             ,<<"jonny5">>
                                                             ,NewConfig
                                                             ),
    lager:info("saved config: ~s", [_SavedConfig]),

    %% TODO: Create a call with a number matching that classifier
    _ = send_channel_create(AccountId, ResellerId, CaribbeanCallId, <<"caribbean">>),
    {'ok', CaribbeanResp} = send_authz_req(AccountId, ResellerId, CaribbeanCallId, <<"caribbean">>),
    lager:info("authz resp: ~p", [CaribbeanResp]),
    _ = send_channel_destroy(AccountId, ResellerId, CaribbeanCallId, <<"caribbean">>),

    'true' = is_authorized(CaribbeanResp),

    %% Re-save system_config bypass
    OldConfig = kz_json:from_list([{<<"default">>
                                   ,kz_json:from_list([{<<"bypass_authz_classifiers">>, BaseBypass}])}
                                  ]
                                 ),

    _ReSavedConfig = pqc_cb_system_configs:patch_default_config(API
                                                               ,<<"jonny5">>
                                                               ,OldConfig
                                                               ),

    cleanup(API, [AccountId]).

-spec is_authorized(kz_json:object()) -> boolean().
is_authorized(JObj) ->
    kz_json:is_true(<<"Is-Authorized">>, JObj).

create_account(API, AccountName) ->
    AccountResp = properly_accountant:create_account(API, AccountName),
    lager:info("created account: ~s", [AccountResp]),

    kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)).

reseller_id(API, AccountId) ->
    FetchResp = pqc_cb_accounts:fetch(API, AccountId),
    lager:info("account fetched: ~s", [FetchResp]),

    kz_json:get_value([<<"data">>, <<"reseller_id">>], kz_json:decode(FetchResp)).

%% -spec send_authz_req(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
%%           {'ok', kz_json:object()} |
%%           {'error', any()}.
%% send_authz_req(AccountId, ResellerId, CallId) ->
%%     send_authz_req(AccountId, ResellerId, CallId, 'undefined').

send_authz_req(AccountId, ResellerId, CallId, Classifier) ->
    send_authz_req(AccountId, ResellerId, CallId, Classifier, <<"inbound">>).

send_authz_req(AccountId, ResellerId, CallId, Classifier, CallDirection) ->
    ToNumber = to_number(Classifier),
    Req = [{<<"Call-Direction">>, CallDirection}
          ,{<<"Call-ID">>, CallId}
          ,{<<"Caller-ID-Name">>, <<?MODULE_STRING>>}
          ,{<<"Caller-ID-Number">>, <<"14157900001">>}
          ,{<<"From">>, <<?MODULE_STRING>>}
          ,{<<"Request">>, <<ToNumber/binary, "@realm.com">>}
          ,{<<"To">>, <<ToNumber/binary, "@realm.com">>}
          ,{<<"Custom-Channel-Vars">>, kz_json:from_list([{<<"Account-ID">>, AccountId}
                                                         ,{<<"Reseller-ID">>, ResellerId}
                                                         ])
           }
          | kz_api:default_headers(<<?MODULE_STRING>>, <<"5.0">>)
          ],
    kz_amqp_worker:call(Req
                       ,fun kapi_authz:publish_authz_req/1
                       ,fun kapi_authz:authz_resp_v/1
                       ,3 * ?MILLISECONDS_IN_SECOND
                       ).

to_number('undefined') -> <<"14157900000">>;
to_number(<<"emergency">>) -> <<"933">>;
to_number(<<"tollfree_us">>) -> <<"+18001234567">>;
to_number(<<"caribbean">>) -> <<"+16846516238">>.

-spec send_channel_destroy(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
send_channel_destroy(AccountId, ResellerId, CallId) ->
    send_channel_destroy(AccountId, ResellerId, CallId, 'undefined').

send_channel_destroy(AccountId, ResellerId, CallId, Classifier) ->
    send_channel_destroy(AccountId, ResellerId, CallId, Classifier, <<"inbound">>).

send_channel_destroy(AccountId, ResellerId, CallId, Classifier, CallDirection) ->
    ToNumber = to_number(Classifier),
    Event = [{<<"Call-Direction">>, CallDirection}
            ,{<<"Call-ID">>, CallId}
            ,{<<"Caller-ID-Name">>, <<?MODULE_STRING>>}
            ,{<<"Caller-ID-Number">>, <<"14157900001">>}
            ,{<<"From">>, <<?MODULE_STRING>>}
            ,{<<"Request">>, <<ToNumber/binary, "@realm.com">>}
            ,{<<"To">>, <<ToNumber/binary, "@realm.com">>}
            ,{<<"Timestamp">>, kz_time:now_s()}
            ,{<<"Custom-Channel-Vars">>, kz_json:from_list([{<<"Account-ID">>, AccountId}
                                                           ,{<<"Reseller-ID">>, ResellerId}
                                                           ])
             }
            | kz_api:default_headers(<<"call_event">>, <<"CHANNEL_DESTROY">>, <<?MODULE_STRING>>, <<"5.0">>)
            ],
    kz_amqp_worker:cast(Event, fun kapi_call:publish_event/1).

%% -spec send_channel_create(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
%% send_channel_create(AccountId, ResellerId, CallId) ->
%%     send_channel_create(AccountId, ResellerId, CallId, 'undefined').

send_channel_create(AccountId, ResellerId, CallId, Classifier) ->
    send_channel_create(AccountId, ResellerId, CallId, Classifier, <<"inbound">>).

send_channel_create(AccountId, ResellerId, CallId, Classifier, CallDirection) ->
    ToNumber = to_number(Classifier),
    Event = [{<<"Call-Direction">>, CallDirection}
            ,{<<"Call-ID">>, CallId}
            ,{<<"Caller-ID-Name">>, <<?MODULE_STRING>>}
            ,{<<"Caller-ID-Number">>, <<"14157900001">>}
            ,{<<"From">>, <<?MODULE_STRING>>}
            ,{<<"Request">>, <<ToNumber/binary, "@realm.com">>}
            ,{<<"To">>, <<ToNumber/binary, "@realm.com">>}
            ,{<<"Timestamp">>, kz_time:now_s()}
            ,{<<"Custom-Channel-Vars">>, kz_json:from_list([{<<"Account-ID">>, AccountId}
                                                           ,{<<"Reseller-ID">>, ResellerId}
                                                           ])
             }
            | kz_api:default_headers(<<"call_event">>, <<"CHANNEL_CREATE">>, <<?MODULE_STRING>>, <<"5.0">>)
            ],
    'ok' = kz_amqp_worker:cast(Event, fun kapi_call:publish_event/1),
    timer:sleep(10).

-spec query_limits(kz_term:ne_binary()) -> non_neg_integer().
query_limits(AccountId) ->
    j5_channels:total_calls(AccountId).

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = properly_maintenance:cleanup_module_accounts(?MODULE),
    cleanup_system().

cleanup(API, AccountIds) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, AccountIds),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.

update_limits(API, AccountId, Trunks) ->
    _Update = pqc_cb_limits:update(API
                                  ,AccountId
                                  ,kz_json:from_list([{<<"twoway_trunks">>, Trunks}
                                                     ,{<<"accept_charges">>, 'true'}
                                                     ]
                                                    )
                                  ),
    lager:info("update limits: ~s", [_Update]).
