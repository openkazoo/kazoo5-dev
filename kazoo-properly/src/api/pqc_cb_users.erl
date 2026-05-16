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
-module(pqc_cb_users).

%% API requests
-export([summary/2
        ,paginated_summary/3, paginated_summary/4
        ,create/3
        ,fetch/3
        ,update/3
        ,patch/4
        ,delete/3
        ,delete/4
        ,qrcode/3

        ,devices/3
        ,paginated_devices/4, paginated_devices/5
        ]).

-export([users_url/2, user_url/3]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, users_url(API, AccountId)).

-spec paginated_summary(pqc_cb_api:state(), kz_term:ne_binary(), pos_integer()) ->
          pqc_cb_api:response().
paginated_summary(API, AccountId, PageSize) ->
    paginated_summary(API, AccountId, PageSize, 'undefined').

-spec paginated_summary(pqc_cb_api:state(), kz_term:ne_binary(), pos_integer(), kz_term:api_ne_binary()) ->
          pqc_cb_api:response().
paginated_summary(API, AccountId, PageSize, StartKey) ->
    pqc_cb_crud:summary(API, users_url(API, AccountId, PageSize, StartKey)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_users:doc()) -> pqc_cb_api:response().
create(API, AccountId, UserJObj) ->
    URL = users_url(API, AccountId),

    ExpectedHeaders = [{"content-type", "application/json"}
                      ,{"location", {'match', expected_location_value(URL)}}
                      ],
    Expectations = [pqc_cb_expect:codes_and_headers([201], ExpectedHeaders)],

    Envelope = pqc_cb_api:create_envelope(UserJObj),

    pqc_cb_crud:create(API, URL, Envelope, Expectations).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, UserId) ->
    pqc_cb_crud:fetch(API, user_url(API, AccountId, UserId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_users:doc()) -> pqc_cb_api:response().
update(API, AccountId, UserJObj) ->
    URL = user_url(API, AccountId, kz_doc:id(UserJObj)),

    Envelope = pqc_cb_api:create_envelope(UserJObj),

    pqc_cb_crud:update(API, URL, Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, UserId, PatchJObj) ->
    URL = user_url(API, AccountId, UserId),

    Envelope = pqc_cb_api:create_envelope(PatchJObj),

    pqc_cb_crud:patch(API, URL, Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, UserId) ->
    URL = user_url(API, AccountId, UserId),

    pqc_cb_crud:delete(API, URL).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
delete(API, AccountId, UserId, RequestBody) ->
    URL = user_url(API, AccountId, UserId),
    Expectations = [pqc_cb_expect:code(200)],
    pqc_cb_api:make_request(Expectations
                           ,fun kz_http:delete/3
                           ,URL
                           ,pqc_cb_api:request_headers(API)
                           ,pqc_cb_api:create_envelope(RequestBody)
                           ).

-spec qrcode(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
qrcode(API, AccountId, UserId) ->
    Expectations = [pqc_cb_expect:code(200)],
    pqc_cb_crud:fetch(API
                     ,user_thing_url(API, AccountId, UserId, <<"qrcode">>)
                     ,Expectations
                     ,pqc_cb_api:request_headers(API, [{<<"accept">>, "image/png"}])
                     ).

-spec devices(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
devices(API, AccountId, UserId) ->
    DevicesURL = user_url(API, AccountId, UserId) ++ "/devices",
    pqc_cb_crud:fetch(API, DevicesURL).

-spec paginated_devices(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), pos_integer()) ->
          pqc_cb_api:response().
paginated_devices(API, AccountId, UserId, PageSize) ->
    paginated_devices(API, AccountId, UserId, PageSize, 'undefined').

-spec paginated_devices(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), pos_integer(), kz_term:api_ne_binary()) ->
          pqc_cb_api:response().
paginated_devices(API, AccountId, UserId, PageSize, StartKey) ->
    DevicesURL = user_url(API, AccountId, UserId)
        ++ "/devices" ++ "?" ++ page_size(PageSize) ++ start_key(StartKey),

    pqc_cb_crud:fetch(API, DevicesURL).

-spec users_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
users_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"users">>).

users_url(API, AccountId, PageSize, StartKey) ->
    users_url(API, AccountId)
        ++ "?" ++ page_size(PageSize) ++ start_key(StartKey).

page_size(PageSize) when is_integer(PageSize) ->
    "page_size=" ++ kz_term:to_list(PageSize).

start_key('undefined') -> "";
start_key(<<StartKey/binary>>) ->
    "&start_key=" ++ kz_term:to_list(StartKey).

-spec user_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
user_url(API, AccountId, UserId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"users">>, UserId).

-spec user_thing_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
user_thing_url(API, AccountId, UserId, Thing) ->
    string:join([users_url(API, AccountId), kz_term:to_list(UserId), kz_term:to_list(Thing)], "/").

%% take http://whatever:port/v2/... and get /v2/.../{regex}
expected_location_value(URL) ->
    expected_location_value(URL, "(\\w{32})").

expected_location_value(URL, Id) ->
    {'match', [_Host, Path]} = re:run(URL, "^(.+)(/v2/.+$)", [{'capture','all_but_first', 'list'}]),
    Path ++ [$/ | kz_term:to_list(Id)].
