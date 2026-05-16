%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% @author Navoda Ginige
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_websites).

%% API requests
-export([summary/2
        ,user_summary/3
        ,create/3
        ,fetch/3 ,fetch/4
        ,update/3 ,update/4, update_binary/4
        ,patch/4
        ,delete/3
        ]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, website_url(API, AccountId)).

-spec user_summary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
user_summary(API, AccountId, UserId) ->
    pqc_cb_crud:summary(API, user_website_url(API, AccountId, UserId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_media:doc()) -> pqc_cb_api:response().
create(API, AccountId, MediaJObj) ->
    URL = website_url(API, AccountId),

    ExpectedHeaders = [{"content-type", "application/json"},
                       {"location", {'match', expected_location_value(URL)}}
                      ],
    Expectations = [pqc_cb_expect:codes_and_headers([201], ExpectedHeaders)],

    Envelope = pqc_cb_api:create_envelope(MediaJObj),

    pqc_cb_crud:create(API, URL, Envelope, Expectations).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, WebsiteId) ->
    fetch(API, AccountId, WebsiteId, <<"application/json">>).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, WebsiteId, AcceptType) ->
    ExpectedHeaders = [{"content-type", kz_term:to_list(AcceptType)}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],

    pqc_cb_crud:fetch(API
                     ,website_url(API, AccountId, WebsiteId)
                     ,Expectations
                     ,pqc_cb_api:request_headers(API, [{<<"accept">>, kz_term:to_list(AcceptType)}])
                     ).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_media:doc()) -> pqc_cb_api:response().
update(API, AccountId, MediaJObj) ->
    URL = website_url(API, AccountId, kz_doc:id(MediaJObj)),

    Envelope = pqc_cb_api:create_envelope(MediaJObj),

    pqc_cb_crud:update(API, URL, Envelope).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), iodata()) -> pqc_cb_api:response().
update(API, AccountId, WebsiteId, Data) ->
    URL = website_url(API, AccountId, WebsiteId),

    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],

    pqc_cb_crud:update(API
                      ,URL
                      ,Data
                      ,Expectations
                      ,pqc_cb_api:request_headers(API, [{<<"content-type">>, "audio/mp3"}])
                      ).

-spec update_binary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), iodata()) -> pqc_cb_api:response().
update_binary(API, AccountId, WebsiteId, Data) ->
    URL = website_url(API, AccountId, WebsiteId),

    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],

    pqc_cb_crud:update(API
                      ,URL
                      ,Data
                      ,Expectations
                      ,pqc_cb_api:request_headers(API, [{<<"content-type">>, "image/png"}])
                      ).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, WebsiteId, PatchJObj) ->
    URL = website_url(API, AccountId, WebsiteId),

    Envelope = pqc_cb_api:create_envelope(PatchJObj),

    pqc_cb_crud:patch(API, URL, Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, WebsiteId) ->
    URL = website_url(API, AccountId, WebsiteId),

    pqc_cb_crud:delete(API, URL).

-spec website_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
website_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"websites">>).

-spec website_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
website_url(API, AccountId, WebsiteId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"websites">>, WebsiteId).

-spec user_website_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
user_website_url(API, AccountId, UserId) ->
    string:join([pqc_cb_users:user_url(API, AccountId, UserId), "websites"], "/").

%% take http://whatever:port/v2/... and get /v2/.../{regex}
expected_location_value(URL) ->
    expected_location_value(URL, "(\\w{32})").

expected_location_value(URL, Id) ->
    {'match', [_Host, Path]} = re:run(URL, "^(.+)(/v2/.+$)", [{'capture','all_but_first', 'list'}]),
    Path ++ [$/ | kz_term:to_list(Id)].
