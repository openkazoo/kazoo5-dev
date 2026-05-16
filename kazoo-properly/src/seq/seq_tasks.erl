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
-module(seq_tasks).

-export([seq/0
        ,seq_kzoo_87/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-spec seq() -> 'ok'.
seq() ->
    seq_kzoo_87().

-spec seq_kzoo_87() -> 'ok'.
seq_kzoo_87() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_tasks']),
    AccountId = create_account(API),
    TaskId = kz_binary:rand_hex(16),
    {'error', Error} = pqc_cb_tasks:fetch(API, AccountId, TaskId, <<"start_key=undefined&limit=15">>),
    lager:info("expected error fetching '~s': ~s", [TaskId, Error]),
    ErrorResp = kz_json:decode(Error),

    404 = kz_json:get_integer_value(<<"error">>, ErrorResp),
    <<"bad identifier">> = kz_json:get_ne_binary_value(<<"message">>, ErrorResp),
    <<"error">> = kz_json:get_ne_binary_value(<<"status">>, ErrorResp),
    [TaskId] = kz_json:get_list_value(<<"data">>, ErrorResp),

    cleanup(API),
    lager:info("FINISHED KZOO-87").

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = pqc_accounts:cleanup_accounts([<<?MODULE_STRING>>]),
    cleanup_system().

cleanup(API) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = pqc_accounts:cleanup_accounts(API, [<<?MODULE_STRING>>]),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.

-spec create_account(pqc_cb_api:state()) -> kz_term:ne_binary().
create_account(API) ->
    AccountResp = properly_accountant:create_account(API, <<?MODULE_STRING>>),
    lager:info("created account: ~s", [AccountResp]),

    kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)).
