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
-module(seq_menus).

-export([seq/0
        ,cleanup/0
        ,new_menu/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_menus']),
    AccountId = create_account(API),

    EmptySummaryResp = pqc_cb_menus:summary(API, AccountId),
    ?INFO("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    MenuJObj = new_menu(),
    CreateResp = pqc_cb_menus:create(API, AccountId, MenuJObj),
    ?INFO("created menu ~s", [CreateResp]),
    CreatedMenu = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    MenuId = kz_doc:id(CreatedMenu),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_menus:patch(API, AccountId, MenuId, Patch),
    ?INFO("patched to ~s", [PatchResp]),

    SummaryResp = pqc_cb_menus:summary(API, AccountId),
    ?INFO("summary resp: ~s", [SummaryResp]),
    [SummaryMenu] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    MenuId = kz_doc:id(SummaryMenu),

    DeleteResp = pqc_cb_menus:delete(API, AccountId, MenuId),
    ?INFO("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_menus:summary(API, AccountId),
    ?INFO("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API),
    lager:info("FINISHED MENU SEQ").

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

-spec new_menu() -> kzd_menus:doc().
new_menu() ->
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_menus:set_name/2, kz_binary:rand_hex(4)}]
                        ,kzd_menus:new()
                        )
     ).
