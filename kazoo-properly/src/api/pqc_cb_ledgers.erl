%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023-2025, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_ledgers).

%% API functions
-export([fetch/2, fetch/3
        ,fetch_by_source/3, fetch_by_source/4
        ,credit/3
        ,debit/3
        ,total/2
        ]).

-include("properly.hrl").

%% API functions
-spec fetch(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, ?NE_BINARY=AccountId) ->
    fetch(API, AccountId, <<"application/json">>).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, ?NE_BINARY=AccountId, ?NE_BINARY=AcceptType) ->
    LedgersURL = ledgers_url(API, AccountId),
    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"accept">>, kz_term:to_list(AcceptType)}]),

    ExpectedHeaders = [{"content-type", kz_term:to_list(AcceptType)}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],

    pqc_cb_crud:fetch(API, LedgersURL, Expectations, RequestHeaders).

-spec fetch_by_source(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
fetch_by_source(API, ?NE_BINARY=AccountId, ?NE_BINARY=SourceType) ->
    fetch_by_source(API, AccountId, SourceType, <<"application/json">>).

-spec fetch_by_source(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
fetch_by_source(API, ?NE_BINARY=AccountId, SourceType, ?NE_BINARY=AcceptType) ->
    LedgersURL = ledgers_source_url(API, AccountId, SourceType),
    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"accept">>, kz_term:to_list(AcceptType)}]),

    ExpectedHeaders = [{"content-type", kz_term:to_list(AcceptType)}],
    Expectations = [pqc_cb_expect:codes_and_headers([200],ExpectedHeaders)
                   ,pqc_cb_expect:code(204)
                   ],

    pqc_cb_crud:fetch(API, LedgersURL, Expectations, RequestHeaders).

-spec credit(pqc_cb_api:state(), kz_term:ne_binary(), kzd_ledgers:doc()) ->
          pqc_cb_api:response().
credit(API, ?NE_BINARY=AccountId, Ledger) ->
    LedgersURL = ledgers_credit_url(API, AccountId),

    Envelope = pqc_cb_api:create_envelope(Ledger),

    pqc_cb_crud:create(API, LedgersURL, Envelope).

-spec debit(pqc_cb_api:state(), kz_term:ne_binary(), kzd_ledgers:doc()) ->
          pqc_cb_api:response().
debit(API, ?NE_BINARY=AccountId, Ledger) ->
    LedgersURL = ledgers_debit_url(API, AccountId),

    Envelope = pqc_cb_api:create_envelope(Ledger),

    pqc_cb_crud:create(API, LedgersURL, Envelope).

-spec total(pqc_cb_api:state(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
total(API, AccountId) ->
    URL = ledgers_source_url(API, AccountId, <<"total">>),
    pqc_cb_crud:fetch(API, URL).

-spec ledgers_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
ledgers_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"ledgers">>).

-spec ledgers_source_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
ledgers_source_url(API, AccountId, SourceType) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"ledgers">>, SourceType).

-spec ledgers_credit_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
ledgers_credit_url(API, AccountId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"ledgers">>, <<"credit">>).

-spec ledgers_debit_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
ledgers_debit_url(API, AccountId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"ledgers">>, <<"debit">>).
