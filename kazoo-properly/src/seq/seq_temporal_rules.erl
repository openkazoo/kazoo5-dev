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
-module(seq_temporal_rules).

-export([seq/0
        ,cleanup/0
        ,new_temporal_rule/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_temporal_rules']),
    AccountId = create_account(API),

    EmptySummaryResp = pqc_cb_temporal_rules:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    TemporalRuleJObj = new_temporal_rule(),
    CreateResp = pqc_cb_temporal_rules:create(API, AccountId, TemporalRuleJObj),
    lager:info("created temporal_rule ~s", [CreateResp]),
    CreatedTemporalRule = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    TemporalRuleId = kz_doc:id(CreatedTemporalRule),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_temporal_rules:patch(API, AccountId, TemporalRuleId, Patch),
    lager:info("patched to ~s", [PatchResp]),

    SummaryResp = pqc_cb_temporal_rules:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryTemporalRule] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    TemporalRuleId = kz_doc:id(SummaryTemporalRule),

    FetchResp = pqc_cb_temporal_rules:fetch(API, AccountId, TemporalRuleId),
    lager:info("fetch resp: ~s", [FetchResp]),
    TemporalRuleId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(FetchResp)),

    {Year, _M, _D} = erlang:date(),
    TauDay = {{Year, 6, 28}, {6, 28, 31}},
    TauTimestamp = calendar:datetime_to_gregorian_seconds(TauDay),

    TauResp = pqc_cb_temporal_rules:fetch(API, AccountId, TemporalRuleId, kz_json:from_list([{<<"timestamp">>, TauTimestamp}])),
    lager:info("fetch tau day: ~s", [TauResp]),
    TauEval = kz_json:decode(TauResp),
    'true' = kz_json:is_true([<<"metadata">>, <<"rule_matches">>], TauEval),
    TemporalRuleId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], TauEval),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, TauEval),

    PiDay = {{Year, 3, 14}, {15, 9, 26}},
    PiTimestamp = calendar:datetime_to_gregorian_seconds(PiDay),
    PiResp = pqc_cb_temporal_rules:fetch(API, AccountId, TemporalRuleId, kz_json:from_list([{<<"timestamp">>, PiTimestamp}])),
    lager:info("fetch pi day: ~s", [PiResp]),
    PiEval = kz_json:decode(PiResp),
    'false' = kz_json:is_true([<<"metadata">>, <<"rule_matches">>], PiEval),
    TemporalRuleId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], PiEval),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, PiEval),

    DeleteResp = pqc_cb_temporal_rules:delete(API, AccountId, TemporalRuleId),
    lager:info("delete resp: ~s", [DeleteResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(DeleteResp)),

    EmptyAgain = pqc_cb_temporal_rules:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API),
    lager:info("FINISHED TEMPORAL_RULE SEQ").

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

-spec new_temporal_rule() -> kzd_temporal_rules:doc().
new_temporal_rule() ->
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_temporal_rules:set_cycle/2, <<"yearly">>}
                         ,{fun kzd_temporal_rules:set_days/2, [28]}
                         ,{fun kzd_temporal_rules:set_month/2, 6}
                         ,{fun kzd_temporal_rules:set_ordinal/2, <<"every">>}
                         ,{fun kzd_temporal_rules:set_name/2, <<"Tau Day">>}
                         ]
                        ,kzd_temporal_rules:new()
                        )
     ).
