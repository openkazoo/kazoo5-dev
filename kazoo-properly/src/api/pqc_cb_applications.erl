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
-module(pqc_cb_applications).

-export([summary/2
        ,create/4
        ,fetch/3
        ,delete/3
        ,update/4
        ,patch/4

        ,allowed_apps/4
        ,allowed_app/5

        ,applications_url/2
        ,application_url/3

        ,new_application_doc/1
        ,new_application_doc/2
        ]).

-export([summary_blocklists/3
        ,fetch_blocklist/4
        ,create_blocklist/4
        ,delete_blocklist/4

        ,blocklists_url/3
        ,blocklist_url/4
        ]).
-export([summary_entitlements/3
        ,fetch_entitlement/4
        ,create_entitlement/5
        ,update_entitlement/5
        ,delete_entitlement/4

        ,entitlements_url/3
        ,entitlement_url/4
        ]).

-define(TEST_FILTER, <<"seq_applications">>).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, applications_url(API, AccountId)).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, AppId) ->
    pqc_cb_crud:fetch(API, application_url(API, AccountId, AppId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
create(API, AccountId, AppId, ApplicationJObj) ->
    Envelope = pqc_cb_api:create_envelope(ApplicationJObj),
    pqc_cb_crud:create(API, application_url(API, AccountId, AppId), Envelope).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
update(API, AccountId, ApplicationId, ApplicationJObj) ->
    Envelope = pqc_cb_api:create_envelope(ApplicationJObj),
    pqc_cb_crud:update(API, application_url(API, AccountId, ApplicationId), Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, ApplicationId, ApplicationJObj) ->
    Envelope = pqc_cb_api:create_envelope(ApplicationJObj),
    pqc_cb_crud:patch(API, application_url(API, AccountId, ApplicationId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, AppId) ->
    pqc_cb_crud:delete(API, application_url(API, AccountId, AppId)).

-spec allowed_apps(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:api_ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
allowed_apps(API, AccountId, UserId, AppType) ->
    pqc_cb_crud:summary(API, allowed_apps_url(API, AccountId, UserId, AppType)).

-spec allowed_app(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:api_ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
allowed_app(API, AccountId, UserId, AppType, AppId) ->
    pqc_cb_crud:fetch(API, allowed_app_url(API, AccountId, UserId, AppType, AppId)).

-spec summary_blocklists(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary_blocklists(API, AccountId, AppType) ->
    pqc_cb_crud:summary(API, blocklists_url(API, AccountId, AppType)).

-spec fetch_blocklist(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch_blocklist(API, AccountId, AppType, AppId) ->
    pqc_cb_crud:fetch(API, blocklist_url(API, AccountId, AppType, AppId)).

-spec create_blocklist(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
create_blocklist(API, AccountId, AppType, AppId) ->
    Envelope = pqc_cb_api:create_envelope(kz_json:new()),
    pqc_cb_crud:create(API, blocklist_url(API, AccountId, AppType, AppId), Envelope).

-spec delete_blocklist(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete_blocklist(API, AccountId, AppType, AppId) ->
    pqc_cb_crud:delete(API, blocklist_url(API, AccountId, AppType, AppId)).

-spec summary_entitlements(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary_entitlements(API, AccountId, AppType) ->
    pqc_cb_crud:summary(API, entitlements_url(API, AccountId, AppType)).

-spec fetch_entitlement(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch_entitlement(API, AccountId, AppType, AppId) ->
    pqc_cb_crud:fetch(API, entitlement_url(API, AccountId, AppType, AppId)).

-spec create_entitlement(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
create_entitlement(API, AccountId, AppType, AppId, EntitlementObj) ->
    Envelope = pqc_cb_api:create_envelope(EntitlementObj),
    pqc_cb_crud:create(API, entitlement_url(API, AccountId, AppType, AppId), Envelope).

-spec update_entitlement(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
update_entitlement(API, AccountId, AppType, AppId, EntitlementObj) ->
    Envelope = pqc_cb_api:create_envelope(EntitlementObj),
    pqc_cb_crud:update(API, entitlement_url(API, AccountId, AppType, AppId), Envelope).

-spec delete_entitlement(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete_entitlement(API, AccountId, AppType, AppId) ->
    pqc_cb_crud:delete(API, entitlement_url(API, AccountId, AppType, AppId)).

-spec applications_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
applications_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"applications">>).

-spec allowed_apps_url(pqc_cb_api:state(), kz_term:ne_binary(),  kz_term:api_ne_binary(), kz_term:ne_binary()) -> string().
allowed_apps_url(API, AccountId, 'undefined', AppType) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"applications">>, AppType);
allowed_apps_url(API, AccountId, UserId, AppType) ->
    string:join([pqc_cb_users:user_url(API, AccountId, UserId)
                ,"applications"
                ,kz_term:to_list(AppType)
                ], "/").

-spec allowed_app_url(pqc_cb_api:state(), kz_term:ne_binary(),  kz_term:api_ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
allowed_app_url(API, AccountId, 'undefined', AppType, AppId) ->
    string:join([pqc_cb_accounts:account_url(API, AccountId)
                ,"applications"
                ,kz_term:to_list(AppType)
                ,kz_term:to_list(AppId)
                ], "/");
allowed_app_url(API, AccountId, UserId, AppType, AppId) ->
    string:join([pqc_cb_users:user_url(API, AccountId, UserId)
                ,"applications"
                ,kz_term:to_list(AppType)
                ,kz_term:to_list(AppId)
                ], "/").

-spec application_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
application_url(API, AccountId, AppId) ->
    string:join([pqc_cb_accounts:account_url(API, AccountId)
                ,"applications"
                ,"application"
                ,kz_term:to_list(AppId)
                ], "/").

-spec blocklists_url(pqc_cb_api:state(), kz_term:ne_binary(),  kz_term:ne_binary()) -> string().
blocklists_url(API, AccountId, AppType) ->
    string:join([pqc_cb_accounts:account_url(API, AccountId)
                ,"applications"
                ,kz_term:to_list(AppType)
                ,"blocklists"
                ], "/").

-spec blocklist_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
blocklist_url(API, AccountId, AppType, AppId) ->
    string:join([pqc_cb_accounts:account_url(API, AccountId)
                ,"applications"
                ,kz_term:to_list(AppType)
                ,kz_term:to_list(AppId)
                ,"block"
                ], "/").

-spec entitlements_url(pqc_cb_api:state(), kz_term:ne_binary(),  kz_term:ne_binary()) -> string().
entitlements_url(API, AccountId, AppType) ->
    string:join([pqc_cb_accounts:account_url(API, AccountId)
                ,"applications"
                ,kz_term:to_list(AppType)
                ,"entitlements"
                ], "/").

-spec entitlement_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
entitlement_url(API, AccountId, AppType, AppId) ->
    string:join([pqc_cb_accounts:account_url(API, AccountId)
                ,"applications"
                ,kz_term:to_list(AppType)
                ,kz_term:to_list(AppId)
                ,"entitlement"
                ], "/").

-spec new_application_doc(kz_term:ne_binary()) -> kz_json:object().
new_application_doc(AppType) ->
    new_application_doc(AppType, kz_binary:rand_hex(5)).

-spec new_application_doc(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_json:object().
new_application_doc(AppType, Name) ->
    Setters = [{fun kzd_applications:set_author/2, kz_binary:rand_hex(6)}
              ,{fun kzd_applications:set_license/2, kz_binary:rand_hex(10)}
              ,{fun kzd_applications:set_name/2, Name}
              ,{fun kzd_applications:set_version/2, kz_binary:rand_hex(3)}
              ,{fun kzd_applications:set_type/2, AppType}
              ],

    %% adding extra field so we can search for doc in master account on cleanup
    kz_json:set_value(?TEST_FILTER
                     ,'true'
                     ,kz_doc:setters(kzd_applications:new(), Setters)
                     ).
