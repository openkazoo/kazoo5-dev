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
-module(seq_groups).

-export([seq/0
        ,cleanup/0
        ,new_group/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_groups']),
    AccountId = create_account(API),

    EmptySummaryResp = pqc_cb_groups:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    GroupJObj = new_group(),
    CreateResp = pqc_cb_groups:create(API, AccountId, GroupJObj),
    lager:info("created group ~s", [CreateResp]),
    CreatedGroup = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    GroupId = kz_doc:id(CreatedGroup),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_groups:patch(API, AccountId, GroupId, Patch),
    lager:info("patched to ~s", [PatchResp]),

    SummaryResp = pqc_cb_groups:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryGroup] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    GroupId = kz_doc:id(SummaryGroup),

    DeleteResp = pqc_cb_groups:delete(API, AccountId, GroupId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_groups:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API),
    lager:info("FINISHED GROUP SEQ").

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

-spec new_group() -> kzd_groups:doc().
new_group() ->
    kz_doc:public_fields(
      kzd_groups:set_name(kzd_groups:new()
                         ,kz_binary:rand_hex(4)
                         )
     ).
