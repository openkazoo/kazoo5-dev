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
-module(seq_match_lists).

-export([seq/0
        ,cleanup/0
        ,new_match_list/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_match_lists']),
    AccountId = create_account(API),

    EmptySummaryResp = pqc_cb_match_lists:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    ListJObj = new_match_list(),
    CreateResp = pqc_cb_match_lists:create(API, AccountId, ListJObj),
    lager:info("created list ~s", [CreateResp]),
    CreatedList = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    ListId = kz_doc:id(CreatedList),

    Key = kz_binary:rand_hex(5),
    Value = kz_binary:rand_hex(5),
    Patch = kz_json:from_list([{Key, Value}]),
    PatchResp = pqc_cb_match_lists:patch(API, AccountId, ListId, Patch),
    lager:info("patched to ~s", [PatchResp]),
    PatchedList = kz_json:get_json_value(<<"data">>, kz_json:decode(PatchResp)),
    ListId = kz_doc:id(PatchedList),
    Value = kz_json:get_ne_binary_value(Key, PatchedList),

    SummaryResp = pqc_cb_match_lists:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryList] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    ListId = kz_doc:id(SummaryList),

    DeleteResp = pqc_cb_match_lists:delete(API, AccountId, ListId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_match_lists:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API),
    lager:info("FINISHED LIST SEQ").

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

-spec new_match_list() -> kzd_match_lists:doc().
new_match_list() ->
    DefaultMatchList = kz_json_schema:add_defaults(kzd_match_lists:new(), kzd_match_lists:schema()),
    Rules = [],
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_match_lists:set_name/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_match_lists:set_rules/2, Rules}
                         ]
                        ,DefaultMatchList
                        )
     ).
