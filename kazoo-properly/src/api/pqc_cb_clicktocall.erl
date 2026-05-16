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
-module(pqc_cb_clicktocall).

-export([summary/2]).
-export([create/3]).
-export([fetch/3]).
-export([update/3]).
-export([patch/4]).
-export([delete/3]).
-export([connect/3]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, clicktocall_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_clicktocall:doc()) -> pqc_cb_api:response().
create(API, AccountId, ClicktocallJObj) ->
    Envelope = pqc_cb_api:create_envelope(ClicktocallJObj),
    pqc_cb_crud:create(API, clicktocall_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, ClicktocallId) ->
    pqc_cb_crud:fetch(API, clicktocall_url(API, AccountId, ClicktocallId)).

-spec connect(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
connect(API, AccountId, ClicktocallId) ->
    pqc_cb_crud:fetch(API, clicktocall_create_url(API, AccountId, ClicktocallId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_clicktocall:doc()) -> pqc_cb_api:response().
update(API, AccountId, ClicktocallJObj) ->
    Envelope = pqc_cb_api:create_envelope(ClicktocallJObj),
    pqc_cb_crud:update(API, clicktocall_url(API, AccountId, kz_doc:id(ClicktocallJObj)), Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, ClicktocallId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, clicktocall_url(API, AccountId, ClicktocallId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, ClicktocallId) ->
    pqc_cb_crud:delete(API, clicktocall_url(API, AccountId, ClicktocallId)).


-spec clicktocall_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
clicktocall_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"clicktocall">>).

-spec clicktocall_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
clicktocall_url(API, AccountId, ClicktocallId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"clicktocall">>, ClicktocallId).

-spec clicktocall_create_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
clicktocall_create_url(API, AccountId, ClicktocallId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"clicktocall">>, <<ClicktocallId/binary, "/connect">>).
