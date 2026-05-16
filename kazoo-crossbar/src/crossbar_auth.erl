%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2026, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(crossbar_auth).

-export([create_auth_token/2, create_auth_token/3
        ,validate_auth_token/1, validate_auth_token/2
        ,authorize_auth_token/1
        ,reset_identity_secret/1
        ,log_success_auth/4, log_success_auth/5, log_success_auth/6
        ,log_failed_auth/4, log_failed_auth/5, log_failed_auth/6
        ,get_inherited_config/1
        ,available_scopes/1
        ,scopes/2
        ,validate_refresh_token/1, refresh_token/1

        ,get_auth_account_info/1
        ,is_account_locked/2
        ,maybe_lock_account/3
        ,find_account_buckets/1
        ,unlock_account/1
        ]).

-include("crossbar.hrl").

-define(CB_DEFAULT_SCOPES, [?APP_NAME]).

-define(DEFAULT_METHOD_CONFIG(LogSuccess), ?DEFAULT_METHOD_CONFIG(LogSuccess, ?SECONDS_IN_HOUR)).
-define(DEFAULT_METHOD_CONFIG(LogSuccess, TokenExpirationTime),
        kz_json:from_list(
          [{<<"enabled">>, 'true'}
          ,{<<"token_auth_expiry_s">>, TokenExpirationTime}
          ,{<<"log_failed_attempts">>, 'true'}
          ,{<<"log_successful_attempts">>, LogSuccess}
          ,{<<"scopes">>, ?CB_DEFAULT_SCOPES}
          ]
         )
       ).

-define(DEFAULT_AUTH_CONFIG,
        kz_json:from_list(
          [{<<"cb_user_auth">>, ?DEFAULT_METHOD_CONFIG('true')}
          ,{<<"cb_api_auth">>, ?DEFAULT_METHOD_CONFIG('false')}
          ,{<<"cb_desktop_auth">>, ?DEFAULT_METHOD_CONFIG('false')}
          ,{<<"cb_auth">>, ?DEFAULT_METHOD_CONFIG('false')}
          ,{<<"cb_ip_auth">>, ?DEFAULT_METHOD_CONFIG('false')}
          ,{<<"cb_conference_auth">>, ?DEFAULT_METHOD_CONFIG('false', <<"infinity">>)}
          ]
         )
       ).

-define(DEFAULT_AUTH_EXPIRY, kapps_config:get_integer(?AUTH_CONFIG_CAT, <<"token_auth_expiry_s">>, ?SECONDS_IN_HOUR)).
-define(SHOULD_LOG_SUCCESS, kapps_config:get_is_true(?AUTH_CONFIG_CAT, <<"log_successful_attempts">>, 'true')).
-define(AUTH_MODULE_SCOPES_KEY(AuthModule), [<<"auth_modules">>, AuthModule, <<"scopes">>]).

-spec create_auth_token(cb_context:context(), atom()) ->
          cb_context:context().
create_auth_token(Context, AuthModule) ->
    create_auth_token(Context, AuthModule, []).

-type token_option() :: {'expiration_timestamp', pos_integer()}. % unix seconds
-type token_options() :: [token_option()].

-spec create_auth_token(cb_context:context(), atom(), token_options()) ->
          cb_context:context().
create_auth_token(Context, AuthModule, TokenOptions) ->
    JObj = cb_context:doc(Context),
    Method = kz_term:to_binary(AuthModule),
    AccountId = kz_json:get_first_defined([<<"account_id">>, [<<"Claims">>, <<"account_id">>]], JObj),
    case kz_json:is_empty(JObj) of
        'true' ->
            Reason = <<"empty creds doc, no auth token created">>,
            lager:debug("~s", [Reason]),
            log_failed_auth(Method, <<"jwt_auth_token">>, Reason, Context, AccountId),
            crossbar_util:response('error', <<"invalid credentials">>, 401, Context);
        'false' ->
            create_auth_token(Context, Method, TokenOptions, JObj, AccountId)
    end.

-spec create_auth_token(cb_context:context(), kz_term:ne_binary(), token_options(), kz_json:object(), kz_term:api_ne_binary()) ->
          cb_context:context().
create_auth_token(Context, <<Method/binary>>, TokenOptions, JObj, AccountId) ->
    AuthConfig = get_account_config(AccountId),

    case is_auth_module_enabled(Method, AuthConfig) of
        'false' ->
            Reason = <<"authentication module ", Method/binary, " is disabled">>,
            log_failed_auth(Method, <<"jwt_auth_token">>, Reason, Context, AccountId, AuthConfig),
            crossbar_util:response('error', <<"invalid credentials">>, 401, Context);
        'true' ->
            create_auth_token(Context, Method, TokenOptions, JObj, AccountId, AuthConfig)
    end.

create_auth_token(Context, Method, TokenOptions, JObj, AccountId, AuthConfig) ->
    Data = cb_context:req_data(Context),
    OwnerId = kz_json:get_first_defined([<<"owner_id">>, [<<"Claims">>, <<"owner_id">>]], JObj),

    Expiration = token_auth_expiry(Method, TokenOptions, AuthConfig),

    ReqClaims = kz_json:get_json_value(<<"Claims">>, JObj, kz_json:new()),
    AdditionalClaims = props:filter_undefined([{<<"account_id">>, AccountId}
                                              ,{<<"owner_id">>, OwnerId}
                                              ,{<<"method">>, Method}
                                              ,{<<"exp">>, Expiration}
                                              ,{<<"mfa_resp">>, kz_json:get_ne_value(<<"multi_factor_response">>, Data)}
                                              ]),
    Claims = kz_json:to_proplist(kz_json:set_values(AdditionalClaims, ReqClaims)),

    IsMultiFactor = is_multi_factor_enabled(Context, Claims, AuthConfig),

    case maybe_create_token(Context, Claims, AuthConfig, Method, IsMultiFactor) of
        {'ok', Token} ->
            Setters = [{fun cb_context:set_auth_token/2, Token}
                      ,{fun cb_context:set_auth_doc/2, kz_json:from_list(Claims)}
                      ,{fun cb_context:store/3, 'include_token', 'true'}
                      ],
            Props = props:filter_undefined(
                      [{<<"account_id">>, AccountId}
                      ,{<<"owner_id">>, OwnerId}
                      ]),
            RespObj = kz_json:set_values(Props, kz_json:delete_key(<<"Claims">>, JObj)),
            Resp = crossbar_util:response_auth(RespObj, AccountId, OwnerId),

            lager:debug("created new local auth token: ~s", [kz_json:encode(Resp)]),

            log_success_auth(Method, <<"jwt_auth_token">>, <<"authentication resulted in token creation">>, Context, AccountId, AuthConfig),

            crossbar_util:response(Resp, cb_context:setters(Context, Setters));
        {'error', R} ->
            Reason = kz_term:to_binary(R),
            lager:debug("could not create new local auth token, ~s", [Reason]),
            log_failed_auth(Method, <<"jwt_auth_token">>, Reason, Context, AccountId, AuthConfig),

            cb_context:add_system_error('invalid_credentials', Context);
        {'error', Reason, RespJObj} ->
            lager:debug("authentication factor module requested that the client should preform second-factor authentication, returning ~s with response ~p"
                       ,[kz_term:to_binary(Reason), RespJObj]
                       ),
            MFAReq = kz_json:from_list(
                       [{<<"message">>, <<"client needs to preform second-factor authentication">>}
                       ,{<<"multi_factor_request">>, RespJObj}
                       ,{<<"user_id">>, OwnerId}
                       ]
                      ),
            cb_context:add_system_error(401, 'invalid_credentials', MFAReq, Context)
    end.

-spec maybe_create_token(cb_context:context(), kz_term:proplist(), kz_json:object(), kz_term:ne_binary(), boolean()) ->
          {'ok', kz_term:ne_binary()} |
          {'error', any()} |
          {'error', any(), any()}.
maybe_create_token(_Context, Claims, _AuthConfig, _Method, 'false') ->
    kz_auth:create_token(Claims);
maybe_create_token(Context, Claims, AuthConfig, Method, 'true') ->
    lager:debug("auth module ~s is configured to use multi factor", [Method]),

    AccountId = props:get_value(<<"account_id">>, Claims),
    MultiFactorOpts = kz_json:get_json_value(method_config_path(Method, <<"multi_factor">>), AuthConfig),
    NewClaims = props:filter_undefined(
                  [{<<"mfa_options">>, MultiFactorOpts}
                  | Claims
                  ]),

    case kz_mfa_auth:authenticate(NewClaims) of
        {'ok', 'authenticated'} ->
            Reason = <<"multi factor authentication was successful">>,
            lager:debug("~s, creating local auth token", [Reason]),
            log_success_auth(Method, <<"multi_factor">>, Reason, Context, AccountId, AuthConfig),
            kz_auth:create_token(Claims);
        {'error', 'no_provider'} ->
            Reason = <<"no multi factor authentication provider is configured">>,
            lager:debug("~s, creating local auth token", [Reason]),
            log_failed_auth(Method, <<"multi_factor">>, Reason, Context, AccountId, AuthConfig),
            kz_auth:create_token(Claims);
        {'error', {'configuration', Reason}} ->
            lager:error("mfa configuration error : ~s", [Reason]),
            kz_auth:create_token(Claims);
        {'error', Reason}=Error ->
            log_failed_auth(Method, <<"multi_factor">>, kz_term:to_binary(Reason), Context, AccountId, AuthConfig),
            Error;
        {'error', 401, _MFAReq}=Retry -> Retry
    end.

-spec validate_auth_token(map() | kz_term:ne_binary()) ->
          {'ok', kz_json:object()} | {'error', any()}.
validate_auth_token(Token) ->
    validate_auth_token(Token, []).

-spec validate_auth_token(map() | kz_term:ne_binary(), kz_term:proplist()) ->
          {'ok', kz_json:object()} | {'error', any()}.
validate_auth_token(Token, Options) ->
    case kz_auth:validate_token(Token, Options) of
        {'error', 'no_jwt_signed_token'} -> maybe_db_token(Token);
        {'ok', Claims} ->
            ProxyIPs = props:get_value(<<"proxy_ips">>, Options),
            maybe_check_proxy(Claims, ProxyIPs)
    end.

maybe_check_proxy(Claims, 'undefined') ->
    {'ok', Claims};
maybe_check_proxy(Claims, ProxyIPs) ->
    case kz_json:is_true(<<"should_check_originating_proxy">>, Claims, 'false') of
        'true' -> check_proxy(Claims, ProxyIPs);
        'false' -> {'ok', Claims}
    end.

check_proxy(Claims, ProxyIPs) ->
    AccountId = kz_json:get_first_defined([<<"original_account_id">>, <<"account_id">>], Claims),
    UserId = kz_json:get_first_defined([<<"original_owner_id">>, <<"owner_id">>], Claims),
    UserProxies = kzd_users:allowed_proxy_ips(AccountId, UserId),
    AccountProxies = kzd_accounts:allowed_proxy_ips(AccountId),
    validate_proxy_ips(Claims, ProxyIPs, UserProxies, AccountProxies).

validate_proxy_ips(Claims, _, [], []) -> {'ok', Claims};
validate_proxy_ips(Claims, ProxyIPs, [], AccountProxies) ->
    validate_proxy_ips(Claims, ProxyIPs, AccountProxies);
validate_proxy_ips(Claims, ProxyIPs, UserProxies, _) ->
    validate_proxy_ips(Claims, ProxyIPs, UserProxies).

validate_proxy_ips(Claims, ProxyIPs, AllowedProxies) ->
    case kz_term:list_contains(ProxyIPs, AllowedProxies) of
        'true' -> {'ok', Claims};
        'false' ->
            lager:info("proxies ~p are not on allowed proxy list ~p", [ProxyIPs, AllowedProxies]),
            {'error', 'forbidden'}
    end.

-spec authorize_auth_token(map() | kz_term:ne_binary()) ->
          {'ok', kz_json:object()} | {'error', any()}.
authorize_auth_token(Token) ->
    kz_auth:authorize_token(Token).

-spec maybe_db_token(map() | kz_term:ne_binary()) ->
          {'ok', kz_json:object()} | {'error', any()}.
maybe_db_token(AuthToken) ->
    kz_datamgr:open_cache_doc(?KZ_TOKEN_DB, AuthToken).

%%------------------------------------------------------------------------------
%% @doc Update `pvt_signature_secret' for user
%% @end
%%------------------------------------------------------------------------------
-spec reset_identity_secret(cb_context:context()) -> cb_context:context().
reset_identity_secret(Context) ->
    Doc = kz_auth_identity:reset_doc_secret(cb_context:doc(Context)),
    cb_context:set_doc(Context, Doc).

%%------------------------------------------------------------------------------
%% @doc Get merge result of account and its parents, reseller and system
%% authentication configuration.
%% @end
%%------------------------------------------------------------------------------
-spec get_account_config(kz_term:api_ne_binary()) -> kz_json:object().
get_account_config(AccountId) ->
    get_account_config(AccountId, ?AUTH_CONFIG_CAT, <<"auth_modules">>, ?DEFAULT_AUTH_CONFIG).

get_account_config(AccountId, ConfigCat, Key, Default) ->
    kapps_account_config:get_hierarchy(AccountId
                                      ,ConfigCat
                                      ,Key
                                      ,Default
                                      ).

-spec get_inherited_config(cb_context:context()) -> kz_json:object().
get_inherited_config(Context) ->
    AccountId = cb_context:account_id(Context),
    get_inherited_config(AccountId, kz_services_reseller:is_reseller(AccountId)).

-spec get_inherited_config(kz_term:ne_binary(), boolean()) -> kz_json:object().
get_inherited_config(_, 'true') ->
    kapps_config:get_json(?AUTH_CONFIG_CAT, <<"auth_modules">>);
get_inherited_config(AccountId, 'false') ->
    ParentId = kzd_accounts:get_parent_account_id(AccountId),
    kapps_account_config:get_hierarchy(ParentId, ?AUTH_CONFIG_CAT, <<"auth_modules">>).

%%------------------------------------------------------------------------------
%% @doc Utility func to generate method's config path
%% @end
%%------------------------------------------------------------------------------
-spec method_config_path(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_json:path().
method_config_path(Method, Key) -> [Method, Key].

%%------------------------------------------------------------------------------
%% @doc Utility func to generate method's multi-factor config path
%% @end
%%------------------------------------------------------------------------------
-spec method_mfa_path(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_json:path().
method_mfa_path(Method, Key) -> [Method, <<"multi_factor">>, Key].

-spec token_auth_expiry(kz_term:ne_binary(), token_options(), kz_json:object()) -> non_neg_integer() | 'null'.
token_auth_expiry(Method, TokenOptions, AuthConfig) ->
    token_auth_expiry(Method, TokenOptions, AuthConfig, props:get_integer_value('expiration', TokenOptions)).

token_auth_expiry(Method, _TokenOptions, AuthConfig, 'undefined') ->
    Path = method_config_path(Method, <<"token_auth_expiry_s">>),
    case kz_json:get_integer_value(Path, AuthConfig, 'undefined') of
        'undefined' ->
            case ?DEFAULT_AUTH_EXPIRY of
                TokenExp when TokenExp > 0 ->
                    kz_time:current_unix_tstamp() + TokenExp;
                _ -> 'null'
            end;
        TokenExp when TokenExp > 0 ->
            kz_time:current_unix_tstamp() + TokenExp;
        _Else ->
            'null'
    end;
token_auth_expiry(_Method, _TokenOptions, _AuthConfig, Expiration) ->
    lager:info("using options-supplied exipration ~p", [Expiration]),
    Expiration.

%%------------------------------------------------------------------------------
%% @doc Check if is authenticator module is enabled or not.
%% @end
%%------------------------------------------------------------------------------
-spec is_auth_module_enabled(kz_term:ne_binary(), kz_json:object()) -> boolean().
is_auth_module_enabled(Method, Config) ->
    kz_json:is_true(method_config_path(Method, <<"enabled">>), Config, 'true').

%%------------------------------------------------------------------------------
%% @doc Checks if authenticator module is configured to do multi factor auth.
%% @end
%%------------------------------------------------------------------------------
-spec is_multi_factor_enabled(cb_context:context(),kz_term:proplist(), kz_json:object()) -> boolean().
is_multi_factor_enabled(Context, Claims, AuthConfig) ->
    is_multi_factor_enabled(Context
                           ,kz_term:is_true(cb_context:fetch(Context, 'bypass_multi_factor', 'false'))
                           ,Claims
                           ,AuthConfig
                           ).

-spec is_multi_factor_enabled(cb_context:context(), boolean(),kz_term:proplist(), kz_json:object()) -> boolean().
is_multi_factor_enabled(Context, 'true', Claims, _AuthConfig) ->
    Method = props:get_ne_binary_value(<<"method">>, Claims),
    AuthType = cb_context:fetch(Context, 'auth_type', Method),
    lager:info("auth module ~s with auth type ~s is bypassing multi factor authentication", [Method, AuthType]),
    'false';
is_multi_factor_enabled(_, 'false', Claims, AuthConfig) ->
    MasterId = master_account_id(),
    Method = props:get_ne_binary_value(<<"method">>, Claims),
    ClaimAccountId = props:get_ne_binary_value(<<"account_id">>, Claims),
    MFAAccountId = kz_json:get_ne_binary_value(method_mfa_path(Method, <<"account_id">>), AuthConfig),
    IncludeSubAccounts = kz_json:is_true(method_mfa_path(Method, <<"include_subaccounts">>), AuthConfig),

    kz_json:is_true(method_mfa_path(Method, <<"enabled">>), AuthConfig)
        andalso multi_factor_allowed_for_account(MasterId, ClaimAccountId, MFAAccountId, IncludeSubAccounts).

%%------------------------------------------------------------------------------
%% @doc Checks if multi factor is enabled by looking at system, account and hierarchy.
%% If the configuration comes from a parent account
%% then we should look for property `multi_factor.include_subaccounts'.
%% If it's `false' then authentication should to proceed normally
%% without multi factor.
%%
%% * If account is master, allow
%% * If account is the same as mfa account, allow
%% * If there is no account in mfa, return allow
%% * If account ids are not same, return 'include_subaccounts' boolean
%% @end
%%------------------------------------------------------------------------------
-spec multi_factor_allowed_for_account(kz_term:api_binary(), kz_term:api_binary(), kz_term:api_binary(), boolean()) -> boolean().
multi_factor_allowed_for_account(?NE_BINARY=Master, ?NE_BINARY=Master, _, _) -> 'true';
multi_factor_allowed_for_account(_Master, _ClaimAccountId, 'undefined', _) -> 'true';
multi_factor_allowed_for_account(_Master, AccountId, AccountId, _) -> 'true';
multi_factor_allowed_for_account(_Master, _ClaimAccountId, _ParentAccount, IncludeSubAcc) -> IncludeSubAcc.

-spec master_account_id() -> kz_term:api_ne_binary().
master_account_id() ->
    case kapps_util:get_master_account_id() of
        {'ok', Id} -> Id;
        {'error', _R} ->
            lager:debug("failed to find master account id: ~p", [_R]),
            'undefined'
    end.

%%------------------------------------------------------------------------------
%% @doc Log successful authentication if configured to do so.
%% @end
%%------------------------------------------------------------------------------
-spec log_success_auth(atom() | kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), cb_context:context()) -> 'ok'.
log_success_auth(AuthModule, AuthType, Reason, Context) ->
    log_success_auth(AuthModule, AuthType, Reason, Context, 'undefined', 'undefined').

-spec log_success_auth(atom() | kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), cb_context:context(), kz_term:api_ne_binary()) -> 'ok'.
log_success_auth(AuthModule, AuthType, Reason, Context, AccountId) ->
    log_success_auth(AuthModule, AuthType, Reason, Context, AccountId, 'undefined').

-spec log_success_auth(atom() | kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), cb_context:context(), kz_term:api_ne_binary(), kz_term:api_object()) -> 'ok'.
log_success_auth(AuthModule, AuthType, Reason, Context, 'undefined', AuthConfig) ->
    case cb_context:account_id(Context) of
        'undefined' -> 'ok';
        AccountId -> log_success_auth(AuthModule, AuthType, Reason, Context, AccountId, AuthConfig)
    end;
log_success_auth(AuthModule, AuthType, Reason, Context, AccountId, 'undefined') ->
    log_success_auth(AuthModule, AuthType, Reason, Context, AccountId, get_account_config(AccountId));
log_success_auth(AuthModule, AuthType, Reason, Context, AccountId, AuthConfig) ->
    Method = kz_term:to_binary(AuthModule),
    case is_log_type_enabled(<<"success">>, Method, AuthConfig) of
        'false' -> 'ok';
        'true' ->
            log_attempts(Context, AccountId, Method, <<"success">>, AuthType, Reason)
    end.

%%------------------------------------------------------------------------------
%% @doc Log failed authentication if configured to do so.
%% @end
%%------------------------------------------------------------------------------
-spec log_failed_auth(atom() | kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), cb_context:context()) -> 'ok'.
log_failed_auth(AuthModule, AuthType, Reason, Context) ->
    log_failed_auth(AuthModule, AuthType, Reason, Context, 'undefined', 'undefined').

-spec log_failed_auth(atom() | kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), cb_context:context(), kz_term:api_binary()) -> 'ok'.
log_failed_auth(AuthModule, AuthType, Reason, Context, AccountId) ->
    log_failed_auth(AuthModule, AuthType, Reason, Context, AccountId, 'undefined').

-spec log_failed_auth(atom() | kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), cb_context:context(), kz_term:api_ne_binary(), kz_term:api_object()) -> 'ok'.
log_failed_auth(AuthModule, AuthType, Reason, Context, 'undefined', AuthConfig) ->
    case cb_context:account_id(Context) of
        'undefined' -> 'ok';
        AccountId -> log_failed_auth(AuthModule, AuthType, Reason, Context, AccountId, AuthConfig)
    end;
log_failed_auth(AuthModule, AuthType, Reason, Context, AccountId, 'undefined') ->
    log_failed_auth(AuthModule, AuthType, Reason, Context, AccountId, get_account_config(AccountId));
log_failed_auth(AuthModule, AuthType, Reason, Context, AccountId, AuthConfig) ->
    Method = kz_term:to_binary(AuthModule),
    case is_log_type_enabled(<<"failed">>, Method, AuthConfig) of
        'false' -> 'ok';
        'true' ->
            log_attempts(Context, AccountId, Method, <<"failed">>, AuthType, Reason)
    end.

-spec is_log_type_enabled(kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> boolean().
is_log_type_enabled(<<"failed">>, Method, AuthConfig) ->
    kz_json:is_true(method_config_path(Method, <<"log_failed_attempts">>), AuthConfig);
is_log_type_enabled(<<"success">>, Method, AuthConfig) ->
    kz_json:is_true(method_config_path(Method, <<"log_successful_attempts">>), AuthConfig).

-spec log_attempts(cb_context:context(), kz_term:api_ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
log_attempts(Context, AccountId, Method, Status, AuthType, Reason) ->
    Now = kz_time:now_s(),
    MODB = kzs_util:format_account_mod_id(AccountId, Now),

    LogId = kazoo_modb_util:modb_id(Now),

    Props = [{<<"_id">>, LogId}
            ,{<<"auth_type">>, cb_context:fetch(Context, 'auth_type', AuthType)}
            ,{<<"status">>, Status}
            ,{<<"auth_module">>, Method}
            ,{<<"message">>, Reason}
            ,{<<"client_headers">>, kz_json:from_map(cb_context:req_headers(Context))}
            ,{<<"client_ip">>, cb_context:client_ip(Context)}
            ,{<<"crossbar_request_id">>, cb_context:req_id(Context)}
            ,{<<"timestamp">>, Now}
            ],
    Doc0 = maybe_add_metadata(cb_context:doc(Context), kz_json:from_list(Props)),
    Doc = kz_doc:update_pvt_parameters(Doc0, MODB, [{'type', <<"login_attempt">>}
                                                   ,{'now', Now}
                                                   ]),
    _ = kazoo_modb:save_doc(MODB, maybe_add_metadata(cb_context:doc(Context), Doc)),
    'ok'.

-spec maybe_add_metadata(kz_term:api_object(), kz_json:object()) -> kz_json:object().
maybe_add_metadata(ContextDoc, Doc) ->
    case kz_term:is_empty(ContextDoc) of
        'true' -> Doc;
        'false' -> kz_json:set_value(<<"metadata">>, ContextDoc, Doc)
    end.

%%------------------------------------------------------------------------------
%% @doc fetch or set default scopes for an auth_module
%% @end
%%------------------------------------------------------------------------------
-spec available_scopes(atom() | kz_term:ne_binary()) -> kz_term:ne_binaries().
available_scopes(AuthModule) when is_atom(AuthModule) ->
    available_scopes(kz_term:to_binary(AuthModule));
available_scopes(AuthModule) ->
    kapps_config:get_ne_binaries(?AUTH_CONFIG_CAT, ?AUTH_MODULE_SCOPES_KEY(AuthModule), [?APP_NAME], <<"default">>).

%%------------------------------------------------------------------------------
%% @doc resolve scope restrictions to scopes
%% @end
%%------------------------------------------------------------------------------
-spec scopes(kz_term:ne_binary(), kz_term:ne_binaries() | binary()) -> kz_term:api_binaries().
scopes(_AccountId, []) ->
    [];
scopes(AccountId, ScopeRestrictions) when is_list(ScopeRestrictions) ->
    Fun = fun(R, Acc) ->
                  scopes(AccountId, R) ++ Acc
          end,
    lists:foldl(Fun, [], ScopeRestrictions);
scopes(AccountId, ScopeRestriction) when is_binary(ScopeRestriction) ->
    AccountDb = kzs_util:format_account_db(AccountId),
    case kz_datamgr:open_cache_doc(AccountDb, ScopeRestriction) of
        {'ok', Doc} ->
            kz_json:get_list_value(<<"scopes">>, Doc, []);
        _ -> 'undefined'
    end.

-spec get_renew_config(cb_context:context()) -> kz_json:object().
get_renew_config(Context) ->
    get_account_config(cb_context:auth_account_id(Context)).

-spec is_auth_module_renew_enabled(kz_term:ne_binary(), kz_json:object()) -> boolean().
is_auth_module_renew_enabled(Method, Config) ->
    kz_json:is_true(method_config_path(Method, <<"renew">>), Config, 'false').

-spec is_auth_module_renew_enabled(cb_context:context()) -> boolean().
is_auth_module_renew_enabled(Context) ->
    is_auth_module_renew_enabled(auth_method(Context), get_renew_config(Context)).

auth_method(Context) ->
    kz_json:get_binary_value(<<"method">>, cb_context:auth_doc(Context)).

-spec validate_refresh_token(cb_context:context()) -> cb_context:context().
validate_refresh_token(Context) ->
    validate_refresh_token(Context, auth_method(Context)).

validate_refresh_token(Context, 'undefined') ->
    lager:warning("trying to renew a token without method"),
    crossbar_util:response('error', <<"invalid token for renew">>, 412, Context);
validate_refresh_token(Context, Method) ->
    case is_auth_module_renew_enabled(Context) of
        'true' -> allow_refresh_token(Context);
        'false' -> deny_refresh_token(Context, Method)
    end.

deny_refresh_token(Context, Method) ->
    lager:warning("denying renew for a '~s' token", [Method]),
    crossbar_util:response('error', <<Method/binary, " not allowed to renew">>, 405, Context).

allow_refresh_token(Context) ->
    AuthDoc = cb_context:auth_doc(Context),
    Doc = kz_json:set_value(<<"Claims">>, AuthDoc, kz_json:new()),
    Setters = [{fun cb_context:set_resp_status/2, 'success'}
              ,{fun cb_context:set_doc/2, Doc}
              ],
    cb_context:setters(Context, Setters).

-spec refresh_token(cb_context:context()) -> cb_context:context().
refresh_token(Context) ->
    Setters = [{fun create_auth_token/2, auth_method(Context)}
              ,{fun cb_context:set_resp_data/2, kz_json:new()}
              ],
    cb_context:setters(Context, Setters).

-spec get_auth_account_info(cb_context:context()) -> list().
get_auth_account_info(Context) ->
    ReqData = cb_context:req_data(Context),
    [Value
     || Key <-  [<<"account_id">>
                ,<<"account_name">>
                ,<<"account_realm">>
                ,<<"realm">>
                ,<<"phone_number">>
                ],
        Value <- [kz_json:get_ne_binary_value(Key, ReqData)],
        kz_term:is_not_empty(Value)
    ].

-spec is_account_locked(cb_context:context(), kz_term:ne_binaries()) ->
          {boolean(), cb_context:context()}.
is_account_locked(Context, []) ->
    {'false', Context};
is_account_locked(Context, BucketNames) ->
    case kapps_config:is_true(?AUTH_CONFIG_CAT, <<"lock_account_on_failed_attempts">>, 'false') of
        'true' ->
            case is_account_locked(BucketNames) of
                'true'->
                    Error = kz_json:from_list([{<<"message">>, <<"your account is locked because of too many failed login attempts">>}]),
                    {'true', cb_context:add_system_error(401, <<"account_is_locked">>, Error, Context)};
                'false' ->
                    {'false', Context}
            end;
        'false' ->
            {'false', Context}
    end.

-spec is_account_locked(kz_term:ne_binaries()) -> boolean().
is_account_locked([]) ->
    'false';
is_account_locked([BucketName|BucketNames]) ->
    case kz_buckets:tokens_remaining(?CROSSBAR_AUTH_BUCKET, BucketName) of
        0 -> 'true';
        _Remaining ->
            is_account_locked(BucketNames)
    end.

-spec maybe_lock_account(cb_context:context(), kz_term:ne_binaries(), non_neg_integer()) ->
          cb_context:context().
maybe_lock_account(Context, [], _TokenCost) ->
    Context;
maybe_lock_account(Context, BucketNames, TokenCost) ->
    case kapps_config:is_true(?AUTH_CONFIG_CAT, <<"lock_account_on_failed_attempts">>) of
        'true' ->
            maybe_lock_account_fold(Context, BucketNames, TokenCost);
        _Other ->
            Context
    end.

-spec maybe_lock_account_fold(cb_context:context(), kz_term:ne_binaries(), non_neg_integer()) ->
          cb_context:context().
maybe_lock_account_fold(Context, [], _TokenCost) ->
    Context;
maybe_lock_account_fold(Context, [BucketName|BucketNames], TokenCost) ->
    case kz_buckets:consume_tokens_until(?CROSSBAR_AUTH_BUCKET, BucketName, TokenCost) of
        'true' ->
            maybe_lock_account(Context, BucketNames, TokenCost);
        'false' ->
            Error = kz_json:from_list([{<<"message">>, <<"your account is locked because of too many failed login attempts">>}]),
            cb_context:add_system_error(401, <<"account_is_locked">>, Error, Context)
    end.

-spec find_account_buckets(kz_term:ne_binary()) -> kz_term:ne_binaries().
find_account_buckets(AccountId) ->
    [Key
     || Key <- [AccountId
               ,kzd_accounts:fetch_name(AccountId)
               ,kzd_accounts:fetch_realm(AccountId)
               ],
        kz_term:is_not_empty(Key),
        kz_buckets:exists(?CROSSBAR_AUTH_BUCKET, Key)
    ].

-spec unlock_account(kz_term:ne_binaries()) -> 'ok'.
unlock_account(BucketNames) ->
    _ = [kz_buckets:stop_bucket(?CROSSBAR_AUTH_BUCKET, BucketName)
         || BucketName <- BucketNames
        ],
    'ok'.
