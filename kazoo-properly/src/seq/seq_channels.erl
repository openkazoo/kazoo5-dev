%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_channels).

-export([seq/0
        ,seq_kcro_93/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    lists:foreach(fun(F) -> F() end, [fun seq_kcro_93/0]).

-spec seq_kcro_93() -> 'ok'.
seq_kcro_93() ->
    API = pqc_cb_api:init_api(['crossbar', 'ecallmgr'], ['cb_channels']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    UUID = kz_binary:rand_hex(8),
    Expectation = [pqc_cb_expect:code(404)],

    FetchResp = pqc_cb_channels:fetch(API, AccountId, UUID, Expectation),
    lager:debug("fetch resp: ~s", [FetchResp]),
    'true' = verify_matches(kz_json:decode(FetchResp), bad_identifier_matches(UUID)),
    lager:info("all expected fields match"),

    cleanup(API, [AccountId]),
    lager:info("FINISHED CHANNELS SEQ_KCRO_93").

-spec verify_matches(kz_json:object(), kz_term:proplist()) -> boolean().
verify_matches(JObj, Matches) ->
    lists:all(fun kz_term:identity/1
             ,[verify_match(K, V, kz_json:get_value(K, JObj)) || {K, V} <- Matches]
             ).

verify_match(_K, RespV, RespV) -> 'true';
verify_match(_K, _ExpectedV, _GotV) ->
    lager:info("failed to match key '~s': got ~p expected ~p", [_K, _GotV, _ExpectedV]),
    'false'.

-spec bad_identifier_matches(kz_term:ne_binary()) -> kz_term:proplist().
bad_identifier_matches(UUID) ->
    [{<<"data">>, [UUID]}
    ,{<<"error">>, <<"404">>}
    ,{<<"message">>, <<"bad identifier">>}
    ,{<<"status">>, <<"error">>}
    ].

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = properly_maintenance:cleanup_module_accounts(?MODULE),
    cleanup_system().

cleanup(API, AccountIds) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, AccountIds),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.

-spec create_account(pqc_cb_api:state(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_account(API, AccountName) ->
    AccountResp = properly_accountant:create_account(API, AccountName),
    lager:info("created account: ~s", [AccountResp]),

    kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)).
