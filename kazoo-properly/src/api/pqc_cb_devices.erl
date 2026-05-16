%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_devices).

-export([summary/2]).
-export([create/3, create/4]).
-export([fetch/3]).
-export([patch/4]).
-export([update/3]).
-export([delete/3]).

-export([registrations/2]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, devices_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_devices:doc()) -> pqc_cb_api:response().
create(API, AccountId, DeviceJObj) ->
    create(API, AccountId, DeviceJObj, kz_json:new()).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_devices:doc(), kz_json:object()) -> pqc_cb_api:response().
create(API, AccountId, DeviceJObj, EnvelopeData) ->
    Envelope = pqc_cb_api:create_envelope(DeviceJObj, EnvelopeData),
    pqc_cb_crud:create(API, devices_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, DeviceId) ->
    pqc_cb_crud:fetch(API, device_url(API, AccountId, DeviceId)).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, DeviceId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, device_url(API, AccountId, DeviceId), Envelope).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_devices:doc()) -> pqc_cb_api:response().
update(API, AccountId, DeviceJObj) ->
    Envelope = pqc_cb_api:create_envelope(DeviceJObj),
    pqc_cb_crud:update(API, device_url(API, AccountId, kz_doc:id(DeviceJObj)), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, DeviceId) ->
    pqc_cb_crud:delete(API, device_url(API, AccountId, DeviceId)).

-spec registrations(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
registrations(API, AccountId) ->
    URL = device_url(API, AccountId, <<"status">>),
    pqc_cb_crud:fetch(API, URL).

-spec devices_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
devices_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"devices">>).

-spec device_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
device_url(API, AccountId, DeviceId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"devices">>, DeviceId).
