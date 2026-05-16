%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2026, 2600Hz
%%% @doc User auth module
%%% @author Karl Anderson
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_user_auth).

-export([init/0
        ,available_scopes/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,authorize/1, authorize/2
        ,authenticate/1, authenticate/2
        ,validate/1, validate/2
        ,put/1, put/2
        ,post/2
        ,find_account/2
        ,find_user_by_hash/1
        ]).

-include("crossbar.hrl").

-define(LIST_BY_USERNAME, <<"users/list_by_username">>).
-define(ACCT_MD5_LIST, <<"users/creds_by_md5">>).
-define(ACCT_SHA1_LIST, <<"users/creds_by_sha">>).
-define(USER_AUTH_TOKENS, kapps_config:get_integer(?CONFIG_CAT, <<"user_auth_tokens">>, 35)).
-define(RESET_ID_EXPIRY, kapps_config:get_integer(?CONFIG_CAT, <<"reset_id_expiry_s">>, ?SECONDS_IN_HOUR)).

-define(SWITCH_USER, <<"impersonate_user">>).
-define(RECOVERY, <<"recovery">>).
-define(RESET_ID, <<"reset_id">>).
-define(RESET_ID_SIZE_DEFAULT, 137).
-define(RESET_PVT_TYPE, <<"password_reset">>).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.authenticate.user_auth">>, ?MODULE, 'authenticate'),
    _ = crossbar_bindings:bind(<<"*.authorize.user_auth">>, ?MODULE, 'authorize'),
    _ = crossbar_bindings:bind(<<"*.allowed_methods.user_auth">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.user_auth">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.user_auth">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.put.user_auth">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.user_auth">>, ?MODULE, 'post'),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc emit valid available scopes for this module
%% @end
%%------------------------------------------------------------------------------
-spec available_scopes() -> kz_term:ne_binaries().
available_scopes() ->
    kz_auth_scope:available_scopes(?APP).

%%------------------------------------------------------------------------------
%% @doc This function determines the verbs that are appropriate for the
%% given Nouns. For example `/accounts/' can only accept `GET' and `PUT'.
%%
%% Failure here returns `405 Method Not Allowed'.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() -> [?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(?RECOVERY) -> [?HTTP_PUT, ?HTTP_POST];
allowed_methods(_AuthToken) -> [?HTTP_GET].

%%------------------------------------------------------------------------------
%% @doc This function determines if the provided list of Nouns are valid.
%% Failure here returns `404 Not Found'.
%% @end
%%------------------------------------------------------------------------------

-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> boolean().
resource_exists(?RECOVERY) -> 'true';
resource_exists(_AuthToken) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec authorize(cb_context:context()) -> boolean() | {'stop', cb_context:context()}.
authorize(Context) ->
    authorize_nouns(Context, cb_context:req_nouns(Context), cb_context:req_verb(Context)).

-spec authorize(cb_context:context(), path_token()) -> boolean() | {'stop', cb_context:context()}.
authorize(Context, _) ->
    authorize_nouns(Context, cb_context:req_nouns(Context), cb_context:req_verb(Context)).

-spec authorize_nouns(cb_context:context(), req_nouns(), req_verb()) -> boolean() | {'stop', cb_context:context()}.
authorize_nouns(Context
               ,[{<<"user_auth">>, []}
                ,{<<"users">>, [RequestUserId]}
                ,{<<"accounts">>, [RequestAccountId]}
                ]
               ,?HTTP_PUT
               ) ->
    maybe_authorize_impersonation(Context, RequestAccountId, RequestUserId, cb_context:auth_account_id(Context));
authorize_nouns(_Context, [{<<"user_auth">>, [?RECOVERY]}], Method) when Method =:= ?HTTP_POST;
                                                                         Method =:= ?HTTP_PUT ->
    %% allow recovery
    lager:debug("authorizing request"),
    'true';
authorize_nouns(Context, [{<<"user_auth">>, []}], ?HTTP_PUT) ->
    case cb_context:req_value(Context, <<"action">>) of
        'undefined' ->
            %% allow user auth
            lager:debug("authorizing request"),
            'true';
        ?SWITCH_USER ->
            %% do not allow if no user/account is set
            lager:error("not authorizing user impersonation when no user or account are provided"),
            {'stop', cb_context:add_system_error('forbidden', Context)};
        _ ->
            %% disallow other actions
            'false'
    end;
authorize_nouns(_, [{<<"user_auth">>, [_AuthToken]}], ?HTTP_GET) ->
    lager:debug("authorizing request"),
    'true';
authorize_nouns(_, _Nouns, _) -> 'false'.

maybe_authorize_impersonation(Context, _RequestAccountId, _RequestUserId, 'undefined') ->
    lager:info("no auth account on auth token"),
    forbidden(Context);
maybe_authorize_impersonation(Context, RequestAccountId, RequestUserId, RequestAccountId) ->
    {'ok', RootAccountId} = kapps_util:get_master_account_id(),
    Method = kz_json:get_ne_binary_value(<<"method">>, cb_context:auth_doc(Context)),
    case
        (RootAccountId =:= RequestAccountId)
        andalso (Method =:= <<"cb_api_auth">>)
    of
        'false' ->
            lager:info("auth token's account id matches request's account id ~s, not allowed", [RequestAccountId]),
            forbidden(Context);
        'true' ->
            lager:info("auth token's account id matches root account id ~s, auth method ~s", [RequestAccountId, Method]),
            maybe_authorize_impersonation(Context, RequestAccountId, RequestUserId, RequestAccountId, cb_context:auth_user_id(Context))
    end;
maybe_authorize_impersonation(Context, RequestAccountId, RequestUserId, AuthAccountId) ->
    case cb_context:is_superduper_admin(Context) of
        'false' ->
            lager:info("auth account id ~s is not superduper", [AuthAccountId]),
            forbidden(Context);
        'true' ->
            maybe_authorize_impersonation(Context, RequestAccountId, RequestUserId, AuthAccountId, cb_context:auth_user_id(Context))
    end.

maybe_authorize_impersonation(Context, RequestAccountId, RequestUserId, AuthAccountId, 'undefined') ->
    maybe_authorize_impersonation_via_api_token(Context, RequestAccountId, RequestUserId, AuthAccountId
                                               ,kz_json:get_value(<<"method">>, cb_context:auth_doc(Context))
                                               );
maybe_authorize_impersonation(Context, RequestAccountId, RequestUserId, AuthAccountId, AuthUserId) ->
    case cb_context:is_account_admin(Context) of
        'true' ->
            lager:debug("authorizing request"),
            'true';
        'false' ->
            lager:error("non-admin user ~s in non super-duper admin account ~s tried to impersonate user ~s in account ~s"
                       ,[AuthUserId, AuthAccountId, RequestUserId, RequestAccountId]
                       ),
            forbidden(Context)
    end.

forbidden(Context) ->
    {'stop', cb_context:add_system_error('forbidden', Context)}.

maybe_authorize_impersonation_via_api_token(_Context, _RequestAccountId, _RequestUserId, _AuthAccountId, <<"cb_api_auth">>) ->
    lager:info("API auth token used, authorizing request"),
    'true';
maybe_authorize_impersonation_via_api_token(Context, _RequestAccountId, _RequestUserId, _AuthAccountId, _Method) ->
    lager:info("no auth user id supplied, and non-API auth token used, not allowing"),
    forbidden(Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec authenticate(cb_context:context()) -> boolean().
authenticate(Context) ->
    authenticate_nouns(cb_context:req_nouns(Context)).

-spec authenticate(cb_context:context(), path_token()) -> boolean().
authenticate(Context, _) ->
    authenticate_nouns(cb_context:req_nouns(Context)).

authenticate_nouns([{<<"user_auth">>, []}]) -> 'true';
authenticate_nouns([{<<"user_auth">>, [?RECOVERY]}]) -> 'true';
authenticate_nouns(_Nouns) -> 'false'.

%%------------------------------------------------------------------------------
%% @doc This function determines if the parameters and content are correct
%% for this request
%%
%% Failure here returns 400.
%% @end
%%------------------------------------------------------------------------------

-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    TokenCost = cb_modules_util:token_cost(Context, ?USER_AUTH_TOKENS),
    case cb_modules_util:consume_tokens_until(Context, TokenCost) of
        {'true', Context1} ->
            maybe_validate_auth_attempts(Context1, TokenCost);
        {'false', Context1} ->
            cb_context:add_system_error('too_many_requests', Context1)
    end.

-spec maybe_validate_auth_attempts(cb_context:context(), non_neg_integer()) -> cb_context:context().
maybe_validate_auth_attempts(Context, TokenCost) ->
    AuthBuckets = crossbar_auth:get_auth_account_info(Context),
    case crossbar_auth:is_account_locked(Context, AuthBuckets) of
        {'true', Context1} ->
            Context1;
        {'false', Context1} ->
            Context2 = validate_action(Context1, cb_context:req_value(Context1, <<"action">>)),
            case cb_context:resp_error_code(Context2) of
                401 ->
                    crossbar_auth:maybe_lock_account(Context2, AuthBuckets, TokenCost);
                _ ->
                    Context2
            end
    end.

-spec validate_action(cb_context:context(), kz_term:api_ne_binary()) -> cb_context:context().
validate_action(Context, 'undefined') ->
    cb_context:validate_request_data(<<"user_auth">>, Context, fun maybe_authenticate_user/1);
validate_action(Context, ?SWITCH_USER) ->
    {'ok', _, TokenClaims} = kz_auth_jwt:decode(cb_context:auth_token(Context)),
    ShouldCheck = should_check_originating_proxy(props:get_is_true(<<"should_check_originating_proxy">>, TokenClaims)
                                                ,kz_term:is_true(cb_context:req_value(Context, <<"should_check_originating_proxy">>))
                                                ),
    ClaimsProp = props:filter_undefined([{<<"original_account_id">>, cb_context:auth_account_id(Context)}
                                        ,{<<"original_owner_id">>, cb_context:auth_user_id(Context)}
                                        ,{<<"owner_id">>, cb_context:user_id(Context)}
                                        ,{<<"account_id">>, cb_context:account_id(Context)}
                                        ,{<<"should_check_originating_proxy">>, ShouldCheck}
                                        ]),
    Claims = kz_json:from_list(
               [{<<"account_id">>, cb_context:account_id(Context)}
               ,{<<"owner_id">>, cb_context:user_id(Context)}
               ,{<<"Claims">>, kz_json:from_list(ClaimsProp)}
               ]
              ),
    Setters = [{fun cb_context:set_resp_status/2, 'success'}
              ,{fun cb_context:store/3, 'auth_type', ?SWITCH_USER}
              ,{fun cb_context:store/3, 'bypass_multi_factor', 'true'}
              ,{fun cb_context:set_doc/2, Claims}
              ],
    Context1 = cb_context:setters(Context, Setters),
    lager:info("user ~s from account ~s is impersonating user ~s from account ~s"
              ,[cb_context:auth_user_id(Context), cb_context:auth_account_id(Context)
               ,cb_context:user_id(Context), cb_context:account_id(Context)
               ]
              ),
    maybe_account_is_expired(Context1, cb_context:account_id(Context));
validate_action(Context, _Action) ->
    lager:debug("unknown action ~s", [_Action]),
    cb_context:add_system_error(<<"action required">>, Context).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ?RECOVERY) ->
    TokenCost = cb_modules_util:token_cost(Context, ?USER_AUTH_TOKENS),
    case cb_modules_util:consume_tokens_until(Context, TokenCost) of
        {'true', Context1} ->
            validate_recovery(Context1);
        {'false', Context1} ->
            cb_context:add_system_error('too_many_requests', Context1)
    end;
validate(Context, AuthToken) ->
    Context1 = cb_context:set_db_name(Context, ?KZ_TOKEN_DB),
    maybe_get_auth_token(Context1, AuthToken).

-spec validate_recovery(cb_context:context()) -> cb_context:context().
validate_recovery(Context) ->
    case cb_context:req_verb(Context) of
        ?HTTP_PUT ->
            Schema = <<"user_auth_recovery">>,
            OnSuccess = fun find_user_for_password_recovery/1,
            cb_context:validate_request_data(Schema, Context, OnSuccess);
        ?HTTP_POST ->
            Schema = <<"user_auth_recovery_reset">>,
            OnSuccess = fun maybe_load_user_doc_via_reset_id/1,
            cb_context:validate_request_data(Schema, Context, OnSuccess)
    end.

-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_auth:create_auth_token(maybe_include_claims(Context), ?MODULE).

-spec put(cb_context:context(), path_token()) -> cb_context:context().
put(Context, ?RECOVERY) ->
    maybe_do_recovery(Context).

maybe_do_recovery(Context) ->
    _ = cb_context:put_reqid(Context),
    maybe_do_recovery(Context, cb_context:db_name(Context)).

maybe_do_recovery(Context, 'undefined') ->
    lager:debug("failed to find account and/or user for password recovery, pretending success result to avoid account crawling attack"),
    Msg = <<"Password resend email was sent, please check your email to learn how to reset your password.">>,
    crossbar_util:response(Msg, Context);
maybe_do_recovery(Context, DB) ->
    MODB = kazoo_modb:get_modb(DB),
    save_reset_id_then_send_email(Context, MODB).

-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, ?RECOVERY) ->
    UserDoc = crossbar_doc:update_pvt_parameters(cb_context:doc(Context), Context),
    case kz_datamgr:save_doc(cb_context:account_id(Context), UserDoc) of
        {'ok', NewDoc} ->
            DocForCreation =
                kz_json:from_list(
                  [{<<"account_id">>, cb_context:account_id(Context)}
                  ,{<<"owner_id">>, kz_doc:id(NewDoc)}
                  ]),
            Context1 = crossbar_doc:handle_datamgr_success(NewDoc, Context),
            Setters = [{fun cb_context:set_doc/2, DocForCreation}
                      ,{fun cb_context:store/3, 'bypass_multi_factor', 'true'}
                      ],
            crossbar_auth:create_auth_token(cb_context:setters(Context1, Setters), ?MODULE);
        {'error', Reason} ->
            lager:debug("failed to update user doc: ~p", [Reason]),
            crossbar_doc:handle_datamgr_errors(Reason, kz_doc:id(UserDoc), Context)
    end.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc add user defined claims to the token request
%% @end
%%------------------------------------------------------------------------------
-spec maybe_include_claims(cb_context:context()) -> cb_context:context().
maybe_include_claims(Context) ->
    case maybe_fetch_scopes(Context) of
        'undefined' -> Context;
        Scopes when is_list(Scopes) ->
            DocWithClaims =
                kz_json:set_value([<<"Claims">>, <<"scope">>]
                                 ,kz_auth_scope:to_str(Scopes)
                                 ,cb_context:doc(Context)
                                 ),
            cb_context:set_doc(Context, DocWithClaims)
    end.

-spec maybe_fetch_scopes(cb_context:context()) -> kz_term:api_ne_binaries().
maybe_fetch_scopes(Context) ->
    AccountId = kz_json:get_ne_binary_value(<<"account_id">>, cb_context:doc(Context)),
    OwnerId = kz_json:get_ne_binary_value(<<"owner_id">>, cb_context:doc(Context)),
    case kzd_users:fetch(AccountId, OwnerId) of
        {'ok', Doc} ->
            kzd_users:scope_restrictions(Doc);
        _Error -> 'undefined'
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec maybe_get_auth_token(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
maybe_get_auth_token(Context, AuthToken) ->
    case AuthToken =:= cb_context:auth_token(Context) of
        'true' ->
            AuthAccountId = cb_context:auth_account_id(Context),
            AccountId = cb_context:account_id(Context),
            create_auth_resp(Context, AccountId, AuthAccountId);
        'false' -> cb_context:add_system_error('invalid_credentials', Context)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec create_auth_resp(cb_context:context(), kz_term:ne_binary(),  kz_term:ne_binary()) ->
          cb_context:context().
create_auth_resp(Context, AccountId, AccountId) ->
    lager:debug("account ~s is same as auth account", [AccountId]),
    crossbar_util:response(crossbar_util:response_auth(cb_context:auth_doc(Context))
                          ,Context
                          );
create_auth_resp(Context, _AccountId, _AuthAccountId) ->
    lager:debug("forbidding token for account ~s and auth account ~s"
               ,[_AccountId, _AuthAccountId]),
    cb_context:add_system_error('forbidden', Context).

%%------------------------------------------------------------------------------
%% @doc This function determines if the credentials are valid based on the
%% provided hash method
%%
%% Attempt to lookup and compare the user creds in the provided accounts.
%%
%% Failure here returns 401
%% @end
%%------------------------------------------------------------------------------

-spec maybe_authenticate_user(cb_context:context()) -> cb_context:context().
maybe_authenticate_user(Context) ->
    JObj = cb_context:doc(Context),
    Credentials = kzd_user_auth:credentials(JObj),
    Method = kzd_user_auth:method(JObj),

    AccountName = kzd_accounts:normalize_name(kz_json:get_value(<<"account_name">>, JObj)),
    PhoneNumber = kzd_user_auth:phone_number(JObj),
    AccountRealm = kz_json:get_first_defined([<<"account_realm">>, <<"realm">>], JObj),
    AccountId = kz_json:get_value(<<"account_id">>, JObj),

    case find_account([{'phone_number', PhoneNumber}
                      ,{'realm', AccountRealm}
                      ,{'name', AccountName}
                      ,{'id', AccountId}
                      ]
                     ,Context
                     )
    of
        {'error', _} ->
            cb_context:add_system_error('invalid_credentials', Context);
        {'ok', ?NE_BINARY=Account} ->
            maybe_auth_account(Context, Credentials, Method, Account);
        {'ok', Accounts} ->
            maybe_auth_accounts(Context, Credentials, Method, Accounts)
    end.

-spec maybe_authenticate_user(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          cb_context:context().
maybe_authenticate_user(Context, Credentials, <<"md5">>, ?NE_BINARY=Account) ->
    Options = [{'key', Credentials}
              ,{'databases', [kzs_util:format_account_db(Account)]}
              ,{'should_paginate', 'false'}
              ,{'unchunkable', 'true'}
              ],
    Context1 = crossbar_view:load(Context, ?ACCT_MD5_LIST, Options),
    case cb_context:resp_status(Context1) of
        'success' -> load_md5_results(Context1, cb_context:doc(Context1), Account);
        _Status ->
            Reason = <<"md5 credentials do not belong to any user">>,
            lager:debug("~s: ~s: ~p"
                       ,[Reason, _Status, cb_context:doc(Context1)]),
            crossbar_auth:log_failed_auth(?MODULE, <<"credentials">>, Reason, Context, Account),
            cb_context:add_system_error('invalid_credentials', Context1)
    end;
maybe_authenticate_user(Context, Credentials, <<"sha">>, ?NE_BINARY=Account) ->
    Options = [{'key', Credentials}
              ,{'databases', [kzs_util:format_account_db(Account)]}
              ,{'should_paginate', 'false'}
              ,{'unchunkable', 'true'}
              ],
    Context1 = crossbar_view:load(Context, ?ACCT_SHA1_LIST, Options),
    case cb_context:resp_status(Context1) of
        'success' -> load_sha1_results(Context1, cb_context:doc(Context1), Account);
        _Status ->
            Reason = <<"sha credentials do not belong to any user">>,
            lager:debug("~s", [Reason]),
            crossbar_auth:log_failed_auth(?MODULE, <<"credentials">>, Reason, Context, Account),
            cb_context:add_system_error('invalid_credentials', Context)
    end;
maybe_authenticate_user(Context, _Creds, _Method, Account) ->
    Reason = kz_term:to_binary(io_lib:format("invalid creds by method ~s", [_Method])),
    lager:debug("~s", [Reason]),
    crossbar_auth:log_failed_auth(?MODULE, <<"credentials">>, Reason, Context, Account),
    cb_context:add_system_error('invalid_credentials', Context).

-spec maybe_auth_account(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          cb_context:context().
maybe_auth_account(Context, Credentials, Method, Account) ->
    Context1 = maybe_authenticate_user(Context, Credentials, Method, Account),
    case cb_context:resp_status(Context1) of
        'success' ->
            maybe_account_is_expired(Context1, Account);
        _Status -> Context1
    end.

-spec maybe_auth_accounts(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binaries()) ->
          cb_context:context().
maybe_auth_accounts(Context, _, _, []) ->
    lager:debug("no account(s) specified"),
    cb_context:add_system_error('invalid_credentials', Context);
maybe_auth_accounts(Context, Credentials, Method, [Account|Accounts]) ->
    Context1 = maybe_authenticate_user(Context, Credentials, Method, Account),
    case cb_context:resp_status(Context1) of
        'success' ->
            maybe_account_is_expired(Context1, Account);
        _Status ->
            maybe_auth_accounts(Context, Credentials, Method, Accounts)
    end.

-spec maybe_account_is_expired(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
maybe_account_is_expired(Context, Account) ->
    case kzd_accounts:is_expired(Account) of
        'false' -> maybe_account_is_enabled(Context, Account);
        {'true', Expired} ->
            resp_account_expired(Context, Account, Expired)
    end.

resp_account_expired(Context, Account, Expired) ->
    _ = kz_process:spawn(fun crossbar_util:maybe_disable_account/1, [Account]),
    Cause =
        kz_json:from_list(
          [{<<"message">>, <<"account expired">>}
          ,{<<"cause">>, Expired}
          ]
         ),
    Reason = kz_term:to_binary(io_lib:format("account expired: ~p", [Expired])),
    crossbar_auth:log_failed_auth(?MODULE, <<"credentials">>, Reason, Context, Account),
    cb_context:add_validation_error(<<"account">>, <<"expired">>, Cause, Context).

-spec maybe_account_is_enabled(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
maybe_account_is_enabled(Context, Account) ->
    case kzd_accounts:is_enabled(Account) of
        'true' ->
            maybe_authorized_proxy(Context, Account, cb_context:req_value(Context, <<"action">>));
        'false' ->
            Reason = kz_term:to_binary(io_lib:format("account ~p is disabled", [Account])),
            lager:debug("~s", [Reason]),
            crossbar_auth:log_failed_auth(?MODULE, <<"credentials">>, Reason, Context, Account),
            Cause =
                kz_json:from_list(
                  [{<<"message">>, <<"account disabled">>}]
                 ),
            cb_context:add_validation_error(<<"account">>, <<"disabled">>, Cause, Context)
    end.

-spec load_sha1_results(cb_context:context(), kz_json:objects() | kz_json:object(), kz_term:ne_binary())->
          cb_context:context().
load_sha1_results(Context, [JObj], Account)->
    lager:debug("found SHA1 credentials belong to user ~s", [kz_doc:id(JObj)]),
    maybe_from_allowed_proxy(Context, JObj, Account);
load_sha1_results(Context, [JObj|_], Account)->
    lager:debug("found more that one user with SHA1 creds, using ~s", [kz_doc:id(JObj)]),
    maybe_from_allowed_proxy(Context, JObj, Account);
load_sha1_results(Context, [], Account)->
    Reason = io_lib:format("failed to find a user with SHA1 creds, request from IP address: ~s", [cb_context:client_ip(Context)]),
    lager:warning("~s", [Reason]),
    crossbar_auth:log_failed_auth(?MODULE, <<"credentials">>, kz_term:to_binary(Reason), Context, Account),
    cb_context:add_system_error('invalid_credentials', Context).

-spec load_md5_results(cb_context:context(), kz_json:objects() | kz_json:object(), kz_term:ne_binary()) ->
          cb_context:context().
load_md5_results(Context, [JObj], Account) ->
    lager:debug("found MD5 credentials belong to user ~s", [kz_doc:id(JObj)]),
    maybe_from_allowed_proxy(Context, JObj, Account);
load_md5_results(Context, [JObj|_], Account) ->
    lager:debug("found more that one user with MD5 creds, using ~s", [kz_doc:id(JObj)]),
    maybe_from_allowed_proxy(Context, JObj, Account);
load_md5_results(Context, [], Account) ->
    Reason = io_lib:format("failed to find a user with MD5 creds, request from IP address: ~s", [cb_context:client_ip(Context)]),
    lager:warning("~s", [Reason]),
    crossbar_auth:log_failed_auth(?MODULE, <<"credentials">>, kz_term:to_binary(Reason), Context, Account),
    cb_context:add_system_error('invalid_credentials', Context).

-spec maybe_from_allowed_proxy(cb_context:context(), kz_json:object(), kz_term:api_binary()) -> cb_context:context().
maybe_from_allowed_proxy(Context, JObj, Account) ->
    AllowedProxies = kzd_users:allowed_proxy_ips(kzs_util:format_account_id(Account), kz_doc:id(JObj)),
    ProxyIPs = cb_context:proxy_ips(Context),
    case maybe_proxy_auth(ProxyIPs, AllowedProxies) of
        'true' -> set_credentials_doc(Context, kz_json:get_value(<<"value">>, JObj), AllowedProxies);
        'false' ->
            lager:info("user doc proxies ~p are not on allowed proxy list ~p", [ProxyIPs, AllowedProxies]),
            cb_context:add_system_error('forbidden', Context)
    end.

-spec maybe_authorized_proxy(cb_context:context(), kz_term:ne_binary(), kz_json:api_json_term()) -> cb_context:context().
maybe_authorized_proxy(Context, _, ?SWITCH_USER) -> Context;
maybe_authorized_proxy(Context, Account, _) ->
    AllowedProxies = kzd_accounts:allowed_proxy_ips(Account),
    ProxyIPs = cb_context:proxy_ips(Context),
    case maybe_proxy_auth(ProxyIPs, AllowedProxies) of
        'true' -> maybe_update_claims(Context, AllowedProxies);
        'false' ->
            lager:info("account doc proxies ~p are not on allowed proxy list ~p", [ProxyIPs, AllowedProxies]),
            cb_context:add_system_error('forbidden', Context)
    end.

maybe_proxy_auth(_, []) -> 'true';
maybe_proxy_auth(ProxyIPs, AllowedProxies) ->
    kz_term:list_contains(ProxyIPs, AllowedProxies).

-spec set_credentials_doc(cb_context:context(), kz_json:object(), kz_term:api_list()) -> cb_context:context().
set_credentials_doc(Context, JObj, AllowedProxies) ->
    lager:info("set creds for ~p", [JObj]),
    Ctx = cb_context:store(Context, 'auth_type', <<"credentials">>),
    cb_context:set_doc(Ctx, kz_json:set_value(<<"Claims">>, base_claims(JObj, AllowedProxies), JObj)).

base_claims(JObj, []) ->
    Keys = [<<"account_id">>, <<"owner_id">>],
    kz_json:filter(fun({K, _V}) -> lists:member(K, Keys) end, JObj);
base_claims(JObj, _AllowedProxies) ->
    Keys = [<<"account_id">>, <<"owner_id">>],
    JObj1 = kz_json:filter(fun({K, _V}) -> lists:member(K, Keys) end, JObj),
    kz_json:set_value(<<"should_check_originating_proxy">>, <<"true">>, JObj1).

maybe_update_claims(Context, []) ->
    Context;
maybe_update_claims(Context, _AllowedProxies) ->
    Claims = kz_json:get_value(<<"Claims">>, cb_context:doc(Context)),
    case kz_json:get_value(<<"should_check_originating_proxy">>, Claims, 'undefined') of
        'undefined' ->
            NewClaims = kz_json:set_value(<<"should_check_originating_proxy">>, <<"true">>, Claims),
            cb_context:set_doc(Context, kz_json:set_value(<<"Claims">>, NewClaims, cb_context:doc(Context)));
        _ -> Context
    end.

-spec find_user_for_password_recovery(cb_context:context()) -> cb_context:context().
find_user_for_password_recovery(Context) ->
    JObj = cb_context:doc(Context),
    Options = [{'phone_number', kzd_user_auth:phone_number(JObj)}
              ,{'realm', kz_json:get_first_defined([<<"account_realm">>, <<"realm">>], JObj)}
              ,{'name', kzd_accounts:normalize_name(kz_json:get_value(<<"account_name">>, JObj))}
              ,{'id',  kz_json:get_ne_binary_value(<<"account_id">>, JObj)}
              ],
    case find_account(Options ,Context) of
        {'error', _Context1} ->
            lager:debug("failed to find account, responding empty result for password recovery"),
            crossbar_doc:handle_json_success(kz_json:new(), Context);
        {'ok', [Account|_]} -> maybe_load_user_doc_by_username(Account, Context);
        {'ok', Account} ->     maybe_load_user_doc_by_username(Account, Context)
    end.

-spec maybe_load_user_doc_by_username(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
maybe_load_user_doc_by_username(Account, Context) ->
    JObj = cb_context:doc(Context),
    AccountDb = kzs_util:format_account_db(Account),
    lager:debug("attempting to lookup user name in db: ~s", [AccountDb]),
    AuthType = <<"user_auth_recovery">>,
    Username = kz_json:get_value(<<"username">>, JObj),
    ViewOptions = [{'key', Username}
                  ,'include_docs'
                  ],
    case kz_datamgr:get_results(AccountDb, ?LIST_BY_USERNAME, ViewOptions) of
        {'ok', [User]} ->
            case kz_json:is_false([<<"doc">>, <<"enabled">>], JObj) of
                'false' ->
                    lager:debug("user name '~s' was found and is not disabled, continue", [Username]),
                    Doc = kz_json:get_value(<<"doc">>, User),
                    cb_context:setters(Context, [{fun cb_context:set_db_name/2, Account}
                                                ,{fun cb_context:set_doc/2, Doc}
                                                ,{fun cb_context:set_resp_status/2, 'success'}
                                                ,{fun cb_context:store/3, 'auth_type', AuthType}
                                                ]);
                'true' ->
                    Reason = kz_term:to_binary(io_lib:format("user name '~s' was found but is disabled", [Username])),
                    lager:debug("~s", [Reason]),
                    crossbar_auth:log_failed_auth(?MODULE, AuthType, Reason, Context, Account),
                    Msg =
                        kz_json:from_list(
                          [{<<"message">>, <<"The provided user name is disabled">>}
                          ,{<<"cause">>, Username}
                          ]),
                    cb_context:add_validation_error(<<"username">>, <<"forbidden">>, Msg, Context)
            end;
        _ ->
            Reason = kz_term:to_binary(io_lib:format("The provided user name ~s was not found", [Username])),
            crossbar_auth:log_failed_auth(?MODULE, AuthType, Reason, Context, Account),
            crossbar_doc:handle_json_success(kz_json:new(), Context)
    end.

-spec save_reset_id_then_send_email(cb_context:context(), kz_term:ne_binary()) ->
          cb_context:context().
save_reset_id_then_send_email(Context, MoDb) ->
    ResetId = reset_id(MoDb),
    UserDoc = cb_context:doc(Context),
    UserId = kz_doc:id(UserDoc),
    %% Not much chance for doc to already exist
    case kazoo_modb:save_doc(MoDb, create_resetid_doc(ResetId, UserId)) of
        {'ok', _} ->
            Email = kzd_users:email(UserDoc),
            lager:debug("created recovery id, sending email to '~s'", [Email]),
            UIURL = kz_json:get_ne_binary_value(<<"ui_url">>, cb_context:req_data(Context)),
            Link = reset_link(UIURL, ResetId),
            lager:debug("created password reset link: ~s", [Link]),
            Notify = [{<<"Email">>, Email}
                     ,{<<"First-Name">>, kzd_users:first_name(UserDoc)}
                     ,{<<"Last-Name">>,  kzd_users:last_name(UserDoc)}
                     ,{<<"Timezone">>, kzd_users:timezone(UserDoc)}
                     ,{<<"User-ID">>, UserId}
                     ,{<<"Password-Reset-Link">>, Link}
                     ,{<<"Account-ID">>, kz_doc:account_id(UserDoc)}
                     ,{<<"Account-DB">>, kz_doc:account_db(UserDoc)}
                     | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
                     ],
            kapps_notify_publisher:cast(Notify, fun kapi_notifications:publish_password_recovery/1),
            Msg = <<"Password resend email was sent, please check your email to learn how to reset your password.">>,
            crossbar_util:response(Msg, Context);
        {'error', Reason} ->
            crossbar_doc:handle_datamgr_errors(Reason, 'undefined', Context)
    end.

-spec maybe_load_user_doc_via_reset_id(cb_context:context()) -> cb_context:context().
maybe_load_user_doc_via_reset_id(Context) ->
    ResetId = kz_json:get_ne_binary_value(?RESET_ID, cb_context:req_data(Context)),
    MoDb = reset_id(ResetId),
    AuthType = <<"user_auth_recovery_reset">>,
    lager:debug("looking up password reset doc: ~s", [ResetId]),
    case kazoo_modb:open_doc(MoDb, ResetId) of
        {'ok', ResetIdDoc} ->
            lager:debug("found password reset doc"),
            AccountId = kzs_util:format_account_id(MoDb),
            Context1 = crossbar_doc:load(kz_json:get_value(<<"pvt_userid">>, ResetIdDoc)
                                        ,cb_context:set_db_name(Context, AccountId)
                                        ,?TYPE_CHECK_OPTION(kzd_users:type())
                                        ),
            maybe_load_user_doc_via_reset_id(Context1
                                            ,AccountId
                                            ,ResetId
                                            ,cb_context:resp_status(Context1)
                                            ,is_resetid_expired(ResetIdDoc)
                                            );
        {'error', _Reason} ->
            lager:debug("failed to find password recovery with reset_id ~s: ~p", [ResetId, _Reason]),
            Reason = <<"The provided reset_id did not resolve to any user">>,
            Msg = kz_json:from_list(
                    [{<<"message">>, Reason}
                    ,{<<"cause">>, ResetId}
                    ]),
            crossbar_auth:log_failed_auth(?MODULE, AuthType, Reason, Context),
            cb_context:add_validation_error(<<"user">>, <<"not_found">>, Msg, Context)
    end.

is_resetid_expired(Doc) ->
    Now = kz_time:now_s(),
    CreateTime = kz_doc:created(Doc, Now),
    0 =:= kz_time:decr_timeout(?RESET_ID_EXPIRY, CreateTime, Now).

maybe_load_user_doc_via_reset_id(Context, _, ResetId, 'success', 'true') ->
    Reason = <<"The provided reset_id is expired">>,
    Msg = kz_json:from_list(
            [{<<"reason">>, Reason}
            ,{<<"cause">>, ResetId}
            ]),
    crossbar_auth:log_failed_auth(?MODULE, <<"user_auth_recovery_reset">>, Reason, Context),
    cb_context:add_system_error('forbidden', Msg, Context);
maybe_load_user_doc_via_reset_id(Context, AccountId, _ResetId, 'success', _) ->
    NewUserDoc = kz_json:set_value(<<"require_password_update">>, 'true', cb_context:doc(Context)),
    cb_context:setters(Context, [{fun cb_context:set_doc/2, NewUserDoc}
                                ,{fun cb_context:store/3, 'auth_type', <<"user_auth_recovery_reset">>}
                                ,{fun cb_context:set_account_id/2, AccountId}
                                ]);
maybe_load_user_doc_via_reset_id(Context, _, ResetId, _, _) ->
    Reason = <<"The provided reset_id did not resolve to any user">>,
    Msg = kz_json:from_list(
            [{<<"message">>, Reason}
            ,{<<"cause">>, ResetId}
            ]),
    crossbar_auth:log_failed_auth(?MODULE, <<"user_auth_recovery_reset">>, Reason, Context),
    cb_context:add_validation_error(<<"user">>, <<"not_found">>, Msg, Context).

-spec reset_id(kz_term:ne_binary()) -> kz_term:ne_binary().
reset_id(?MATCH_MODB_SUFFIX_ENCODED(A, B, Rest, YYYY, MM)) ->
    <<Y1:1/binary, Y2:1/binary, Y3:1/binary, Y4:1/binary>> = YYYY,
    <<M1:1/binary, M2:1/binary>> = MM,
    <<N1:1/binary, N2:1/binary, N3:1/binary, Noise/binary>> = kz_binary:rand_hex((reset_id_size() - (32 + 4 + 2 + 3 + 1)) div 2),

    <<(?MATCH_ACCOUNT_RAW(A, B, Rest))/binary,
      N1/binary, Y1/binary, Y4/binary,
      N2/binary, M2/binary, Y2/binary,
      N3/binary, Y3/binary, M1/binary,
      Noise/binary
    >>;
reset_id(<<AccountId:32/binary,
           _N1:1/binary, Y1:1/binary, Y4:1/binary,
           _N2:1/binary, M2:1/binary, Y2:1/binary,
           _N3:1/binary, Y3:1/binary, M1:1/binary,
           _Noi:8, _se/binary
         >>) ->
    ?MATCH_ACCOUNT_RAW(A, B, Rest) = kz_term:to_lower_binary(AccountId),
    YYYY = <<Y1/binary, Y2/binary, Y3/binary, Y4/binary>>,
    MM = <<M1/binary, M2/binary>>,
    ?MATCH_MODB_SUFFIX_ENCODED(A, B, Rest, YYYY, MM).

-spec reset_link(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
reset_link(UIURL, ResetId) ->
    case binary:match(UIURL, <<$?>>) of
        'nomatch' -> <<UIURL/binary, "?recovery=", ResetId/binary>>;
        _ -> <<UIURL/binary, "&recovery=", ResetId/binary>>
    end.

-spec create_resetid_doc(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_json:object().
create_resetid_doc(ResetId, UserId) ->
    kz_json:from_list(
      [{<<"_id">>, ResetId}
      ,{<<"pvt_userid">>, UserId}
      ,{<<"pvt_created">>, kz_time:now_s()}
      ,{<<"pvt_type">>, ?RESET_PVT_TYPE}
      ]).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-type account_type() :: 'phone_number' | 'name' | 'realm' | 'id'.
-spec find_account([{account_type(), kz_term:api_ne_binary()}], cb_context:context()) ->
          {'ok', kz_term:ne_binary() | kz_term:ne_binaries()} |
          {'error', cb_context:context()}.

find_account([], Context) -> {'error', Context};
find_account([{_Type, 'undefined'} | Types], Context) ->
    find_account(Types, Context);
find_account([{'name', AccountName} | Types], Context) ->
    case kapps_util:get_accounts_by_name(AccountName) of
        {'ok', AccountDb} ->
            lager:debug("found account by name '~s': ~s", [AccountName, AccountDb]),
            {'ok', AccountDb};
        {'multiples', AccountDbs} ->
            lager:debug("the account name returned multiple results"),
            {'ok', AccountDbs};
        {'error', _} ->
            find_account(Types, error_no_account_name(Context, AccountName))
    end;
find_account([{'realm', AccountRealm} | Types], Context) ->
    case kapps_util:get_account_by_realm(AccountRealm) of
        {'ok', _AccountDb}=OK ->
            lager:debug("found account by realm '~s': ~s", [AccountRealm, _AccountDb]),
            OK;
        {'multiples', AccountDbs} ->
            lager:debug("the account realm returned multiple results"),
            {'ok', AccountDbs};
        {'error', _} ->
            find_account(Types, error_no_account_realm(Context, AccountRealm))
    end;
find_account([{'phone_number', PhoneNumber} | Types], Context) ->
    case knm_numbers:lookup_account(PhoneNumber) of
        {'ok', AccountId, _} ->
            AccountDb = kzs_util:format_account_db(AccountId),
            lager:debug("found account by phone number '~s': ~s", [PhoneNumber, AccountDb]),
            {'ok', AccountDb};
        {'error', _} ->
            find_account(Types, error_no_account_phone_number(Context, PhoneNumber))
    end;
find_account([{'id', AccountId} | Types], Context) ->
    case kzd_accounts:fetch(AccountId) of
        {'ok', AccountJObj} ->
            {'ok', kz_doc:account_db(AccountJObj)};
        {'error', 'not_found'} ->
            find_account(Types, error_no_account_id(Context, AccountId))
    end.

-spec error_no_account_phone_number(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
error_no_account_phone_number(Context, PhoneNumber) ->
    Msg =
        kz_json:from_list(
          [{<<"message">>, <<"The provided phone number could not be found">>}
          ,{<<"cause">>, PhoneNumber}
          ]),
    cb_context:add_validation_error(<<"phone_number">>, <<"not_found">>, Msg, Context).

-spec error_no_account_id(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
error_no_account_id(Context, AccountId) ->
    Msg =
        kz_json:from_list(
          [{<<"message">>, <<"The provided account ID could not be found">>}
          ,{<<"cause">>, AccountId}
          ]),
    cb_context:add_validation_error(<<"account_id">>, <<"not_found">>, Msg, Context).

-spec error_no_account_realm(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
error_no_account_realm(Context, AccountRealm) ->
    Msg =
        kz_json:from_list(
          [{<<"message">>, <<"The provided account realm could not be found">>}
          ,{<<"cause">>, AccountRealm}
          ]),
    cb_context:add_validation_error(<<"account_realm">>, <<"not_found">>, Msg, Context).

-spec error_no_account_name(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
error_no_account_name(Context, AccountName) ->
    Msg =
        kz_json:from_list(
          [{<<"message">>, <<"The provided account name could not be found">>}
          ,{<<"cause">>, AccountName}
          ]),
    cb_context:add_validation_error(<<"account_name">>, <<"not_found">>, Msg, Context).

-spec reset_id_size() -> integer().
reset_id_size() ->
    Size = kapps_config:get_integer(?CONFIG_CAT, <<"reset_id_size">>, ?RESET_ID_SIZE_DEFAULT),
    kz_math:clamp(180, 42, Size).

should_check_originating_proxy('true', _) -> <<"true">>;
should_check_originating_proxy(_, 'true') -> <<"true">>;
should_check_originating_proxy(_, _) -> 'undefined'.

-spec find_user_by_hash(cb_context:context()) -> cb_context:context().
find_user_by_hash(Context) ->
    cb_context:validate_request_data(<<"user_auth">>, Context, fun maybe_authenticate_user/1).
