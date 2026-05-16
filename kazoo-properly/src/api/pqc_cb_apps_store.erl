%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc Apps Store API
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_apps_store).

-export([summary/2, summary/3]).
-export([fetch/3]).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, apps_store_url(API, AccountId)).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId, UserId) ->
    pqc_cb_crud:summary(API, app_user_url(API, AccountId, UserId)).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, AppId) ->
    pqc_cb_crud:fetch(API, app_url(API, AccountId, AppId)).

-spec apps_store_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
apps_store_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"apps_store">>).

-spec app_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
app_url(API, AccountId, AppId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"apps_store">>, AppId).

-spec app_user_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
app_user_url(API, AccountId, UserId) ->
    string:join([pqc_cb_accounts:account_url(API, AccountId)
                ,"users"
                ,kz_term:to_list(UserId)
                ,"apps_store"
                ], "/").
