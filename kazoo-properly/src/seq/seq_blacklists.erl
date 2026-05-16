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
-module(seq_blacklists).

-export([seq/0
        ,cleanup/0
        ,new_blacklist/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_blacklists']),
    AccountId = create_account(API),

    EmptySummaryResp = pqc_cb_blacklists:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    BlacklistJObj = new_blacklist(),
    CreateResp = pqc_cb_blacklists:create(API, AccountId, BlacklistJObj),
    lager:info("created blacklist ~s", [CreateResp]),
    CreatedBlacklist = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    BlacklistId = kz_doc:id(CreatedBlacklist),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_blacklists:patch(API, AccountId, BlacklistId, Patch),
    lager:info("patched to ~s", [PatchResp]),

    SummaryResp = pqc_cb_blacklists:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryBlacklist] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    BlacklistId = kz_doc:id(SummaryBlacklist),

    DeleteResp = pqc_cb_blacklists:delete(API, AccountId, BlacklistId),
    lager:info("delete resp: ~s", [DeleteResp]),
    Deleted = kz_json:decode(DeleteResp),

    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, Deleted),
    BlacklistId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], Deleted),
    'true' = kz_json:is_true([<<"metadata">>, <<"deleted">>], Deleted),

    EmptyAgain = pqc_cb_blacklists:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API),
    lager:info("FINISHED BLACKLIST SEQ").

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

-spec new_blacklist() -> kzd_blacklists:doc().
new_blacklist() ->
    kz_doc:public_fields(
      kzd_blacklists:set_name(kzd_blacklists:new()
                             ,kz_binary:rand_hex(4)
                             )
     ).
