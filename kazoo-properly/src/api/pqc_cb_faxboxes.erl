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
-module(pqc_cb_faxboxes).

-export([summary/2]).
-export([create/3]).
-export([fetch/3]).
-export([update/3]).
-export([patch/4]).
-export([delete/3]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, faxboxes_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_faxbox:doc()) -> pqc_cb_api:response().
create(API, AccountId, FaxboxJObj) ->
    Envelope = pqc_cb_api:create_envelope(FaxboxJObj),
    pqc_cb_crud:create(API, faxboxes_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, FaxboxId) ->
    pqc_cb_crud:fetch(API, faxbox_url(API, AccountId, FaxboxId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_faxbox:doc()) -> pqc_cb_api:response().
update(API, AccountId, FaxboxJObj) ->
    Envelope = pqc_cb_api:create_envelope(FaxboxJObj),
    pqc_cb_crud:update(API, faxbox_url(API, AccountId, kz_doc:id(FaxboxJObj)), Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, FaxboxId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, faxbox_url(API, AccountId, FaxboxId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, FaxboxId) ->
    pqc_cb_crud:delete(API, faxbox_url(API, AccountId, FaxboxId)).


-spec faxboxes_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
faxboxes_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"faxboxes">>).

-spec faxbox_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
faxbox_url(API, AccountId, FaxboxId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"faxboxes">>, FaxboxId).
