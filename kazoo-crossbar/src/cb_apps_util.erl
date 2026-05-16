%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2024, 2600Hz
%%% @doc
%%% @author Peter Defebvre
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_apps_util).

-export([allowed_apps/1
        ,allowed_apps/2
        ]).
-export([allowed_app/2]).
-export([allowed_applications/2
        ,allowed_applications/3
        ,allowed_application/3
        ,allowed_application/4
        ]).
-export([load_default_apps/0
        ,load_default_app/1
        ,ensure_master_account_id/2
        ]).
-export([create_apps_store_doc/1]).

-export([app_whitelabel_doc_id/1]).
-export([find_attachment/2]).

-include("crossbar.hrl").

-define(CB_APPS_STORE_LIST, <<"apps_store/crossbar_listing">>).

-type apps_map() :: #{AppId::kz_term:ne_binary() => AppDoc::kz_json:object() | boolean()}.
-type apps() :: kz_json:objects() | apps_map().

%%------------------------------------------------------------------------------
%% @doc Get allowed applications from service plans.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_apps(kz_term:ne_binary()) -> kz_json:objects().
allowed_apps(AccountId) ->
    allowed_apps(AccountId, 'undefined').

-spec allowed_apps(kz_term:ne_binary(), kz_term:api_ne_binary()) -> kz_json:objects().
allowed_apps(AccountId, UserId) ->
    allowed_apps(AccountId, UserId, load_default_apps('true')).

%%------------------------------------------------------------------------------
%% @doc Get an application object if allowed.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_app(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:api_object().
allowed_app(AccountId, AppId) ->
    case [App || App <- allowed_apps(AccountId, 'undefined', load_default_app(AppId, 'true')),
                 AppId =:= kz_doc:id(App)
         ]
    of
        [App|_] ->
            %% More than one service plan can have the same app, hence taking the head
            App;
        [] -> 'undefined'
    end.

-spec allowed_apps(kz_term:ne_binary(), kz_term:api_ne_binary(), apps_map()) -> kz_json:objects().
allowed_apps(_AccountId, _UserId, DefaultApps) when map_size(DefaultApps) =:= 0 ->
    [];
allowed_apps(AccountId, UserId, DefaultApps) ->
    Routines = [fun allowed_service_plan/3
               ,fun maybe_remove_kappex_apps/3
               ,fun apps_whitelabel_override/3
               ,fun allowed_apps_store_doc/3
               ,fun allowed_whitelabel_doc/3
               ,fun allowed_master_account/3
               ],
    Apps = lists:foldl(fun(F, AppsMap) ->
                               F(AccountId, UserId, AppsMap)
                       end
                      ,DefaultApps
                      ,Routines
                      ),
    maps:fold(fun ret_allowed_apps/3, [], Apps).

-spec ret_allowed_apps(kz_term:ne_binary(), kz_json:object(), kz_json:objects()) -> kz_json:objects().
ret_allowed_apps(_AppId, AppJObj, Acc) ->
    case kzd_app:is_published(AppJObj) of
        'true' ->
            lager:debug("allowing access to ~s due to ~s"
                       ,[kzd_app:name(AppJObj)
                        ,kz_json:get_value(<<"authority">>, AppJObj, <<"default">>)
                        ]
                       ),
            [AppJObj | Acc];
        'false' ->
            lager:debug("disallowing access to ~s due to ~s"
                       ,[kzd_app:name(AppJObj)
                        ,kz_json:get_value(<<"authority">>, AppJObj, <<"default">>)
                        ]
                       ),
            [AppJObj | Acc]
    end.

-spec allowed_applications(kz_term:ne_binary(), kz_term:api_ne_binary()) -> kz_json:objects().
allowed_applications(AppType, AccountId) ->
    allowed_applications(AppType, AccountId, 'undefined').

-spec allowed_applications(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_ne_binary()) -> kz_json:objects().
allowed_applications(AppType, AccountId, UserId) ->
    Routines = [fun load_applications_from_master/4
               ,fun merge_reseller_applications_to_master/4
               ,fun maybe_remove_kappex_apps/4
               ,fun apply_blocklists/4
               ,fun apply_service_plan_to_applications/4
               ,fun apply_application_entitlements/4
               ],
    Apps = lists:foldl(fun(F, AppsMap) -> F(AppType, AccountId, UserId, AppsMap) end, #{}, Routines),
    maps:fold(fun ret_allowed_applications/3, [], Apps).

-spec allowed_application(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          {'ok', kz_json:object()} |
          {'error', any()}.
allowed_application(AppType, AppId, AccountId) ->
    allowed_application(AppType, AppId, AccountId, 'undefined').

-spec allowed_application(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          {'ok', kz_json:object()} |
          {'error', any()}.
allowed_application(AppType, AppId, AccountId, UserId) ->
    {'ok', MasterAccountId} = kapps_util:get_master_account_id(),
    MasterApp = load_application_from_db(MasterAccountId, AppType, AppId, <<"master">>),

    Routines = [fun apply_blocklists/4
               ,fun apply_service_plan_to_applications/4
               ,fun apply_application_entitlements/4
               ],
    case merge_reseller_application_to_master(AppType, AppId, AccountId, MasterApp) of
        {'error', _}=Error ->
            Error;
        {'ok', Acc} ->
            Apps = lists:foldl(fun(F, AppsMap) -> F(AppType, AccountId, UserId, AppsMap) end, Acc, Routines),
            case maps:fold(fun ret_allowed_applications/3, [], Apps) of
                [] ->
                    {'error', 'not_found'};
                [App|_] ->
                    {'ok', App}
            end
    end.

-spec ret_allowed_applications(kz_term:ne_binary(), kz_json:object(), kz_json:objects()) -> kz_json:objects().
ret_allowed_applications(_AppId, AppJObj, Acc) ->
    %% unlike ret_allowed_apps, this actually filters out the app that is not published
    case kzd_applications:published(AppJObj) of
        'true' ->
            lager:debug("allowing access to ~s due to ~s"
                       ,[kzd_applications:name(AppJObj)
                        ,kzd_applications:pvt_authority(AppJObj)
                        ]
                       ),
            [AppJObj | Acc];
        'false' ->
            lager:debug("disallowing access to ~s due to ~s"
                       ,[kzd_applications:name(AppJObj)
                        ,kzd_applications:pvt_authority(AppJObj)
                        ]
                       ),
            [AppJObj | Acc]
    end.

-spec load_applications_from_master(kz_term:ne_binary(), kz_term:ne_binary()
                                   ,kz_term:api_ne_binary(), apps_map()
                                   ) -> apps_map().
load_applications_from_master(AppType, _AccountId, _UserId, _Acc) ->
    {'ok', MasterAccountId} = kapps_util:get_master_account_id(),
    load_applications_from_db(MasterAccountId, AppType, <<"master">>).

-spec merge_reseller_applications_to_master(kz_term:ne_binary(), kz_term:ne_binary()
                                           ,kz_term:api_ne_binary(), apps_map()
                                           ) -> apps_map().
merge_reseller_applications_to_master(AppType, AccountId, _UserId, MasterAcc) ->
    ResellerId = kz_services_reseller:get_id(AccountId),
    case kapps_util:get_master_account_id() of
        {'ok', ResellerId} -> MasterAcc;
        {'ok', AccountId} -> MasterAcc;
        _ ->
            ResellerApps = load_applications_from_db(ResellerId, AppType, <<"reseller">>),
            maps:fold(fun merge_reseller_to_master_fold/3, MasterAcc, ResellerApps)
    end.

-spec merge_reseller_application_to_master(kz_term:ne_binary(), kz_term:ne_binary(),kz_term:ne_binary()
                                          ,{'ok', kz_json:object()} | {'error', any()}
                                          ) -> {'ok', apps_map()} | {'error', any()}.
merge_reseller_application_to_master(AppType, AppId, AccountId, MasterApp) ->
    ResellerId = kz_services_reseller:get_id(AccountId),
    case kapps_util:get_master_account_id() of
        {'ok', ResellerId} -> maybe_merge_reseller_to_master(AppId, MasterApp, {'error', 'no_merge'});
        {'ok', AccountId} -> maybe_merge_reseller_to_master(AppId, MasterApp, {'error', 'no_merge'});
        _ ->
            ResellerApp = load_application_from_db(ResellerId, AppType, AppId, <<"reseller">>),
            maybe_merge_reseller_to_master(AppId, MasterApp, ResellerApp)
    end.

-spec merge_reseller_to_master_fold(kz_term:ne_binary(), apps_map(), apps_map()) ->
          apps_map().
merge_reseller_to_master_fold(AppId, ResellerApp, Acc) ->
    case maps:get(AppId, Acc, 'undefined') of
        'undefined' ->
            maps:put(AppId, ResellerApp, Acc);
        MasterApp ->
            maps:put(AppId, merge_reseller_to_master(ResellerApp, MasterApp), Acc)
    end.

-spec maybe_merge_reseller_to_master(kz_term:ne_binary()
                                    ,{'ok', kz_json:object()} | {'error', any()}
                                    ,{'ok', kz_json:object()} | {'error', any()}
                                    ) -> {'ok', apps_map()} | {'error', any()}.
maybe_merge_reseller_to_master(_, {'error', _}=Error, {'error', _}) ->
    Error;
maybe_merge_reseller_to_master(AppId, {'ok', MasterApp}, {'error', _}) ->
    {'ok', #{AppId => MasterApp}};
maybe_merge_reseller_to_master(AppId, {'error', _}, {'ok', ResellerApp}) ->
    {'ok', #{AppId => ResellerApp}};
maybe_merge_reseller_to_master(AppId, {'ok', MasterApp}, {'ok', ResellerApp}) ->
    {'ok', #{AppId => merge_reseller_to_master(ResellerApp, MasterApp)}}.

-spec merge_reseller_to_master(kz_json:object(), kz_json:object()) -> kz_json:object().
merge_reseller_to_master(ResellerApp, MasterApp) ->
    Published = kzd_applications:published(MasterApp, 'true'),
    kzd_applications:set_published(kz_json:merge(MasterApp, ResellerApp), Published).

-spec load_applications_from_db(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> apps_map().
load_applications_from_db(AccountId, AppType, Source) ->
    ViewOptions = [{'startkey', [AppType]}
                  ,{'endkey', [AppType, kz_term:high_unicode_value()]}
                  ,'include_docs'
                  ],

    case kz_datamgr:get_results(AccountId, <<"application/crossbar_listing">>, ViewOptions) of
        {'ok', JObjs} ->
            maps:from_list(
              [{kz_doc:id(JObj)
               ,track_attachments(kz_json:get_json_value(<<"doc">>, JObj), Source)
               }
               || JObj <- JObjs
              ]
             );
        {'error', _Reason} ->
            lager:error("failed to lookup apps in ~s: ~p", [AccountId, _Reason]),
            #{}
    end.

%% saving current attachments to temprory key, so when the doc get
%% merged with reseller we can find out where the attachment is coming from.
-spec track_attachments(kz_json:object(), kz_term:ne_binary()) -> kz_json:object().
track_attachments(JObj, Source) ->
    Prop = [{<<"_id">>, kz_doc:id(JObj)}
           ,{<<"pvt_account_db">>, kz_doc:account_db(JObj)}
           ,{<<"_attachments">>, kz_doc:attachments(JObj)}
           ],
    kz_json:set_value([<<"pvt_app_attachments">>, Source]
                     ,kz_json:from_list(Prop)
                     ,JObj
                     ).

-spec load_application_from_db(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          {'ok', kz_json:object()} |
          {'error', any()}.
load_application_from_db(AccountId, AppType, AppId, Source) ->
    case kz_datamgr:open_doc(AccountId, AppId) of
        {'ok', JObj} ->
            case kzd_applications:type(JObj) of
                AppType ->
                    {'ok', track_attachments(JObj, Source)};
                _Other ->
                    lager:error("expected type ~s for app ~s in account ~s but got ~s"
                               ,[AppType, AppId, AccountId, _Other]
                               ),
                    {'error', {'mismatch_app_type', _Other}}
            end;
        {'error', 'not_found'}=Error ->
            lager:debug("app ~s not found in account ~s", [AppId, AccountId]),
            Error;
        {'error', _Reason}=Error ->
            lager:error("failed to lookup app ~s in ~s: ~p", [AppId, AccountId, _Reason]),
            Error
    end.

-spec apply_blocklists(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_ne_binary(), apps_map()) ->
          apps_map().
apply_blocklists(_AppType, _AccountId, _UserId, Acc) when map_size(Acc) =:= 0 ->
    Acc;
apply_blocklists(AppType, AccountId, _UserId, Acc) ->
    LoadOptions = [{'startkey', [AppType]}
                  ,{'endkey', [AppType, kz_term:high_unicode_value()]}
                  ],
    BlocklistApps = load_blocklists(kz_services_reseller:get_id(AccountId), LoadOptions),
    Fun = fun(AppId, _, AccIn)->
                  case maps:get(AppId, AccIn, 'undefined') of
                      'undefined' ->
                          AccIn;
                      AppJObj ->
                          Setters = [{fun kzd_applications:set_published/2, 'false'}
                                    ,{fun kzd_applications:set_pvt_authority/2, <<"blocklist">>}
                                    ],
                          maps:put(AppId, kz_doc:setters(AppJObj, Setters), AccIn)
                  end
          end,
    maps:fold(Fun, Acc, BlocklistApps).

-spec load_blocklists(kz_term:api_ne_binary(), kz_term:proplist()) -> apps_map().
load_blocklists('undefined',  _) ->
    lager:debug("cannot load blocklists, account has no reseller", []),
    #{};
load_blocklists(ResellerId, LoadOptions) ->
    case kz_datamgr:get_results(ResellerId, <<"application/blocklists">>, LoadOptions) of
        {'ok', JObjs} ->
            maps:from_list(
              [{kzd_application_blocklist:app_id(kz_json:get_value(<<"value">>, JObj)), 'true'}
               || JObj <- JObjs
              ]
             );
        {'error', _Reason} ->
            lager:error("failed to lookup blocklists in ~s: ~p", [ResellerId, _Reason]),
            #{}
    end.

-spec apply_service_plan_to_applications(kz_term:ne_binary(), kz_term:ne_binary()
                                        ,kz_term:api_ne_binary(), apps_map()
                                        ) -> apps_map().
apply_service_plan_to_applications(_AppType, _AccountId, _UserId, Acc) when map_size(Acc) =:= 0 ->
    Acc;
apply_service_plan_to_applications(_AppType, AccountId, _UserId, Acc) ->
    ServicesApps = get_services_apps(AccountId),
    kz_json:foldl(apply_plan_to_application_fun(), Acc, ServicesApps).

-spec apply_plan_to_application_fun() ->
          fun((kz_term:ne_binary(), kz_json:object(), apps_map()) -> apps_map()).
apply_plan_to_application_fun() ->
    fun(AppId, ServicesAppJObj, Acc) ->
            AppJObj = maps:get(AppId, Acc, 'undefined'),
            case kz_json:get_ne_binary_value([AppId, <<"publish">>], ServicesAppJObj, 'undefined') of
                'undefined' ->
                    Acc;
                <<"block">> when AppJObj =/= 'undefined' ->
                    Setters = [{fun kzd_applications:set_published/2, 'false'}
                              ,{fun kzd_applications:set_pvt_authority/2, <<"service_plan">>}
                              ],
                    maps:put(AppId, kz_doc:setters(AppJObj, Setters), Acc);
                <<"allow">> when AppJObj =/= 'undefined' ->
                    Setters = [{fun kzd_applications:set_published/2, 'true'}
                              ,{fun kzd_applications:set_pvt_authority/2, <<"service_plan">>}
                              ],
                    maps:put(AppId, kz_doc:setters(AppJObj, Setters), Acc);
                _ ->
                    Acc
            end
    end.

-spec apply_application_entitlements(kz_term:ne_binary(), kz_term:ne_binary()
                                    ,kz_term:api_ne_binary(), apps_map()
                                    ) -> apps_map().
apply_application_entitlements(AppType, AccountId, UserId, Acc) ->
    LoadOptions = [{'startkey', [AppType]}
                  ,{'endkey', [AppType, kz_term:high_unicode_value()]}
                  ],
    Entitlements = load_entitlements(AccountId, LoadOptions),
    Fun = fun (AppId, AppJObj, AccIn) ->
                  JObj = apply_entitlements(AccountId, UserId, Entitlements, AppId, AppJObj),
                  maps:put(AppId, JObj, AccIn)
          end,
    maps:fold(Fun, #{}, Acc).

-spec apply_entitlements(kz_term:ne_binary(), kz_term:api_ne_binary(), apps_map(), kz_term:ne_binary(), kz_json:object()) ->
          kz_json:object().
apply_entitlements(AccountId, UserId, Entitlements, AppId, AppJObj) ->
    case kzd_applications:published(AppJObj, 'true') of
        'false' ->
            %% app is not published or is blocked
            AppJObj;
        'true' ->
            Entitlement = maps:get(AppId, Entitlements, 'undefined'),
            apply_entitlement(AccountId, UserId, AppJObj, Entitlement)
    end.

-spec apply_entitlement(kz_term:ne_binary(), kz_term:api_ne_binary(), kz_json:object(), kz_json:object()) ->
          kz_json:object().
apply_entitlement(_, _, AppJObj, 'undefined') ->
    %% no entitlement means the app is not active for this account
    %% keep this pvt_authority in sync with `cb_applications:should_allow_admin_app_listing/2'
    Setters = [{fun kzd_applications:set_published/2, 'false'}
              ,{fun kzd_applications:set_pvt_authority/2, <<"entitlement">>}
              ],
    kz_doc:setters(AppJObj, Setters);
apply_entitlement(AccountId, UserId, AppJObj, Entitlement) ->
    EntitleType = kzd_application_entitlement:type(Entitlement),
    %% keep this pvt_authority in sync with `cb_applications:should_allow_admin_app_listing/2'
    Setters = [{fun kzd_applications:set_published/2, is_entitled(AccountId, UserId, Entitlement, EntitleType)}
              ,{fun kzd_applications:set_pvt_authority/2, <<"entitlement">>}
              ],
    kz_doc:setters(AppJObj, Setters).

-spec is_entitled(kz_term:ne_binary(), kz_term:api_ne_binary(), kz_json:object(), kz_term:api_ne_binary()) ->
          boolean().
is_entitled(_AccountId, _UserId, _Entitlement, <<"all">>) ->
    'true';
is_entitled(_, 'undefined', _, _) ->
    %% if not 'all' then user id is required to determine the entitlement status
    'false';
is_entitled(AccountId, UserId, _Entitlement, <<"admins">>) ->
    kzd_users:is_account_admin(AccountId, UserId);
is_entitled(_AccountId, UserId, Entitlement, <<"specific">>) ->
    Users = kzd_application_entitlement:users(Entitlement, []),
    lists:member(UserId, Users);
is_entitled(_, _, _, _) ->
    %% bad configuration, dont show the app
    'false'.

-spec load_entitlements(kz_term:ne_binary(), kz_term:proplist()) -> apps_map().
load_entitlements(AccountId, ViewOptions) ->
    case kz_datamgr:get_results(AccountId, <<"application/entitlements">>, ['include_docs' | ViewOptions]) of
        {'ok', JObjs} ->
            maps:from_list(
              [{kzd_application_entitlement:app_id(kz_json:get_value(<<"doc">>, JObj)), kz_json:get_value(<<"doc">>, JObj)}
               || JObj <- JObjs
              ]
             );
        {'error', _Reason} ->
            lager:error("failed to lookup apps in ~s: ~p", [AccountId, _Reason]),
            #{}
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec apps_whitelabel_override(kz_term:ne_binary(), kz_term:api_binary(), apps_map()) -> apps_map().
apps_whitelabel_override(AccountId, _UserId, AppsMap) ->
    {'ok', MasterAccountId} = kapps_util:get_master_account_id(),
    case AccountId =:= MasterAccountId of
        'true' -> AppsMap;
        'false' ->
            Overrides = fetch_apps_whitelabel_overrides(AccountId, AppsMap),
            maps:map(merge_app_whitelabel(Overrides), AppsMap)
    end.

-spec fetch_apps_whitelabel_overrides(AccountId::kz_term:ne_binary(), AppsMap::apps_map()) -> Overrides::apps_map().
fetch_apps_whitelabel_overrides(AccountId, AppsMap) ->
    AppIds = [app_whitelabel_doc_id(AppId) || AppId <- maps:keys(AppsMap)],
    case kz_datamgr:open_docs(AccountId, AppIds) of
        {'ok', JObjs} ->
            maps:from_list(
              [{app_whitelabel_doc_id_to_app_id(kz_doc:id(Doc)), Doc}
               || JObj <- JObjs,
                  Doc <- [kz_json:get_json_value(<<"doc">>, JObj)],
                  Doc =/= 'undefined'
              ]
             );
        {'error', _Reason} ->
            lager:debug("failed to get app overrides for account ~s: ~p", [AccountId, _Reason]),
            #{}
    end.

-spec merge_app_whitelabel(apps_map()) ->
          fun((kz_term:ne_binary(), kz_json:object()) -> kz_json:object()).
merge_app_whitelabel(Overrides) ->
    DeleteKeys = [<<"publish">>, <<"allowed_users">>, <<"name">>],
    fun(AppId, AppJObj) ->
            Override = maps:get(AppId, Overrides, kz_json:new()),
            merge_attachment_wise(AppJObj
                                 ,kz_json:delete_keys(DeleteKeys, kz_doc:public_fields(Override, 'false'))
                                 ,<<"app_whitelabel">>
                                 ,kz_doc:id(Override)
                                 ,kz_doc:account_db(Override)
                                 ,kz_doc:attachments(Override)
                                 )
    end.

%%------------------------------------------------------------------------------
%% @doc Load the application list from the accounts service plan, or the
%% reseller if that is empty. Set the published parameter on each app doc,
%% loading the doc if missing and nnot from the master, if its set in the
%% service plan.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_service_plan(kz_term:ne_binary(), kz_term:api_ne_binary(), apps_map()) -> apps_map().
allowed_service_plan(AccountId, _UserId, AppsMap) ->
    ServicesApps = get_services_apps(AccountId),
    Props = [{<<"authority">>, <<"service_plan">>}],
    maps:map(fun(AppId, AppJObj) ->
                     case kz_json:is_true([AppId, <<"enabled">>], ServicesApps, 'undefined') of
                         'undefined' -> AppJObj;
                         'true' -> kzd_app:publish(kz_json:set_values(Props, AppJObj));
                         'false' -> kzd_app:unpublish(kz_json:set_values(Props, AppJObj))
                     end
             end
            ,ensure_allowed_service_apps(ServicesApps, AppsMap)
            ).

-spec ensure_allowed_service_apps(kz_json:object(), apps_map()) -> apps_map().
ensure_allowed_service_apps(ServicesApps, AppsMap) ->
    {'ok', MasterAccountId} = kapps_util:get_master_account_id(),
    kz_json:foldl(ensure_allowed_service_apps_fold(MasterAccountId), AppsMap, ServicesApps).

-spec ensure_allowed_service_apps_fold(kz_term:ne_binary()) ->
          fun((kz_term:ne_binary(), kz_json:object(), apps_map()) -> apps_map()).
ensure_allowed_service_apps_fold(MasterAccountId) ->
    fun(AppId, ServicesAppJObj, AppsMap) ->
            VendorId = kz_json:get_ne_binary_value(<<"vendor_id">>, ServicesAppJObj, MasterAccountId),
            Enabled = kz_json:is_true(<<"enabled">>, ServicesAppJObj, 'true'),
            case VendorId =/= MasterAccountId
                andalso Enabled
            of
                'true' -> add_service_app_doc(VendorId, AppId, AppsMap);
                'false' -> AppsMap
            end
    end.

-spec add_service_app_doc(kz_term:ne_binary(), kz_term:ne_binary(), apps_map()) -> apps_map().
add_service_app_doc(VendorId, AppId, AppsMap) ->
    case kzd_app:fetch(VendorId, AppId) of
        {'ok', VendorAppJObj} ->
            lager:debug("including service app ~s from ~s"
                       ,[kzd_app:name(VendorAppJObj), VendorId]
                       ),
            Props = [{<<"authority">>, <<"vendor_account">>}
                    ,{<<"pvt_account_id">>, VendorId}
                    ,{<<"pvt_account_db">>, kzs_util:format_account_db(VendorId)}
                    ],
            AppJObj = maps:get(AppId, AppsMap, kz_json:new()),
            AppsMap#{AppId => merge_attachment_wise(AppJObj
                                                   ,kz_json:set_values(Props, VendorAppJObj)
                                                   ,<<"service_plan">>
                                                   )
                    };
        {'error', _R} ->
            AppsMap
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec allowed_apps_store_doc(kz_term:ne_binary(), kz_term:api_binary(), apps_map()) -> apps_map().
allowed_apps_store_doc(AccountId, UserId, AppsMap) ->
    case kzd_apps_store:fetch(AccountId) of
        {'error', _R} ->
            lager:error("failed to fetch apps store doc in ~s : ~p"
                       ,[AccountId, _R]
                       ),
            AppsMap;
        {'ok', AppStoreJObj} ->
            maps:map(allowed_apps_store_doc_map(AccountId, UserId, AppStoreJObj)
                    ,AppsMap
                    )
    end.

-spec allowed_apps_store_doc_map(kz_term:ne_binary(), kz_term:api_binary(), kz_json:object()) ->
          fun((kz_term:ne_binary(), kz_json:object()) -> kz_json:object()).
allowed_apps_store_doc_map(AccountId, UserId, AppStoreJObj) ->
    fun(AppId, AppJObj) ->
            AppPermissions = kz_json:get_ne_json_value(AppId, kzd_apps_store:apps(AppStoreJObj)),
            case is_blacklisted(AppJObj, AppStoreJObj) of
                'true' ->
                    Props = [{<<"authority">>, <<"app_store_blacklist">>}],
                    kzd_app:unpublish(kz_json:set_values(Props, AppJObj));
                'false' when AppPermissions =:= 'undefined' -> AppJObj;
                'false' ->
                    Authority = kz_json:from_list([{<<"authority">>, <<"app_store">>}]),
                    IsPublished = kzd_app:is_published(AppJObj),
                    case is_authorized(AccountId, UserId, AppPermissions) of
                        'true' when IsPublished ->
                            kz_json:merge([kzd_app:publish(AppJObj), AppPermissions, Authority]);
                        'true' ->
                            kz_json:merge([AppJObj, AppPermissions]);
                        'false' ->
                            kz_json:merge([kzd_app:unpublish(AppJObj), AppPermissions, Authority])
                    end
            end
    end.

-spec is_authorized(kz_term:ne_binary(), kz_term:api_ne_binary(), kz_json:object()) -> boolean().
is_authorized(_, 'undefined', _) ->
    'true';
is_authorized(AccountId, UserId, AppPermissions) ->
    AllowedType = kzd_app:allowed_users(AppPermissions, <<"specific">>),
    SpecificIds = get_specific_ids(kzd_app:users(AppPermissions)),
    case {AllowedType, SpecificIds} of
        {<<"all">>, _} -> 'true';
        {<<"specific">>, []} -> 'false';
        {<<"specific">>, UserIds} ->
            lists:member(UserId, UserIds);
        {<<"admins">>, _} ->
            kzd_users:is_account_admin(AccountId, UserId);
        {_A, _U} ->
            lager:error("unknown data ~p : ~p", [_A, _U]),
            'false'
    end.

-spec get_specific_ids(kz_term:ne_binaries()) -> kz_term:ne_binaries().
get_specific_ids(UserIds) ->
    [UserId || UserId <- UserIds, is_binary(UserId)].

-spec is_blacklisted(kz_json:object(), kz_json:object()) -> boolean().
is_blacklisted(App, JObj) ->
    Blacklist = kzd_apps_store:blacklist(JObj),
    lists:member(kz_doc:id(App), Blacklist).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec allowed_whitelabel_doc(kz_term:ne_binary(), kz_term:api_binary(), apps_map()) -> apps_map().
allowed_whitelabel_doc(AccountId, _UserId, AppsMap) ->
    WhitelabelJObj = get_whitelabel_doc(AccountId),
    IsReseller = kz_services_reseller:is_reseller(AccountId),
    maps:map(fun(_, AppJObj) ->
                     case kzd_app:name(AppJObj) =:= <<"port">>
                         andalso (not IsReseller)
                         andalso kzd_whitelabel:hide_port(WhitelabelJObj)
                     of
                         'false' -> AppJObj;
                         'true' ->
                             Props = [{<<"authority">>, <<"whitelabel_hide_port">>}],
                             kzd_app:unpublish(kz_json:set_values(Props, AppJObj))
                     end
             end
            ,AppsMap
            ).

-spec get_whitelabel_doc(kz_term:ne_binary()) -> kz_json:object().
get_whitelabel_doc(AccountId) ->
    case kzd_whitelabel:fetch(AccountId) of
        {'ok', JObj} -> JObj;
        {'error', 'not_found'} ->
            kzd_whitelabel:new();
        {'error', _R} ->
            lager:error("failed to load whitelabel doc for ~s: ~p"
                       ,[AccountId, _R]
                       ),
            kzd_whitelabel:new()
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec allowed_master_account(kz_term:ne_binary(), kz_term:api_binary(), apps_map()) -> apps_map().
allowed_master_account(AccountId, _UserId, AppsMap) ->
    {'ok', MasterAccountId} = kapps_util:get_master_account_id(),
    case AccountId =:= MasterAccountId of
        'false' -> AppsMap;
        'true' ->
            Props = [{<<"authority">>, <<"super_admin">>}],
            maps:map(fun(_AppId, AppJObj) ->
                             kzd_app:publish(kz_json:set_values(Props, AppJObj))
                     end
                    ,AppsMap
                    )
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec load_default_apps() -> apps().
load_default_apps() ->
    load_default_apps('false').

-spec load_default_apps(ReturnAsMap::boolean()) -> apps().
load_default_apps(ReturnAsMap) ->
    {'ok', MasterAccountDb} = kapps_util:get_master_account_db(),
    case kz_datamgr:get_results(MasterAccountDb, ?CB_APPS_STORE_LIST, ['include_docs']) of
        {'ok', JObjs} ->
            return_load_default(MasterAccountDb, JObjs, ReturnAsMap);
        {'error', _E} ->
            lager:error("failed to lookup apps in ~s", [MasterAccountDb]),
            return_load_default(MasterAccountDb, [], ReturnAsMap)

    end.

-spec load_default_app(kz_term:ne_binary()) -> apps().
load_default_app(AppId) ->
    load_default_app(AppId).

-spec load_default_app(kz_term:ne_binary(), ReturnAsMap::boolean()) -> apps().
load_default_app(AppId, ReturnAsMap) ->
    {'ok', MasterAccountDb} = kapps_util:get_master_account_db(),
    case kz_datamgr:open_doc(MasterAccountDb, AppId) of
        {'ok', JObj} ->
            return_load_default(MasterAccountDb, [JObj], ReturnAsMap);
        {'error', _E} ->
            lager:error("failed to lookup app ~s in ~s", [AppId, MasterAccountDb]),
            return_load_default(MasterAccountDb, [], ReturnAsMap)
    end.

return_load_default(MasterAccountDb, JObjs, 'true') ->
    %% next line we use Doc as default because this function may be called from outside
    %% and app doc is directly opened
    maps:from_list(
      [{kz_doc:id(JObj), ensure_master_account_id(MasterAccountDb, kz_json:get_value(<<"doc">>, JObj, JObj))}
       || JObj <- JObjs
      ]
     );
return_load_default(MasterAccountDb, JObjs, 'false') ->
    [ensure_master_account_id(MasterAccountDb, kz_json:get_value(<<"doc">>, JObj, JObj))
     || JObj <- JObjs
    ].

-spec ensure_master_account_id(kz_term:ne_binary(), kz_json:object()) -> kz_json:object().
ensure_master_account_id(Account, Doc) ->
    AccountId = kzs_util:format_account_id(Account),
    AccountDb = kzs_util:format_account_db(Account),
    Props = [{<<"authority">>, <<"master_account">>}
            ,{[<<"pvt_app_attachments">>, <<"master">>, <<"_id">>], kz_doc:id(Doc)}
            ,{[<<"pvt_app_attachments">>, <<"master">>, <<"pvt_account_db">>], AccountDb}
            ,{[<<"pvt_app_attachments">>, <<"master">>, <<"_attachments">>], kz_doc:attachments(Doc)}
            ],
    JObj = kz_json:set_values(Props, Doc),
    case kz_doc:account_db(JObj) =/= AccountDb
        orelse kz_doc:account_id(JObj) =/= AccountId
    of
        'false' -> JObj;
        'true' ->
            set_account(Account, JObj)
    end.

-spec set_account(kz_term:ne_binary(), kz_json:object()) -> kz_json:object().
set_account(Account, JObj) ->
    AccountDb = kzs_util:format_account_db(Account),
    Corrected =
        kz_json:set_values(
          [{<<"pvt_account_id">>, kzs_util:format_account_id(Account)}
          ,{<<"pvt_account_db">>, AccountDb}
          ], JObj),
    case kz_datamgr:save_doc(AccountDb, Corrected) of
        {'ok', Doc} -> Doc;
        {'error', _R} ->
            lager:error("failed to correct app"),
            Corrected
    end.

%%--1----------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec create_apps_store_doc(kz_term:ne_binary()) -> {'ok', kz_json:object()} | {'error', any()}.
create_apps_store_doc(Account) ->
    Doc = kzd_apps_store:new(Account),
    kz_datamgr:save_doc(kzs_util:format_account_db(Account), Doc).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec get_services_apps(kz_term:ne_binary()) -> kz_json:object().
get_services_apps(AccountId) ->
    ServicesApps = kz_services_applications:fetch(AccountId),
    case kz_term:is_not_empty(ServicesApps)
        orelse kz_services_reseller:is_reseller(AccountId)
    of
        'true' -> ServicesApps;
        'false' ->
            ResellerId = kz_services_reseller:get_id(AccountId),
            lager:debug("account ~s doesn't have apps in service plan, checking reseller ~s"
                       ,[AccountId, ResellerId]
                       ),
            kz_services_applications:fetch(ResellerId)
    end.

%%------------------------------------------------------------------------------
%% @doc Merge specific app document to app document while preserving where
%% attachments are coming from.
%% @end
%%------------------------------------------------------------------------------
-spec merge_attachment_wise(kz_json:object(), kz_json:object(), kz_json:key()) -> kz_json:object().
merge_attachment_wise(AppJObj, NewAppJObj, Type) ->
    merge_attachment_wise(AppJObj
                         ,NewAppJObj
                         ,Type
                         ,kz_doc:id(NewAppJObj)
                         ,kz_doc:account_db(NewAppJObj)
                         ,kz_doc:attachments(NewAppJObj)
                         ).

-spec merge_attachment_wise(kz_json:object(), kz_json:object(), kz_json:key()
                           ,kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()
                           ) -> kz_json:object().
merge_attachment_wise(AppJObj, NewAppJObj, Type, NewDocId, NewAccountDb, NewAttachments) ->
    Prop = [{[<<"pvt_app_attachments">>, Type, <<"_id">>], NewDocId}
           ,{[<<"pvt_app_attachments">>, Type, <<"pvt_account_db">>], NewAccountDb}
           ,{[<<"pvt_app_attachments">>, Type, <<"_attachments">>], NewAttachments}
           ],
    kz_json:set_values(Prop, kz_json:merge(AppJObj, kz_json:delete_keys(kz_doc:path_attachments(), NewAppJObj))).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec find_attachment(kz_json:object(), kz_term:api_ne_binary()) ->
          kz_either:either('not_found'
                          ,{AttachmentName::kz_term:ne_binary(), AttachmentsObject::kz_json:object()}
                          ).
find_attachment(_, 'undefined') ->
    {'error', 'not_found'};
find_attachment(JObj, AttachmentName) ->
    %% order of finding attachment key is important
    %% for example reseller can override master
    Keys = [<<"reseller">> %% only application
           ,<<"app_whitelabel">> %% only app
           ,<<"service_plan">> %% only app
           ,<<"master">> %% both application and app
           ],
    find_attachment(JObj, AttachmentName, Keys).

-spec find_attachment(kz_json:object(), kz_term:api_ne_binary(), kz_json:keys()) ->
          kz_either:either('not_found'
                          ,{AttachmentName::kz_term:ne_binary(), AttachmentsObject::kz_json:object()}
                          ).
find_attachment(JObj, AttachmentName, []) ->
    %% if app doc is opened via crossbar_doc:load_doc
    case kz_doc:attachment(JObj, AttachmentName) of
        'undefined' ->
            {'error', 'not_found'};
        _AttObj ->
            {'ok', {AttachmentName, JObj}}
    end;
find_attachment(JObj, AttachmentName, [Key | Keys]) ->
    %% if the app doc is opened via allowed_app(s)/allowed_application(s)
    Path = [<<"pvt_app_attachments">>, Key, <<"_attachments">>, AttachmentName],
    case kz_term:is_empty(kz_json:get_ne_json_value(Path, JObj)) of
        'true' ->
            find_attachment(JObj, AttachmentName, Keys);
        'false' ->
            {'ok', {AttachmentName
                   ,kz_json:get_json_value([<<"pvt_app_attachments">>, Key], JObj)
                   }
            }
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec app_whitelabel_doc_id(AppId::kz_term:ne_binary()) -> DocId::kz_term:ne_binary().
app_whitelabel_doc_id(AppId) ->
    <<"app_whitelabel-", AppId/binary>>.

-spec app_whitelabel_doc_id_to_app_id(AppWhitelabelId::kz_term:ne_binary()) -> AppId::kz_term:ne_binary().
app_whitelabel_doc_id_to_app_id(<<"app_whitelabel-", AppId/binary>>) ->
    AppId;
app_whitelabel_doc_id_to_app_id(Other) ->
    Other.

%%------------------------------------------------------------------------------
%% @doc Check apps and if they are from Marketplace check if their apps are running.
%%
%% This will make sure the Marketplace apps which are currently  not running
%% will not be listed in available apps and makes MUI or Commland App loaders
%% only show current running apps.
%% @end
%%------------------------------------------------------------------------------
-spec maybe_remove_kappex_apps(kz_term:ne_binary(), kz_term:api_ne_binary(), apps_map()) -> apps_map().
maybe_remove_kappex_apps(_AccountId, _UserId, AppsMap) ->
    Kapps = get_kapps(),
    maps:fold(fun (AppId, AppJObj, AppsMapAcc) ->
                      %% `from_kappex' is set by UI wrapper in metadata doc on app startup
                      IsFromKappex = kz_json:is_true(<<"from_kappex">>, AppJObj),
                      case should_remove_kappex_app(Kapps, AppJObj, IsFromKappex) of
                          'true' ->
                              AppsMapAcc;
                          'false' ->
                              AppsMapAcc#{AppId => AppJObj}
                      end
              end
             ,#{}
             ,AppsMap
             ).

%%------------------------------------------------------------------------------
%% @doc Check apps and if they are from Marketplace check if their apps are running.
%%
%% Equivalent to `maybe_remove_kappex_apps(AccountId, UserId, AppsMap)'
%% @end
%%------------------------------------------------------------------------------
-spec maybe_remove_kappex_apps(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_ne_binary(), apps_map()) -> apps_map().
maybe_remove_kappex_apps(_AppType, AccountId, UserId, AppsMap) ->
    maybe_remove_kappex_apps(AccountId, UserId, AppsMap).

%%------------------------------------------------------------------------------
%% @doc Get a list of all running app across the whole cluster.
%% @end
%%------------------------------------------------------------------------------
-spec get_kapps() -> kz_term:ne_binaries().
get_kapps() ->
    ZoneProperties = [kz_json:values(ZoneNode) || ZoneNode <- kz_json:values(kz_nodes:status_to_json())],
    NodeProperties = [kz_json:values(NodeType) || NodeType <- lists:append(ZoneProperties)],
    RunningKapps = [kz_json:get_list_value(<<"kapps">>, Node, [])
                    || Node <- lists:append(NodeProperties)
                   ],
    lists:usort(lists:append(RunningKapps)).

-spec should_remove_kappex_app(kz_term:ne_binaries(), kz_json:object(), boolean()) -> boolean().
should_remove_kappex_app(Kapps, AppJObj, 'true') ->
    KappexName = get_app_kappex_name(AppJObj),
    not lists:member(KappexName, Kapps);
should_remove_kappex_app(_Kapps, _AppJObj, 'false') ->
    'false'.

%%------------------------------------------------------------------------------
%% @doc Get OTP name of the app from kappex_name field in metadata or make
%% name it in case metadata is old and does not have that field.
%% @end
%%------------------------------------------------------------------------------
-spec get_app_kappex_name(kz_json:object()) -> kz_term:ne_binary().
get_app_kappex_name(AppJObj) ->
    %% `kappex_name' is set by UI wrapper in metadata doc on app startup
    case kz_json:get_ne_binary_value(<<"kappex_name">>, AppJObj) of
        'undefined' ->
            kappexify_appname(AppJObj);
        KappexName ->
            KappexName
    end.

%%------------------------------------------------------------------------------
%% @doc Convert the UI app name to valid OTP and appex app name .
%%
%% Appex UI apps are prefix either with `commland_' or `monsterui_'.
%% @end
%%------------------------------------------------------------------------------
-spec kappexify_appname(kz_json:object()) -> kz_term:ne_binary().
kappexify_appname(AppJObj) ->
    Name = binary:replace(kzd_applications:name(AppJObj, <<>>), <<"-">>, <<"_">>, ['global']),
    case kzd_applications:type(AppJObj) of
        <<"commland_ui">> ->
            <<"commland_", Name/binary>>;
        _ ->
            <<"monsterui_", Name/binary>>
    end.
