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
-module(pqc_cb_temporal_rules_sets).

-export([summary/2]).
-export([create/3]).
-export([fetch/3]).
-export([update/3]).
-export([patch/4]).
-export([delete/3]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, temporal_rules_sets_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_temporal_rules_sets:doc()) -> pqc_cb_api:response().
create(API, AccountId, Temporal_rules_setJObj) ->
    Envelope = pqc_cb_api:create_envelope(Temporal_rules_setJObj),
    pqc_cb_crud:create(API, temporal_rules_sets_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, Temporal_rules_setId) ->
    pqc_cb_crud:fetch(API, temporal_rules_set_url(API, AccountId, Temporal_rules_setId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_temporal_rules_sets:doc()) -> pqc_cb_api:response().
update(API, AccountId, Temporal_rules_setJObj) ->
    Envelope = pqc_cb_api:create_envelope(Temporal_rules_setJObj),
    pqc_cb_crud:update(API, temporal_rules_set_url(API, AccountId, kz_doc:id(Temporal_rules_setJObj)), Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, Temporal_rules_setId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, temporal_rules_set_url(API, AccountId, Temporal_rules_setId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, Temporal_rules_setId) ->
    pqc_cb_crud:delete(API, temporal_rules_set_url(API, AccountId, Temporal_rules_setId)).


-spec temporal_rules_sets_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
temporal_rules_sets_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"temporal_rules_sets">>).

-spec temporal_rules_set_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
temporal_rules_set_url(API, AccountId, Temporal_rules_setId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"temporal_rules_sets">>, Temporal_rules_setId).
