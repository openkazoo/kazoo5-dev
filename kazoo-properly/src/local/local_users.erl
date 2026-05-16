%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(local_users).

-export([local/0
        ,local_kzoo_303/0
        ,cleanup/0
        ]).

-include("properly.hrl").
-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).

-spec local() -> 'ok'.
local() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun local_kzoo_303/0]
                 ).

-spec local_kzoo_303() -> 'ok'.
local_kzoo_303() ->
    lager:info("testing KZOO-303 for password requirements enforcement", []),
    API = pqc_cb_api:init_api(['crossbar'], ['cb_users']),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account ~s", [AccountResp]),
    AccountId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    ConfigResp = pqc_cb_system_configs:get_default_config(API, <<"auth.password">>),
    lager:info("config resp: ~s", [ConfigResp]),
    ConfigOrig = kz_json:decode(ConfigResp),
    CurrentEnforce = kz_json:is_true([<<"default">>, <<"should_enforce_strength">>], ConfigOrig),
    CurrentPrevent = kz_json:is_true([<<"default">>, <<"should_prevent_reuse">>], ConfigOrig),

    InsecureUser = kz_doc:setters(seq_users:new_user()
                                 ,[{fun kzd_users:set_username/2, kz_binary:rand_hex(6)}
                                  ,{fun kzd_users:set_password/2, <<"bad">>}
                                  ]
                                 ),

    CreateUser = pqc_cb_users:create(API, AccountId, InsecureUser),
    lager:info("created a user with insecure password: ~s", [CreateUser]),
    NewUser = kz_json:get_value(<<"data">>, kz_json:decode(CreateUser)),

    WithInsecurePass = kzd_users:set_password(NewUser, <<"stillbad">>),
    WithSecurePass1 = kzd_users:set_password(NewUser, <<"Security_1s_S0_exiciting!">>),
    WithSecurePass2 = kzd_users:set_password(WithSecurePass1, <<"I_ran_out_0f_!dea">>),

    try
        _ = patch_auth_password_config(API, <<"should_enforce_strength">>, 'true'),
        _ = patch_auth_password_config(API, <<"should_prevent_reuse">>, 'false'),
        %% add a small delay to let db and cache to ketchup :)
        kapps_account_config:flush_all_strategies(AccountId, <<"auth.password">>),

        lager:info("testing password enforcement with an insecure password"),
        UpdateInsecure = pqc_cb_users:update(API, AccountId, WithInsecurePass),
        lager:info("tried updating user with an insecure password: ~s", [UpdateInsecure]),
        {'error', UpdatedInsecure} = UpdateInsecure,
        'true' = passowrd_validation_err(kz_json:decode(UpdatedInsecure), [<<"at least one special character is required">>
                                                                          ,<<"at least one digit is required">>
                                                                          ,<<"at least one upper case character is required">>
                                                                          ,<<"minimum password length is 10 characters">>
                                                                          ]
                                        ),

        lager:info("testing password enforcement with a secure password"),
        UpdatedSecure = pqc_cb_users:update(API, AccountId, WithSecurePass1),
        lager:info("updated user with a secure password: ~s", UpdatedSecure),
        <<"success">> = kz_json:get_value(<<"status">>, kz_json:decode(UpdatedSecure)),

        _ = patch_auth_password_config(API, <<"should_prevent_reuse">>, 'true'),
        %% too fast kapps_account_config cache can't ketchup
        kapps_account_config:flush_all_strategies(AccountId, <<"auth.password">>),

        lager:info("testing prevent updating user with same password"),
        UpdatePrevent = pqc_cb_users:update(API, AccountId, WithSecurePass1),
        lager:info("tried updating user with same secure password: ~s", [UpdatePrevent]),
        {'error', UpdatedPrevent} = UpdatePrevent,
        'true' = passowrd_validation_err(kz_json:decode(UpdatedPrevent), [<<"cannot use same password">>]),

        lager:info("testing updating user with a different secure password"),
        UpdatedDifferent = pqc_cb_users:update(API, AccountId, WithSecurePass2),
        lager:info("updated user with a different secure password: ~s", [UpdatedDifferent]),
        <<"success">> = kz_json:get_value(<<"status">>, kz_json:decode(UpdatedDifferent)),

        cleanup(API, [AccountId]),
        lager:info("FINISHED KZOO-303")
    after
        _ = patch_auth_password_config(API, <<"should_enforce_strength">>, CurrentEnforce),
        _ = patch_auth_password_config(API, <<"should_prevent_reuse">>, CurrentPrevent),
        'ok'
    end.

patch_auth_password_config(API, Key, Value) ->
    Payload = kz_json:from_list([{<<"default">>, kz_json:from_list([{Key, Value}])}]),
    pqc_cb_system_configs:patch_default_config(API, <<"auth.password">>, Payload).

passowrd_validation_err(Resp, Errors) ->
    Path = [<<"data">>, <<"password">>, <<"insecure">>, <<"details">>],
    RespErrors = kz_json:get_value(Path, Resp),
    lists:all(fun(Error) -> lists:member(Error, Errors) end, RespErrors).

-spec cleanup() -> 'ok'.
cleanup() ->
    properly_maintenance:cleanup_module_accounts(?MODULE).

-spec cleanup(pqc_cb_api:state(), kz_term:ne_binaries()) -> 'ok'.
cleanup(API, AccountIds) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, AccountIds),
    _ = pqc_cb_api:cleanup(API),
    'ok'.
