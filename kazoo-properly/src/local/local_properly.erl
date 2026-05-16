%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023, 2600Hz
%%% @doc Test /properly Crossbar API.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(local_properly).

-export([local/0
        ,local_crossbar_put_replies/0
        ,cleanup/0, cleanup/1
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).
%%% `cb_properly' Crossbar API's implementation is within properly/src/integration folder.
-define(API_NAME, 'cb_properly').

-type asserts() :: [{kz_term:ne_binary() | kz_term:ne_binaries(), kz_term:ne_binary()}].

-spec local() -> 'ok'.
local() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun local_crossbar_put_replies/0]
                 ).

-spec local_crossbar_put_replies() -> 'ok'.
local_crossbar_put_replies() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts', ?API_NAME]),
    'true' = lists:member(?API_NAME, crossbar_maintenance:running_modules()),

    %% Create testing account.
    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    lager:info("created account ~s", [AccountResp]),
    AccountId = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    Tests = [{"return_200", 200, [{<<"status">>, <<"success">>}
                                 ,{[<<"data">>, <<"ok">>], <<"success">>}
                                 ]}
            ,{"", 201, [{<<"status">>, <<"success">>}]}
            ,{"return_202", 202, [{<<"status">>, <<"success">>}
                                 ,{<<"data">>, <<"processing">>}
                                 ]}
            ,{"return_400", 400, [{[<<"data">>, <<"bad">>], <<"request">>}
                                 | error_asserts(<<"400">>, <<"invalid request">>)
                                 ]}
            ,{"return_401", 401, error_asserts(<<"401">>, <<"invalid credentials">>)}
            ,{"return_402", 402, [{[<<"data">>, <<"payment">>], <<"required">>}
                                 | error_asserts(<<"402">>, <<"accept charges">>)
                                 ]}
            ,{"return_404", 404, [{<<"data">>, [<<"invalid-id">>]}
                                 | error_asserts(<<"404">>, <<"bad identifier">>)
                                 ]}
            ,{"return_500", 500, error_asserts(<<"500">>, <<"something went wrong">>)}
            ],

    StrAccountURL = pqc_cb_accounts:account_url(API, AccountId),
    Payload = pqc_cb_api:create_envelope(kz_json:new()),
    'true' = lists:all(fun({PathToken, ExpCode, Asserts}) ->
                               lager:info("running '~s' test case", [PathToken]),
                               URL = string:join([StrAccountURL, "properly", PathToken], "/"),
                               BodyExpect = fun(Reply) -> assert(Reply, Asserts) end,
                               Expectations = [pqc_cb_expect:expect([ExpCode], [], BodyExpect)],
                               %% Since expectations were provided, failing test cases should
                               %% return something like {error, binary}, instead of just a binary.
                               kz_term:is_ne_binary(pqc_cb_crud:create(API, URL, Payload, Expectations))
                       end
                      ,Tests
                      ),

    lager:info("FINISHED local_crossbar_put_replies"),
    cleanup(API).

-spec error_asserts(kz_term:ne_binary(), kz_term:ne_binary()) -> asserts().
error_asserts(Error, Msg) ->
    [{<<"status">>, <<"error">>}
    ,{<<"error">>, Error}
    ,{<<"message">>, Msg}
    ].

-spec assert(kz_term:ne_binary(), asserts()) -> 'ok'.
assert(BinReply, Asserts) ->
    JObj = kz_json:decode(BinReply),
    'true' = lists:all(fun({K, V}) -> V =:= kz_json:get_value(K, JObj) end, Asserts),
    'ok'.

-spec cleanup() -> 'ok'.
cleanup() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),
    cleanup(API).

-spec cleanup(pqc_cb_api:state()) -> 'ok'.
cleanup(API) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, ?ACCOUNT_NAMES),
    _ = pqc_cb_api:cleanup(API),
    'ok'.
