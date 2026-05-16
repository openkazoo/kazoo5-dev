%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2026, 2600Hz
%%% @doc Simple authorization module
%%% Authenticates tokens if they are accessing the parent or
%%% child account only
%%%
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
-module(cb_simple_authz).

-export([init/0
        ,authorize/1
        ,is_account_descendant/1, is_account_descendant/2
        ]).

-include("crossbar.hrl").

-define(SYS_ADMIN_MODS, [<<"acls">>
                        ,<<"rates">>
                        ,<<"sup">>
                        ,<<"scopes">>
                        ]).

%% Endpoints performing their own auth
-define(IGNORE_MODS, kapps_config:get_ne_binaries(?CONFIG_CAT, <<"simple_authz_ignored_modules">>, [])).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.authorize">>, ?MODULE, 'authorize'),
    'ok'.

-spec authorize(cb_context:context()) -> boolean().
authorize(Context) ->
    authorize(Context, cb_context:req_verb(Context), cb_context:req_nouns(Context)).

authorize(Context, Verb, [{?KZ_ACCOUNTS_DB, []}]) ->
    cb_context:is_superduper_admin(Context)
        orelse Verb =:= ?HTTP_PUT;
authorize(Context, Verb, _Nouns) ->
    AuthAccountId = cb_context:auth_account_id(Context),
    IsSysAdmin = cb_context:is_superduper_admin(AuthAccountId),
    case not should_ignore(Context)
        andalso allowed_if_sys_admin_mod(IsSysAdmin, Context)
    of
        'false' ->
            lager:info("the request can not be authorized by this module"),
            'false';
        'true' ->
            do_authorize(Context, Verb)
    end.

do_authorize(Context, Verb) ->
    AuthAccountId = cb_context:auth_account_id(Context),
    IsSysAdmin = cb_context:is_superduper_admin(AuthAccountId),
    case account_is_descendant(IsSysAdmin, Context) of
        'true' ->
            lager:info("authorizing the request"),
            'true';
        'stop' ->
            lager:info("the request is not authorized by this module"),
            {'stop', cb_context:add_system_error('forbidden', Context)};
        'false' ->
            case Verb =:= ?HTTP_GET
                andalso cb_context:magic_pathed(Context)
            of
                'true' ->
                    lager:info("authorizing the request"),
                    'true';
                'false' ->
                    lager:info("the request can not be authorized by this module"),
                    'false'
            end
    end.


-spec should_ignore(cb_context:context()) -> boolean().
should_ignore(Context) ->
    lists:any(fun should_ignore_noun/1, cb_context:req_nouns(Context)).

should_ignore_noun({Noun, _}) ->
    case lists:member(Noun, ?IGNORE_MODS) of
        'true' ->
            lager:info("authorizing, the request module '~s' should be ignored by this module", [Noun]),
            'true';
        'false' -> 'false'
    end.

%%------------------------------------------------------------------------------
%% @doc Returns true if the requested account id is a descendant or the same
%% as the account id that has been authorized to make the request.
%% @end
%%------------------------------------------------------------------------------
-spec account_is_descendant(boolean(), cb_context:context()) -> boolean() | 'stop'.
account_is_descendant('true', _Context) ->
    'true';
account_is_descendant('false', Context) ->
    account_is_descendant('false', Context, cb_context:auth_account_id(Context)).

account_is_descendant('false', _Context, 'undefined') ->
    lager:info("auth account id is undefined, let other modules decide the fate of authorizing this request"),
    'false';
account_is_descendant('false', Context, AuthAccountId) ->
    Nouns = cb_context:req_nouns(Context),
    %% get the accounts/.... component from the URL
    case props:get_value(?KZ_ACCOUNTS_DB, Nouns) of
        [ReqAccountId|_Params] ->
            %% the request that this module process the first element of after 'accounts'
            %% in the URL has to be the requested account id
            case is_account_descendant(AuthAccountId, ReqAccountId) of
                'true' -> 'true';
                'false' -> 'stop'
            end;
        _ ->
            %% if the URL did not have the accounts noun then this module denies access
            lager:info("no account id in request path, let other modules decide the fate of authorizing this request"),
            'false'
    end.

%% @ returns whether the auth account ID is ancestor to the URL
%% account ID (or auth token is for superduper admin)
-spec is_account_descendant(cb_context:context()) -> boolean().
is_account_descendant(Context) ->
    case cb_context:is_superduper_admin(Context) of
        'true' -> 'true';
        'false' ->
            is_account_descendant(cb_context:auth_account_id(Context)
                                 ,cb_context:account_id(Context)
                                 )
    end.

-spec is_account_descendant(kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
is_account_descendant('undefined', _) -> 'false';
is_account_descendant(_, 'undefined') -> 'false';
is_account_descendant(<<AuthAccountId/binary>>, <<AuthAccountId/binary>>) ->
    'true';
is_account_descendant(<<AuthAccountId/binary>>, <<ReqAccountId/binary>>) ->
    %% we will get the requested account definition from accounts using a view
    %% with a complex key (whose alternate value is useful to use on retrieval)
    lager:debug("checking if account ~s is a descendant of ~s", [ReqAccountId, AuthAccountId]),
    Tree = kzd_accounts:tree(ReqAccountId),
    case lists:member(AuthAccountId, Tree) of
        'true' ->
            lager:info("authorizing requested account is a descendant of the auth token"),
            'true';
        'false' ->
            lager:info("not authorizing, requested account is not a descendant of the auth token"),
            'false'
    end.

%%------------------------------------------------------------------------------
%% @doc Returns true the request is not for a system admin module (as defined
%% by the list above) or if it is and the account is a superduper admin.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_if_sys_admin_mod(boolean(), cb_context:context()) -> boolean().
allowed_if_sys_admin_mod(IsSysAdmin, Context) ->
    case is_sys_admin_mod(Context) of
        %% if this is request is not made to a system admin module then this
        %% function doesn't deny it
        'false' ->
            lager:info("authorizing, the request does not contain any system administration modules"),
            'true';
        %% if this request is to a system admin module then check if the
        %% account has the 'pvt_superduper_admin'
        'true' when IsSysAdmin ->
            lager:info("authorizing superduper admin access to system administration module"),
            'true';
        'true' ->
            lager:info("not authorizing, the request contains a system administration module"),
            'false'
    end.

%%------------------------------------------------------------------------------
%% @doc Returns true if the request contains a system admin module.
%% @end
%%------------------------------------------------------------------------------
-spec is_sys_admin_mod(cb_context:context()) -> boolean().
is_sys_admin_mod(Context) ->
    Nouns = cb_context:req_nouns(Context),
    lists:any(fun kz_term:identity/1
             ,[props:get_value(Mod, Nouns) =/= 'undefined' || Mod <- ?SYS_ADMIN_MODS]
             ).
