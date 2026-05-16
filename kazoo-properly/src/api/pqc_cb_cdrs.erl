%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2024-, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_cdrs).

%% API Shims
-export([summary/2, summary/3
        ,paginated_summary/2, paginated_summary/3, paginated_summary/4
        ,unpaginated_summary/2, unpaginated_summary/3
        ,fetch/3
        ,interactions/2
        ,paginated_interactions/2
        ,paginated_interactions/3
        ,legs/3
        ]).

-include_lib("proper/include/proper.hrl").
-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).
-define(CDRS_PER_MONTH, 4).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    summary(API, AccountId, <<"application/json">>).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId, Accept) ->
    URL = cdrs_url(API, AccountId),
    Headers = [{<<"accept">>, kz_term:to_list(Accept)}],
    RequestHeaders = pqc_cb_api:request_headers(API, Headers),

    ExpectedHeaders = [{"content-type", kz_term:to_list(Accept)}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)
                   ,pqc_cb_expect:code(204)
                   ],

    pqc_cb_crud:summary(API, URL, Expectations, RequestHeaders).

-spec unpaginated_summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
unpaginated_summary(API, AccountId) ->
    unpaginated_summary(API, AccountId, 'default').

-type should_chunk() :: boolean() | 'default'.
-spec unpaginated_summary(pqc_cb_api:state(), kz_term:ne_binary(), should_chunk()) -> pqc_cb_api:response().
unpaginated_summary(API, AccountId, ShouldChunk) ->
    URL = cdrs_url(API, AccountId) ++ "?paginate=false" ++ should_chunk(ShouldChunk),

    Expectations = [pqc_cb_expect:codes([200, 204])],

    pqc_cb_crud:summary(API, URL, Expectations).

should_chunk('default') -> "";
should_chunk('true') -> "&is_chunked=true";
should_chunk('false') -> "&is_chunked=false".

-spec paginated_summary(pqc_cb_api:state(), kz_term:ne_binary()) ->
          kz_json:objects().
paginated_summary(API, AccountId) ->
    paginated_summary(API, AccountId, 'undefined').

-spec paginated_summary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          kz_json:objects().
paginated_summary(API, AccountId, OwnerId) ->
    paginated_summary(API, AccountId, OwnerId, ?CDRS_PER_MONTH div 2).

-spec paginated_summary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:api_ne_binary(), pos_integer()) ->
          kz_json:objects().
paginated_summary(API, AccountId, OwnerId, PageSize) ->
    URL = paginated_cdrs_url(API, AccountId, OwnerId, PageSize),
    RequestHeaders = pqc_cb_api:request_headers(API),

    EmptyResExpect = pqc_cb_expect:code(204),
    HasResExpect = pqc_cb_expect:expect([200], [{"content-type", "application/json"}], fun page_size_is_integer/1),
    Expectations = [HasResExpect
                   ,EmptyResExpect
                   ],

    collect_paginated_results(API, URL, URL, RequestHeaders, Expectations, []).

page_size_is_integer('undefined') -> {"Expected a body.", []};
page_size_is_integer(Body) ->
    try kz_json:decode(Body) of
        JObj ->
            MaybeInt = kz_json:get_value(<<"page_size">>, JObj),
            int_or_message(MaybeInt, "Expected an integer")
    catch
        _:_ ->
            {"Expected parsable json", []}
    end.

int_or_message('undefined', _) -> 'ok';
int_or_message(Int, _) when is_integer(Int) -> 'ok';
int_or_message(_, Message) -> {'error', Message, []}.

collect_paginated_results(API, BaseURL, URL, RequestHeaders, Expectations, Collected) ->
    %% ?DEV_LOG("Url: ~p", [kz_term:to_binary(URL)]),
    JSON = pqc_cb_crud:summary(API, URL, Expectations, RequestHeaders),
    handle_paginated_results(API, BaseURL, RequestHeaders, Expectations, Collected, kz_json:decode(JSON)).

handle_paginated_results(API, BaseURL, RequestHeaders, Expectations, Collected, RespJObj) ->
    Data = kz_json:get_list_value(<<"data">>, RespJObj, []),
    %% ?DEV_LOG("Ids: ~p", [[kz_doc:id(J) || J <- Data]]),
    case kz_json:get_ne_binary_value(<<"next_start_key">>, RespJObj) of
        'undefined' -> Data ++ Collected;
        NextStartKey ->
            %% ?DEV_LOG("NextStartKey: ~1000p~n~n", [kz_view_cursor:decode_bookmark(NextStartKey)]),
            lager:info("collecting next page from ~s: ~s", [BaseURL, NextStartKey]),
            collect_paginated_results(API
                                     ,BaseURL
                                     ,BaseURL ++ [$& | start_key(NextStartKey)]
                                     ,update_request_id(RequestHeaders)
                                     ,Expectations
                                     ,Data ++ Collected
                                     )
    end.

update_request_id(RequestHeaders) ->
    NewRequestId = case re:split(kz_http_util:get_resp_header("x-request-id", RequestHeaders), "-") of
                       [Id, Now] -> iolist_to_binary([Id, "-", Now, "-", "1"]);
                       [Id, Now, Nth] -> iolist_to_binary([Id, "-", Now, "-", incr_nth(Nth)])
                   end,
    props:set_value(<<"x-request-id">>, kz_term:to_list(NewRequestId), RequestHeaders).

incr_nth(Nth) ->
    integer_to_list(kz_term:to_integer(Nth) + 1).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, CDRId) ->
    URL = cdr_url(API, AccountId, CDRId),
    pqc_cb_crud:fetch(API, URL).

-spec interactions(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
interactions(API, AccountId) ->
    URL = interactions_url(API, AccountId),
    pqc_cb_crud:fetch(API, URL).

-spec paginated_interactions(pqc_cb_api:state(), kz_term:ne_binary()) ->
          {'error', binary()} |
          kz_json:objects().
paginated_interactions(API, AccountId) ->
    paginated_interactions(API, AccountId, 'undefined').

-spec paginated_interactions(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          {'error', binary()} |
          kz_json:objects().
paginated_interactions(API, AccountId, OwnerId) ->
    URL = paginated_interactions_url(API, AccountId, OwnerId, 2),
    RequestHeaders = pqc_cb_api:request_headers(API),
    collect_paginated_results(API, URL, URL, RequestHeaders, [pqc_cb_expect:code(200)], []).

-spec legs(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
legs(API, AccountId, InteractionId) ->
    URL = legs_url(API, AccountId, InteractionId),
    pqc_cb_crud:fetch(API, URL).

legs_url(API, AccountId, InteractionId) ->
    string:join([pqc_cb_accounts:account_url(API, AccountId), "cdrs", "legs", kz_term:to_list(InteractionId)], "/").

interactions_url(API, AccountId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"cdrs">>, <<"interaction">>).

paginated_interactions_url(API, AccountId, 'undefined', PageSize) ->
    interactions_url(API, AccountId) ++ "?" ++ page_size(PageSize);
paginated_interactions_url(API, AccountId, OwnerId, PageSize) ->
    string:join([pqc_cb_accounts:account_url(API, AccountId)
                ,"users", kz_term:to_list(OwnerId)
                ,"cdrs", "interaction"
                ]
               ,"/"
               )
        ++ "?" ++ page_size(PageSize).

cdr_url(API, AccountId, CDRId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"cdrs">>, CDRId).

cdrs_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"cdrs">>).

paginated_cdrs_url(API, AccountId, 'undefined', PageSize) ->
    cdrs_url(API, AccountId) ++ "?" ++ page_size(PageSize);
paginated_cdrs_url(API, AccountId, OwnerId, PageSize) ->
    string:join([pqc_cb_accounts:account_url(API, AccountId), "users", kz_term:to_list(OwnerId), "cdrs"], "/")
        ++ "?" ++ page_size(PageSize).

page_size(N) -> "page_size=" ++ kz_term:to_list(N).

start_key(StartKey) -> "start_key=" ++ kz_term:to_list(StartKey).
