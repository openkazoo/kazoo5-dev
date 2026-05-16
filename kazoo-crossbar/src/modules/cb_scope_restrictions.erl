%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2025, 2600Hz
%%% @doc Manage scope restrictions
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_scope_restrictions).

-include("crossbar.hrl").
-export([init/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,validate/1, validate/2
        ,post/2
        ,put/1
        ,delete/2
        ]).

-define(PVT_TYPE, <<"scope_restriction">>).
-define(SCOPE_RESTRICTIONS_LIST, <<"scope_restrictions/crossbar_listing">>).
-define(SCHEMA, <<"scope_restrictions">>).
%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.scope_restrictions">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.scope_restrictions">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.scope_restrictions">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.put.scope_restrictions">>, ?MODULE, 'put'),
    _ =  crossbar_bindings:bind(<<"*.execute.post.scope_restrictions">>, ?MODULE, 'post'),
    crossbar_bindings:bind(<<"*.execute.delete.scope_restrictions">>, ?MODULE, 'delete').

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_ScopeRestriction) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_DELETE].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% For example:
%%
%% ```
%%    /scope_restictions => []
%%    /scope_restictions/foo => [<<"foo">>]
%%    /scope_restictions/foo/bar => [<<"foo">>, <<"bar">>]
%% '''
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_ScopeRestriction) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /scope_restictions might load a list of skel objects
%% /scope_restictions/123 might load the skel object 123
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_scope_restriction(Context, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ScopeRestriction) ->
    validate_scope_restriction(Context, ScopeRestriction, cb_context:req_verb(Context)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_scope_restriction(cb_context:context(), http_method()) -> cb_context:context().
validate_scope_restriction(Context, ?HTTP_GET) ->
    Options = [{'mapper', crossbar_view:get_doc_fun()}
              ,'include_docs'
              ],
    crossbar_view:load(Context, ?SCOPE_RESTRICTIONS_LIST, Options);
validate_scope_restriction(Context, ?HTTP_PUT) ->
    validate_request(Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_scope_restriction(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_scope_restriction(Context, ScopeRestriction, ?HTTP_DELETE) ->
    crossbar_doc:load(ScopeRestriction, Context, ?TYPE_CHECK_OPTION(?PVT_TYPE));
validate_scope_restriction(Context, ScopeRestriction, ?HTTP_GET) ->
    Options = [{'startkey', ScopeRestriction}
              ,{'endkey', ScopeRestriction}
              ,{'mapper', crossbar_view:get_doc_fun()}
              ,'include_docs'
              ],
    crossbar_view:load(Context, ?SCOPE_RESTRICTIONS_LIST, Options);
validate_scope_restriction(Context, ScopeRestriction, ?HTTP_POST) ->
    validate_request(Context, ScopeRestriction).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_request(cb_context:context()) -> cb_context:context().
validate_request(Context) ->
    validate_request(Context, 'undefined').

-spec validate_request(cb_context:context(), api_path_token()) -> cb_context:context().
validate_request(Context, ScopeRestriction) ->
    OnSuccess = fun(C) -> on_successful_validation(C, ScopeRestriction) end,
    cb_context:validate_request_data(?SCHEMA, Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec on_successful_validation(cb_context:context(), api_path_token()) -> cb_context:context().
on_successful_validation(Context, 'undefined') ->
    JObj = cb_context:doc(Context),
    Doc = kz_json:set_values([{kz_doc:path_type(), ?PVT_TYPE}
                             ,{kz_doc:path_id(), scope_id(kz_doc:id(JObj))}
                             ], JObj),
    cb_context:set_doc(Context, Doc);
on_successful_validation(Context, ScopeRestriction) ->
    crossbar_doc:load_merge(ScopeRestriction, Context, ?TYPE_CHECK_OPTION(?PVT_TYPE)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, _ScopeRestriction) ->
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

-spec scope_id(kz_term:api_ne_binary()) -> kz_term:ne_binary().
scope_id('undefined') ->
    kz_term:to_binary([<<"api:">>, kz_binary:rand_hex(4)]);
scope_id(<<"api:", _/binary>>=Id) ->
    Id;
scope_id(Id) ->
    kz_term:to_binary([<<"api:">>, Id]).
