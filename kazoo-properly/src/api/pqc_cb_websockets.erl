%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2024-, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_websockets).

%% API functions
-export([available/1

         %% Account operations
        ,summary/2
        ,details/3
        ]).

-include("properly.hrl").

-spec available(pqc_cb_api:state()) -> pqc_cb_api:response().
available(API) ->
    URL = base_websockets_url(API),
    pqc_cb_crud:summary(API, URL).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    WebsocketsURL = websockets_url(API, AccountId),
    pqc_cb_crud:summary(API, WebsocketsURL).

-spec details(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
details(API, AccountId, WebsocketId) ->
    URL = websocket_url(API, AccountId, WebsocketId),
    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],
    pqc_cb_crud:fetch(API, URL, Expectations).

-spec base_websockets_url(pqc_cb_api:state()) -> string().
base_websockets_url(API) ->
    pqc_cb_crud:collection_url(API, <<"websockets">>).

-spec websockets_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
websockets_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"websockets">>).

-spec websocket_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
websocket_url(API, AccountId, WebsocketId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"websockets">>, WebsocketId).
