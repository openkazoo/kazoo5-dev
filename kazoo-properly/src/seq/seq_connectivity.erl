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
-module(seq_connectivity).

-export([seq/0
        ,cleanup/0
        ,new_connectivity/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_connectivity']),
    AccountId = create_account(API, ?ACCOUNT_NAME),
    {'ok', AccountDoc} = kzd_accounts:fetch(AccountId),
    AccountRealm = kzd_accounts:realm(AccountDoc),

    EmptySummaryResp = pqc_cb_connectivity:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    ConnectivityJObj = new_connectivity(),
    CreateResp = pqc_cb_connectivity:create(API, AccountId, ConnectivityJObj),
    lager:info("created connectivity ~s", [CreateResp]),
    CreatedConnectivity = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    ConnectivityId = kz_doc:id(CreatedConnectivity),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_connectivity:patch(API, AccountId, ConnectivityId, Patch),
    lager:info("patched to ~s", [PatchResp]),

    SummaryResp = pqc_cb_connectivity:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [ConnectivityId] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),

    Edited = kzd_connectivity:set_account_auth_realm(CreatedConnectivity, kz_binary:rand_hex(4)),
    EditedResp = pqc_cb_connectivity:update(API, AccountId, Edited),
    lager:info("edited resp: ~s", [EditedResp]),
    EditedDoc = kz_json:get_json_value(<<"data">>, kz_json:decode(EditedResp)),
    AccountRealm = kzd_connectivity:account_auth_realm(EditedDoc),
    ConnectivityId = kz_doc:id(EditedDoc),

    DeleteResp = pqc_cb_connectivity:delete(API, AccountId, ConnectivityId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_connectivity:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED CONNECTIVITY SEQ").

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

    kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)).

-spec new_connectivity() -> kzd_connectivity:doc().
new_connectivity() ->
    kz_doc:setters(kzd_connectivity:new()
                  ,[{fun kzd_connectivity:set_account_auth_realm/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_connectivity:set_name/2, <<?MODULE_STRING>>}
                   ,{fun kzd_connectivity:set_servers/2, []}
                   ]).
