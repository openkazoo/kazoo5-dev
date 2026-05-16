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
-module(seq_resource_templates).

-export([seq/0
        ,cleanup/0
        ,new_resource_template/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_resource_templates']),
    AccountId = create_account(API),

    EmptySummaryResp = pqc_cb_resource_templates:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    Resource_templateJObj = new_resource_template(),
    CreateResp = pqc_cb_resource_templates:create(API, AccountId, Resource_templateJObj),
    lager:info("created resource_template ~s", [CreateResp]),
    CreatedResource_template = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    Resource_templateId = kz_doc:id(CreatedResource_template),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_resource_templates:patch(API, AccountId, Resource_templateId, Patch),
    lager:info("patched to ~s", [PatchResp]),

    SummaryResp = pqc_cb_resource_templates:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryResource_template] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    Resource_templateId = kz_doc:id(SummaryResource_template),

    DeleteResp = pqc_cb_resource_templates:delete(API, AccountId, Resource_templateId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_resource_templates:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API),
    lager:info("FINISHED RESOURCE_TEMPLATE SEQ").

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = seq_accounts:cleanup_accounts(?ACCOUNT_NAMES),
    cleanup_system().

cleanup(API) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, ?ACCOUNT_NAMES),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.

-spec create_account(pqc_cb_api:state()) -> kz_term:ne_binary().
create_account(API) ->
    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    lager:info("created account: ~s", [AccountResp]),

    kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)).

-spec new_resource_template() -> kzd_resource_templates:doc().
new_resource_template() ->
    kz_doc:public_fields(
      kz_json:from_list([{<<"template_name">>, kz_binary:rand_hex(4)}])
     ).
