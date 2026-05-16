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
-module(pqc_cb_media).

%% API requests
-export([summary/2
        ,create/3
        ,fetch/3, fetch/4
        ,fetch_binary/3
        ,update/3, update/4
        ,update_binary/4
        ,patch/4
        ,delete/3
        ]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, media_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_media:doc()) -> pqc_cb_api:response().
create(API, AccountId, MediaJObj) ->
    URL = media_url(API, AccountId),

    ExpectedHeaders = [{"content-type", "application/json"},
                       {"location", {'match', expected_location_value(URL)}}
                      ],
    Expectations = [pqc_cb_expect:codes_and_headers([201], ExpectedHeaders)],

    Envelope = pqc_cb_api:create_envelope(MediaJObj),

    pqc_cb_crud:create(API, URL, Envelope, Expectations).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, MediaId) ->
    fetch(API, AccountId, MediaId, <<"application/json">>).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, MediaId, AcceptType) ->
    ExpectedHeaders = [{"content-type", kz_term:to_list(AcceptType)}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],

    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"accept">>, kz_term:to_list(AcceptType)}]),

    pqc_cb_crud:fetch(API, media_url(API, AccountId, MediaId), Expectations, RequestHeaders).

-spec fetch_binary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch_binary(API, AccountId, MediaId) ->
    AcceptType = "audio/mp3",
    ExpectedHeaders = [{"content-type", AcceptType}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],

    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"accept">>, AcceptType}]),

    pqc_cb_crud:fetch(API, media_bin_url(API, AccountId, MediaId), Expectations, RequestHeaders).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_media:doc()) -> pqc_cb_api:response().
update(API, AccountId, MediaJObj) ->
    URL = media_url(API, AccountId, kz_doc:id(MediaJObj)),

    Envelope = pqc_cb_api:create_envelope(MediaJObj),

    pqc_cb_crud:update(API, URL, Envelope).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), iodata()) -> pqc_cb_api:response().
update(API, AccountId, MediaId, Data) ->
    URL = media_url(API, AccountId, MediaId),

    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],

    pqc_cb_crud:update(API
                      ,URL
                      ,Data
                      ,Expectations
                      ,pqc_cb_api:request_headers(API, [{<<"content-type">>, "audio/mp3"}])
                      ).

-spec update_binary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), iodata()) -> pqc_cb_api:response().
update_binary(API, AccountId, MediaId, Data) ->
    URL = media_bin_url(API, AccountId, MediaId),

    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],

    pqc_cb_crud:update(API
                      ,URL
                      ,Data
                      ,Expectations
                      ,pqc_cb_api:request_headers(API, [{<<"content-type">>, "audio/mp3"}])
                      ).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, MediaId, PatchJObj) ->
    URL = media_url(API, AccountId, MediaId),

    Envelope = pqc_cb_api:create_envelope(PatchJObj),

    pqc_cb_crud:patch(API, URL, Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, MediaId) ->
    pqc_cb_crud:delete(API, media_url(API, AccountId, MediaId)).

-spec media_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
media_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"media">>).

-spec media_bin_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
media_bin_url(API, AccountId, MediaId) ->
    media_url(API, AccountId, MediaId) ++ "/raw".

-spec media_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
media_url(API, AccountId, MediaId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"media">>, MediaId).

%% take http://whatever:port/v2/... and get /v2/.../{regex}
expected_location_value(URL) ->
    expected_location_value(URL, "(\\w{32})").

expected_location_value(URL, Id) ->
    {'match', [_Host, Path]} = re:run(URL, "^(.+)(/v2/.+$)", [{'capture','all_but_first', 'list'}]),
    Path ++ [$/ | kz_term:to_list(Id)].
