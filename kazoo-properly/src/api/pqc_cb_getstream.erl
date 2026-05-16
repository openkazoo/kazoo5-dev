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
-module(pqc_cb_getstream).

%% API requests
-export([account_summary/2
        ,user_status/3
        ,enable/3
        ,disable/4
        ,delete/3
        ]).

-spec account_summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
account_summary(API, AccountId) ->
    pqc_cb_crud:summary(API, account_getstream_url(API, AccountId)).

-spec user_status(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
user_status(API, AccountId, UserId) ->
    pqc_cb_crud:fetch(API, user_getstream_url(API, AccountId, UserId)).

-spec enable(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
enable(API, AccountId, UserId) ->
    Envelope = pqc_cb_api:create_envelope(kz_json:new()),
    pqc_cb_crud:create(API, user_getstream_url(API, AccountId, UserId), Envelope).

-spec disable(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
disable(API, AccountId, UserId, GetstreamObj) ->
    Envelope = pqc_cb_api:create_envelope(GetstreamObj),
    pqc_cb_crud:patch(API, user_getstream_url(API, AccountId, UserId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, UserId) ->
    pqc_cb_crud:delete(API, user_getstream_url(API, AccountId, UserId)).

-spec account_getstream_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
account_getstream_url(API, AccountId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"users">>, <<"getstream">>).

-spec user_getstream_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
user_getstream_url(API, AccountId, UserId) ->
    string:join([pqc_cb_users:user_url(API, AccountId, UserId), "getstream"], "/").
