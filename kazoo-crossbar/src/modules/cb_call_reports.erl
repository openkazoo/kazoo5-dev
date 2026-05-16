%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2020-, Ooma Inc.
%%% @doc Write call quality/issue reports
%%% @author Daniel Finke
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_call_reports).

-export([init/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,validate/1, validate/2
        ,put/1
        ]).

-include("crossbar.hrl").

-define(ALLOWED_TYPES, <<"allowed_types">>).

-define(SYSTEM_SCHEMA_ID, <<"crossbar.call_reports">>).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.call_reports">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.call_reports">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.call_reports">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.put.call_reports">>, ?MODULE, 'put').

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(?ALLOWED_TYPES) ->
    [?HTTP_GET].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(?ALLOWED_TYPES) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_call_reports(Context, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ?ALLOWED_TYPES) ->
    %% Get list of allowed types
    Context1 = crossbar_util:response(kzd_call_reports:allowed_types(), Context),

    case kapps_config:get_category(?SYSTEM_SCHEMA_ID) of
        {'ok', ConfigDoc} ->
            %% Set cache ETag
            cb_context:set_resp_etag(Context1, crossbar_doc:rev_to_etag(ConfigDoc));
        {'error', _} ->
            Context
    end.

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is PUT, execute the actual action, usually a db save.
%% @end
%%------------------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_doc:save(Context).

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Validate a request to create a new call report.
%% @end
%%------------------------------------------------------------------------------
-spec validate_call_reports(cb_context:context(), http_method()) -> cb_context:context().
validate_call_reports(Context, ?HTTP_PUT) ->
    create(Context).

%%------------------------------------------------------------------------------
%% @doc Create a new instance with the data provided, if it is valid
%% @end
%%------------------------------------------------------------------------------
-spec create(cb_context:context()) -> cb_context:context().
create(Context) ->
    ReqJObj = cb_context:req_data(Context),
    case kzd_call_reports:validate(ReqJObj) of
        {'true', CallReportJObj} ->
            lager:debug("successfully validated call report object"),
            Context1 = cb_context:update_successfully_validated_request(Context, CallReportJObj),
            cb_context:set_db_name(Context1, kazoo_modb:get_modb(cb_context:account_id(Context)));
        {'validation_errors', ValidationErrors} ->
            lager:info("validation errors on call report"),
            cb_context:add_doc_validation_errors(Context, ValidationErrors);
        {'system_error', Error} when is_atom(Error) ->
            lager:info("system error validating call report: ~p", [Error]),
            cb_context:add_system_error(Error, Context);
        {'system_error', {Error, Message}} ->
            lager:info("system error validating call report: ~p, ~p", [Error, Message]),
            cb_context:add_system_error(Error, Message, Context)
    end.
