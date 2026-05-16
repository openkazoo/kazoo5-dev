%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2026, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_multi_factor).

-export([providers_summary/1
        ,provider_create/2
        ,provider_fetch/2
        ,provider_delete/2
        ,qrcode_create/2
        ]).

-include("properly.hrl").

-spec providers_summary(pqc_cb_api:state()) -> pqc_cb_api:response().
providers_summary(API) ->
    pqc_cb_crud:summary(API, providers_url(API)).

-spec provider_create(pqc_cb_api:state(), kzd_multi_factor_provider:doc()) ->
          pqc_cb_api:response().
provider_create(API, ProviderJObj) ->
    Envelope = pqc_cb_api:create_envelope(ProviderJObj),
    pqc_cb_crud:create(API, providers_url(API), Envelope).

-spec provider_fetch(pqc_cb_api:state(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
provider_fetch(API, ProviderId) ->
    pqc_cb_crud:fetch(API, provider_url(API, ProviderId)).

-spec provider_delete(pqc_cb_api:state(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
provider_delete(API, ProviderId) ->
    pqc_cb_crud:delete(API, provider_url(API, ProviderId)).

-spec providers_url(pqc_cb_api:state()) -> string().
providers_url(API) ->
    pqc_cb_crud:collection_url(API, <<"multi_factor">>).

provider_url(API, ProviderId) ->
    pqc_cb_crud:entity_url(API, <<"multi_factor">>, ProviderId).

-spec qrcode_create(pqc_cb_api:state(), kz_json:json_term()) -> pqc_cb_api:response().
qrcode_create(API, QRDataObj) ->
    URL = qr_url(API),
    RequestEnvelope = pqc_cb_api:create_envelope(QRDataObj),
    Expectations = [pqc_cb_expect:code(201)],
    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"accept">>, "application/json"}
                                                     ,{<<"content-type">>, "application/json"}]),
    pqc_cb_crud:create(API, URL, RequestEnvelope, Expectations, RequestHeaders).

-spec qr_url(pqc_cb_api:state()) -> kz_http:url().
qr_url(API) ->
    Collection = string:join([kz_term:to_list(<<"multi_factor">>), kz_term:to_list(<<"qrcode">>)], "/"),
    pqc_cb_crud:collection_url(API, Collection).