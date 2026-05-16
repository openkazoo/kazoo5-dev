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
-module(pqc_cb_blacklists).

-export([summary/2]).
-export([create/3]).
-export([fetch/3]).
-export([update/3]).
-export([patch/4]).
-export([delete/3]).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, blacklists_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_blacklists:doc()) -> pqc_cb_api:response().
create(API, AccountId, BlacklistJObj) ->
    Envelope = pqc_cb_api:create_envelope(BlacklistJObj),
    pqc_cb_crud:create(API, blacklists_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, BlacklistId) ->
    pqc_cb_crud:fetch(API, blacklist_url(API, AccountId, BlacklistId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_blacklists:doc()) -> pqc_cb_api:response().
update(API, AccountId, BlacklistJObj) ->
    Envelope = pqc_cb_api:create_envelope(BlacklistJObj),
    pqc_cb_crud:update(API, blacklist_url(API, AccountId, kz_doc:id(BlacklistJObj)), Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, BlacklistId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, blacklist_url(API, AccountId, BlacklistId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, BlacklistId) ->
    pqc_cb_crud:delete(API, blacklist_url(API, AccountId, BlacklistId)).

-spec blacklists_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
blacklists_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"blacklists">>).

-spec blacklist_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
blacklist_url(API, AccountId, BlacklistId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"blacklists">>, BlacklistId).
