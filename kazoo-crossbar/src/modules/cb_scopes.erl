%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2026, 2600Hz
%%% @doc Manage system_auth scopes
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_scopes).

-include("crossbar.hrl").
-export([init/0
        ,authorize/1
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,validate/1, validate/2
        ,post/2
        ,put/1
        ,delete/2
        ]).

-define(SCOPES_KEY, <<"scopes">>).
-define(SCHEMA, ?SCOPES_KEY).
-define(PVT_TYPE, <<"scope">>).
-define(SCOPES_CAT, <<"system_auth">>).
-define(SCOPES_LIST, <<"scopes/crossbar_listing">>).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.authorize.scopes">>, ?MODULE, 'authorize'),
    _ = crossbar_bindings:bind(<<"*.allowed_methods.scopes">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.scopes">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.scopes">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.put.scopes">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.delete.scopes">>, ?MODULE, 'delete'),
    crossbar_bindings:bind(<<"*.execute.post.scopes">>, ?MODULE, 'post').

%%------------------------------------------------------------------------------
%% @doc Authorizes the incoming request, returning true if the requestor is
%% allowed to access the resource, or false if not.
%% @end
%%------------------------------------------------------------------------------
-spec authorize(cb_context:context()) -> boolean() | {'stop', cb_context:context()}.
authorize(Context) ->
    case cb_context:is_superduper_admin(Context)
        andalso cb_context:req_nouns(Context)
    of
        [{?SCOPES_KEY, _}] -> 'true';
        'false' ->
            {'stop', cb_context:add_system_error('forbidden', Context)};
        _ ->
            {'stop', cb_context:add_system_error('bad_identifier', Context)}
    end.

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_Scope) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_DELETE].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% For example:
%%
%% ```
%%    /scopes => []
%%    /scopes/foo => [<<"foo">>]
%%    /scopesfoo/bar => [<<"foo">>, <<"bar">>]
%% '''
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_Scope) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /scopes might load a list of skel objects
%% /scopes/123 might load the skel object 123
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_scope(set_to_system_auth_db(Context), cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, Scope) ->
    validate_scope(set_to_system_auth_db(Context), Scope, cb_context:req_verb(Context)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_scope(cb_context:context(), http_method()) -> cb_context:context().
validate_scope(Context, ?HTTP_GET) ->
    scope_summary(Context);
validate_scope(Context, ?HTTP_PUT) ->
    validate_request(Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_scope(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_scope(Context, Scope, ?HTTP_DELETE) ->
    crossbar_doc:load(Scope, Context, ?TYPE_CHECK_OPTION(?PVT_TYPE));
validate_scope(Context, Scope, ?HTTP_GET) ->
    scope_summary(Context, Scope);
validate_scope(Context, Scope, ?HTTP_POST) ->
    validate_request(Context, Scope).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_request(cb_context:context()) -> cb_context:context().
validate_request(Context) ->
    validate_request(Context, 'undefined').

-spec validate_request(cb_context:context(), api_path_token()) -> cb_context:context().
validate_request(Context, Scope) ->
    OnSuccess = fun(C) -> on_successful_validation(C, Scope) end,
    cb_context:validate_request_data(?SCHEMA, Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec on_successful_validation(cb_context:context(), path_token()) -> cb_context:context().
on_successful_validation(Context, 'undefined') ->
    cb_context:set_doc(Context, kz_doc:set_type(cb_context:doc(Context), ?PVT_TYPE));
on_successful_validation(Context, Scope) ->
    crossbar_doc:load_merge(Scope, Context, ?TYPE_CHECK_OPTION(?PVT_TYPE)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, _Scope) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_doc:save(Context).

-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _) ->
    crossbar_doc:delete(Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec set_to_system_auth_db(cb_context:context()) -> cb_context:context().
set_to_system_auth_db(Context) ->
    cb_context:setters(Context
                      ,[{fun cb_context:set_db_name/2, ?SCOPES_CAT}
                       ,{fun cb_context:set_account_id/2, cb_context:auth_account_id(Context)}
                       ]).

%%------------------------------------------------------------------------------
%% @doc returns summary of system scope(s)
%% @end
%%------------------------------------------------------------------------------
-spec scope_summary(cb_context:context()) -> cb_context:context().
scope_summary(Context) ->
    scope_summary(Context, 'undefined').

-spec scope_summary(cb_context:context(), path_token() | 'undefined') -> cb_context:context().
scope_summary(Context, Scope) ->
    Options = props:filter_undefined(
                [{'databases', [?SCOPES_CAT]}
                ,{'key', Scope}
                ,{'mapper', crossbar_view:get_doc_fun()}
                ,{'should_paginate', 'false'}
                ,{'unchunkable', 'true'}
                ,'include_docs'
                ]),
    crossbar_view:load(Context, ?SCOPES_LIST, Options).
