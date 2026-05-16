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
-module(pqc_cb_phone_numbers).

%% Crossbar API test functions
-export([summary/2
        ,list_number/3
        ,identify_number/3
        ,identify_number/4

        ,add_number/3
        ,add_number/4
        ,add_numbers/3
        ,update_number/3
        ,update_number/4
        ,update_number/5
        ,port_number/3
        ,port_number/4
        ,port_number/5
        ,reserve_number/3
        ,reserve_number/4
        ,reserve_number/5
        ,activate_number/3
        ,activate_number/5
        ,remove_number/3
        ,remove_number/4
        ,check_numbers/3
        ,check_numbers/4

        ,available_numbers/3
        ]).

-export([activate_numbers/3
        ,activate_numbers/4
        ]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, numbers_url(API, AccountId)).

-spec list_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
list_number(_API, 'undefined', _Number) -> ?FAILED_RESPONSE;
list_number(API, AccountId, Number) ->
    URL = number_url(API, AccountId, Number),
    Expectations = [pqc_cb_expect:codes([200, 404])],

    pqc_cb_crud:fetch(API, URL, Expectations).

-spec identify_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
identify_number(API, AccountId, Number) ->
    identify_number(API, AccountId, Number, [pqc_cb_expect:codes([200, 404])]).

-spec identify_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary(), [pqc_cb_expect:expectation()]) -> pqc_cb_api:response().
identify_number(_API, 'undefined', _Number, _Expectations) -> ?FAILED_RESPONSE;
identify_number(API, AccountId, Number, Expectations) ->
    URL = number_url(API, AccountId, Number, "identify"),

    pqc_cb_crud:fetch(API, URL, Expectations).

-spec add_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
add_number(API, AccountId, Number) ->
    add_number(API, AccountId, Number, kz_json:new()).

-spec add_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary(), kz_json:object()) ->
          pqc_cb_api:response().
add_number(_API, 'undefined', _Number, _RequestData) -> ?FAILED_RESPONSE;
add_number(API, AccountId, Number, RequestData) ->
    URL = number_url(API, AccountId, Number),
    RequestEnvelope  = pqc_cb_api:create_envelope(RequestData
                                                 ,kz_json:from_list([{<<"accept_charges">>, 'true'}])
                                                 ),
    Expectations = [pqc_cb_expect:codes([201, 404, 409])],

    pqc_cb_crud:create(API, URL, RequestEnvelope, Expectations).

-spec add_numbers(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_json:object()) ->
          pqc_cb_api:response().
add_numbers(_API, 'undefined', _RequestData) -> ?FAILED_RESPONSE;
add_numbers(API, AccountId, RequestData) ->
    URL = collection_url(API, AccountId, ""),
    RequestEnvelope  = pqc_cb_api:create_envelope(RequestData
                                                 ,kz_json:from_list([{<<"accept_charges">>, 'true'}])
                                                 ),

    pqc_cb_crud:create(API, URL, RequestEnvelope).

-spec update_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
update_number(API, AccountId, Number) ->
    add_number(API, AccountId, Number, kz_json:new()).

-spec update_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary(), kz_json:object()) ->
          pqc_cb_api:response().
update_number(API, AccountId, Number, RequestData) ->
    RequestEnvelope  = pqc_cb_api:create_envelope(RequestData
                                                 ,kz_json:from_list([{<<"accept_charges">>, 'true'}])
                                                 ),
    Expectations = [pqc_cb_expect:codes([200, 400, 404])],
    update_number(API, AccountId, Number, RequestEnvelope, Expectations).

-spec update_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary(), kz_json:object(), [pqc_cb_expect:expectation()]) ->
          pqc_cb_api:response().
update_number(_API, 'undefined', _Number, _RequestEnvelope, _Expectations) -> ?FAILED_RESPONSE;
update_number(API, AccountId, Number, RequestEnvelope, Expectations) ->
    URL = number_url(API, AccountId, Number),

    pqc_cb_crud:update(API, URL, RequestEnvelope, Expectations).

-spec port_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
port_number(API, AccountId, Number) ->
    port_number(API, AccountId, Number, kz_json:new()).

-spec port_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary(), kz_json:object()) ->
          pqc_cb_api:response().
port_number(API, AccountId, Number, RequestData) ->
    RequestEnvelope  = pqc_cb_api:create_envelope(RequestData
                                                 ,kz_json:from_list([{<<"accept_charges">>, 'true'}])
                                                 ),
    Expectations = [pqc_cb_expect:codes([201, 400, 404, 409])],
    port_number(API, AccountId, Number, RequestEnvelope, Expectations).

-spec port_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary(), kz_json:object(), [pqc_cb_expect:expectation()]) ->
          pqc_cb_api:response().
port_number(_API, 'undefined', _Number, _RequestEnvelope, _Expectations) -> ?FAILED_RESPONSE;
port_number(API, AccountId, Number, RequestEnvelope, Expectations) ->
    URL = number_url(API, AccountId, Number, "port"),

    pqc_cb_crud:create(API, URL, RequestEnvelope, Expectations).

-spec reserve_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
reserve_number(API, AccountId, Number) ->
    reserve_number(API, AccountId, Number, kz_json:new()).

-spec reserve_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary(), kz_json:object()) ->
          pqc_cb_api:response().
reserve_number(API, AccountId, Number, RequestData) ->
    RequestEnvelope  = pqc_cb_api:create_envelope(RequestData
                                                 ,kz_json:from_list([{<<"accept_charges">>, 'true'}])
                                                 ),
    Expectations = [pqc_cb_expect:codes([201, 400, 404, 409])],
    reserve_number(API, AccountId, Number, RequestEnvelope, Expectations).

-spec reserve_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary(), kz_json:object(), [pqc_cb_expect:expectation()]) ->
          pqc_cb_api:response().
reserve_number(_API, 'undefined', _Number, _RequestEnvelope, _Expectations) -> ?FAILED_RESPONSE;
reserve_number(API, AccountId, Number, RequestEnvelope, Expectations) ->
    URL = number_url(API, AccountId, Number, "reserve"),

    pqc_cb_crud:create(API, URL, RequestEnvelope, Expectations).

-spec remove_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
remove_number(API, AccountId, Number) ->
    remove_number(API, AccountId, Number, [pqc_cb_expect:codes([200, 400, 404])]).

-spec remove_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary(), [pqc_cb_expect:expectation()]) -> pqc_cb_api:response().
remove_number(_API, 'undefined', _Number, _Expectations) -> ?FAILED_RESPONSE;
remove_number(API, AccountId, Number, Expectations) ->
    URL = number_url(API, AccountId, Number),

    pqc_cb_crud:delete(API, URL, Expectations).

-spec check_numbers(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_json:object()) ->
          pqc_cb_api:response().
check_numbers(API, AccountId, RequestData) ->
    RequestEnvelope  = pqc_cb_api:create_envelope(RequestData
                                                 ,kz_json:from_list([{<<"accept_charges">>, 'true'}])
                                                 ),
    Expectations = [pqc_cb_expect:codes([400, 404])],
    check_numbers(API, AccountId, RequestEnvelope, Expectations).

-spec check_numbers(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_json:object(), [pqc_cb_expect:expectation()]) ->
          pqc_cb_api:response().
check_numbers(_API, 'undefined', _RequestEnvelope, _Expectations) -> ?FAILED_RESPONSE;
check_numbers(API, AccountId, RequestEnvelope, Expectations) ->
    URL = number_url(API, AccountId, <<"check">>),

    pqc_cb_crud:update(API, URL, RequestEnvelope, Expectations).

-spec available_numbers(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
available_numbers(_API, 'undefined', _QueryString) -> ?FAILED_RESPONSE;
available_numbers(API, AccountId, QueryString) ->
    URL = available_numbers_url(API, AccountId, QueryString),
    Expectations = [pqc_cb_expect:codes([200, 404])],

    pqc_cb_crud:fetch(API, URL, Expectations).

-spec activate_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
activate_number(API, AccountId, Number) ->
    RequestEnvelope  = pqc_cb_api:create_envelope(kz_json:new(), kz_json:from_list([{<<"accept_charges">>, 'true'}])),
    Expectations = [pqc_cb_expect:codes([201, 400, 404, 500])],
    activate_number(API, AccountId, Number, RequestEnvelope, Expectations).

-spec activate_number(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary(), kz_json:object(), [pqc_cb_expect:expectation()]) -> pqc_cb_api:response().
activate_number(_API, 'undefined', _Number, _RequestEnvelope, _Expectations) -> ?FAILED_RESPONSE;
activate_number(API, AccountId, Number, RequestEnvelope, Expectations) ->
    URL = number_url(API, AccountId, Number, "activate"),

    pqc_cb_crud:create(API, URL, RequestEnvelope, Expectations).

-spec activate_numbers(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binaries()) -> pqc_cb_api:response().
activate_numbers(API, AccountId, Numbers) ->
    RequestEnvelope  = pqc_cb_api:create_envelope(kz_json:from_list([{<<"numbers">>, Numbers}])
                                                 ,kz_json:from_list([{<<"accept_charges">>, 'true'}])
                                                 ),
    Expectations = [pqc_cb_expect:codes([201, 404, 500])],
    activate_numbers(API, AccountId, RequestEnvelope, Expectations).

-spec activate_numbers(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_json:object(), [pqc_cb_expect:expectation()]) -> pqc_cb_api:response().
activate_numbers(_API, 'undefined', _RequestEnvelope, _Expectations) -> ?FAILED_RESPONSE;
activate_numbers(API, AccountId, RequestEnvelope, Expectations) ->
    URL = collection_url(API, AccountId, "activate"),
    RequestHeaders = pqc_cb_api:request_headers(API),

    pqc_cb_api:make_request(Expectations
                           ,fun kz_http:put/3
                           ,URL
                           ,RequestHeaders
                           ,kz_json:encode(RequestEnvelope)
                           ).

-spec numbers_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
numbers_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"phone_numbers">>).

-spec number_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
number_url(API, AccountId, Number) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"phone_numbers">>, kz_http_util:urlencode(Number)).

-spec number_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), string()) -> string().
number_url(API, AccountId, Number, PathToken) ->
    number_url(API, AccountId, Number) ++ "/" ++ PathToken.

-spec available_numbers_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
available_numbers_url(API, AccountId, QueryString) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"phone_numbers">>, QueryString).

-spec collection_url(pqc_cb_api:state(), kz_term:ne_binary(), string()) -> iolist().
collection_url(API, AccountId, PathToken) ->
    string:join([numbers_url(API, AccountId)
                ,"collection"
                ,PathToken
                ]
               ,"/"
               ).
