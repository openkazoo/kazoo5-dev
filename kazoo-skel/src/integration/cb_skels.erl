%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Skeleton module for Crossbar API endpoints
%%% @author Karl Anderson
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_skels).

-export([init/0
        ,authenticate/1
        ,authorize/1
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,content_types_provided/1
        ,content_types_accepted/1
        ,languages_provided/1
        ,charsets_provided/1
        ,encodings_provided/1
        ,validate/1, validate/2
        ,billing/1
        ,put/1
        ,post/2
        ,patch/2
        ,delete/2
        ,etag/1
        ,expires/1
        ,finish_request/1
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
    Bindings = [{<<"*.authenticate">>, 'authenticate'}
               ,{<<"*.authorize">>, 'authorize'}
               ,{<<"*.allowed_methods.skels">>, 'allowed_methods'}
               ,{<<"*.resource_exists.skels">>, 'resource_exists'}
               ,{<<"*.content_types_provided.skels">>, 'content_types_provided'}
               ,{<<"*.content_types_accepted.skels">>, 'content_types_accepted'}
               ,{<<"*.languages_provided.skels">>, 'languages_provided'}
               ,{<<"*.charsets_provided.skels">>, 'charsets_provided'}
               ,{<<"*.encodings_provided.skels">>, 'encodings_provided'}
               ,{<<"*.validate.skels">>, 'validate'}
               ,{<<"*.billing">>, 'billing'}
               ,{<<"*.execute.get.skels">>, 'get'}
               ,{<<"*.execute.put.skels">>, 'put'}
               ,{<<"*.execute.post.skels">>, 'post'}
               ,{<<"*.execute.patch.skels">>, 'patch'}
               ,{<<"*.execute.delete.skels">>, 'delete'}
               ,{<<"*.etag.skels">>, 'etag'}
               ,{<<"*.expires.skels">>, 'expires'}
               ,{<<"*.finish_request">>, 'finish_request'}
               ],
    cb_modules_util:bind(?MODULE, Bindings),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc Authenticates the incoming request, returning true if the requestor is
%% known, or false if not.
%% @end
%%------------------------------------------------------------------------------
-spec authenticate(cb_context:context()) -> 'false'.
authenticate(_ThingId) -> 'false'.

%%------------------------------------------------------------------------------
%% @doc Authorizes the incoming request, returning true if the requestor is
%% allowed to access the resource, or false if not.
%% @end
%%------------------------------------------------------------------------------
-spec authorize(cb_context:context()) -> 'false'.
authorize(_ThingId) -> 'false'.

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
%% @doc What content-types will the module be using to respond (matched against
%% client's accept header).
%% Of the form `{atom(), [{Type, SubType}]} :: {to_json, [{<<"application">>, <<"json">>}]}'
%% @end
%%------------------------------------------------------------------------------
-spec content_types_provided(cb_context:context()) -> cb_context:context().
content_types_provided(Context) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc What content-types will the module be requiring (matched to the client's
%% Content-Type header.
%% Of the form `{atom(), [{Type, SubType}]} :: {to_json, [{<<"application">>, <<"json">>}]}'
%% @end
%%------------------------------------------------------------------------------
-spec content_types_accepted(cb_context:context()) -> cb_context:context().
content_types_accepted(Context) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc If you provide alternative languages, return a list of languages and optional
%% quality value.
%%
%% e.g.: `[<<"en">>, <<"en-gb;q=0.7">>, <<"da;q=0.5">>]'
%% @end
%%------------------------------------------------------------------------------
-spec languages_provided(cb_context:context()) -> cb_context:context().
languages_provided(Context) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc If you provide alternative charsets, return a list of charsets and optional
%% quality value.
%%  e.g. `[<<"iso-8859-5">>, <<"unicode-1-1;q=0.8">>]'
%% @end
%%------------------------------------------------------------------------------
-spec charsets_provided(cb_context:context()) -> cb_context:context().
charsets_provided(Context) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc If you provide alternative encodings, return a list of encodings and optional
%% quality value.
%% e.g. : `[<<"gzip;q=1.0">>, <<"identity;q=0.5">>, <<"*;q=0">>]'
%% @end
%%------------------------------------------------------------------------------
-spec encodings_provided(cb_context:context()) -> cb_context:context().
encodings_provided(Context) ->
    Context.

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
%% @doc If you handle billing-related calls, this callback will allow you to
%% execute those.
%% @end
%%------------------------------------------------------------------------------
-spec billing(cb_context:context()) -> cb_context:context().
billing(Context) ->
    Context.

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
%% @doc If you want to manipulate the etag header, change it here in the cb_context{}
%% @end
%%------------------------------------------------------------------------------
-spec etag(cb_context:context()) -> cb_context:context().
etag(Context) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc Set the expires header
%% @end
%%------------------------------------------------------------------------------
-spec expires(cb_context:context()) -> cb_context:context().
expires(Context) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc The response has gone out, do some cleanup of your own here.
%% @end
%%------------------------------------------------------------------------------
-spec finish_request(cb_context:context()) -> cb_context:context().
finish_request(Context) ->
    Context.

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
    crossbar_view:load(Context, ?CB_LIST, [{'mapper', fun normalize_view_results/2}]).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec on_successful_validation(cb_context:context(), kz_term:api_ne_binary()) -> cb_context:context().
on_successful_validation(Context, 'undefined') ->
    cb_context:set_doc(Context, kz_doc:set_type(cb_context:doc(Context), kzd_skels:type()));
on_successful_validation(Context, ThingId) ->
    crossbar_doc:load_merge(ThingId, Context, ?TYPE_CHECK_OPTION(kzd_skels:type())).

%%------------------------------------------------------------------------------
%% @doc Normalizes the results of a view.
%%
%% This is a simple normalizer function, for which you can just use this as
%% mapper option:
%%
%% ```
%%     {'mapper', crossbar_view:get_id_fun()}
%% '''
%% @end
%%------------------------------------------------------------------------------
-spec normalize_view_results(kz_json:object(), kz_json:objects()) -> kz_json:objects().
normalize_view_results(JObj, Acc) ->
    [kz_doc:id(JObj)|Acc].
