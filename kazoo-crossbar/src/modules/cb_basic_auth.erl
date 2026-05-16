%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2024, 2600Hz
%%% @doc Basic auth module
%%% This is a simple auth mechanism, once the user has acquired an
%%% auth token this module will allow access.  This module should be
%%% updated to be FAR more robust.
%%%
%%% @author Karl Anderson
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_basic_auth).

-export([init/0
        ,authenticate/1
        ]).

-include("crossbar.hrl").

-define(DEFAULT_BASIC_AUTH_TYPE, <<"md5">>).
-define(BASIC_AUTH_KEY, <<"basic_auth_type">>).
-define(BASIC_AUTH_TYPE, kapps_config:get_ne_binary(?AUTH_CONFIG_CAT, ?BASIC_AUTH_KEY, ?DEFAULT_BASIC_AUTH_TYPE)).

-define(ACCT_MD5_LIST, <<"users/creds_by_md5">>).
-define(ACCT_SHA1_LIST, <<"users/creds_by_sha">>).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.early_authenticate">>, ?MODULE, 'authenticate'),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

-spec authenticate(cb_context:context()) ->
          'false' |
          {'true' | 'stop', cb_context:context()}.
authenticate(Context) ->
    authenticate(Context, cb_context:auth_token_type(Context)).

-spec authenticate(cb_context:context(), atom()) ->
          'false' |
          {'true' | 'stop', cb_context:context()}.
authenticate(Context, 'basic') ->
    TokenCost = cb_modules_util:token_cost(Context),
    case cb_modules_util:consume_tokens(Context, TokenCost) of
        {'true', Context1} ->
            maybe_validate_auth_attempts(Context1, TokenCost, parse_basic_auth(Context1));
        {'false', Context1} ->
            lager:warning("rate limiting threshold hit for ~s!", [cb_context:client_ip(Context1)]),
            {'stop', cb_context:add_system_error('too_many_requests', Context1)}
    end;
authenticate(_Context, _TokenType) -> 'false'.

-spec maybe_validate_auth_attempts(cb_context:context(), non_neg_integer(), kz_term:ne_binaries()) ->
          'false' |
          {'true' | 'stop', cb_context:context()}.
maybe_validate_auth_attempts(_Context, _TokenCost, []) ->
    'false';
maybe_validate_auth_attempts(Context, TokenCost, [AccountId, Credentials]) ->
    case crossbar_auth:is_account_locked(Context, [AccountId]) of
        {'true', Context1} ->
            {'stop', Context1};
        {'false', Context1} ->
            case check_basic_token(Context1, [AccountId, Credentials]) of
                {'stop', Context2} ->
                    {'stop', crossbar_auth:maybe_lock_account(Context2, [AccountId], TokenCost)};
                'false' ->
                    _ = crossbar_auth:maybe_lock_account(Context1, [AccountId], TokenCost),
                    'false';
                Other -> Other
            end
    end.

-spec check_basic_token(cb_context:context(), kz_term:ne_binaries()) ->
          'false' |
          {'true' | 'stop', cb_context:context()}.
check_basic_token(Context, [AccountId, Credentials]) ->
    AuthToken = cb_context:auth_token(Context),
    case kz_cache:peek_local(?CACHE_NAME, {'basic_auth', AuthToken}) of
        {'ok', JObj} -> is_expired(Context, JObj);
        {'error', 'not_found'} ->
            check_credentials(Context, AccountId, Credentials);
        _ ->
            lager:debug("basic token '~s' check failed", [AuthToken]),
            'false'
    end.

-spec parse_basic_auth(cb_context:context()) -> kz_term:ne_binaries().
parse_basic_auth(Context) ->
    lager:debug("checking basic token: '~s'", [cb_context:auth_token(Context)]),
    case cb_context:auth_token(Context) of
        <<>> -> [];
        'undefined' -> [];
        AuthToken ->
            case binary:split(base64:decode(AuthToken), <<":">>) of
                [_AccountId, _Credentials]=Creds -> Creds;
                _ ->
                    lager:debug("invalid basic auth token"),
                    []
            end
    end.

-spec check_credentials(cb_context:context(), kz_term:ne_binary(), kz_term:api_binary()) ->
          'false' |
          {'true' | 'stop', cb_context:context()}.
check_credentials(Context, AccountId, Credentials) ->
    lager:debug("checking credentials '~s' for account '~s'", [Credentials, AccountId]),
    BasicType = kapps_account_config:get(AccountId, ?AUTH_CONFIG_CAT, ?BASIC_AUTH_KEY, ?BASIC_AUTH_TYPE),
    check_credentials(Context, AccountId, Credentials, BasicType).

-spec check_credentials(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary() | {kz_term:ne_binary(), kz_term:ne_binary()}, kz_term:ne_binary()) ->
          'false' |
          {'true' | 'stop', cb_context:context()}.
check_credentials(Context, AccountId, {Username, Password}, _BasicType) ->
    {MD5, _SHA1} = cb_modules_util:pass_hashes(Username, Password),
    check_credentials(Context, AccountId, MD5, <<"md5">>);
check_credentials(Context, AccountId, Credentials, <<"sha">>) ->
    case get_credential_doc(AccountId, ?ACCT_SHA1_LIST, Credentials) of
        'undefined' -> 'false';
        JObj -> is_expired(Context, JObj)
    end;
check_credentials(Context, AccountId, Credentials, <<"md5">>) ->
    case get_credential_doc(AccountId, ?ACCT_MD5_LIST, Credentials) of
        'undefined' -> 'false';
        JObj -> is_expired(Context, JObj)
    end;
check_credentials(Context, AccountId, Credentials, BasicType) ->
    case binary:split(Credentials, <<":">>) of
        [User, Pass] -> check_credentials(Context, AccountId, {User, Pass}, BasicType);
        _ -> 'false'
    end.

-spec get_credential_doc(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:api_object().
get_credential_doc(AccountId, View, Key) ->
    AccountDb = kzs_util:format_account_db(AccountId),
    Options = [{'key', Key}, 'include_docs'],
    case kz_datamgr:get_results(AccountDb, View, Options) of
        {'ok', [JObj]} -> kz_json:get_value(<<"doc">>, JObj);
        _ -> 'undefined'
    end.

-spec is_expired(cb_context:context(), kz_json:object()) ->
          {'true' | 'stop', cb_context:context()}.
is_expired(Context, JObj) ->
    AccountId = kz_doc:account_id(JObj),
    case kzd_accounts:is_expired(AccountId) of
        'false' ->
            maybe_account_is_enabled(Context, JObj);
        {'true', Expired} ->
            _ = kz_process:spawn(fun crossbar_util:maybe_disable_account/1, [AccountId]),
            Cause =
                kz_json:from_list(
                  [{<<"message">>, <<"account expired">>}
                  ,{<<"cause">>, Expired}
                  ]
                 ),
            Context1 = cb_context:add_validation_error(<<"account">>, <<"expired">>, Cause, Context),
            {'stop', Context1}
    end.

-spec maybe_account_is_enabled(cb_context:context(), kz_json:object()) ->
          {'true' | 'stop', cb_context:context()}.
maybe_account_is_enabled(Context, JObj) ->
    AccountId = kz_doc:account_id(JObj),
    AccountDb = kzs_util:format_account_db(AccountId),
    case kzd_accounts:is_enabled(AccountId) of
        'true' ->
            EndpointId = kz_doc:id(JObj),
            CacheProps = [{'origin', {'db', AccountDb, EndpointId}}],
            AuthToken = cb_context:auth_token(Context),
            kz_cache:store_local(?CACHE_NAME, {'basic_auth', AuthToken}, JObj, CacheProps),
            {'true', set_auth_doc(Context, JObj)};
        'false' ->
            Reason = kz_term:to_binary(io_lib:format("account ~p is disabled", [AccountId])),
            lager:debug("~s", [Reason]),
            crossbar_auth:log_failed_auth(?MODULE, <<"basic_auth">>, Reason, Context, AccountId),
            Cause = kz_json:from_list(
                      [{<<"message">>, <<"account disabled">>}]
                     ),
            {'stop', cb_context:add_validation_error(<<"account">>, <<"disabled">>, Cause, Context)}
    end.

-spec set_auth_doc(cb_context:context(), kz_json:object()) ->
          cb_context:context().
set_auth_doc(Context, JObj) ->
    AuthAccountId = kz_doc:account_id(JObj),
    OwnerId = kz_doc:id(JObj),
    Setters = [{fun cb_context:set_auth_doc/2, auth_doc(JObj)}
              ,{fun cb_context:set_auth_account_id/2, AuthAccountId}
              | maybe_add_is_admins(AuthAccountId, OwnerId)
              ],
    cb_context:setters(Context, Setters).

-spec auth_doc(kz_json:object()) -> kz_json:object().
auth_doc(JObj) ->
    kz_json:from_list(
      [{<<"account_id">>, kz_doc:account_id(JObj)}
      ,{<<"identity_sig">>, kzd_users:signature_secret(JObj)}
      ,{<<"iss">>, <<"kazoo">>}
      ,{<<"method">>, kz_term:to_binary(?MODULE)}
      ,{<<"owner_id">>, kz_doc:id(JObj)}
      ]).

-spec maybe_add_is_admins(kz_term:api_ne_binary(), kz_term:api_ne_binary()) -> cb_context:setters().
maybe_add_is_admins(?NE_BINARY = AuthAccountId, ?NE_BINARY = OwnerId) ->
    [{fun cb_context:set_is_superduper_admin/2, cb_context:is_superduper_admin(AuthAccountId)}
    ,{fun cb_context:set_is_account_admin/2, cb_context:is_account_admin(AuthAccountId, OwnerId)}
    ];
maybe_add_is_admins(?NE_BINARY = AuthAccountId, 'undefined') ->
    [{fun cb_context:set_is_superduper_admin/2, cb_context:is_superduper_admin(AuthAccountId)}];
maybe_add_is_admins(_, _) ->
    [].
