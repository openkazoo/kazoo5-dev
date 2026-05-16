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
-module(pqc_cb_callflows).

-export([summary/2]).
-export([create/3]).
-export([fetch/3]).
-export([update/3]).
-export([patch/4]).
-export([delete/3]).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, callflows_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_callflows:doc()) -> pqc_cb_api:response().
create(API, AccountId, CallflowJObj) ->
    Envelope = pqc_cb_api:create_envelope(CallflowJObj),
    pqc_cb_crud:create(API, callflows_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, CallflowId) ->
    pqc_cb_crud:fetch(API, callflow_url(API, AccountId, CallflowId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_callflows:doc()) -> pqc_cb_api:response().
update(API, AccountId, CallflowJObj) ->
    Envelope = pqc_cb_api:create_envelope(CallflowJObj),
    pqc_cb_crud:update(API, callflow_url(API, AccountId, kz_doc:id(CallflowJObj)), Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, CallflowId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, callflow_url(API, AccountId, CallflowId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, CallflowId) ->
    pqc_cb_crud:delete(API, callflow_url(API, AccountId, CallflowId)).

-spec callflows_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
callflows_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"callflows">>).

-spec callflow_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
callflow_url(API, AccountId, CallflowId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"callflows">>, CallflowId).
