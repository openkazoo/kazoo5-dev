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
-module(pqc_cb_conferences).

-export([summary/2, summary/3]).
-export([create/3]).
-export([fetch/3]).
-export([patch/4]).
-export([delete/3]).
-export([update/3]).

-export([action/5]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    summary(API, AccountId, []).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:proplist()) -> pqc_cb_api:response().
summary(API, AccountId, QS) ->
    pqc_cb_crud:summary(API, conferences_url(API, AccountId, QS)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_conferences:doc()) -> pqc_cb_api:response().
create(API, AccountId, ConferenceJObj) ->
    Envelope = pqc_cb_api:create_envelope(ConferenceJObj),
    pqc_cb_crud:create(API, conferences_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, ConferenceId) ->
    pqc_cb_crud:fetch(API, conference_url(API, AccountId, ConferenceId)).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, ConferenceId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, conference_url(API, AccountId, ConferenceId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, ConferenceId) ->
    pqc_cb_crud:delete(API, conference_url(API, AccountId, ConferenceId)).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_conference:doc()) -> pqc_cb_api:response().
update(API, AccountId, ConferenceJObj) ->
    Envelope = pqc_cb_api:create_envelope(ConferenceJObj),
    pqc_cb_crud:update(API, conference_url(API, AccountId, kz_doc:id(ConferenceJObj)), Envelope).

%% ConferenceAction: 'lock', 'unlock', 'play', 'record', 'vars', 'dial'
-spec action(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
action(API, AccountId, ConferenceId, ConferenceAction, ActionData) ->
    Envelope = pqc_cb_api:create_envelope(ActionData, kz_json:from_list([{<<"action">>, ConferenceAction}])),

    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],

    pqc_cb_crud:create(API, conference_url(API, AccountId, ConferenceId), Envelope, Expectations).

-spec conferences_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
conferences_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"conferences">>).

-spec conferences_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:proplist()) -> string().
conferences_url(API, AccountId, []) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"conferences">>);
conferences_url(API, AccountId, QSProps) ->
    QS = kz_http_util:props_to_querystring(QSProps),
    URL = iolist_to_binary([pqc_cb_crud:collection_url(API, AccountId, <<"conferences">>), "?", QS]),
    kz_term:to_list(URL).

-spec conference_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
conference_url(API, AccountId, ConferenceId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"conferences">>, ConferenceId).
