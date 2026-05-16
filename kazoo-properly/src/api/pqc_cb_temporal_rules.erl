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
-module(pqc_cb_temporal_rules).

-export([summary/2]).
-export([create/3]).
-export([fetch/3, fetch/4]).
-export([update/3]).
-export([patch/4]).
-export([delete/3]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, temporal_rules_url(API, AccountId)).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_temporal_rules:doc()) -> pqc_cb_api:response().
create(API, AccountId, Temporal_ruleJObj) ->
    Envelope = pqc_cb_api:create_envelope(Temporal_ruleJObj),
    pqc_cb_crud:create(API, temporal_rules_url(API, AccountId), Envelope).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, TemporalRuleId) ->
    pqc_cb_crud:fetch(API, temporal_rule_url(API, AccountId, TemporalRuleId)).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
fetch(API, AccountId, TemporalRuleId, QueryString) ->
    URL = temporal_rule_url(API, AccountId, TemporalRuleId),
    URLWithQS = lists:flatten([URL, "?", kz_http_util:json_to_querystring(QueryString)]),
    pqc_cb_crud:fetch(API, URLWithQS).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_temporal_rules:doc()) -> pqc_cb_api:response().
update(API, AccountId, Temporal_ruleJObj) ->
    Envelope = pqc_cb_api:create_envelope(Temporal_ruleJObj),
    pqc_cb_crud:update(API, temporal_rule_url(API, AccountId, kz_doc:id(Temporal_ruleJObj)), Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, TemporalRuleId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, temporal_rule_url(API, AccountId, TemporalRuleId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, TemporalRuleId) ->
    pqc_cb_crud:delete(API, temporal_rule_url(API, AccountId, TemporalRuleId)).


-spec temporal_rules_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
temporal_rules_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"temporal_rules">>).

-spec temporal_rule_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
temporal_rule_url(API, AccountId, TemporalRuleId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"temporal_rules">>, TemporalRuleId).
