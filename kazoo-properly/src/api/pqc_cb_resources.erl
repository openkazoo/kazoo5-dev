%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_resources).

-export([summary/2, summary/3]).
-export([create/3]).
-export([fetch/3]).
-export([update/3]).
-export([patch/4]).
-export([delete/3]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:api_ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    summary(API, AccountId, 'undefined').

-spec summary(pqc_cb_api:state(), kz_term:api_ne_binary(), 'undefined' | iodata()) -> pqc_cb_api:response().
summary(API, AccountId, QueryString) ->
    pqc_cb_crud:summary(API, resources_url(API, AccountId, QueryString)).

-spec create(pqc_cb_api:state(), kz_term:api_ne_binary(), kzd_resources:doc()) -> pqc_cb_api:response().
create(API, AccountId, ResourceJObj) ->
    Envelope = pqc_cb_api:create_envelope(ResourceJObj),
    pqc_cb_crud:create(API, resources_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, ResourceId) ->
    pqc_cb_crud:fetch(API, resource_url(API, AccountId, ResourceId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_resource:doc()) -> pqc_cb_api:response().
update(API, AccountId, ResourceJObj) ->
    Envelope = pqc_cb_api:create_envelope(ResourceJObj),
    pqc_cb_crud:update(API, resource_url(API, AccountId, kz_doc:id(ResourceJObj)), Envelope).

-spec patch(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, ResourceId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, resource_url(API, AccountId, ResourceId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, ResourceId) ->
    pqc_cb_crud:delete(API, resource_url(API, AccountId, ResourceId)).

resources_url(API, AccountId, 'undefined') ->
    resources_url(API, AccountId);
resources_url(API, AccountId, QueryString) ->
    [resources_url(API, AccountId), $?, QueryString].

-spec resources_url(pqc_cb_api:state(), kz_term:api_ne_binary()) -> string().
resources_url(#{base_url := APIBase}, 'undefined') ->
    APIBase ++ "/resources";
resources_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"resources">>).

-spec resource_url(pqc_cb_api:state(), kz_term:api_ne_binary(), kz_term:ne_binary()) -> string().
resource_url(#{base_url := APIBase}, 'undefined', ResourceId) ->
    APIBase ++ "/resources/" ++ kz_term:to_list(ResourceId);
resource_url(API, AccountId, ResourceId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"resources">>, ResourceId).
