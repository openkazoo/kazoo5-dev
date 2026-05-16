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
-module(pqc_cb_security).

-export([summary/1
        ,account_summary/2
        ,account_update/3
        ,account_patch/3
        ,account_delete/2
        ]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state()) -> pqc_cb_api:response().
summary(API) ->
    pqc_cb_crud:summary(API, security_url(API)).

-spec account_summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
account_summary(API, AccountId) ->
    pqc_cb_crud:summary(API, security_url(API, AccountId)).

-spec account_update(pqc_cb_api:state(), kz_term:ne_binary(), kz_json:object()) ->
          pqc_cb_api:response().
account_update(API, AccountId, SecurityJObj) ->
    Envelope = pqc_cb_api:create_envelope(SecurityJObj),
    pqc_cb_crud:update(API, security_url(API, AccountId), Envelope).

-spec account_patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_json:object()) ->
          pqc_cb_api:response().
account_patch(API, AccountId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, security_url(API, AccountId), Envelope).

-spec account_delete(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
account_delete(API, AccountId) ->
    pqc_cb_crud:delete(API, security_url(API, AccountId)).

-spec security_url(pqc_cb_api:state()) -> string().
security_url(API) ->
    pqc_cb_crud:collection_url(API, <<"security">>).

-spec security_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
security_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"security">>).
