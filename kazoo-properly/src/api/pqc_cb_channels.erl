%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_channels).

-export([summary/2
        ,fetch/3, fetch/4
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, channels_url(API, AccountId)).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, UUID) ->
    fetch(API, AccountId, UUID, [pqc_cb_expect:code(200)]).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), [pqc_cb_expect:expectation()]) -> pqc_cb_api:response().
fetch(API, AccountId, UUID, Expectations) ->
    pqc_cb_crud:fetch(API, channel_url(API, AccountId, UUID), Expectations).

-spec channels_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
channels_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"channels">>).

-spec channel_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
channel_url(API, AccountId, UUID) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"channels">>, UUID).
