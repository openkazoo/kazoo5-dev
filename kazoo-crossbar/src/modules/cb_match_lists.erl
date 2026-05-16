%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Module for Crossbar API to manage match lists
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_match_lists).

-export([init/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,validate/1, validate/2
        ,put/1
        ,post/2
        ,patch/2
        ,delete/2
        ]).

-include_lib("crossbar/src/crossbar.hrl").

%% There is a master design document in
%% core/kazoo_couch/priv/couchdb/views/account-crossbar_listings.json
%% If you need specific fields exposed in the summary view, find the
%% "by_type_id" view and add a case clause to add the doc's fields to
%% the `defaultValue` object (which is emitted at the end)
-define(CB_LIST, <<"crossbar_listings/by_type_id">>).

%% We define the API endpoint name by the collection name. This
%% module's {COLLECTION} would be "match_lists" while the {RESOURCE}
%% provided would be "match_list".
%%
%% A JSON schema should be added that matches the collection name (so
%% "{COLLECTION}.json" in this case). When `make ci-docs` is run from
%% the KAZOO root, an accessor module in core/kazoo_documents will be
%% created: `kzd_{COLLECTION}.erl`
%%
%% Two functions to add to the kzd module are `schema/0` and `type/0`
%% which return the name of the schema (generally {COLLECTION}) and
%% pvt_type (generally {RESOURCE}).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    Bindings = [{<<"*.allowed_methods.match_lists">>, 'allowed_methods'}
               ,{<<"*.resource_exists.match_lists">>, 'resource_exists'}
               ,{<<"*.validate.match_lists">>, 'validate'}
               ,{<<"*.execute.put.match_lists">>, 'put'}
               ,{<<"*.execute.post.match_lists">>, 'post'}
               ,{<<"*.execute.patch.match_lists">>, 'patch'}
               ,{<<"*.execute.delete.match_lists">>, 'delete'}
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
    [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_MatchListId) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_PATCH, ?HTTP_DELETE].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% For example:
%%
%% ```
%%    /match_lists => []
%%    /match_lists/foo => [<<"foo">>]
%%    /match_lists/foo/bar => [<<"foo">>, <<"bar">>]
%% '''
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_MatchListId) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /match_lists might load a list of match_list objects
%% /match_lists/123 might load the match_list object 123
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_match_lists(Context, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, MatchListId) ->
    validate_match_list(Context, MatchListId, cb_context:req_verb(Context)).

-spec validate_match_lists(cb_context:context(), http_method()) -> cb_context:context().
validate_match_lists(Context, ?HTTP_GET) ->
    summary(Context);
validate_match_lists(Context, ?HTTP_PUT) ->
    create(Context).

-spec validate_match_list(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_match_list(Context, MatchListId, ?HTTP_GET) ->
    read(Context, MatchListId);
validate_match_list(Context, MatchListId, ?HTTP_POST) ->
    update(MatchListId, Context);
validate_match_list(Context, MatchListId, ?HTTP_PATCH) ->
    validate_patch(Context, MatchListId);
validate_match_list(Context, MatchListId, ?HTTP_DELETE) ->
    read(Context, MatchListId).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is PUT, execute the actual action, usually a db save.
%% @end
%%------------------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is POST, execute the actual action, usually a db save
%% (after a merge perhaps).
%% @end
%%------------------------------------------------------------------------------
-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, _MatchListId) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is PATCH, execute the actual action, usually a db save
%% (after a merge perhaps).
%% @end
%%------------------------------------------------------------------------------
-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, _MatchListId) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is DELETE, execute the actual action, usually a db delete
%% @end
%%------------------------------------------------------------------------------
-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _MatchListId) ->
    crossbar_doc:delete(Context).

%%------------------------------------------------------------------------------
%% @doc Create a new instance with the data provided, if it is valid
%% @end
%%------------------------------------------------------------------------------
-spec create(cb_context:context()) -> cb_context:context().
create(Context) ->
    OnSuccess = fun(Ctx) -> on_successful_validation(Ctx, 'undefined') end,
    cb_context:validate_request_data(kzd_match_lists:schema(), Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc Load an instance from the database
%% @end
%%------------------------------------------------------------------------------
-spec read(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
read(Context, MatchListId) ->
    crossbar_doc:load(MatchListId, Context, ?TYPE_CHECK_OPTION(kzd_match_lists:type())).

%%------------------------------------------------------------------------------
%% @doc Update an existing menu document with the data provided, if it is
%% valid
%% @end
%%------------------------------------------------------------------------------
-spec update(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
update(MatchListId, Context) ->
    OnSuccess = fun(Ctx) -> on_successful_validation(Ctx, MatchListId) end,
    cb_context:validate_request_data(kzd_match_lists:schema(), Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc Update-merge an existing menu document with the data provided, if it is
%% valid
%% @end
%%------------------------------------------------------------------------------
-spec validate_patch(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
validate_patch(Context, MatchListId) ->
    crossbar_doc:patch_and_validate(MatchListId, Context, fun update/2).

%%------------------------------------------------------------------------------
%% @doc Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%------------------------------------------------------------------------------
-spec summary(cb_context:context()) -> cb_context:context().
summary(Context) ->
    Selector = [{'start', [{<<"doc_type">>, kzd_match_lists:type()}]}
               ,{'end', [{<<"doc_type">>, kzd_match_lists:type()}]}
               ],
    Options = [{'doc_type', kzd_match_lists:type()}
              ,{'mapper', crossbar_view:get_value_fun()}
              ],
    crossbar_view:find(Context, ?CB_LIST, Selector, Options).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec on_successful_validation(cb_context:context(), kz_term:api_ne_binary()) -> cb_context:context().
on_successful_validation(Context, 'undefined') ->
    cb_context:set_doc(Context, kz_doc:set_type(cb_context:doc(Context), kzd_match_lists:type()));
on_successful_validation(Context, MatchListId) ->
    crossbar_doc:load_merge(MatchListId, Context, ?TYPE_CHECK_OPTION(kzd_match_lists:type())).
