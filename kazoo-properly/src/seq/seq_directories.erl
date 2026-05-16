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
-module(seq_directories).

-export([seq/0
        ,cleanup/0
        ,new_directory/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_directories']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_directories:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    FirstCreateResp = pqc_cb_directories:create(API, AccountId, new_directory()),
    lager:info("created first directory: ~s", [FirstCreateResp]),
    FirstDirectory = kz_json:get_json_value(<<"data">>, kz_json:decode(FirstCreateResp)),
    FirstDirectoryId = kz_doc:id(FirstDirectory),

    FirstUsers = create_users(API, AccountId, FirstDirectoryId),
    FirstUserIds = [kz_doc:id(User) || User <- FirstUsers],
    lager:info("created users: ~p", [FirstUserIds]),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_directories:patch(API, AccountId, FirstDirectoryId, Patch),
    lager:info("patched to ~s", [PatchResp]),

    SecondCreateResp = pqc_cb_directories:create(API, AccountId, new_directory()),
    lager:info("created second directory: ~s", [SecondCreateResp]),
    SecondDirectory = kz_json:get_json_value(<<"data">>, kz_json:decode(SecondCreateResp)),
    SecondDirectoryId = kz_doc:id(SecondDirectory),

    SecondUsers = create_users(API, AccountId, SecondDirectoryId),
    SecondUserIds = [kz_doc:id(User) || User <- SecondUsers],

    %% ensure we get the "earlier" directory to test that we don't
    %% fetch the other directory's users
    {DirectoryId, UserIds} =
        case FirstDirectoryId > SecondDirectoryId of
            'true' -> {SecondDirectoryId, SecondUserIds};
            'false' -> {FirstDirectoryId, FirstUserIds}
        end,

    FetchResp = pqc_cb_directories:fetch(API, AccountId, DirectoryId, [{<<"paginate">>, 'false'}]),
    lager:info("fetched directory: ~s", [FetchResp]),
    FetchedUsers = kz_json:get_list_value([<<"data">>, <<"users">>], kz_json:decode(FetchResp)),
    lager:info("fetched users: ~p created users: ~p", [length(FetchedUsers), length(UserIds)]),

    'true' = length(UserIds) =:= length(FetchedUsers),
    'true' = lists:all(fun(FetchedUser) ->
                               lists:member(kz_json:get_ne_binary_value(<<"user_id">>, FetchedUser)
                                           ,UserIds
                                           )
                       end
                      ,FetchedUsers
                      ),

    FirstDeleteResp = pqc_cb_directories:delete(API, AccountId, FirstDirectoryId),
    lager:info("first delete resp: ~s", [FirstDeleteResp]),

    SecondDeleteResp = pqc_cb_directories:delete(API, AccountId, SecondDirectoryId),
    lager:info("second delete resp: ~s", [SecondDeleteResp]),

    EmptyAgain = pqc_cb_directories:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED DIRECTORIES SEQ").

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

-spec new_directory() -> kzd_directories:doc().
new_directory() ->
    kz_doc:public_fields(
      kzd_directories:set_name(kzd_directories:new()
                              ,kz_binary:rand_hex(4)
                              )
     ).

-spec create_users(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> [kzd_users:doc()].
create_users(API, AccountId, DirectoryId) ->
    [create_user(API, AccountId, DirectoryId, N) || N <- lists:seq(1, 10)].

-spec create_user(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), 1..10) -> kzd_users:doc().
create_user(API, AccountId, DirectoryId, NthUser) ->
    Directories = kz_json:from_list([{DirectoryId, kz_binary:rand_hex(16)}]),
    UserDoc = kzd_users:set_directories(seq_users:new_user(), Directories),

    Results = pqc_cb_users:create(API, AccountId, kz_json:set_value(<<"nth">>, NthUser, UserDoc)),
    kz_json:get_json_value(<<"data">>, kz_json:decode(Results)).
