%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2024-, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_webhooks).

%% API functions
-export([list_available/1
        ,samples/1, sample/2

         %% Account operations
        ,summary/2
        ,create/3
        ,patch/4
        ,delete/3
        ]).

-include("properly.hrl").

-spec list_available(pqc_cb_api:state()) -> pqc_cb_api:response().
list_available(API) ->
    URL = base_webhooks_url(API),

    pqc_cb_crud:summary(API, URL).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    WebhooksURL = webhooks_url(API, AccountId),

    pqc_cb_crud:summary(API, WebhooksURL).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
create(API, AccountId, WebhookData) ->
    URL = webhooks_url(API, AccountId),
    pqc_cb_crud:create(API, URL, pqc_cb_api:create_envelope(WebhookData)).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, WebhookId, PatchJObj) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, webhook_url(API, AccountId, WebhookId), Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, WebhookId) ->
    URL = webhook_url(API, AccountId, WebhookId),
    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],
    pqc_cb_crud:delete(API, URL, Expectations).

-spec samples(pqc_cb_api:state()) -> pqc_cb_api:response().
samples(API) ->
    URL = samples_url(API),

    pqc_cb_crud:fetch(API, URL).

-spec sample(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
sample(API, SampleId) ->
    URL = sample_url(API, SampleId),

    pqc_cb_crud:fetch(API, URL).

-spec base_webhooks_url(pqc_cb_api:state()) -> string().
base_webhooks_url(API) ->
    pqc_cb_crud:collection_url(API, <<"webhooks">>).

-spec webhooks_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
webhooks_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"webhooks">>).

-spec webhook_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
webhook_url(API, AccountId, WebhookId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"webhooks">>, WebhookId).

-spec samples_url(pqc_cb_api:state()) -> string().
samples_url(API) ->
    pqc_cb_crud:entity_url(API, <<"webhooks">>, <<"samples">>).

-spec sample_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
sample_url(API, SampleId) ->
    string:join([samples_url(API), kz_term:to_list(SampleId)], "/").
