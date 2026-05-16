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
-module(pqc_cb_screenpops).

-export([summary/2, summary/3]).
-export([user_summary/3]).
-export([create/3]).
-export([fetch/3]).
-export([patch/4]).
-export([delete/3]).
-export([update/3]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    summary(API, AccountId, []).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:proplist()) -> pqc_cb_api:response().
summary(API, AccountId, QS) ->
    pqc_cb_crud:summary(API, screenpops_url(API, AccountId, QS)).

-spec user_summary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
user_summary(API, AccountId, UserId) ->
    pqc_cb_crud:summary(API, screenpops_user_url(API, AccountId, UserId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_screenpops:doc()) -> pqc_cb_api:response().
create(API, AccountId, ScreenpopJObj) ->
    Envelope = pqc_cb_api:create_envelope(ScreenpopJObj),
    pqc_cb_crud:create(API, screenpops_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, ScreenpopId) ->
    pqc_cb_crud:fetch(API, screenpop_url(API, AccountId, ScreenpopId)).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, ScreenpopId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, screenpop_url(API, AccountId, ScreenpopId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, ScreenpopId) ->
    pqc_cb_crud:delete(API, screenpop_url(API, AccountId, ScreenpopId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_screenpops:doc()) -> pqc_cb_api:response().
update(API, AccountId, ScreenpopJObj) ->
    Envelope = pqc_cb_api:create_envelope(ScreenpopJObj),
    pqc_cb_crud:update(API, screenpop_url(API, AccountId, kz_doc:id(ScreenpopJObj)), Envelope).

-spec screenpops_user_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
screenpops_user_url(API, AccountId, UserId) ->
    string:join([pqc_cb_crud:entity_url(API, AccountId, <<"users">>, UserId)
                ,kz_term:to_list(<<"screenpops">>)
                ], "/").

-spec screenpops_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
screenpops_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"screenpops">>).

-spec screenpops_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:proplist()) -> string().
screenpops_url(API, AccountId, []) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"screenpops">>);
screenpops_url(API, AccountId, QSProps) ->
    QS = kz_http_util:props_to_querystring(QSProps),
    URL = iolist_to_binary([pqc_cb_crud:collection_url(API, AccountId, <<"screenpops">>), "?", QS]),
    kz_term:to_list(URL).

-spec screenpop_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
screenpop_url(API, AccountId, ScreenpopId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"screenpops">>, ScreenpopId).
