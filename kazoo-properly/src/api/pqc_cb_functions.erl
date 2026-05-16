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
-module(pqc_cb_functions).

%% API requests
-export([summary/2
        ,create/3
        ,fetch/3
        ,update/3
        ,patch/4
        ,delete/3
        ]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, functions_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_functions:doc()) -> pqc_cb_api:response().
create(API, AccountId, FunctionJObj) ->
    Envelope = pqc_cb_api:create_envelope(FunctionJObj),
    pqc_cb_crud:create(API, functions_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, FunctionId) ->
    pqc_cb_crud:fetch(API, function_url(API, AccountId, FunctionId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_functions:doc()) -> pqc_cb_api:response().
update(API, AccountId, FunctionJObj) ->
    Envelope = pqc_cb_api:create_envelope(FunctionJObj),
    pqc_cb_crud:update(API, function_url(API, AccountId, kz_doc:id(FunctionJObj)), Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, FunctionId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, function_url(API, AccountId, FunctionId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, FunctionId) ->
    pqc_cb_crud:delete(API, function_url(API, AccountId, FunctionId)).

-spec functions_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
functions_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"functions">>).

-spec function_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
function_url(API, AccountId, FunctionId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"functions">>, FunctionId).
