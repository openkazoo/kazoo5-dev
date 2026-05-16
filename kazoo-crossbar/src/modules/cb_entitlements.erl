%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2026, 2600Hz
%%% @doc Entitlementeton module for Crossbar API endpoints implementing basic CRUD
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_entitlements).

-export([init/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,authorize/1, authorize/2
        ,validate/1, validate/2
        ,post/2
        ]).

-include_lib("crossbar/src/crossbar.hrl").

-define(PATH_ENROLLMENT, <<"enrollment">>).
-define(ENTITLEMENTS, <<"entitlements">>).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    Bindings = [{<<"*.allowed_methods.entitlements">>, 'allowed_methods'}
               ,{<<"*.resource_exists.entitlements">>, 'resource_exists'}
               ,{<<"*.authorize.entitlements">>, 'authorize'}
               ,{<<"*.validate.entitlements">>, 'validate'}
               ,{<<"*.execute.post.entitlements">>, 'post'}
               ],
    cb_modules_util:bind(?MODULE, Bindings),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(?PATH_ENROLLMENT) ->
    [?HTTP_POST];
allowed_methods(_AppId) -> [?HTTP_GET]. % GET applications/lol_ui/entitlements

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% For example:
%%
%% ```
%%    /entitlements => []
%%    /entitlements/foo => [<<"foo">>]
%%    /entitlements/foo/bar => [<<"foo">>, <<"bar">>]
%% '''
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(?PATH_ENROLLMENT) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec authorize(cb_context:context()) -> boolean() | {'stop', cb_context:context()}.
authorize(Context) ->
    case maybe_reroute_applications_app_entitlements(Context) of
        {'true', _AppType} -> cb_applications:maybe_admin(Context);
        'false' -> 'true'
    end.

-spec authorize(cb_context:context(), path_token()) -> boolean().
authorize(_Context, ?PATH_ENROLLMENT) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /entitlements might load a list of entitlement objects
%% /entitlements/123 might load the entitlement object 123
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    case maybe_reroute_applications_app_entitlements(Context) of
        {'true', AppType} ->
            cb_applications:validate(Context, AppType, ?ENTITLEMENTS);
        'false' ->
            get_account_entitlements(Context)
    end.

-spec validate(cb_context:context(), path_token()) ->
          cb_context:context() |
          {'stop', cb_context:context()}.
validate(Context, ?PATH_ENROLLMENT) ->
    CapabilityIds = kz_json:get_list_value(<<"capabilities">>, cb_context:req_data(Context), []),
    ShouldEnroll = kz_json:is_true(<<"enroll">>, cb_context:req_data(Context)),

    %% could be Account or {AuthAccount, Account} when overlaying by a reaseller
    case get_account_id(Context) of
        'undefined' ->
            {'stop', cb_context:add_system_error('forbidden', Context)};
        AccountId ->
            UserId = cb_context:user_id(Context),

            lager:debug("fetching entitlements for account ~s (user ~s if any)", [AccountId, UserId]),
            Entitlements = kz_entitlements:entitlements(AccountId, UserId),

            lager:info("attempting to ~senroll in capabilities: ~s"
                      ,[log_maybe_enroll(ShouldEnroll)
                       ,kz_binary:join(CapabilityIds)
                       ]),
            validate_capabilities(Context, CapabilityIds, ShouldEnroll, kzd_entitlements:capabilities(Entitlements))
    end.

log_maybe_enroll('true') -> "";
log_maybe_enroll('false') -> "un".

validate_capabilities(Context, CapabilityIds, ShouldEnroll, Capabilities) ->
    {Enrollments, _, _} = lists:foldl(fun validate_capability/2
                                     ,{kz_json:new(), ShouldEnroll, Capabilities}
                                     ,CapabilityIds
                                     ),
    crossbar_doc:handle_datamgr_success(Enrollments, Context).

validate_capability(CapabilityId, {Enrollments, ShouldEnroll, Capabilities}) ->
    case kz_json:get_json_value(CapabilityId, Capabilities) of
        'undefined' -> {Enrollments, ShouldEnroll, Capabilities}; % capability ID not available
        Capability ->
            case kzd_capability:enabled(Capability, 'false') of
                'false' -> {Enrollments, ShouldEnroll, Capabilities}; % capability not enabled by parent
                'true' ->
                    lager:info("capability ~s is available and enabled, updatig", [CapabilityId]),
                    {kz_json:set_values([{[CapabilityId, <<"enabled">>], ShouldEnroll}
                                        ,{[CapabilityId, <<"enrolled">>], kz_time:now_s()}
                                        ]
                                       ,Enrollments
                                       )
                    ,ShouldEnroll
                    ,Capabilities
                    }
            end
    end.

-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, ?PATH_ENROLLMENT) ->
    Enrollments = cb_context:doc(Context),

    case kz_entitlements:update_enrollments(Enrollments, get_account_id(Context), cb_context:user_id(Context)) of
        {'ok', Entitlements} ->
            crossbar_doc:handle_datamgr_success(Entitlements, Context);
        {'error', E} ->
            crossbar_doc:handle_datamgr_errors(E, 'undefined', Context)
    end.

%% since client can include "account_id" in request body, we need to
%% check that the auth account can use that ID
-spec get_account_id(cb_context:context()) ->
          'undefined' | %% auth account is trying to access ineligible account
          kz_term:ne_binary() | %% account to calculate entitlements for
          kz_entitlements:overlay_account().
get_account_id(Context) ->
    AuthAccountId = cb_context:auth_account_id(Context),
    DataAccountId = kz_json:get_ne_binary_value(<<"account_id">>, cb_context:req_data(Context)),
    URIAccountId = cb_context:account_id(Context),

    get_account_id(AuthAccountId, DataAccountId, URIAccountId).

%% if request if for auth account
get_account_id(AuthAccountId, 'undefined', AuthAccountId) -> AuthAccountId;
%% if request is for sub-account of auth account
get_account_id(AuthAccountId, 'undefined', URIAccountId) ->
    case cb_simple_authz:is_account_descendant(AuthAccountId, URIAccountId) of
        'true' -> URIAccountId;
        'false' -> 'undefined'
    end;
get_account_id(AuthAccountId, AuthAccountId, AuthAccountId) -> AuthAccountId;

%% if request is for sub-account as an overlay in auth account
%% /v2/accounts/{AUTH_ACCOUNT_ID} {"data":{"account_id":"{DATA_ACCOUNT_ID}",...}}
get_account_id(AuthAccountId, DataAccountId, AuthAccountId) ->
    case cb_simple_authz:is_account_descendant(AuthAccountId, DataAccountId) of
        'false' -> 'undefined';
        'true' ->
            lager:debug("using overlay from ~s for req account ~s", [AuthAccountId, DataAccountId]),
            {AuthAccountId, DataAccountId}
    end;
%% if req data and URI match, auth account is already checked by API server for access to URI accountg
get_account_id(_AuthAccountId, URIAccountId, URIAccountId) ->
    URIAccountId;
get_account_id(AuthAccountId, DataAccountId, URIAccountId) ->
    case cb_simple_authz:is_account_descendant(AuthAccountId, DataAccountId)
        andalso cb_simple_authz:is_account_descendant(AuthAccountId, URIAccountId)
    of
        'false' -> 'undefined';
        'true' ->
            lager:debug("using overlay from ~s for req account ~s", [URIAccountId, DataAccountId]),
            {URIAccountId, DataAccountId}
    end.

-spec get_account_entitlements(cb_context:context()) -> cb_context:context() | {'stop', cb_context:context()}.
get_account_entitlements(Context) ->
    case get_account_id(Context) of
        'undefined' ->
            {'stop', cb_context:add_system_error('forbidden', Context)};
        AccountId ->
            Entitlements = kz_entitlements:entitlements(AccountId
                                                       ,cb_context:user_id(Context)
                                                       ),

            lager:info("entitlements found for acct ~s user: ~s: ~p", [AccountId
                                                                      ,cb_context:user_id(Context)
                                                                      ,Entitlements
                                                                      ]),

            crossbar_doc:handle_json_success(Entitlements, Context, ?HTTP_GET)
    end.

-spec maybe_reroute_applications_app_entitlements(cb_context:context()) ->
          {'true', kz_term:ne_binary()} | 'false'.
maybe_reroute_applications_app_entitlements(Context) ->
    case cb_context:req_nouns(Context) of
        [{?ENTITLEMENTS, []}, {<<"applications">>, [AppType]}, {<<"accounts">>, [_AccountId]}] ->
            {'true', AppType};
        _Other -> 'false'
    end.
