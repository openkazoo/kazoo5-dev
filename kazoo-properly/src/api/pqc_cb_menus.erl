%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_menus).

%% API requests
-export([summary/2
        ,create/3
        ,fetch/3
        ,update/3
        ,patch/4
        ,delete/3
        ]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, menus_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_menus:doc()) -> pqc_cb_api:response().
create(API, AccountId, MenuJObj) ->
    URL = menus_url(API, AccountId),
    Envelope = pqc_cb_api:create_envelope(MenuJObj),
    pqc_cb_crud:create(API, URL, Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, MenuId) ->
    pqc_cb_crud:fetch(API, menu_url(API, AccountId, MenuId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_menus:doc()) -> pqc_cb_api:response().
update(API, AccountId, MenuJObj) ->
    URL = menu_url(API, AccountId, kz_doc:id(MenuJObj)),
    Envelope = pqc_cb_api:create_envelope(MenuJObj),
    pqc_cb_crud:update(API, URL, Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, MenuId, PatchJObj) ->
    URL = menu_url(API, AccountId, MenuId),
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, URL, Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, MenuId) ->
    URL = menu_url(API, AccountId, MenuId),
    pqc_cb_crud:delete(API, URL).

-spec menus_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
menus_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"menus">>).

-spec menu_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
menu_url(API, AccountId, MenuId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"menus">>, MenuId).
