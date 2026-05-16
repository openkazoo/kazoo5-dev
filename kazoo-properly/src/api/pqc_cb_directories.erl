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
-module(pqc_cb_directories).

-export([summary/2]).
-export([create/3]).
-export([fetch/3, fetch/4]).
-export([update/3]).
-export([patch/4]).
-export([delete/3]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, directories_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_directories:doc()) -> pqc_cb_api:response().
create(API, AccountId, DirectoryJObj) ->
    Envelope = pqc_cb_api:create_envelope(DirectoryJObj),
    pqc_cb_crud:create(API, directories_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, DirectoryId) ->
    fetch(API, AccountId, DirectoryId, 'undefined').

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_proplist()) -> pqc_cb_api:response().
fetch(API, AccountId, DirectoryId, QueryString) ->
    pqc_cb_crud:fetch(API, directory_url(API, AccountId, DirectoryId) ++ querystring(QueryString)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_directories:doc()) -> pqc_cb_api:response().
update(API, AccountId, DirectoryJObj) ->
    Envelope = pqc_cb_api:create_envelope(DirectoryJObj),
    pqc_cb_crud:update(API, directory_url(API, AccountId, kz_doc:id(DirectoryJObj)), Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, DirectoryId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, directory_url(API, AccountId, DirectoryId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, DirectoryId) ->
    pqc_cb_crud:delete(API, directory_url(API, AccountId, DirectoryId)).

-spec directories_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
directories_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"directories">>).

-spec directory_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
directory_url(API, AccountId, DirectoryId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"directories">>, DirectoryId).

querystring('undefined') -> "";
querystring([]) -> "";
querystring(QS) -> ["?", pqc_util:to_querystring(QS)].
