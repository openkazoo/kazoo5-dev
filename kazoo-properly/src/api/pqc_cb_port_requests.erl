%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% @author Manushi Perera
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_port_requests).

-export([summary/2]).
-export([create/3]).
-export([fetch_descendants/2]).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, ports_account_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_port_requests:doc()) -> pqc_cb_api:response().
create(API, AccountId, PortRequestsJObj) ->
    Envelope = pqc_cb_api:create_envelope(PortRequestsJObj),
    pqc_cb_crud:create(API, ports_account_url(API, AccountId), Envelope).

-spec fetch_descendants(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch_descendants(API, AccountId) ->
    pqc_cb_crud:fetch(API, ports_descendants_url(API, AccountId)).

-spec ports_account_url(pqc_cb_api:state(), string() | kz_term:ne_binary()) -> string().
ports_account_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"port_requests">>).

-spec ports_descendants_url(pqc_cb_api:state(), string() | kz_term:ne_binary()) -> string().
ports_descendants_url(API, AccountId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"descendants">>, <<"port_requests">>).
