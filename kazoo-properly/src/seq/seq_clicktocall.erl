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
-module(seq_clicktocall).

-export([seq/0
        ,cleanup/0
        ,new_clicktocall/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_clicktocall']),
    AccountId = create_account(API),

    EmptySummaryResp = pqc_cb_clicktocall:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    ClicktocallJObj = new_clicktocall(),
    CreateResp = pqc_cb_clicktocall:create(API, AccountId, ClicktocallJObj),
    lager:info("created clicktocall ~s", [CreateResp]),
    CreatedClicktocall = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    ClicktocallId = kz_doc:id(CreatedClicktocall),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_clicktocall:patch(API, AccountId, ClicktocallId, Patch),
    lager:info("patched to ~s", [PatchResp]),

    SummaryResp = pqc_cb_clicktocall:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryClicktocall] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    ClicktocallId = kz_doc:id(SummaryClicktocall),

    DeleteResp = pqc_cb_clicktocall:delete(API, AccountId, ClicktocallId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_clicktocall:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API),
    lager:info("FINISHED CLICKTOCALL SEQ").

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

-spec new_clicktocall() -> kzd_clicktocall:doc().
new_clicktocall() ->
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_clicktocall:set_name/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_clicktocall:set_extension/2, <<"2600">>}
                         ]
                        ,kzd_clicktocall:new()
                        )
     ).
