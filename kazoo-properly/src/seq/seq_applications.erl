%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% @author Kevin Damas
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_applications).

-export([seq/0
        ,seq_master_checks/0
        ,seq_reseller_checks/0
        ,seq_account_checks/0
        ,cleanup/0
        ]).

-properly({'standalone', [seq_account_checks/0]}).

-define(RESELLER_NAME, kz_term:to_binary([?MODULE_STRING, "-reseller"])).
-define(SUB_ACCOUNT_NAME, kz_term:to_binary([?MODULE_STRING, "-subaccount"])).

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).

%% lol type apps are so wololo
-define(APP_TYPE, <<"lol_ui">>).

%% add an extra field for each test (the test function name)
%% so we can search docs in master account if we need them
-define(TEST_FILTER, <<"seq_applications">>).

%% extra field per each test functions for propuse of logging and search
-define(FILTER_KEY, kz_term:to_binary(?FUNCTION_NAME)).

-spec seq() -> any().
seq() ->
    Funs = [fun seq_master_checks/0
           ,fun seq_reseller_checks/0
           ,fun seq_account_checks/0
           ],
    lists:foreach(fun(Fun) -> Fun() end, Funs).

-spec seq_master_checks() -> 'ok'.
seq_master_checks() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_applications', 'cb_entitlements']),
    AccountId = maps:get('account_id', API),

    AppId = kz_binary:rand_uuid(),
    AppDoc = new_app_doc(?FILTER_KEY),

    %% EmptySummaryTypeResp = pqc_cb_applications:summary(API, AccountId),
    %% lager:info("empty applications summary resp: ~p", [EmptySummaryTypeResp]),
    %% [] = get_seq_apps(kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryTypeResp)), ?FILTER_KEY),

    {_AppId, _} = app_create_read_update(API, AccountId, AppId, AppDoc, ?FILTER_KEY),

    DeleteResp = pqc_cb_applications:delete(API, AccountId, AppId),
    lager:info("deleted application resp: ~p", [DeleteResp]),
    _ = kz_json:unsafe_decode(DeleteResp),

    cleanup(API, [], []).

-spec seq_reseller_checks() -> 'ok'.
seq_reseller_checks() ->
    MasterAPI = pqc_cb_api:init_api(['crossbar'], ['cb_applications', 'cb_entitlements']),
    MasterAccountId = maps:get('account_id', MasterAPI),

    lager:info("creating reseller account"),
    AccountId = create_account(MasterAPI, ?ACCOUNT_NAME, 'true'),

    #{token := ResellerAdmin
     ,id := AdminId
     } = create_and_auth_user(MasterAPI, AccountId, <<"admin">>),

    AdminAPI = MasterAPI#{auth_token => ResellerAdmin
                         ,account_id => AccountId
                         ,auth_account_id => AccountId
                         },

    AppId = kz_binary:rand_uuid(),
    AppDoc = new_app_doc(?FILTER_KEY),

    %% test reseller for cru on apps
    _ = app_create_read_update(AdminAPI, AccountId, AppId, AppDoc, ?FILTER_KEY),

    %% testing override
    OverrideMasterAppId = kz_binary:rand_uuid(),
    OverrideMasterAppDoc = new_app_doc(?FILTER_KEY),
    {_, OverrideMasterUpdated} = app_create_read_update(MasterAPI, MasterAccountId, OverrideMasterAppId, OverrideMasterAppDoc, ?FILTER_KEY),
    OverrideAppDoc = kzd_applications:set_name(OverrideMasterUpdated
                                              ,<<"reseller-override-", (kzd_applications:name(OverrideMasterUpdated))/binary>>
                                              ),
    {OverrideMasterAppId, OverrideUpdated} = app_create_read_update(AdminAPI, AccountId, OverrideMasterAppId, OverrideAppDoc, ?FILTER_KEY),
    <<"reseller-override-", _/binary>> = kzd_applications:name(OverrideUpdated),

    #{token := User
     ,id := UserId
     } = create_and_auth_user(MasterAPI, AccountId, <<"user">>),
    UserAPI = AdminAPI#{auth_token => User},

    regular_user_permission_checks(UserAPI, AccountId, AppId, ?FILTER_KEY),

    %% create master app for testing entitlements
    %% because the apps are available to account id in url from its **upper** reseller or master
    %% even if the account in url is reseller itself
    MasterAppId = kz_binary:rand_uuid(),
    MasterAppDoc = new_app_doc(?FILTER_KEY),
    {_, _MasterUpdated} = app_create_read_update(MasterAPI, MasterAccountId, MasterAppId, MasterAppDoc, ?FILTER_KEY),

    entitlement_permission_checks(AdminAPI, AdminId, UserAPI, UserId, AccountId, MasterAppId, ?FILTER_KEY),


    cleanup(MasterAPI, [AccountId], [MasterAppId, OverrideMasterAppId]).

-spec seq_account_checks() -> 'ok'.
seq_account_checks() ->
    MasterAPI = pqc_cb_api:init_api(['crossbar'], ['cb_applications', 'cb_entitlements']),
    %% MasterAccountId = maps:get('account_id', MasterAPI),

    lager:info("creating reseller account"),
    ResellerAccountId = create_account(MasterAPI, ?RESELLER_NAME, 'true'),

    #{token := ResellerAdmin
      %% ,id := ResellerAdminId
     } = create_and_auth_user(MasterAPI, ResellerAccountId, <<"admin">>),

    ResellerAdminAPI = MasterAPI#{auth_token => ResellerAdmin
                                 ,account_id => ResellerAccountId
                                 ,auth_account_id => ResellerAccountId
                                 },

    AppId = kz_binary:rand_uuid(),
    AppDoc = new_app_doc(?FILTER_KEY),

    %% create app to test entitlement/blocklists in sub-account
    {AppId, _UpdatedApp} = app_create_read_update(ResellerAdminAPI, ResellerAccountId, AppId, AppDoc, ?FILTER_KEY),

    lager:info("creating sub-account account"),
    AccountId = create_account(ResellerAdminAPI, ?SUB_ACCOUNT_NAME, 'false'),

    #{token := AdminUser
     ,id := AdminId
     } = create_and_auth_user(ResellerAdminAPI, AccountId, <<"admin">>),
    AdminAPI = MasterAPI#{auth_token => AdminUser
                         ,account_id => AccountId
                         ,auth_account_id => AccountId
                         },

    lager:info("~s: regular account cannot get summary", [?FILTER_KEY]),
    {'error', _} = pqc_cb_applications:summary(AdminAPI, AccountId),

    lager:info("~s: regular account cannot get blocklists summary", [?FILTER_KEY]),
    {'error', _} = pqc_cb_applications:summary_blocklists(AdminAPI, AccountId, ?APP_TYPE),

    lager:info("~s: regular account cannot create fetch app without user id in path", [?FILTER_KEY]),
    {'error', _} = pqc_cb_applications:fetch(AdminAPI, AccountId, AppId),

    lager:info("~s: regular account cannot create apps", [?FILTER_KEY]),
    {'error', _} = pqc_cb_applications:create(AdminAPI, AccountId, kz_binary:rand_uuid(), AppDoc),

    #{token := User
     ,id := UserId
     } = create_and_auth_user(AdminAPI, AccountId, <<"user">>),
    UserAPI = AdminAPI#{auth_token => User},

    regular_user_permission_checks(UserAPI, AccountId, AppId, ?FILTER_KEY),
    entitlement_permission_checks(AdminAPI, AdminId, UserAPI, UserId, AccountId, AppId, ?FILTER_KEY),
    block_permission_checks(ResellerAdminAPI, AdminAPI, AdminId, ResellerAccountId, AccountId, AppId, ?FILTER_KEY),

    cleanup(MasterAPI, [AccountId], []).

app_create_read_update(API, AccountId, AppId, AppDoc, FilterKey) ->
    EmptySummaryResp = pqc_cb_applications:summary(API, AccountId),
    lager:info("~s: empty applications summary resp: ~p", [FilterKey, EmptySummaryResp]),
    [] = get_seq_apps(kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryResp)), FilterKey),

    CreateAppResp = pqc_cb_applications:create(API, AccountId, AppId, AppDoc),
    lager:info("~s: create application resp: ~p", [FilterKey, CreateAppResp]),
    AppId = kz_doc:id(kz_json:get_value(<<"data">>, kz_json:decode(CreateAppResp))),

    FetchResp = pqc_cb_applications:fetch(API, AccountId, AppId),
    lager:info("~s: application fetch resp: ~p", [FilterKey, FetchResp]),
    AppId = kz_doc:id(kz_json:get_value([<<"data">>], kz_json:decode(FetchResp))),

    UpdateAppResp = pqc_cb_applications:update(API, AccountId, AppId, kzd_applications:set_author(AppDoc, <<"lol">>)),
    lager:info("~s: update application resp: ~p", [FilterKey, UpdateAppResp]),
    UpdateDoc = kz_json:get_value(<<"data">>, kz_json:decode(UpdateAppResp)),
    <<"lol">> = kzd_applications:author(UpdateDoc),

    {AppId, UpdateDoc}.

regular_user_permission_checks(UserAPI, AccountId, AppId, FilterKey) ->
    AppDoc = new_app_doc(FilterKey),
    lager:info("~s: regular users cannot get summary", [FilterKey]),
    {'error', _} = pqc_cb_applications:summary(UserAPI, AccountId),

    lager:info("~s: regular users cannot get blocklists summary", [FilterKey]),
    {'error', _} = pqc_cb_applications:summary_blocklists(UserAPI, AccountId, ?APP_TYPE),

    lager:info("~s: regular users cannot get entitlements summary", [FilterKey]),
    {'error', _} = pqc_cb_applications:summary_entitlements(UserAPI, AccountId, ?APP_TYPE),

    lager:info("~s: regular users cannot create fetch app without user id in path", [FilterKey]),
    {'error', _} = pqc_cb_applications:fetch(UserAPI, AccountId, AppId),

    lager:info("~s: regular users cannot create apps", [FilterKey]),
    {'error', _} = pqc_cb_applications:create(UserAPI, AccountId, kz_binary:rand_hex(16), AppDoc),

    'ok'.

block_permission_checks(ResellerAdminAPI, AdminAPI, AdminId, ResellerAccountId, AccountId, AppId, FilterKey) ->
    EmptyBlocksResp = pqc_cb_applications:summary_blocklists(ResellerAdminAPI, ResellerAccountId, ?APP_TYPE),
    lager:info("~s: empty blocklists summary resp: ~p", [FilterKey, EmptyBlocksResp]),
    [] = kz_json:get_value(<<"data">>, kz_json:decode(EmptyBlocksResp)),

    %% creating entitlement to activate the app for the account
    Entitlement = kz_doc:setters(kzd_application_entitlement:new()
                                ,[{fun kzd_application_entitlement:set_type/2, <<"all">>}]
                                ),
    EntitlementCreated = pqc_cb_applications:create_entitlement(AdminAPI, AccountId, ?APP_TYPE, AppId, Entitlement),
    lager:info("~s: created entitlement resp ~p",[FilterKey, EntitlementCreated]),
    AppId = kzd_application_entitlement:app_id(kz_json:get_value(<<"data">>, kz_json:decode(EntitlementCreated))),

    AllowedBeforeBlock = pqc_cb_applications:allowed_apps(AdminAPI, AccountId, AdminId, ?APP_TYPE),
    lager:info("~s: app is allowed before blocking resp ~p",[FilterKey, AllowedBeforeBlock]),
    [AppId] = [kz_doc:id(App)
               || App <- kz_json:get_list_value([<<"data">>], kz_json:decode(AllowedBeforeBlock)),
                  AppId =:= kz_doc:id(App)
              ],

    BlockCreated = pqc_cb_applications:create_blocklist(ResellerAdminAPI, ResellerAccountId, ?APP_TYPE, AppId),
    lager:info("~s: created blocklist resp ~p",[FilterKey, BlockCreated]),
    AppId = kzd_application_blocklist:app_id(kz_json:get_value(<<"data">>, kz_json:decode(BlockCreated))),

    BlocksResp = pqc_cb_applications:summary_blocklists(ResellerAdminAPI, ResellerAccountId, ?APP_TYPE),
    lager:info("~s: summary blocklists resp ~p",[FilterKey, BlocksResp]),
    [AppId] = [kzd_application_blocklist:app_id(E)
               || E <- kz_json:get_value(<<"data">>, kz_json:decode(BlocksResp))
              ],

    FetchBlockResp = pqc_cb_applications:fetch_blocklist(ResellerAdminAPI, ResellerAccountId, ?APP_TYPE, AppId),
    lager:info("~s: fetch blocklist resp ~p",[FilterKey, FetchBlockResp]),
    AppId = kzd_application_blocklist:app_id(kz_json:get_value(<<"data">>, kz_json:decode(FetchBlockResp))),

    AllowedResp = pqc_cb_applications:allowed_apps(AdminAPI, AccountId, AdminId, ?APP_TYPE),
    lager:info("~s: account is not allowed apps resp after blocking app in reseller ~p",[FilterKey, AllowedResp]),
    [] = [kz_doc:id(App)
          || App <- kz_json:get_list_value([<<"data">>], kz_json:decode(AllowedResp)),
             AppId =:= kz_doc:id(App)
         ],

    DeleteResp = pqc_cb_applications:delete_blocklist(ResellerAdminAPI, ResellerAccountId, ?APP_TYPE, AppId),
    lager:info("~s: delete blocklist resp ~p",[FilterKey, DeleteResp]),
    _ = kz_json:get_value(<<"data">>, kz_json:decode(DeleteResp)),

    AllowedAfterResp = pqc_cb_applications:allowed_apps(AdminAPI, AccountId, AdminId, ?APP_TYPE),
    lager:info("~s: account allowed apps resp after delete blocking in reseller ~p",[FilterKey, AllowedAfterResp]),
    [AppId] = [kz_doc:id(App)
               || App <- kz_json:get_list_value([<<"data">>], kz_json:decode(AllowedAfterResp)),
                  AppId =:= kz_doc:id(App)
              ],

    'ok'.

entitlement_permission_checks(AdminAPI, AdminId, UserAPI, UserId, AccountId, AppId, FilterKey) ->
    EmptyEntitlementsResp = pqc_cb_applications:summary_entitlements(AdminAPI, AccountId, ?APP_TYPE),
    lager:info("~s: empty entitlements summary resp: ~p", [FilterKey, EmptyEntitlementsResp]),
    [] = kz_json:get_value(<<"data">>, kz_json:decode(EmptyEntitlementsResp)),

    NotAllowedResp = pqc_cb_applications:allowed_apps(AdminAPI, AccountId, AdminId, ?APP_TYPE),
    lager:info("~s: app is not active without entitlement resp when a user lists apps ~p",[FilterKey, NotAllowedResp]),
    [] = [kz_doc:id(App)
          || App <- kz_json:get_list_value([<<"data">>], kz_json:decode(NotAllowedResp)),
             AppId =:= kz_doc:id(App)
         ],

    AppListingResp = pqc_cb_applications:allowed_apps(AdminAPI, AccountId, 'undefined', ?APP_TYPE),
    lager:info("~s: admin lists available apps to create entitlements ~p",[FilterKey, AppListingResp]),
    [AppId] = [kz_doc:id(App)
               || App <- kz_json:get_list_value([<<"data">>], kz_json:decode(AppListingResp)),
                  AppId =:= kz_doc:id(App)
              ],

    Entitlement = kz_doc:setters(kzd_application_entitlement:new()
                                ,[{fun kzd_application_entitlement:set_type/2, <<"all">>}]
                                ),
    EntitlementCreated = pqc_cb_applications:create_entitlement(AdminAPI, AccountId, ?APP_TYPE, AppId, Entitlement),
    lager:info("~s: created entitlement resp ~p",[FilterKey, EntitlementCreated]),
    AppId = kzd_application_entitlement:app_id(kz_json:get_value(<<"data">>, kz_json:decode(EntitlementCreated))),

    EntitlementsResp = pqc_cb_applications:summary_entitlements(AdminAPI, AccountId, ?APP_TYPE),
    lager:info("~s: summary entitlements resp ~p",[FilterKey, EntitlementsResp]),
    [AppId] = [kzd_application_entitlement:app_id(E)
               || E <- kz_json:get_value(<<"data">>, kz_json:decode(EntitlementsResp))
              ],

    FetchEntitlementResp = pqc_cb_applications:fetch_entitlement(AdminAPI, AccountId, ?APP_TYPE, AppId),
    lager:info("~s: fetch entitlement resp ~p",[FilterKey, FetchEntitlementResp]),
    Fetched = kz_json:get_value(<<"data">>, kz_json:decode(FetchEntitlementResp)),
    AppId = kzd_application_entitlement:app_id(Fetched),

    AdminAllowResp = pqc_cb_applications:allowed_apps(AdminAPI, AccountId, AdminId, ?APP_TYPE),
    lager:info("~s: fetch admin allowed apps resp ~p",[FilterKey, AdminAllowResp]),
    [AppId] = [kz_doc:id(App)
               || App <- kz_json:get_list_value([<<"data">>], kz_json:decode(AdminAllowResp)),
                  AppId =:= kz_doc:id(App)
              ],

    UserAllowResp = pqc_cb_applications:allowed_apps(UserAPI, AccountId, UserId, ?APP_TYPE),
    lager:info("~s: fetch regular user allowed apps resp ~p",[FilterKey, UserAllowResp]),
    [AppId] = [kz_doc:id(App)
               || App <- kz_json:get_list_value([<<"data">>], kz_json:decode(UserAllowResp)),
                  AppId =:= kz_doc:id(App)
              ],

    UpdatedEntitlement = kzd_application_entitlement:set_type(Entitlement, <<"admins">>),
    UpdateEntitlementResp = pqc_cb_applications:update_entitlement(AdminAPI, AccountId, ?APP_TYPE, AppId, UpdatedEntitlement),
    lager:info("~s: update entitlement resp: ~p",[FilterKey, UpdateEntitlementResp]),
    <<"admins">> = kzd_application_entitlement:type(kz_json:get_value(<<"data">>, kz_json:decode(UpdateEntitlementResp))),

    NewAdminAllowResp = pqc_cb_applications:allowed_apps(AdminAPI, AccountId, AdminId, ?APP_TYPE),
    lager:info("~s: entitelment update to admin returns admin allowed apps resp ~p",[FilterKey, NewAdminAllowResp]),
    [AppId] = [kz_doc:id(App)
               || App <- kz_json:get_list_value([<<"data">>], kz_json:decode(NewAdminAllowResp)),
                  AppId =:= kz_doc:id(App)
              ],

    AdminAfterAllowResp = pqc_cb_applications:allowed_apps(AdminAPI, AccountId, AdminId, ?APP_TYPE),
    lager:info("~s: admin user allowed apps resp after entitlement update ~p",[FilterKey, AdminAfterAllowResp]),
    [AppId] = [kz_doc:id(App)
               || App <- kz_json:get_list_value([<<"data">>], kz_json:decode(AdminAfterAllowResp)),
                  AppId =:= kz_doc:id(App)
              ],

    UserAfterResp = pqc_cb_applications:allowed_apps(UserAPI, AccountId, UserId, ?APP_TYPE),
    lager:info("~s: regular user is not allowed resp after entitlement update ~p",[FilterKey, UserAfterResp]),
    [] = [kz_doc:id(App)
          || App <- kz_json:get_list_value([<<"data">>], kz_json:decode(UserAfterResp)),
             AppId =:= kz_doc:id(App)
         ],

    lager:info("~s: regular user is not allowed to app after entitlement update"),
    {'error', _} = pqc_cb_applications:allowed_app(AdminAPI, AccountId, UserId, ?APP_TYPE, AppId),

    DeleteResp = pqc_cb_applications:delete_entitlement(AdminAPI, AccountId, ?APP_TYPE, AppId),
    lager:info("~s: delete entitlement resp: ~p",[FilterKey, DeleteResp]),
    _ = kz_json:get_value(<<"data">>, kz_json:decode(DeleteResp)),

    NotAllowAfterDeleteResp = pqc_cb_applications:allowed_apps(UserAPI, AccountId, AdminId, ?APP_TYPE),
    lager:info("~s: app is not allowed after deleting its entitlement resp ~p",[FilterKey, NotAllowAfterDeleteResp]),
    [] = [kz_doc:id(App)
          || App <- kz_json:get_list_value([<<"data">>], kz_json:decode(NotAllowAfterDeleteResp)),
             AppId =:= kz_doc:id(App)
         ],

    'ok'.

%% add an extra field for each test (the test function name)
%% so we can search docs in master account if we need them
new_app_doc(FilterKey) ->
    kz_json:set_value(FilterKey
                     ,'true'
                     ,pqc_cb_applications:new_application_doc(?APP_TYPE)
                     ).

get_seq_apps(Data, FilterKey) when is_list(Data) ->
    [App || App <- Data,
            kz_json:is_true(FilterKey, App)
    ].

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = properly_maintenance:cleanup_module_accounts(?MODULE),
    API = pqc_cb_api:authenticate(),
    %% NOTE: delete child account first then parent account
    _ = seq_accounts:cleanup_accounts(API, [?SUB_ACCOUNT_NAME, ?RESELLER_NAME]),
    _ = cleanup_master_apps(API),
    'ok'.

cleanup_master_apps(API) ->
    AccountId = maps:get('account_id', API),

    %% an extra field was added by new_application_doc
    %% so we can search for doc in master account on cleanup
    Url = pqc_cb_applications:applications_url(API, AccountId)
        ++ "?has_key=" ++ kz_term:to_list(?TEST_FILTER),
    case pqc_cb_crud:summary(API, Url) of
        <<Resp/binary>> ->
            case kz_json:get_json_list(<<"data">>, kz_json:decode(Resp)) of
                [] ->
                    'ok';
                Apps ->
                    _ = [pqc_cb_applications:delete(API, AccountId, kz_doc:id(App))
                         || App <- Apps
                        ],
                    'ok'
            end;
        _Other ->
            'ok'
    end.

cleanup(API, AccountNames, MasterApps) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    MasterAccountId = maps:get('account_id', API),
    _ = seq_accounts:cleanup_accounts(API, AccountNames),
    _ = pqc_cb_api:cleanup(API),
    _ = [pqc_cb_applications:delete(API, MasterAccountId, AppId)
         || AppId <- MasterApps
        ],
    'ok'.

create_account(API, AccountName, Promote) ->
    AccountResp = properly_accountant:create_account(API, AccountName),
    lager:info("created account: ~p", [AccountResp]),
    AccountId = kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    case Promote of
        'true' ->
            PromoteResp = pqc_cb_accounts:promote(API, AccountId),
            lager:info("promoted account ~s to reseller: ~p", [AccountId, PromoteResp]),
            _ = kz_json:decode(PromoteResp),
            'ok';
        'false' ->
            'ok'
    end,
    AccountId.

create_and_auth_user(API, AccountId, PrivLevel) ->
    {UserId, Username, Password} = create_user(API, AccountId, PrivLevel),
    AuthNameResp = pqc_cb_user_auth:by_account_id(API, AccountId, Username, Password),
    RespDecode = kz_json:decode(AuthNameResp),
    AuthToken = kz_json:get_binary_value(<<"auth_token">>, RespDecode),
    #{id => UserId
     ,token => AuthToken
     }.

create_user(API, AccountId, PrivLevel) ->
    create_user(API, AccountId, PrivLevel, kz_binary:rand_hex(6)).

create_user(API, AccountId, PrivLevel, Username) ->
    Password = kz_binary:rand_hex(6),

    User = kz_doc:setters(seq_users:new_user()
                         ,[{fun kzd_users:set_username/2, Username}
                          ,{fun kzd_users:set_password/2, Password}
                          ,{fun kzd_users:set_priv_level/2, PrivLevel}
                          ]
                         ),
    lager:info("create a user in account ~s with priv_level ~s",[AccountId, PrivLevel]),
    CreateResp = pqc_cb_users:create(API, AccountId, User),
    lager:info("created user ~p", [CreateResp]),

    CreatedUser = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),

    {kz_doc:id(CreatedUser), Username, Password}.
