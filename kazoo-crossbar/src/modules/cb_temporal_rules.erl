%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc
%%% @author Karl Anderson
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_temporal_rules).

-export([init/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,validate/1, validate/2
        ,put/1
        ,post/2
        ,patch/2
        ,delete/2
        ]).

-include("crossbar.hrl").

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    Bindings = [{<<"*.allowed_methods.temporal_rules">>, 'allowed_methods'}
               ,{<<"*.resource_exists.temporal_rules">>, 'resource_exists'}
               ,{<<"*.validate.temporal_rules">>, 'validate'}
               ,{<<"*.execute.put.temporal_rules">>, 'put'}
               ,{<<"*.execute.post.temporal_rules">>, 'post'}
               ,{<<"*.execute.patch.temporal_rules">>, 'patch'}
               ,{<<"*.execute.delete.temporal_rules">>, 'delete'}
               ],
    cb_modules_util:bind(?MODULE, Bindings),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc This function determines the verbs that are appropriate for the
%% given Nouns. For example `/accounts/' can only accept `GET' and `PUT'.
%%
%% Failure here returns `405 Method Not Allowed'.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_TemporalRuleId) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_PATCH, ?HTTP_DELETE].

%%------------------------------------------------------------------------------
%% @doc This function determines if the provided list of Nouns are valid.
%% Failure here returns `404 Not Found'.
%% @end
%%------------------------------------------------------------------------------

-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc This function determines if the parameters and content are correct
%% for this request
%%
%% Failure here returns 400.
%% @end
%%------------------------------------------------------------------------------

-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_rules(Context, cb_context:req_verb(Context)).

validate_rules(Context, ?HTTP_GET) ->
    summary(Context);
validate_rules(Context, ?HTTP_PUT) ->
    create(Context).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, Id) ->
    validate_rule(Context, Id, cb_context:req_verb(Context)).

validate_rule(Context, Id, ?HTTP_GET) ->
    read(Id, Context);
validate_rule(Context, Id, ?HTTP_POST) ->
    update(Id, Context);
validate_rule(Context, Id, ?HTTP_PATCH) ->
    validate_patch(Id, Context);
validate_rule(Context, Id, ?HTTP_DELETE) ->
    read(Id, Context).

-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, _) ->
    crossbar_doc:save(Context).

-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_doc:save(Context).

-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, _) ->
    crossbar_doc:save(Context).

-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _) ->
    crossbar_doc:delete(Context).

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Create a new instance with the data provided, if it is valid
%% @end
%%------------------------------------------------------------------------------
-spec create(cb_context:context()) -> cb_context:context().
create(Context) ->
    OnSuccess = fun(C) -> on_successful_validation('undefined', C) end,
    cb_context:validate_request_data(kzd_temporal_rules:schema(), Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc Load an instance from the database
%% @end
%%------------------------------------------------------------------------------
-spec read(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
read(Id, Context) ->
    Loaded = crossbar_doc:load(Id, Context, ?TYPE_CHECK_OPTION(kzd_temporal_rules:type())),
    maybe_eval_rule(Loaded).

maybe_eval_rule(Context) ->
    maybe_eval_rule(Context, cb_context:req_value(Context, <<"timestamp">>)).

maybe_eval_rule(Context, 'undefined') ->
    Context;
maybe_eval_rule(Context, Timestamp) when is_integer(Timestamp), Timestamp > ?UNIX_EPOCH_IN_GREGORIAN ->
    eval_rule(Context, Timestamp, cb_context:req_value(Context, <<"timezone">>));
maybe_eval_rule(Context, Timestamp) when is_integer(Timestamp) ->
    lager:info("timestamp ~p does not appear to be in Gregorian seconds"),
    cb_context:add_metadata_value(Context, <<"timestamp">>, <<"malformed">>);
maybe_eval_rule(Context, TS) ->
    Timestamp = kz_term:safe_cast(TS, 'undefined', fun kz_term:to_integer/1),
    maybe_eval_rule(Context, Timestamp).

eval_rule(Context, Timestamp, 'undefined') ->
    Timezone = kzd_accounts:timezone(cb_context:account_id(Context)),
    lager:info("using account timezone ~s", [Timezone]),
    eval_rule(Context, Timestamp, Timezone);
eval_rule(Context, Timestamp, Timezone) ->
    lager:info("eval rule at ~p in ~s", [Timestamp, Timezone]),
    RuleDoc = cb_context:doc(Context),

    StartDate = kz_date:from_gregorian_seconds(kzd_temporal_rules:start_date(RuleDoc, Timestamp), Timezone),
    EndDate = maybe_date_from_gregorian_seconds(kzd_temporal_rules:end_date(RuleDoc), Timezone),

    Rule = ktr_rule:new(kz_doc:id(RuleDoc), RuleDoc, StartDate, EndDate),
    case ktr_routes:process(Timestamp, [Rule]) of
        'undefined' ->
            lager:info("rule does not match for this timestamp"),
            cb_context:add_metadata_value(Context, <<"rule_matches">>, 'false');
        _Id ->
            lager:info("rule matches for this timestamp"),
            cb_context:add_metadata_value(Context, <<"rule_matches">>, 'true')
    end.

-spec maybe_date_from_gregorian_seconds(kz_time:gregorian_seconds(), kz_term:ne_binary()) ->
          kz_time:date().
maybe_date_from_gregorian_seconds('undefined', _TZ) -> 'undefined';
maybe_date_from_gregorian_seconds(EndDate, TZ) -> kz_date:from_gregorian_seconds(EndDate, TZ).

%%------------------------------------------------------------------------------
%% @doc Update an existing menu document with the data provided, if it is
%% valid
%% @end
%%------------------------------------------------------------------------------
-spec update(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
update(Id, Context) ->
    OnSuccess = fun(C) -> on_successful_validation(Id, C) end,
    cb_context:validate_request_data(kzd_temporal_rules:schema(), Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc Update-merge an existing menu document partially with the data provided, if it is
%% valid
%% @end
%%------------------------------------------------------------------------------
-spec validate_patch(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
validate_patch(Id, Context) ->
    crossbar_doc:patch_and_validate(Id, Context, fun update/2).

%%------------------------------------------------------------------------------
%% @doc Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%------------------------------------------------------------------------------
-spec summary(cb_context:context()) -> cb_context:context().
summary(Context) ->
    Options = [{'doc_type', kzd_temporal_rules:type()}
              ,{'mapper', crossbar_view:get_value_fun()}
              ],
    Selector = [{'start', [{<<"doc_type">>, kzd_temporal_rules:type()}]}
               ,{'end', [{<<"doc_type">>, kzd_temporal_rules:type()}]}
               ],
    crossbar_view:find(Context, <<"crossbar_listings/by_type_id">>, Selector, Options).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec on_successful_validation(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
on_successful_validation('undefined', Context) ->
    cb_context:set_doc(Context, kz_doc:set_type(cb_context:doc(Context), kzd_temporal_rules:type()));
on_successful_validation(Id, Context) ->
    crossbar_doc:load_merge(Id, Context, ?TYPE_CHECK_OPTION(kzd_temporal_rules:type())).
