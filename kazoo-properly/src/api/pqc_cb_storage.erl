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
-module(pqc_cb_storage).

%% API Shims
-export([create/3, create/4
        ,fetch/2
        ,update/3, update/4
        ,patch/3
        ,delete/2
        ]).

-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(BASE64_ENCODED, 'true').
-define(SEND_MULTIPART, 'true').

-spec create(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary() | kz_json:object()) ->
          pqc_cb_api:response().
create(API, AccountId, StorageDoc) ->
    create(API, AccountId, StorageDoc, 'undefined').

-spec create(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_json:object(), kz_term:api_boolean()) ->
          pqc_cb_api:response().
create(API, AccountId, StorageDoc, ValidateSettings) ->
    StorageURL = storage_url(API, AccountId, ValidateSettings),
    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"content-type">>, "application/json"}]),
    Expectations = [pqc_cb_expect:code(201)],
    pqc_cb_crud:create(API
                      ,StorageURL
                      ,pqc_cb_api:create_envelope(StorageDoc)
                      ,Expectations
                      ,RequestHeaders
                      ).

-spec fetch(pqc_cb_api:state(), kz_term:api_ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId) ->
    StorageURL = storage_url(API, AccountId),
    pqc_cb_crud:fetch(API, StorageURL).

-spec delete(pqc_cb_api:state(), kz_term:api_ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId) ->
    StorageURL = storage_url(API, AccountId),
    pqc_cb_crud:delete(API, StorageURL).

-spec update(pqc_cb_api:state(), kz_term:api_ne_binary(), kzd_storage:doc()) -> pqc_cb_api:response().
update(API, AccountId, StorageDoc) ->
    update(API, AccountId, StorageDoc, 'undefined').

-spec update(pqc_cb_api:state(), kz_term:api_ne_binary(), kzd_storage:doc(), kz_term:api_boolean()) -> pqc_cb_api:response().
update(API, AccountId, StorageDoc, ValidateSettings) ->
    StorageURL = storage_url(API, AccountId, ValidateSettings),
    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"content-type">>, "application/json"}]),
    RequestEnvelope = pqc_cb_api:create_envelope(StorageDoc),
    Expectations = [pqc_cb_expect:code(200)],
    pqc_cb_crud:update(API
                      ,StorageURL
                      ,RequestEnvelope
                      ,Expectations
                      ,RequestHeaders
                      ).

-spec patch(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, PatchDoc) ->
    StorageURL = storage_url(API, AccountId),
    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"content-type">>, "application/json"}]),
    RequestEnvelope = pqc_cb_api:create_envelope(PatchDoc),
    Expectations = [pqc_cb_expect:code(200)],
    pqc_cb_crud:patch(API
                     ,StorageURL
                     ,RequestEnvelope
                     ,Expectations
                     ,RequestHeaders
                     ).

storage_url(API, 'undefined') ->
    pqc_cb_crud:collection_url(API, <<"storage">>);
storage_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"storage">>).

storage_url(API, AccountId, 'false') ->
    storage_url(API, AccountId) ++ "?validate_settings=false";
storage_url(API, AccountId, _ValidateSettings) ->
    storage_url(API, AccountId).
