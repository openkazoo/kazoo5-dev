%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_commland).

%% API Shims
-export([compatibility/1]).

-include("properly.hrl").

-spec compatibility(pqc_cb_api:state()) -> pqc_cb_api:response().
compatibility(#{request_id := RequestId}=API) ->
    pqc_cb_api:make_request([pqc_cb_expect:code(200)]
                           ,fun(URL, ReqHeaders) -> kz_http:get(URL, ReqHeaders, [{'autoredirect', 'false'}]) end
                           ,compat_url(API)
                           ,pqc_cb_api:default_request_headers(RequestId)
                           ).

compat_url(API) ->
    pqc_cb_crud:entity_url(API, <<"commland">>, <<"compatibility">>).
