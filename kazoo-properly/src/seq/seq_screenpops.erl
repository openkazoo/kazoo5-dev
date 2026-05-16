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
-module(seq_screenpops).

-export([seq/0
        ,cleanup/0
        ,new_screenpop/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_screenpops']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_screenpops:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    ScreenpopJObj = new_screenpop(),
    CreateResp = pqc_cb_screenpops:create(API, AccountId, ScreenpopJObj),
    lager:info("created screenpop ~s", [CreateResp]),
    CreatedScreenpop = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    ScreenpopId = kz_doc:id(CreatedScreenpop),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_screenpops:patch(API, AccountId, ScreenpopId, Patch),
    lager:info("patched to ~s", [PatchResp]),

    SummaryResp = pqc_cb_screenpops:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryScreenpop] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    ScreenpopId = kz_doc:id(SummaryScreenpop),

    DeleteResp = pqc_cb_screenpops:delete(API, AccountId, ScreenpopId),
    lager:info("delete resp: ~s", [DeleteResp]),

    UserId = create_user(API, AccountId),
    ScreenpopJObj1 = new_screenpop([{[<<"permissions">>, <<"allow">>], [UserId]}, {[<<"permissions">>, <<"all_users">>], 'false'}]),
    CreateResp1 = pqc_cb_screenpops:create(API, AccountId, ScreenpopJObj1),
    CreatedScreenpop1 = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp1)),
    ScreenpopId1 = kz_doc:id(CreatedScreenpop1),

    SummaryResp1 = pqc_cb_screenpops:user_summary(API, AccountId, UserId),
    lager:info("summary resp: ~s", [SummaryResp1]),
    [SummaryScreenpop1] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp1)),
    ScreenpopId1 = kz_doc:id(SummaryScreenpop1),

    DeleteResp1 = pqc_cb_screenpops:delete(API, AccountId, ScreenpopId1),
    lager:info("delete resp: ~s", [DeleteResp1]),

    ScreenpopJObj2 = new_screenpop([{[<<"permissions">>, <<"deny">>], [UserId]}, {[<<"permissions">>, <<"all_users">>], 'false'}]),
    CreateResp2 = pqc_cb_screenpops:create(API, AccountId, ScreenpopJObj2),
    CreatedScreenpop2 = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp2)),
    ScreenpopId2 = kz_doc:id(CreatedScreenpop2),

    SummaryResp2 = pqc_cb_screenpops:user_summary(API, AccountId, UserId),
    lager:info("summary resp: ~s", [SummaryResp2]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp2)),

    DeleteResp2 = pqc_cb_screenpops:delete(API, AccountId, ScreenpopId2),
    lager:info("delete resp: ~s", [DeleteResp2]),

    ScreenpopJObj3 = new_screenpop([{[<<"permissions">>, <<"deny">>], [UserId]}, {[<<"permissions">>, <<"all_users">>], 'true'}]),
    CreateResp3 = pqc_cb_screenpops:create(API, AccountId, ScreenpopJObj3),
    CreatedScreenpop3 = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp3)),
    ScreenpopId3 = kz_doc:id(CreatedScreenpop3),

    SummaryResp3 = pqc_cb_screenpops:user_summary(API, AccountId, UserId),
    lager:info("summary resp: ~s", [SummaryResp3]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp3)),

    DeleteResp3 = pqc_cb_screenpops:delete(API, AccountId, ScreenpopId3),
    lager:info("delete resp: ~s", [DeleteResp3]),

    ScreenpopJObj4 = new_screenpop([{[<<"permissions">>, <<"deny">>], [UserId]}, {[<<"permissions">>, <<"allow">>], [UserId]}]),
    CreateResp4 = pqc_cb_screenpops:create(API, AccountId, ScreenpopJObj4),
    CreatedScreenpop4 = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp4)),
    ScreenpopId4 = kz_doc:id(CreatedScreenpop4),

    SummaryResp4 = pqc_cb_screenpops:user_summary(API, AccountId, UserId),
    lager:info("summary resp: ~s", [SummaryResp4]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp4)),

    DeleteResp4 = pqc_cb_screenpops:delete(API, AccountId, ScreenpopId4),
    lager:info("delete resp: ~s", [DeleteResp4]),

    ScreenpopJObj5 = new_screenpop(),
    CreateResp5 = pqc_cb_screenpops:create(API, AccountId, ScreenpopJObj5),
    CreatedScreenpop5 = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp5)),
    ScreenpopId5 = kz_doc:id(CreatedScreenpop5),

    SummaryResp5 = pqc_cb_screenpops:user_summary(API, AccountId, UserId),
    lager:info("summary resp: ~s", [SummaryResp5]),
    [SummaryScreenpop5] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp5)),
    ScreenpopId5 = kz_doc:id(SummaryScreenpop5),

    DeleteResp5 = pqc_cb_screenpops:delete(API, AccountId, ScreenpopId5),
    lager:info("delete resp: ~s", [DeleteResp5]),

    EmptyAgain = pqc_cb_screenpops:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED SCREENPOP SEQ").

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

-spec new_screenpop() -> kzd_screenpops:doc().
new_screenpop() ->
    kz_doc:public_fields(kz_json_schema:add_defaults(kzd_screenpops:new(), kzd_screenpops:schema_name())).

new_screenpop(Options) -> new_screenpop(Options, new_screenpop()).

new_screenpop([], JObj) -> JObj;
new_screenpop([{Key, Value}|Options], JObj) ->
    JObj1 = kz_json:set_value(Key, Value, JObj),
    new_screenpop(Options, JObj1).

create_user(API, AccountId) ->
    UserJObj = new_user(),
    CreateUserResp = pqc_cb_users:create(API, AccountId, UserJObj),
    lager:info("created user ~p", [CreateUserResp]),
    kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(CreateUserResp)).

-spec new_user() -> kzd_users:doc().
new_user() ->
    new_user(kz_json:new()).

-spec new_user(kzd_users:doc()) -> kzd_users:doc().
new_user(UserDoc) ->
    DefaultUser = kz_json_schema:add_defaults(kzd_users:new(), kzd_users:schema()),
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_users:set_first_name/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_users:set_last_name/2, kz_binary:rand_hex(4)}
                         ]
                        ,kz_json:merge(UserDoc, DefaultUser)
                        )
     ).
