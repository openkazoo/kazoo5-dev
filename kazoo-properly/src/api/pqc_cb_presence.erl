%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%% @doc
%%% @author Manushi Perera
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_presence).

-export([summary/2]).
-export([fetch/3]).
-export([update/4]).
-export([update_user_presence/4]).
-export([update_device_presence/4]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, presence_url(API, AccountId)).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, PresenceId) ->
    pqc_cb_crud:fetch(API, presence_url(API, AccountId, PresenceId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kzd_presence:doc()) -> pqc_cb_api:response().
update(API, AccountId, PresenceId, PresenceJObj) ->
    Envelope = pqc_cb_api:create_envelope(PresenceJObj),
    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([202], ExpectedHeaders)],
    pqc_cb_crud:update(API
                      ,presence_url(API, AccountId, PresenceId)
                      ,Envelope
                      ,Expectations
                      ).

-spec update_user_presence(pqc_cb_api:state(), kz_term:ne_binary(), kzd_presence:doc(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
update_user_presence(API, AccountId, PresenceJObj, UserId) ->
    Envelope = pqc_cb_api:create_envelope(PresenceJObj),
    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([202], ExpectedHeaders)],
    pqc_cb_crud:update(API
                      ,presence_user_url(API, AccountId, UserId)
                      ,Envelope
                      ,Expectations
                      ).

-spec update_device_presence(pqc_cb_api:state(), kz_term:ne_binary(), kzd_presence:doc(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
update_device_presence(API, AccountId, PresenceJObj, DeviceId) ->
    Envelope = pqc_cb_api:create_envelope(PresenceJObj),
    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([202], ExpectedHeaders)],
    pqc_cb_crud:update(API
                      ,presence_device_url(API, AccountId, DeviceId)
                      ,Envelope
                      ,Expectations
                      ).

-spec presence_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
presence_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"presence">>).

-spec presence_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
presence_url(API, AccountId, PresenceId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"presence">>, PresenceId).

-spec presence_device_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
presence_device_url(API, AccountId, DeviceId) ->
    string:join([pqc_cb_crud:entity_url(API, AccountId, <<"devices">>, DeviceId), "presence"], "/").

-spec presence_user_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
presence_user_url(API, AccountId, UserId) ->
    string:join([pqc_cb_crud:entity_url(API, AccountId, <<"users">>, UserId), "presence"], "/").
