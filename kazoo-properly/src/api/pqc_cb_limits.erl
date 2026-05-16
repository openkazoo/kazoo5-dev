%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2024-, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_limits).

-export([fetch/2
        ,update/3
        ]).

-include("properly.hrl").

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, <<AccountId/binary>>) ->
    pqc_cb_crud:fetch(API, limits_url(API, AccountId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
update(API, <<AccountId/binary>>, JObj) ->
    RequestEnvelope = pqc_cb_api:create_envelope(JObj),
    pqc_cb_crud:update(API, limits_url(API, AccountId), RequestEnvelope).

-spec limits_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
limits_url(API, <<AccountId/binary>>) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"limits">>).
