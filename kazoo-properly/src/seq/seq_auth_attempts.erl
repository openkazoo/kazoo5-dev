%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2026, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_auth_attempts).

-export([seq/0
        ,seq_auth_types/0
        ,seq_exhaust_tokens/0
        ,seq_kcro_277/0
        ,cleanup/0

        ,create_user/2
        ]).

-include("properly.hrl").

-properly({standalone, [seq_exhaust_tokens/0]}).

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-spec seq() -> 'ok'.
seq() ->
    lists:foreach(fun run_it/1
                 ,[fun seq_auth_types/0
                  ,fun seq_exhaust_tokens/0
                  ,fun seq_kcro_277/0
                  ]
                 ).

run_it(F) -> F().

-spec seq_auth_types() -> 'ok'.
seq_auth_types() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_user_auth', 'cb_basic_auth']),
    AccountName = ?ACCOUNT_NAME,
    {AccountId, AccountRealm} = create_account(API, AccountName),

    {Username, Password} = user_auth(API, AccountId, AccountRealm, AccountName),
    _ = basic_auth(API, AccountId, Username, Password),

    _ = cors_basic_auth(API, AccountId, Username, Password),

    cleanup(API, [AccountId]),
    lager:info("FINISHED AUTH SEQ").

-spec seq_kcro_277() -> 'ok'.
seq_kcro_277() ->
    %% security check if descendant account check is violated when a cb module is implemented authorize callback
    API = pqc_cb_api:init_api(['crossbar'], ['cb_basic_auth', 'cb_notifications', 'cb_search', 'cb_users']),
    AccountName = ?ACCOUNT_NAME,
    {AccountId, AccountRealm} = create_account(API, AccountName),
    {Username, Password} = user_auth(API, AccountId, AccountRealm, AccountName),

    BasicUser = iolist_to_binary([AccountId, $:, kz_binary:md5([Username, $:, Password])]),
    Authorization = base64:encode(BasicUser),

    %% this should failed with error: 403 forbidden
    SummaryResp = pqc_cb_crud:summary(API#{basic_auth => Authorization} %% sub-account auth
                                     ,pqc_cb_crud:collection_url(API
                                                                ,maps:get('account_id', API) %% master account id
                                                                ,<<"notifications">>
                                                                )
                                     ),
    lager:info("notification summary: ~p", [SummaryResp]),
    {'error', Resp} = SummaryResp,
    403 = kz_json:get_integer_value(<<"error">>, kz_json:decode(Resp)),
    <<"forbidden">> = kz_json:get_ne_binary_value(<<"message">>, kz_json:decode(Resp)),

    %% this should failed with error: 403 forbidden
    SearchResp = pqc_cb_crud:summary(API#{basic_auth => Authorization} %% sub-account auth
                                    ,pqc_cb_crud:collection_url(API
                                                               ,maps:get('account_id', API) %% master account id
                                                               ,<<"search">>
                                                               ) ++ "?t=user&q=name&v=accountadmin"
                                    ),
    lager:info("search summary: ~p", [SearchResp]),
    {'error', Searched} = SearchResp,
    403 = kz_json:get_integer_value(<<"error">>, kz_json:decode(Searched)),
    <<"forbidden">> = kz_json:get_ne_binary_value(<<"message">>, kz_json:decode(Searched)),

    {'error', SeeItShouldFailedLikeANormalModule} =
        pqc_cb_crud:patch(API#{basic_auth => Authorization} %% sub-account auth
                         ,pqc_cb_crud:entity_url(API
                                                ,maps:get('account_id', API) %% master account id
                                                ,<<"users">>
                                                     %% if the test above was not forbidden, it would return searched users
                                                     %% so here we could have potentially found the first admin user id
                                                     %% ,kz_doc:id(hd(kz_json:get_value(<<"data">>, kz_json:decode(Searched))))
                                                ,kz_binary:rand_hex(16)
                                                )
                         ,pqc_cb_api:create_envelope(kz_json:from_list([{<<"password">>, <<"admin">>}]))
                         ),
    lager:info("password change attempt: ~p", [SeeItShouldFailedLikeANormalModule]),
    403 = kz_json:get_integer_value(<<"error">>, kz_json:decode(SeeItShouldFailedLikeANormalModule)),
    <<"forbidden">> = kz_json:get_ne_binary_value(<<"message">>, kz_json:decode(SeeItShouldFailedLikeANormalModule)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED SEQ").

-spec seq_exhaust_tokens() -> 'ok'.
seq_exhaust_tokens() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_user_auth']),
    OldTokenCosts = pqc_cb_api:get_current_token_costs(API),
    lager:info("current token costs: ~p", [OldTokenCosts]),
    pqc_cb_api:patch_token_costs(API, 1),

    AccountName = ?ACCOUNT_NAME,
    {AccountId, _AccountRealm} = create_account(API, AccountName),

    {_UserId, Username, Password} = create_user(API, AccountId),

    exhaust_tokens(API, OldTokenCosts, AccountName, Username, Password, 4, 100).

exhaust_tokens(API, OldTokenCosts, _AccountName, _Username, _Password, 0, _TokensLeft) ->
    lager:warning("exhausted expected attempts, still have tokens left: ~p", [_TokensLeft]),
    pqc_cb_api:patch_token_costs(API, OldTokenCosts),
    exit({'error', 'tokens_remain'});
exhaust_tokens(API, OldTokenCosts, AccountName, Username, Password, _Attempts, TokensLeft) when TokensLeft < 35 ->
    lager:info("expect a 429 since tokens left are ~p (attempts left: ~p)", [TokensLeft, _Attempts]),
    {'error', AuthRespJSON} = pqc_cb_user_auth:by_account_name(API, AccountName, Username, Password),
    lager:info("429 auth resp: ~s", [AuthRespJSON]),
    AuthResp = kz_json:decode(AuthRespJSON),

    <<"error">> = kz_json:get_ne_binary_value(<<"status">>, AuthResp),
    429 = kz_json:get_integer_value(<<"error">>, AuthResp),

    pqc_cb_api:patch_token_costs(API, OldTokenCosts),

    cleanup(API, [AccountName]),
    lager:info("FINISHED EXHAUST SEQ");
exhaust_tokens(API, OldTokenCosts, AccountName, Username, Password, Attempts, TokensLeft) ->
    lager:info("expect success since tokens left are ~p", [TokensLeft]),

    AuthRespJSON = pqc_cb_user_auth:by_account_name(API, AccountName, Username, Password),
    lager:info("auth resp: ~s", [AuthRespJSON]),

    AuthResp = kz_json:decode(AuthRespJSON),

    Remaining = kz_json:get_integer_value([<<"tokens">>, <<"remaining">>], AuthResp),
    Consumed = kz_json:get_integer_value([<<"tokens">>, <<"consumed">>], AuthResp),

    case is_integer(Consumed)
        andalso Consumed >= 35
    of
        'true' ->
            lager:info("consumed ~p tokens, remaining: ~p", [Consumed, Remaining]);
        'false' ->
            lager:error("wrong consumed tokens bucket amount ~p, expected at least 35, remaining amount: ~p"
                       ,[Consumed, Remaining]
                       ),
            throw({'error', 'wrong_consume_tokens'})
    end,

    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, AuthResp),
    exhaust_tokens(API, OldTokenCosts, AccountName, Username, Password, Attempts-1, Remaining).

user_auth(API, AccountId, AccountRealm, AccountName) ->
    {UserId, Username, Password} = create_user(API, AccountId),

    AuthNameResp = pqc_cb_user_auth:by_account_name(API, AccountName, Username, Password),
    lager:info("auth resp: ~s", [AuthNameResp]),

    AuthNameData = kz_json:get_json_value(<<"data">>, kz_json:decode(AuthNameResp)),

    UserId = kz_json:get_ne_binary_value(<<"owner_id">>, AuthNameData),
    AccountId = kz_json:get_ne_binary_value(<<"account_id">>, AuthNameData),
    AccountName = kz_json:get_ne_binary_value(<<"account_name">>, AuthNameData),

    AuthRealmResp = pqc_cb_user_auth:by_account_realm(API, AccountRealm, Username, Password),
    lager:info("auth resp: ~s", [AuthRealmResp]),
    AuthRealmData = kz_json:get_json_value(<<"data">>, kz_json:decode(AuthRealmResp)),
    'true' = kz_json:are_equal(AuthNameData, AuthRealmData),
    {Username, Password}.

basic_auth(API, AccountId, Username, Password) ->
    BasicUser = iolist_to_binary([AccountId, $:, kz_binary:md5([Username, $:, Password])]),
    Authorization = base64:encode(BasicUser),

    SummaryResp = pqc_cb_users:summary(API#{basic_auth => Authorization}, AccountId),
    lager:info("basic summary: ~s", [SummaryResp]),
    [UserSummary] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),

    Username = kz_json:get_ne_binary_value(<<"username">>, UserSummary).

cors_basic_auth(API, AccountId, Username, Password) ->
    BasicUser = iolist_to_binary([AccountId, $:, kz_binary:md5([Username, $:, Password])]),
    Authorization = base64:encode(BasicUser),

    UsersURL = pqc_cb_users:users_url(API, AccountId),

    CORSHeaders = [{<<"Access-Control-Request-Method">>, "GET"}
                  ,{<<"Access-Control-Request-Headers">>, "Content-Type, Accept, Authorization"}
                  ,{<<"Origin">>, "http://localhost:2600"}
                  ],

    {'ok', 200, OptionsHeaders, <<>>} = options_req(UsersURL, CORSHeaders),
    lager:info("OPTIONS: ~p", [OptionsHeaders]),

    Methods = props:get_value("access-control-allow-methods", OptionsHeaders),
    ["GET", "OPTIONS", "PUT"] = lists:sort(string:split(Methods, ", ", 'all')),

    AllowHeaders = props:get_value("access-control-allow-headers", OptionsHeaders),
    'true' = lists:member("authorization", string:split(AllowHeaders, ", ", 'all')),

    Expectations = [pqc_cb_expect:code(200)],
    SummaryResp = pqc_cb_crud:summary(API
                                     ,UsersURL
                                     ,Expectations
                                     ,pqc_cb_api:request_headers(API#{basic_auth => Authorization}, CORSHeaders)
                                     ),
    lager:info("basic summary: ~s", [SummaryResp]),
    [UserSummary] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),

    Username = kz_json:get_ne_binary_value(<<"username">>, UserSummary).

options_req(URL, Headers) ->
    kz_http:options(URL, Headers).

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = properly_maintenance:cleanup_module_accounts(?MODULE),
    cleanup_system(pqc_cb_api:authenticate()).

cleanup(API, Accounts) ->
    timer:sleep(2000),
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, Accounts),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system(API).

cleanup_system(API) ->
    pqc_cb_api:patch_token_costs(API, 0).

-spec create_account(pqc_cb_api:state(), kz_term:ne_binary()) ->
          {kz_term:ne_binary(), kz_term:ne_binary()}.
create_account(API, AccountName) ->
    AccountResp = properly_accountant:create_account(API, AccountName),
    lager:info("created account: ~s", [AccountResp]),

    AccountDoc = kz_json:get_json_value(<<"data">>, kz_json:decode(AccountResp)),
    {kz_doc:id(AccountDoc), kzd_accounts:realm(AccountDoc)}.

-spec create_user(pqc_cb_api:state(), kz_term:ne_binary()) ->
          {kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()}.
create_user(API, AccountId) ->
    Username = kz_binary:rand_hex(6),
    Password = kz_binary:rand_hex(6),

    User = kz_doc:setters(seq_users:new_user()
                         ,[{fun kzd_users:set_username/2, Username}
                          ,{fun kzd_users:set_password/2, Password}
                          ]
                         ),
    <<CreateResp/binary>> = pqc_cb_users:create(API, AccountId, User),
    lager:info("created user ~s", [CreateResp]),

    CreatedUser = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    Username = kzd_users:username(CreatedUser),
    'undefined' = kzd_users:password(CreatedUser),

    {kz_doc:id(CreatedUser), Username, Password}.
