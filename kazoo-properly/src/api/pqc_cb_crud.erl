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
-module(pqc_cb_crud).

%% API requests
-export([summary/2, summary/3, summary/4
        ,create/2, create/3, create/4, create/5
        ,fetch/2, fetch/3, fetch/4
        ,update/3, update/4, update/5
        ,patch/2, patch/3, patch/4, patch/5
        ,delete/2, delete/3, delete/4
        ]).

-export([collection_url/2, collection_url/3
        ,entity_url/3, entity_url/4
        ]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_http:url()) ->
          pqc_cb_api:response().
summary(API, URL) ->
    Expectations = [pqc_cb_expect:code(200)],
    summary(API, URL, Expectations).

-spec summary(pqc_cb_api:state(), kz_http:url(), pqc_cb_expect:expectations()) ->
          pqc_cb_api:response().
summary(API, URL, Expectations) ->
    summary(API, URL, Expectations, pqc_cb_api:request_headers(API)).

-spec summary(pqc_cb_api:state(), kz_http:url(), pqc_cb_expect:expectations(), kz_http:headers()) ->
          pqc_cb_api:response().
summary(_API, URL, Expectations, RequestHeaders) ->
    pqc_cb_api:make_request(Expectations
                           ,fun kz_http:get/2
                           ,URL
                           ,RequestHeaders
                           ).

-spec create(pqc_cb_api:state(), kz_http:url()) -> pqc_cb_api:response().
create(API, URL) ->
    create(API, URL, <<>>).

-spec create(pqc_cb_api:state(), kz_http:url(), kz_json:object() | iodata()) ->
          pqc_cb_api:response().
create(API, URL, RequestEnvelope) ->
    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([201], ExpectedHeaders)],
    create(API, URL, RequestEnvelope, Expectations).

-spec create(pqc_cb_api:state(), kz_http:url(), kz_json:object() | iodata(), pqc_cb_expect:expectations()) ->
          pqc_cb_api:response().
create(API, URL, RequestEnvelope, Expectations) ->
    create(API, URL, RequestEnvelope, Expectations, pqc_cb_api:request_headers(API)).

-spec create(pqc_cb_api:state() | string(), kz_http:url(), kz_json:object() | iodata(), pqc_cb_expect:expectations(), kz_http:headers()) ->
          pqc_cb_api:response().
create(_API, URL, RequestEnvelope, Expectations, RequestHeaders) ->
    pqc_cb_api:make_request(Expectations
                           ,fun kz_http:put/3
                           ,URL
                           ,RequestHeaders
                           ,RequestEnvelope
                           ).

-spec fetch(pqc_cb_api:state(), kz_http:url()) ->
          pqc_cb_api:response().
fetch(API, URL) ->
    Expectations = [pqc_cb_expect:code(200)],
    fetch(API, URL, Expectations).

-spec fetch(pqc_cb_api:state(), kz_http:url(), pqc_cb_expect:expectations()) ->
          pqc_cb_api:response().
fetch(API, URL, Expectations) ->
    fetch(API, URL, Expectations, pqc_cb_api:request_headers(API)).

-spec fetch(pqc_cb_api:state(), kz_http:url(), pqc_cb_expect:expectations(), kz_http:headers()) ->
          pqc_cb_api:response().
fetch(_API, URL, Expectations, RequestHeaders) ->
    pqc_cb_api:make_request(Expectations
                           ,fun kz_http:get/2
                           ,URL
                           ,RequestHeaders
                           ).

-spec update(pqc_cb_api:state(), kz_http:url(), iodata() | kz_json:object()) ->
          pqc_cb_api:response().
update(API, URL, RequestEnvelope) ->
    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],
    update(API, URL, RequestEnvelope, Expectations).

-spec update(pqc_cb_api:state(), kz_http:url(), iodata() | kz_json:object(), pqc_cb_expect:expectations()) ->
          pqc_cb_api:response().
update(API, URL, RequestEnvelope, Expectations) ->
    update(API, URL, RequestEnvelope, Expectations, pqc_cb_api:request_headers(API)).

-spec update(pqc_cb_api:state(), kz_http:url(), iodata() | kz_json:object(), pqc_cb_expect:expectations(), kz_http:headers()) ->
          pqc_cb_api:response().
update(_API, URL, RequestEnvelope, Expectations, RequestHeaders) ->
    pqc_cb_api:make_request(Expectations
                           ,fun kz_http:post/3
                           ,URL
                           ,RequestHeaders
                           ,RequestEnvelope
                           ).

-spec patch(pqc_cb_api:state(), kz_http:url()) ->
          pqc_cb_api:response().
patch(API, URL) ->
    patch(API, URL, <<>>).

-spec patch(pqc_cb_api:state(), kz_http:url(), kz_json:object() | binary()) ->
          pqc_cb_api:response().
patch(API, URL, RequestEnvelope) ->
    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],
    patch(API, URL, RequestEnvelope, Expectations).

-spec patch(pqc_cb_api:state(), kz_http:url(), kz_json:object() | binary(), pqc_cb_expect:expectations()) ->
          pqc_cb_api:response().
patch(API, URL, RequestEnvelope, Expectations) ->
    patch(API, URL, RequestEnvelope, Expectations, pqc_cb_api:request_headers(API)).

-spec patch(pqc_cb_api:state(), kz_http:url(), kz_json:object() | binary(), pqc_cb_expect:expectations(), kz_http:headers()) ->
          pqc_cb_api:response().
patch(_API, URL, RequestEnvelope, Expectations, RequestHeaders) ->
    pqc_cb_api:make_request(Expectations
                           ,fun kz_http:patch/3
                           ,URL
                           ,RequestHeaders
                           ,RequestEnvelope
                           ).

-spec delete(pqc_cb_api:state(), kz_http:url()) ->
          pqc_cb_api:response().
delete(API, URL) ->
    delete(API, URL, [pqc_cb_expect:code(200)]).

-spec delete(pqc_cb_api:state(), kz_http:url(), pqc_cb_expect:expectations()) ->
          pqc_cb_api:response().
delete(API, URL, Expectations) ->
    delete(API, URL, Expectations, pqc_cb_api:request_headers(API)).

-spec delete(pqc_cb_api:state(), kz_http:url(), pqc_cb_expect:expectations(), kz_http:headers()) ->
          pqc_cb_api:response().
delete(_API, URL, Expectations, RequestHeaders) ->
    pqc_cb_api:make_request(Expectations
                           ,fun kz_http:delete/2
                           ,URL
                           ,RequestHeaders
                           ).

%% @doc /v2/{COLLECTION} URLs
-spec collection_url(pqc_cb_api:state(), kz_term:ne_binary()) ->
          kz_http:url().
collection_url(API, Collection) ->
    string:join([pqc_cb_api:v2_base_url(API), kz_term:to_list(Collection)], "/").

%% @doc /v2/accounts/{ACCOUNT_ID}/{COLLECTION} URLs
-spec collection_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          kz_http:url().
collection_url(API, AccountId, Collection) ->
    string:join([pqc_cb_accounts:account_url(API, AccountId), kz_term:to_list(Collection)], "/").

%% @doc /v2/{COLLECTION}/{ENTITY_ID} URLs
-spec entity_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          kz_http:url().
entity_url(API, Collection, EntityId) ->
    string:join([collection_url(API, Collection), kz_term:to_list(EntityId)], "/").

%% @doc /v2/accounts/{ACCOUNT_ID}/{COLLECTION}/{ENTITY_ID} URLs
-spec entity_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          kz_http:url().
entity_url(API, AccountId, Collection, EntityId) ->
    string:join([collection_url(API, AccountId, Collection), kz_term:to_list(EntityId)], "/").
