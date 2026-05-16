%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Listener for reg_success, and reg_query AMQP requests
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_registrations).

-export([summary/2
        ,count/2
        ]).

-export([flush_all/2]).
-export([flush_device/3]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, registrations_url(API, AccountId)).

-spec count(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
count(API, AccountId) ->
    pqc_cb_crud:summary(API, registration_url(API, AccountId, <<"count">>)).

-spec flush_all(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
flush_all(API, AccountId) ->
    pqc_cb_crud:delete(API, registrations_url(API, AccountId)).

-spec flush_device(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
flush_device(API, AccountId, Username) ->
    pqc_cb_crud:delete(API, registration_url(API, AccountId, Username)).

-spec registrations_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
registrations_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"registrations">>).

-spec registration_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
registration_url(API, AccountId, EntityId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"registrations">>, EntityId).
