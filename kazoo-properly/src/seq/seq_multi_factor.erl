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
-module(seq_multi_factor).

-export([seq/0
        ,seq_totp/0
        ,seq_impersonate_bypass/0
        ,cleanup/0

        ,should_run/0
        ,seq_kcro_273/0
        ]).

-include("properly.hrl").


-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-spec seq() -> 'ok'.
seq() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun seq_totp/0
                  ,fun seq_impersonate_bypass/0
                  ,fun seq_kcro_273/0
                  ]).

%% @doc test enabling KAZOO TOTP 2FA
-spec seq_totp() -> 'ok'.
seq_totp() ->
    seq_totp(should_run()).

-spec should_run() -> boolean().
should_run() ->
    ScriptName = filename:join([code:lib_dir('properly'), <<"scripts">>, <<"check-qrcode-readiness.py">>]),
    should_run(kz_os:cmd(ScriptName)).

should_run({'ok', <<"True\n">>}) ->
    lager:info("QR code readiness available"),
    'true';
should_run(_Response) ->
    lager:info("readiness check returned unready: ~p", [_Response]),
    lager:info("run: python3 -mpip install --user --upgrade opencv-python numpy Image pyzbar"),
    lager:info("or `make python`"),
    'false'.

seq_totp('false') -> 'ok';
seq_totp('true') ->
    API = pqc_cb_api:init_api(['crossbar']
                             ,['cb_multi_factor', 'cb_users', 'cb_security']
                             ),

    AvailableProvidersResp = pqc_cb_multi_factor:providers_summary(API),
    lager:info("available providers: ~s", [AvailableProvidersResp]),

    %%   1. enable "KAZOO" provider for MFA on user_auth
    Provider = new_kazoo_provider(),
    CreatedProviderResp = pqc_cb_multi_factor:provider_create(API, Provider),
    lager:info("created provider: ~s", [CreatedProviderResp]),

    ProviderId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(CreatedProviderResp)),

    FetchedProviderResp = pqc_cb_multi_factor:provider_fetch(API, ProviderId),
    lager:info("fetched provider: ~s", [FetchedProviderResp]),

    %% general idea:

    %%   2. create account/user
    AccountId = create_account(API, ?ACCOUNT_NAME),
    {UserJObj, _Username, _Password} = create_user(API, AccountId),
    UserId = kz_doc:id(UserJObj),
    {OTPType, OTPArgs} = get_qr_code(API, AccountId, UserId),

    %%   3. create MFA security policy for user_auth in account
    SecuritySummary = pqc_cb_security:summary(API),
    lager:info("security summary: ~s", [SecuritySummary]),

    AccountSecuritySummary = pqc_cb_security:account_summary(API, AccountId),
    lager:info("account security summary: ~s", [AccountSecuritySummary]),

    MFA = kz_json:from_list([{<<"configuration_id">>, ProviderId}
                            ,{<<"account_id">>, AccountId}
                            ,{<<"enabled">>, 'true'}
                            ]),
    UserAuth = kz_json:from_list([{<<"multi_factor">>, MFA}]),
    SecurityDoc = kz_json:set_value([<<"auth_modules">>, <<"cb_user_auth">>], UserAuth, kz_json:new()),

    AccountSecurityUpdate = pqc_cb_security:account_patch(API, AccountId, SecurityDoc),
    lager:info("account security update: ~s", [AccountSecurityUpdate]),

    AccountSecurity = kz_json:decode(AccountSecurityUpdate),
    'true' = kz_json:is_true([<<"data">>, <<"auth_modules">>, <<"cb_user_auth">>, <<"multi_factor">>, <<"enabled">>], AccountSecurity),
    ProviderId = kz_json:get_ne_binary_value([<<"data">>, <<"auth_modules">>, <<"cb_user_auth">>, <<"multi_factor">>, <<"configuration_id">>], AccountSecurity),
    AccountId = kz_json:get_ne_binary_value([<<"data">>, <<"auth_modules">>, <<"cb_user_auth">>, <<"multi_factor">>, <<"account_id">>], AccountSecurity),

    %%   4. PUT /v2/user_auth
    %%      recv 401 with req for TOTP code
    {'error', MFANeededResp} = authenticate_user(API, AccountId, UserJObj),
    lager:info("mfa needed: ~p", [MFANeededResp]),

    Data = kz_json:get_json_value(<<"data">>, kz_json:decode(MFANeededResp)),
    <<"otp">> = kz_json:get_value([<<"multi_factor_request">>, <<"provider_name">>], Data),
    <<"totp">> = kz_json:get_value([<<"multi_factor_request">>, <<"key_type">>], Data),

    %%   5. PUT /v2/user_auth + TOTP code
    %%      recv 200 + auth token
    MFACode = mfa_code(OTPType, OTPArgs),
    AuthUserResp = authenticate_user(API, AccountId, UserJObj, MFACode),
    lager:info("auth user mfa: ~p", [AuthUserResp]),

    AuthUser = kz_json:decode(AuthUserResp),
    AuthData = kz_json:get_json_value(<<"data">>, AuthUser),

    UserAuthToken = kz_json:get_ne_binary_value(<<"auth_token">>, AuthUser),

    UserId = kz_json:get_ne_binary_value(<<"owner_id">>, AuthData),
    AccountId = kz_json:get_ne_binary_value(<<"account_id">>, AuthData),

    use_auth_token(API, AccountId, UserId, UserAuthToken),

    DeletedProviderResp = pqc_cb_multi_factor:provider_delete(API, ProviderId),
    lager:info("deleted provider: ~s", [DeletedProviderResp]),

    cleanup(API, [AccountId]),
    lager:info("FINISHED TOTP SEQ").

-spec seq_impersonate_bypass() -> 'ok'.
seq_impersonate_bypass() ->
    seq_impersonate_bypass(should_run()).

seq_impersonate_bypass('false') -> 'ok';
seq_impersonate_bypass('true') ->
    API = pqc_cb_api:init_api(['crossbar']
                             ,['cb_multi_factor', 'cb_users', 'cb_security']
                             ),

    AvailableProvidersResp = pqc_cb_multi_factor:providers_summary(API),
    lager:info("available providers: ~s", [AvailableProvidersResp]),

    %%   1. enable "KAZOO" provider for MFA on user_auth
    Provider = new_kazoo_provider(),
    CreatedProviderResp = pqc_cb_multi_factor:provider_create(API, Provider),
    lager:info("created provider: ~s", [CreatedProviderResp]),

    ProviderId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(CreatedProviderResp)),

    FetchedProviderResp = pqc_cb_multi_factor:provider_fetch(API, ProviderId),
    lager:info("fetched provider: ~s", [FetchedProviderResp]),

    %% general idea:

    %%   2. create account/user
    AccountId = create_account(API, ?ACCOUNT_NAME),
    {UserJObj, _Username, _Password} = create_user(API, AccountId),
    UserId = kz_doc:id(UserJObj),

    %%   3. create MFA security policy for user_auth in account
    SecuritySummary = pqc_cb_security:summary(API),
    lager:info("security summary: ~s", [SecuritySummary]),

    AccountSecuritySummary = pqc_cb_security:account_summary(API, AccountId),
    lager:info("account security summary: ~s", [AccountSecuritySummary]),

    MFA = kz_json:from_list([{<<"configuration_id">>, ProviderId}
                            ,{<<"account_id">>, AccountId}
                            ,{<<"enabled">>, 'true'}
                            ]),
    UserAuth = kz_json:from_list([{<<"multi_factor">>, MFA}]),
    SecurityDoc = kz_json:set_value([<<"auth_modules">>, <<"cb_user_auth">>], UserAuth, kz_json:new()),

    AccountSecurityUpdate = pqc_cb_security:account_patch(API, AccountId, SecurityDoc),
    lager:info("account security update: ~s", [AccountSecurityUpdate]),

    AccountSecurity = kz_json:decode(AccountSecurityUpdate),
    'true' = kz_json:is_true([<<"data">>, <<"auth_modules">>, <<"cb_user_auth">>, <<"multi_factor">>, <<"enabled">>], AccountSecurity),
    ProviderId = kz_json:get_ne_binary_value([<<"data">>, <<"auth_modules">>, <<"cb_user_auth">>, <<"multi_factor">>, <<"configuration_id">>], AccountSecurity),
    AccountId = kz_json:get_ne_binary_value([<<"data">>, <<"auth_modules">>, <<"cb_user_auth">>, <<"multi_factor">>, <<"account_id">>], AccountSecurity),

    %%   4. PUT /v2/user_auth
    %%      recv 401 with req for TOTP code
    {'error', MFANeededResp} = authenticate_user(API, AccountId, UserJObj),
    lager:info("mfa needed: ~p", [MFANeededResp]),

    Data = kz_json:get_json_value(<<"data">>, kz_json:decode(MFANeededResp)),
    <<"otp">> = kz_json:get_value([<<"multi_factor_request">>, <<"provider_name">>], Data),
    <<"totp">> = kz_json:get_value([<<"multi_factor_request">>, <<"key_type">>], Data),

    %%   5. PUT /v2/user_auth + TOTP code
    %%      recv 200 + auth token
    AuthUserResp = pqc_cb_user_auth:impersonate_user(API, AccountId, UserId),
    lager:info("auth user mfa: ~p", [AuthUserResp]),

    AuthUser = kz_json:decode(AuthUserResp),
    AuthData = kz_json:get_json_value(<<"data">>, AuthUser),

    UserAuthToken = kz_json:get_ne_binary_value(<<"auth_token">>, AuthUser),

    UserId = kz_json:get_ne_binary_value(<<"owner_id">>, AuthData),
    AccountId = kz_json:get_ne_binary_value(<<"account_id">>, AuthData),

    use_auth_token(API, AccountId, UserId, UserAuthToken),

    DeletedProviderResp = pqc_cb_multi_factor:provider_delete(API, ProviderId),
    lager:info("deleted provider: ~s", [DeletedProviderResp]),

    cleanup(API, [AccountId]),
    lager:info("FINISHED TOTP BYPASS SEQ").

-spec seq_kcro_273() -> 'ok'.
seq_kcro_273() ->
    API = pqc_cb_api:init_api(['crossbar']
                             ,['cb_multi_factor', 'cb_users', 'cb_security']
                             ),

    AvailableProvidersResp = pqc_cb_multi_factor:providers_summary(API),
    lager:info("available providers: ~s", [AvailableProvidersResp]),

    %%   1. enable "KAZOO" provider for MFA on user_auth
    Provider = new_kazoo_provider(),
    CreatedProviderResp = pqc_cb_multi_factor:provider_create(API, Provider),
    lager:info("created provider: ~s", [CreatedProviderResp]),

    ProviderId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(CreatedProviderResp)),

    FetchedProviderResp = pqc_cb_multi_factor:provider_fetch(API, ProviderId),
    lager:info("fetched provider: ~s", [FetchedProviderResp]),

    %% general idea:

    %%   2. create account/user
    AccountId = create_account(API, ?ACCOUNT_NAME),

    {UserJObj, Username, Password} = create_user(API, AccountId),
    UserId = kz_doc:id(UserJObj),

    %%   3. create MFA security policy for user_auth in account
    SecuritySummary = pqc_cb_security:summary(API),
    lager:info("security summary: ~s", [SecuritySummary]),

    AccountSecuritySummary = pqc_cb_security:account_summary(API, AccountId),
    lager:info("account security summary: ~s", [AccountSecuritySummary]),

    MFA = kz_json:from_list([{<<"configuration_id">>, ProviderId}
                            ,{<<"account_id">>, AccountId}
                            ,{<<"enabled">>, 'true'}
                            ]),
    UserAuth = kz_json:from_list([{<<"multi_factor">>, MFA}]),
    SecurityDoc = kz_json:set_value([<<"auth_modules">>, <<"cb_user_auth">>], UserAuth, kz_json:new()),

    AccountSecurityUpdate = pqc_cb_security:account_patch(API, AccountId, SecurityDoc),
    lager:info("account security update: ~s", [AccountSecurityUpdate]),

    AccountSecurity = kz_json:decode(AccountSecurityUpdate),
    'true' = kz_json:is_true([<<"data">>, <<"auth_modules">>, <<"cb_user_auth">>, <<"multi_factor">>, <<"enabled">>], AccountSecurity),
    ProviderId = kz_json:get_ne_binary_value([<<"data">>, <<"auth_modules">>, <<"cb_user_auth">>, <<"multi_factor">>, <<"configuration_id">>], AccountSecurity),
    AccountId = kz_json:get_ne_binary_value([<<"data">>, <<"auth_modules">>, <<"cb_user_auth">>, <<"multi_factor">>, <<"account_id">>], AccountSecurity),

    %%   4. PUT /v2/multi_factor/qrcode
    %%      recv 201/403 + qr_code
    QRData = kz_json:from_list([{<<"account_name">>, ?ACCOUNT_NAME}
                               ,{<<"credentials">>, kz_binary:md5([Username, $:, Password])}
                               ,{<<"method">>, <<"md5">>}
                               ]),
    QRCreateResp = pqc_cb_multi_factor:qrcode_create(API, QRData),
    lager:info("first time qr_code generation : ~p", [QRCreateResp]),
    'true' =
        lists:any(
          fun(Obj) -> kz_json:is_defined(<<"qr_url">>, Obj) end,
          kz_json:get_list_value(<<"data">>, kz_json:decode(QRCreateResp), [])
         ),

    QRCreate2Resp = pqc_cb_multi_factor:qrcode_create(API, QRData),
    lager:info("second time qr_code generation : ~p", [QRCreate2Resp]),
    'true' =
        lists:any(
          fun(Obj) -> kz_json:is_defined(<<"qr_url">>, Obj) end,
          kz_json:get_list_value(<<"data">>, kz_json:decode(QRCreate2Resp), [])
         ),

    %%   5. PUT /v2/multi_factor/qrcode + TOTP code
    %%      recv 201
    TotpCodeList = tuple_to_list(kz_auth_otp:totp(AccountId, UserId)),
    SelectedTotpCode = lists:nth(rand:uniform(length(TotpCodeList)), TotpCodeList),
    ValidateQRData = kz_json:from_list([{<<"account_name">>, ?ACCOUNT_NAME}
                                       ,{<<"credentials">>, kz_binary:md5([Username, $:, Password])}
                                       ,{<<"multi_factor_response">>, SelectedTotpCode}
                                       ,{<<"method">>, <<"md5">>}
                                       ]),
    lager:info("multi_factor response validation request data : ~p", [ValidateQRData]),
    ValidationResp = kz_json:decode(pqc_cb_multi_factor:qrcode_create(API, ValidateQRData)),
    <<"success">> = kz_json:get_value(<<"status">>, ValidationResp),
    lager:info("multi_factor response validation success. "),

    {'error', QRCreate3Resp} = pqc_cb_multi_factor:qrcode_create(API, QRData),
    lager:info("third time qr_code generation - after qr code verification: ~p", [QRCreate3Resp]),

    cleanup(API, [AccountId]),
    lager:info("FINISHED TOTP QRCODE SEQ").

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
    lager:info("created user ~p", [CreateResp]),

    CreatedUser = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    Username = kzd_users:username(CreatedUser),
    'undefined' = kzd_users:password(CreatedUser),

    {CreatedUser, Username, Password}.

get_qr_code(API, AccountId, UserId) ->
    QRCode = pqc_cb_users:qrcode(API, AccountId, UserId),
    'ok' = file:write_file(<<"/tmp/qrcode.png">>, QRCode),
    ScriptName = filename:join([code:lib_dir('properly'), <<"scripts">>, <<"qrdecode.py">>]),
    case kz_os:cmd(<<ScriptName/binary, " /tmp/qrcode.png">>) of
        {'ok', Bin} ->
            lager:info("QR code contained ~s", [Bin]),
            {<<"otpauth">>, OTPType, _ProviderAndUser
            ,Querystring, _
            } = kz_http_util:urlsplit(kz_binary:strip_right(Bin, $\n)),

            {kz_term:to_atom(OTPType)
            ,kz_http_util:parse_query_string(kz_binary:strip_right(Querystring, $\n))
            };
        {'error', _, _E} ->
            lager:warning("error qrcode: ~p", [_E]),
            'undefined'
    end.

new_kazoo_provider() ->
    kz_doc:setters(kzd_multi_factor_provider:new()
                  ,[{fun kzd_multi_factor_provider:set_enabled/2, 'true'}
                   ,{fun kzd_multi_factor_provider:set_name/2, <<"KAZOO">>}
                   ,{fun kzd_multi_factor_provider:set_provider_name/2, <<"otp">>}
                   ,{fun kzd_multi_factor_provider:set_settings/2, kz_json:new()}
                   ]
                  ).

authenticate_user(API, AccountId, UserJObj) ->
    authenticate_user(API, AccountId, UserJObj, 'undefined').

authenticate_user(API, AccountId, UserJObj, MFAResp) ->
    Username = kzd_users:username(UserJObj),
    pqc_cb_user_auth:by_account_id(API, AccountId, Username, <<?MODULE_STRING>>, MFAResp).

mfa_code('totp', OTPArgs) ->
    Secret = props:get_value(<<"secret">>, OTPArgs),
    Period = props:get_integer_value(<<"period">>, OTPArgs),
    {_, CurrentT, _} = kz_auth_otp:totp_calc(Secret, Period),
    CurrentT.

use_auth_token(API, AccountId, UserId, UserAuthToken) ->
    FetchResp = pqc_cb_users:fetch(API#{auth_token => UserAuthToken}, AccountId, UserId),
    lager:debug("fetched myself: ~s", [FetchResp]),
    FetchData = kz_json:get_json_value(<<"data">>, kz_json:decode(FetchResp)),

    UserId = kz_doc:id(FetchData),
    'true' = kz_json:is_true(<<"enabled">>, FetchData),
    'ok'.
