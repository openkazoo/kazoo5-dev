%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Skeleton module for Crossbar API endpoints implementing basic CRUD
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_crud).

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
%% module's {COLLECTION} would be "skels" while the {RESOURCE}
%% provided would be "skel".
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
    Bindings = [{<<"*.allowed_methods.skels">>, 'allowed_methods'}
               ,{<<"*.resource_exists.skels">>, 'resource_exists'}
               ,{<<"*.validate.skels">>, 'validate'}
               ,{<<"*.execute.put.skels">>, 'put'}
               ,{<<"*.execute.post.skels">>, 'post'}
               ,{<<"*.execute.patch.skels">>, 'patch'}
               ,{<<"*.execute.delete.skels">>, 'delete'}
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
allowed_methods(_ThingId) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_PATCH, ?HTTP_DELETE].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% For example:
%%
%% ```
%%    /skels => []
%%    /skels/foo => [<<"foo">>]
%%    /skels/foo/bar => [<<"foo">>, <<"bar">>]
%% '''
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_ThingId) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /skels might load a list of skel objects
%% /skels/123 might load the skel object 123
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_skels(Context, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ThingId) ->
    validate_skel(Context, ThingId, cb_context:req_verb(Context)).

-spec validate_skels(cb_context:context(), http_method()) -> cb_context:context().
validate_skels(Context, ?HTTP_GET) ->
    summary(Context);
validate_skels(Context, ?HTTP_PUT) ->
    create(Context).

-spec validate_skel(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_skel(Context, ThingId, ?HTTP_GET) ->
    read(Context, ThingId);
validate_skel(Context, ThingId, ?HTTP_POST) ->
    update(ThingId, Context);
validate_skel(Context, ThingId, ?HTTP_PATCH) ->
    validate_patch(Context, ThingId);
validate_skel(Context, ThingId, ?HTTP_DELETE) ->
    read(Context, ThingId).

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
post(Context, _ThingId) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is PATCH, execute the actual action, usually a db save
%% (after a merge perhaps).
%% @end
%%------------------------------------------------------------------------------
-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, _ThingId) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is DELETE, execute the actual action, usually a db delete
%% @end
%%------------------------------------------------------------------------------
-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _ThingId) ->
    crossbar_doc:delete(Context).

%%------------------------------------------------------------------------------
%% @doc Create a new instance with the data provided, if it is valid
%% @end
%%------------------------------------------------------------------------------
-spec create(cb_context:context()) -> cb_context:context().
create(Context) ->
    OnSuccess = fun(Ctx) -> on_successful_validation(Ctx, 'undefined') end,
    cb_context:validate_request_data(kzd_skels:schema(), Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc Load an instance from the database
%% @end
%%------------------------------------------------------------------------------
-spec read(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
read(Context, ThingId) ->
    crossbar_doc:load(ThingId, Context, ?TYPE_CHECK_OPTION(kzd_skels:type())).

%%------------------------------------------------------------------------------
%% @doc Update an existing menu document with the data provided, if it is
%% valid
%% @end
%%------------------------------------------------------------------------------
-spec update(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
update(ThingId, Context) ->
    OnSuccess = fun(Ctx) -> on_successful_validation(Ctx, ThingId) end,
    cb_context:validate_request_data(kzd_skels:schema(), Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc Update-merge an existing menu document with the data provided, if it is
%% valid
%% @end
%%------------------------------------------------------------------------------
-spec validate_patch(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
validate_patch(Context, ThingId) ->
    crossbar_doc:patch_and_validate(ThingId, Context, fun update/2).

%%------------------------------------------------------------------------------
%% @doc Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%------------------------------------------------------------------------------
-spec summary(cb_context:context()) -> cb_context:context().
summary(Context) ->
    Selector = [{'start', [{<<"doc_type">>, kzd_skels:type()}]}
               ,{'end', [{<<"doc_type">>, kzd_skels:type()}]}
               ],
    Options = [{'doc_type', kzd_skels:type()}
              ,{'mapper', crossbar_view:get_value_fun()}
              ],
    crossbar_view:find(Context, ?CB_LIST, Selector, Options).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec on_successful_validation(cb_context:context(), kz_term:api_ne_binary()) -> cb_context:context().
on_successful_validation(Context, 'undefined') ->
    cb_context:set_doc(Context, kz_doc:set_type(cb_context:doc(Context), kzd_skels:type()));
on_successful_validation(Context, ThingId) ->
    crossbar_doc:load_merge(ThingId, Context, ?TYPE_CHECK_OPTION(kzd_skels:type())).
