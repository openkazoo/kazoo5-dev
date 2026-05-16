%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% @author Navoda Ginige
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_getstream).

-export([seq/0
        ,seq_getstream/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).

-spec seq() -> 'ok'.
seq() ->
    Fs = [fun seq_getstream/0],
    run_funcs(Fs).

run_funcs([]) -> 'ok';
run_funcs([F|Fs]) ->
    _ = F(),
    run_funcs(Fs).

-spec seq_getstream() -> 'ok'.
seq_getstream() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_getstream']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    UserId = create_user(API, AccountId),

    EnableUserResp = pqc_cb_getstream:enable(API, AccountId, UserId),
    lager:info("user getstream enable resp: ~s", [EnableUserResp]),
    'true' = kz_json:is_true([<<"data">>, <<"enabled">>], kz_json:decode(EnableUserResp)),

    UserStatusResp = pqc_cb_getstream:user_status(API, AccountId, UserId),
    lager:info("user getstream status resp: ~s", [UserStatusResp]),
    'true' = kz_json:is_true([<<"data">>, <<"enabled">>], kz_json:decode(UserStatusResp)),

    AccountSummaryResp = pqc_cb_getstream:account_summary(API, AccountId),
    lager:info("account summary resp: ~s", [AccountSummaryResp]),
    [UserJObj] = kz_json:get_list_value([<<"data">>], kz_json:decode(AccountSummaryResp)),
    UserId = kz_json:get_binary_value(<<"id">>, UserJObj),

    DisableGetstreamResp = pqc_cb_getstream:disable(API, AccountId, UserId, patch_getstream_disable_obj()),
    lager:info("user getstream disable resp: ~s", [DisableGetstreamResp]),
    'false' = kz_json:is_true([<<"data">>, <<"enabled">>], kz_json:decode(DisableGetstreamResp)),

    DeleteGetstreamResp = pqc_cb_getstream:delete(API, AccountId, UserId),
    lager:info("user getstream delete resp: ~s", [DeleteGetstreamResp]),
    'false' = kz_json:is_true([<<"data">>, <<"enabled">>], kz_json:decode(DeleteGetstreamResp)),

    EmptySummaryResp = pqc_cb_getstream:account_summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryResp)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED getstream SEQ").

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

-spec create_user(pqc_cb_api:state(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_user(API, AccountId) ->
    UserJObj = new_user(),
    CreateUserResp = pqc_cb_users:create(API, AccountId, UserJObj),
    lager:info("created user ~p", [CreateUserResp]),
    kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>]
                               ,kz_json:decode(CreateUserResp)
                               ).

-spec new_user() -> kzd_users:doc().
new_user() ->
    new_user(kz_json:new()).

-spec new_user(kzd_users:doc()) -> kzd_users:doc().
new_user(UserDoc) ->
    DefaultUser = kz_json_schema:add_defaults(kzd_users:new(), kzd_users:schema()),
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_users:set_first_name/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_users:set_last_name/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_users:set_username/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_users:set_password/2, kz_binary:rand_hex(4)}
                         ]
                        ,kz_json:merge(UserDoc, DefaultUser)
                        )
     ).

-spec patch_getstream_disable_obj() -> kz_json:object().
patch_getstream_disable_obj() ->
    kz_json:from_list([{<<"enabled">>, 'false'}
                      ,{<<"nick_name">>, kz_binary:rand_hex(4)}
                      ]).
