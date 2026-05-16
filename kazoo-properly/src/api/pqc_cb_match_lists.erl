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
-module(pqc_cb_match_lists).

-export([summary/2]).
-export([create/3]).
-export([fetch/3]).
-export([update/3]).
-export([patch/4]).
-export([delete/3]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, lists_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_lists:doc()) -> pqc_cb_api:response().
create(API, AccountId, ListJObj) ->
    Envelope = pqc_cb_api:create_envelope(ListJObj),
    pqc_cb_crud:create(API, lists_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, ListId) ->
    pqc_cb_crud:fetch(API, list_url(API, AccountId, ListId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_lists:doc()) -> pqc_cb_api:response().
update(API, AccountId, ListJObj) ->
    Envelope = pqc_cb_api:create_envelope(ListJObj),
    pqc_cb_crud:update(API, list_url(API, AccountId, kz_doc:id(ListJObj)), Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, ListId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, list_url(API, AccountId, ListId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, ListId) ->
    pqc_cb_crud:delete(API, list_url(API, AccountId, ListId)).


-spec lists_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
lists_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"match_lists">>).

-spec list_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
list_url(API, AccountId, ListId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"match_lists">>, ListId).
