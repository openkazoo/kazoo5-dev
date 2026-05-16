%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2026, 2600Hz
%%% @doc Capabilityeton module for Crossbar API endpoints implementing basic CRUD
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_capabilities).

-export([init/0
        ,authorize/1
        ,allowed_methods/0
        ,resource_exists/0
        ,validate/1
        ,post/1
        ]).

-include_lib("crossbar/src/crossbar.hrl").

%% There is a master design document in
%% core/kazoo_couch/priv/couchdb/views/account-crossbar_listings.json
%% If you need specific fields exposed in the summary view, find the
%% "by_type_id" view and add a case clause to add the doc's fields to
%% the `defaultValue` object (which is emitted at the end)
-define(CB_LIST, <<"crossbar_listings/by_type_id">>).

%% We define the API endpoint name by the collection name. This
%% module's {COLLECTION} would be "capabilities" while the {RESOURCE}
%% provided would be "capability".
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
    Bindings = [{<<"*.allowed_methods.capabilities">>, 'allowed_methods'}
               ,{<<"*.resource_exists.capabilities">>, 'resource_exists'}
               ,{<<"*.validate.capabilities">>, 'validate'}
               ,{<<"*.execute.post.capabilities">>, 'post'}
               ],
    cb_modules_util:bind(?MODULE, Bindings),
    crossbar_maintenance:update_schema(kzd_capability:schema()).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec authorize(cb_context:context()) -> boolean() | {'stop', cb_context:context()}.
authorize(Context) ->
    authorize_nouns(Context, cb_context:req_nouns(Context)).

authorize_nouns(Context, [{<<"capabilities">>, []}]) ->
    case cb_context:is_superduper_admin(Context) of
        'true' -> 'true';
        'false' -> {'stop', Context}
    end;
authorize_nouns(_Context, _Nouns) -> 'false'.

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_POST].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_capabilities(Context, cb_context:req_verb(Context)).

-spec validate_capabilities(cb_context:context(), http_method()) -> cb_context:context().
validate_capabilities(Context, ?HTTP_GET) ->
    read(Context);
validate_capabilities(Context, ?HTTP_POST) ->
    update(Context).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is POST, execute the actual action, usually a db save
%% (after a merge perhaps).
%% @end
%%------------------------------------------------------------------------------
-spec post(cb_context:context()) -> cb_context:context().
post(Context) ->
    Capabilities = cb_context:doc(Context),
    case kz_entitlements:update_capabilities(Capabilities) of
        {'ok', Entitlements} ->
            crossbar_doc:handle_datamgr_success(kzd_entitlements:capabilities(Entitlements), Context);
        {'error', E} ->
            crossbar_doc:handle_datamgr_errors(E, 'undefined', Context)
    end.

%%------------------------------------------------------------------------------
%% @doc Load an instance from the database
%% @end
%%------------------------------------------------------------------------------
-spec read(cb_context:context()) -> cb_context:context().
read(Context) ->
    read(Context, cb_context:req_nouns(Context)).

-spec read(cb_context:context(), req_nouns()) -> cb_context:context().
read(Context, [{<<"capabilities">>, []}]) ->
    Capabilities = kz_entitlements:capabilities(),
    crossbar_doc:handle_datamgr_success(Capabilities, Context);
read(Context, _Nouns) ->
    AccountId = cb_context:account_id(Context),
    UserId = cb_context:user_id(Context),
    Entitlements = kz_entitlements:entitlements(AccountId, UserId),

    Capabilities = kzd_entitlements:capabilities(Entitlements),
    crossbar_doc:handle_datamgr_success(Capabilities, Context).

%%------------------------------------------------------------------------------
%% @doc Update an existing menu document with the data provided, if it is
%% valid
%% @end
%%------------------------------------------------------------------------------
-spec update(cb_context:context()) -> cb_context:context().
update(Context) ->
    update(Context, cb_context:req_nouns(Context)).

update(Context, [{<<"capabilities">>, []}]) ->
    SystemCapabilities = kz_entitlements:capabilities(),
    ReqCapabilities = cb_context:req_data(Context),
    MergedCapabilities = kz_json:merge_jobjs(SystemCapabilities, kz_doc:public_fields(ReqCapabilities)),
    cb_context:validate_request_data(kzd_capability:schema()
                                    ,cb_context:set_req_data(Context, MergedCapabilities)
                                    ).
