%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(local_call_forwarding).

-export([local/0
        ,local_kzoo_270/0
        ,local_kcal_42/0
        ,local_kcal_40/0
        ,local_kzoo_375/0
        ,local_kzoo_393/0
        ,local_ps_35/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).

-spec local() -> 'ok'.
local() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun local_kzoo_270/0]
                 ).

%% Test call forwarding callflow action toggle
-spec local_kzoo_270() -> 'ok'.
local_kzoo_270() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts', 'cb_users', 'cb_devices']),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account ~s", [AccountResp]),

    <<AccountId/binary>> = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    %% create user/device with no cfwd properties
    UserId = create_user(API, AccountId),
    UserDeviceId = create_device(API, AccountId, UserId),
    DeviceId = create_device(API, AccountId),

    Callers = [{UserId, UserDeviceId}
              ,{'undefined', DeviceId}
              ],

    Number = kz_binary:rand_hex(5),
    NewNumber = kz_binary:rand_hex(5),

    %% first, activate call forwarding with feature code
    run(fun activate/1, AccountId, Number, Callers),
    %% next, deactivate call forwarding
    run(fun deactivate/1, AccountId, Number, Callers),
    %% next, toggle back to enabled
    run(fun (C) -> toggle(C, 'true') end, AccountId, Number, Callers),
    %% next, toggle back to disabled
    run(fun (C) -> toggle(C, 'false') end, AccountId, Number, Callers),
    %% %% next, update the number
    %% run(fun update/1, AccountId, Callers),
    %% should still be disabled, so toggle to enabled
    run(fun (C) -> toggle(C, 'false') end, AccountId, Number, Callers),

    %% activate call forwarding with feature code and new number
    run(fun activate/1, AccountId, NewNumber, Callers),

    cleanup(API, [AccountId]).

run(_F, _A, _C, []) -> 'ok';
run(CFFun, AccountId, Capture, [{OwnerId, AuthzId} | Callers]) ->
    Call0 = kapps_call:from_json(
              kz_json:from_list([{<<"Call-ID">>, kz_binary:rand_hex(6)}
                                ,{<<"Account-ID">>, AccountId}
                                ,{<<"Authorizing-ID">>, AuthzId}
                                ,{<<"Owner-ID">>, OwnerId}
                                ])
             ),
    Call = kapps_call:kvs_store('cf_capture_group', Capture, Call0),
    CFFun(Call),
    run(CFFun, AccountId, Capture, Callers).

activate(Call) ->
    Number = kapps_call:kvs_fetch('cf_capture_group', 'undefined', Call),

    lager:info("activating cfwd"),
    run_update(Call, 'true', Number).

deactivate(Call) ->
    lager:info("deactivating cfwd"),
    run_update(Call, 'false').

toggle(Call, ShouldBeEnabled) ->
    Number = kapps_call:kvs_fetch('cf_capture_group', 'undefined', Call),

    lager:info("toggling cfwd to ~p and number ~s", [ShouldBeEnabled, Number]),
    run_update(Call, ShouldBeEnabled, Number).

run_update(Call, IsEnabled) ->
    run_update(Call, IsEnabled, 'undefined').

run_update(Call, IsEnabled, Number) ->
    CFwdRecord = cf_call_forward:get_call_forward(Call),
    UpdatedRecord = toggle_cfwd(CFwdRecord, IsEnabled, Number),
    {'ok', UpdatedEndpoint} = cf_call_forward:update_callfwd(UpdatedRecord, Call),

    CallForwardTypes = kzd_endpoint:call_forward(UpdatedEndpoint),
    CallForward = kzd_call_forward_types:unconditional(CallForwardTypes),
    lager:info("updated cfwd: ~p", [CallForward]),

    %% is cfwd enabled appropriately
    IsEnabled = kzd_call_forward:enabled(CallForward),
    %% is cfwd number set correctly
    'true' =
        (is_binary(Number) %% updated to Number
         andalso Number =:= kzd_call_forward:number(CallForward)
        )
        orelse Number =:= 'undefined'. %% or not updated

toggle_cfwd(CFwdRecord, 'true', Number) ->
    maybe_toggle_number(cf_call_forward:set_active(CFwdRecord), Number);
toggle_cfwd(CFwdRecord, 'false', Number) ->
    maybe_toggle_number(cf_call_forward:set_deactive(CFwdRecord), Number).

maybe_toggle_number(CFwdRecord, 'undefined') -> CFwdRecord;
maybe_toggle_number(CFwdRecord, Number) ->
    cf_call_forward:set_number(CFwdRecord, Number).

%% Setup test account with busy call-forwarded user
-spec local_kcal_42() -> 'ok'.
local_kcal_42() ->
    API = pqc_cb_api:init_api(['crossbar', 'callflow', 'ecallmgr']
                             ,['cb_accounts', 'cb_users', 'cb_devices', 'cb_callflows']
                             ),

    RequestData = kz_json:from_list([{<<"name">>, ?ACCOUNT_NAME}
                                    ,{<<"realm">>, <<"compy64.com">>}
                                    ]),
    AccountResp = properly_accountant:create_account(API, RequestData),
    lager:info("created account ~s", [AccountResp]),

    <<AccountId/binary>> = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    User = seq_users:new_user(),
    CfwdUser = kzd_users:set_call_forward(User, kcal_42_cfwd()),
    CreateUserResp = pqc_cb_users:create(API, AccountId, CfwdUser),
    lager:info("created callee with cfwd: ~s", [CreateUserResp]),
    CreatedUserJObj = kz_json:decode(CreateUserResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, CreatedUserJObj),
    UserId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], CreatedUserJObj),

    setup_test_cfwd(API, AccountId, UserId).

%% Setup test account with selective call-forwarded user
-spec local_kcal_40() -> 'ok'.
local_kcal_40() ->
    API = pqc_cb_api:init_api(['crossbar', 'callflow', 'ecallmgr']
                             ,['cb_accounts', 'cb_users', 'cb_devices', 'cb_callflows', 'cb_match_lists']
                             ),

    RequestData = kz_json:from_list([{<<"name">>, ?ACCOUNT_NAME}
                                    ,{<<"realm">>, <<"compy64.com">>}
                                    ]),
    AccountResp = properly_accountant:create_account(API, RequestData),
    lager:info("created account ~s", [AccountResp]),

    <<AccountId/binary>> = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    MatchListRule = kz_json:from_list([{<<"name">>, <<"Match CID">>}
                                      ,{<<"regex">>, <<"^(username)$">>}
                                      ,{<<"target">>, <<"caller_id_number">>}
                                      ,{<<"type">>, <<"regex">>}
                                      ]),
    MatchList = kz_json:from_list([{<<"name">>, <<"Match list for CID 5000">>}
                                  ,{<<"rules">>, [MatchListRule]}
                                  ]),
    CreatedMatchList = pqc_cb_match_lists:create(API, AccountId, MatchList),
    lager:info("created match list: ~s", [CreatedMatchList]),
    MatchlistId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(CreatedMatchList)),

    User = seq_users:new_user(),
    CfwdUser = kzd_users:set_call_forward(User, kcal_40_cfwd(MatchlistId)),
    CreateUserResp = pqc_cb_users:create(API, AccountId, CfwdUser),
    lager:info("created callee with cfwd: ~s", [CreateUserResp]),
    CreatedUserJObj = kz_json:decode(CreateUserResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, CreatedUserJObj),
    UserId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], CreatedUserJObj),


    setup_test_cfwd(API, AccountId, UserId).

%% Setup test account with selective call-forwarded user and temporal routes
-spec local_kzoo_375() -> 'ok'.
local_kzoo_375() ->
    API = pqc_cb_api:init_api(['crossbar', 'callflow', 'ecallmgr']
                             ,['cb_accounts', 'cb_users', 'cb_devices', 'cb_callflows', 'cb_match_lists', 'cb_temporal_routes']
                             ),

    RequestData = kz_json:from_list([{<<"name">>, ?ACCOUNT_NAME}
                                    ,{<<"realm">>, <<"compy64.com">>}
                                    ]),
    AccountResp = properly_accountant:create_account(API, RequestData),
    lager:info("created account ~s", [AccountResp]),

    <<AccountId/binary>> = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    TemporalRoute = today_rule(),
    TemporalResp = pqc_cb_temporal_rules:create(API, AccountId, TemporalRoute),
    lager:info("created temporal route: ~s", [TemporalResp]),
    TemporalRouteId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(TemporalResp)),

    MatchListRule = kz_json:from_list([{<<"name">>, <<"Time Of Day">>}
                                      ,{<<"temporal_route_id">>, TemporalRouteId}
                                      ,{<<"type">>, <<"temporal_route">>}
                                      ]),
    MatchList = kz_json:from_list([{<<"name">>, <<"Match list for CID 5000">>}
                                  ,{<<"rules">>, [MatchListRule]}
                                  ]),
    CreatedMatchList = pqc_cb_match_lists:create(API, AccountId, MatchList),
    lager:info("created match list: ~s", [CreatedMatchList]),
    MatchlistId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(CreatedMatchList)),

    User = seq_users:new_user(),
    CfwdUser = kzd_users:set_call_forward(User, kcal_40_cfwd(MatchlistId)),
    CreateUserResp = pqc_cb_users:create(API, AccountId, CfwdUser),
    lager:info("created callee with cfwd: ~s", [CreateUserResp]),
    CreatedUserJObj = kz_json:decode(CreateUserResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, CreatedUserJObj),
    UserId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], CreatedUserJObj),

    setup_test_cfwd(API, AccountId, UserId).

setup_test_cfwd(API, AccountId, CfwdUserId) ->
    Device = new_device('undefined'),
    CallerDevice = kz_doc:setters(Device
                                 ,[{fun kzd_devices:set_sip_username/2, <<"username">>}
                                  ,{fun kzd_devices:set_sip_password/2, <<"password">>}
                                  ]
                                 ),
    CreateCallerResp = pqc_cb_devices:create(API, AccountId, CallerDevice),
    lager:info("created caller device: ~s", [CreateCallerResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(CreateCallerResp)),

    Callflow = seq_callflows:new_callflow(),
    Flow = kz_json:from_list([{<<"module">>, <<"user">>}
                             ,{<<"data">>, kz_json:from_list([{<<"id">>, CfwdUserId}])}
                             ]),
    UserCallflow = kzd_callflows:set_flow(Callflow, Flow),
    CreateCallflowResp = pqc_cb_callflows:create(API, AccountId, UserCallflow),
    lager:info("created user callflow: ~s", [CreateCallflowResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(CreateCallflowResp)),

    lager:info("all set to test! dial 2600").

kcal_42_cfwd() ->
    kz_doc:setters(kzd_call_forward:new()
                  ,[{fun kzd_call_forward:set_enabled/2, 'true'}
                   ,{fun kzd_call_forward:set_no_answer_enabled/2, 'true'}
                   ,{fun kzd_call_forward:set_no_answer_number/2, <<"+14158867900">>}
                   ]
                  ).

kcal_40_cfwd(MatchlistId) ->
    SelectiveRule = kz_json:from_list([{<<"enabled">>, 'true'}
                                      ,{<<"match_list_id">>, MatchlistId}
                                      ]),
    SelectiveCfwd = kz_json:from_list([{<<"enabled">>, 'true'}
                                      ,{<<"number">>, <<"+14158867900">>}
                                      ,{<<"rules">>, [SelectiveRule]}
                                      ]
                                     ),
    kz_doc:setters(kzd_call_forward:new()
                  ,[{fun kzd_call_forward:set_enabled/2, 'true'}
                   ,{fun kzd_call_forward:set_selective/2, SelectiveCfwd}
                   ]
                  ).

%% KZOO-393:
%%   1. create user+device
%%   2. add legacy call forwarding enabled=true + number
%%   3. dial *56 (update call forwarding number)
%%      enter new number, hear prompt with new number
%%   4. Verify via API that user's call forwarding is enabled and refs new number
-spec local_kzoo_393() -> kz_term:ne_binary().
local_kzoo_393() ->
    API = pqc_cb_api:init_api(['crossbar', 'callflow', 'ecallmgr']
                             ,['cb_accounts', 'cb_users', 'cb_devices', 'cb_callflows', 'cb_match_lists', 'cb_temporal_routes']
                             ),

    RequestData = kz_json:from_list([{<<"name">>, ?ACCOUNT_NAME}
                                    ,{<<"realm">>, <<"compy64.com">>}
                                    ]),
    AccountResp = properly_accountant:create_account(API, RequestData),
    lager:info("created account ~s", [AccountResp]),

    <<AccountId/binary>> = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    UserId = create_user(API, AccountId),

    Device = new_device(UserId),
    CallerDevice = kz_doc:setters(Device
                                 ,[{fun kzd_devices:set_sip_username/2, <<"caller">>}
                                  ,{fun kzd_devices:set_sip_password/2, <<"caller">>}
                                  ]
                                 ),
    CreateCallerResp = pqc_cb_devices:create(API, AccountId, CallerDevice),
    lager:info("created caller device: ~s", [CreateCallerResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(CreateCallerResp)),

    %% update call forwarding number (but don't toggle 'enabled'
    Star56Callflow = kz_json:from_list([{<<"numbers">>, [<<"*56">>]}
                                       ,{<<"patterns">>, []}
                                       ,{<<"name">>, <<"Star 56">>}
                                       ,{<<"flow">>
                                        ,kz_json:from_list([{<<"module">>, <<"call_forward">>}
                                                           ,{<<"data">>, kz_json:from_list([{<<"action">>, <<"update">>}])}
                                                           ])
                                        }
                                       ]),
    Star56Resp = pqc_cb_callflows:create(API, AccountId, Star56Callflow),
    lager:info("*56 callflow ready: ~s", [Star56Resp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(Star56Resp)),

    %% activate call forwarding (and prompt for number if none set)
    Star72Callflow = kz_json:from_list([{<<"numbers">>, [<<"*72">>]}
                                       ,{<<"patterns">>, []}
                                       ,{<<"name">>, <<"Star 72">>}
                                       ,{<<"flow">>
                                        ,kz_json:from_list([{<<"module">>, <<"call_forward">>}
                                                           ,{<<"data">>, kz_json:from_list([{<<"action">>, <<"activate">>}])}
                                                           ])
                                        }
                                       ]),
    Star72Resp = pqc_cb_callflows:create(API, AccountId, Star72Callflow),
    lager:info("*72 callflow ready: ~s", [Star72Resp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(Star72Resp)),

    %% deactivate call forwarding
    Star73Callflow = kz_json:from_list([{<<"numbers">>, [<<"*73">>]}
                                       ,{<<"patterns">>, []}
                                       ,{<<"name">>, <<"Star 73">>}
                                       ,{<<"flow">>
                                        ,kz_json:from_list([{<<"module">>, <<"call_forward">>}
                                                           ,{<<"data">>, kz_json:from_list([{<<"action">>, <<"deactivate">>}])}
                                                           ])
                                        }
                                       ]),
    Star73Resp = pqc_cb_callflows:create(API, AccountId, Star73Callflow),
    lager:info("*73 callflow ready: ~s", [Star73Resp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(Star73Resp)),

    %% toggle call forwarding
    Star74Callflow = kz_json:from_list([{<<"numbers">>, [<<"*74">>]}
                                       ,{<<"patterns">>, []}
                                       ,{<<"name">>, <<"Star 74">>}
                                       ,{<<"flow">>
                                        ,kz_json:from_list([{<<"module">>, <<"call_forward">>}
                                                           ,{<<"data">>, kz_json:from_list([{<<"action">>, <<"toggle">>}])}
                                                           ])
                                        }
                                       ]),
    Star74Resp = pqc_cb_callflows:create(API, AccountId, Star74Callflow),
    lager:info("*74 callflow ready: ~s", [Star74Resp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(Star74Resp)).

%% setup call forwarding to an extension (vs PSTN DID)
-spec local_ps_35() -> 'ok'.
local_ps_35() ->
    API = pqc_cb_api:init_api(['crossbar', 'callflow', 'ecallmgr']
                             ,['cb_accounts', 'cb_users', 'cb_devices', 'cb_callflows', 'cb_match_lists', 'cb_temporal_routes']
                             ),

    RequestData = kz_json:from_list([{<<"name">>, ?ACCOUNT_NAME}
                                    ,{<<"realm">>, <<"compy64.com">>}
                                    ]),
    AccountResp = properly_accountant:create_account(API, RequestData),
    lager:info("created account ~s", [AccountResp]),

    <<AccountId/binary>> = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    Device = new_device('undefined'),
    CallerDevice = kz_doc:setters(Device
                                 ,[{fun kzd_devices:set_sip_username/2, <<"caller">>}
                                  ,{fun kzd_devices:set_sip_password/2, <<"caller">>}
                                  ,{fun kzd_devices:set_name/2, <<"caller">>}
                                  ]
                                 ),
    CreateCallerResp = pqc_cb_devices:create(API, AccountId, CallerDevice),
    lager:info("created caller device: ~s", [CreateCallerResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(CreateCallerResp)),

    Extension = kz_binary:rand_hex(4),
    CallForwardSettings = kz_json:from_list([{<<"enabled">>, 'true'}
                                            ,{<<"number">>, Extension}
                                            ]),
    CallForward = kzd_call_forward_types:set_unconditional(kz_json:from_list([{<<"enabled">>, 'true'}])
                                                          ,CallForwardSettings
                                                          ),

    CalleeDevice = kz_doc:setters(Device
                                 ,[{fun kzd_devices:set_sip_username/2, <<"callee">>}
                                  ,{fun kzd_devices:set_sip_password/2, <<"callee">>}
                                  ,{fun kzd_devices:set_name/2, <<"callee">>}
                                  ,{fun kzd_devices:set_call_forward/2, CallForward}
                                  ]
                                 ),
    CreateCalleeResp = pqc_cb_devices:create(API, AccountId, CalleeDevice),
    lager:info("created callee device forwarded to ~s: ~s", [Extension, CreateCalleeResp]),
    CalleeRespJObj = kz_json:decode(CreateCalleeResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, CalleeRespJObj),
    CalleeDeviceId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], CalleeRespJObj),

    %% update call forwarding number (but don't toggle 'enabled'
    CalleeCallflow = kz_json:from_list([{<<"numbers">>, [<<"2000">>]}
                                       ,{<<"patterns">>, []}
                                       ,{<<"name">>, <<"Callee callflow">>}
                                       ,{<<"flow">>
                                        ,kz_json:from_list([{<<"module">>, <<"device">>}
                                                           ,{<<"data">>, kz_json:from_list([{<<"id">>, CalleeDeviceId}])}
                                                           ])
                                        }
                                       ]),
    CalleeCallflowResp = pqc_cb_callflows:create(API, AccountId, CalleeCallflow),
    lager:info("2600 callflow ready: ~s", [CalleeCallflowResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(CalleeCallflowResp)),

    %% update call forwarding number (but don't toggle 'enabled'
    CfwdCallflow = kz_json:from_list([{<<"numbers">>, [Extension]}
                                     ,{<<"patterns">>, []}
                                     ,{<<"name">>, <<"Extension callflow">>}
                                     ,{<<"flow">>
                                      ,kz_json:from_list([{<<"module">>, <<"tts">>}
                                                         ,{<<"data">>, kz_json:from_list([{<<"text">>, <<"you have reached the call forward extension.">>}])}
                                                         ])
                                      }
                                     ]),
    CfwdResp = pqc_cb_callflows:create(API, AccountId, CfwdCallflow),
    lager:info("extension ~s callflow ready: ~s", [Extension, CfwdResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(CfwdResp)),

    lager:info("call scenario ready, dial 2000").

create_user(API, AccountId) ->
    User = seq_users:new_user(),
    Resp = pqc_cb_users:create(API, AccountId, User),
    lager:info("created user: ~s", [Resp]),
    <<_/binary>> = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(Resp)).

create_device(API, AccountId) ->
    create_device(API, AccountId, 'undefined').

create_device(API, AccountId, OwnerId) ->
    Resp = pqc_cb_devices:create(API, AccountId, new_device(OwnerId)),
    lager:info("created device: ~s", [Resp]),
    <<_/binary>> = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(Resp)).

new_device('undefined') ->
    seq_devices:new_device();
new_device(OwnerId) ->
    kzd_devices:set_owner_id(seq_devices:new_device(), OwnerId).

-spec cleanup() -> 'ok'.
cleanup() ->
    properly_maintenance:cleanup_module_accounts(?MODULE).

-spec cleanup(pqc_cb_api:state(), kz_term:ne_binaries()) -> 'ok'.
cleanup(API, AccountIds) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, AccountIds),
    _ = pqc_cb_api:cleanup(API),
    'ok'.

today_rule() ->
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_temporal_rules:set_cycle/2, <<"daily">>}
                         ,{fun kzd_temporal_rules:set_name/2, kz_binary:rand_hex(4)}
                         ]
                        ,kzd_temporal_rules:new()
                        )
     ).
