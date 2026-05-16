%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2013-2023, 2600Hz
%%% @doc Quickroutes - bypass any app processing and go direct to endpoint
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_quickroutes).

-export([init/0
        ,authorize/1
        ,allowed_methods/0
        ,resource_exists/0
        ,validate/1
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
    Bindings = [{<<"*.allowed_methods.quickroutes">>, 'allowed_methods'}
               ,{<<"*.authorize.quickroutes">>, 'authorize'}
               ,{<<"*.resource_exists.quickroutes">>, 'resource_exists'}
               ,{<<"*.validate.quickroutes">>, 'validate'}
               ],
    cb_modules_util:bind(?MODULE, Bindings).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec authorize(cb_context:context()) -> boolean().
authorize(Context) ->
    authorize_nouns(Context, cb_context:req_nouns(Context), cb_context:req_verb(Context)).

-spec authorize_nouns(cb_context:context(), req_nouns(), http_method()) -> boolean().
authorize_nouns(Context
               ,[{<<"quickroutes">>,[]}
                ,{<<"accounts">>, [_AccountId]}
                ]
               ,?HTTP_GET
               ) ->
    cb_context:is_account_admin(Context)
        orelse cb_context:is_superduper_admin(Context);
authorize_nouns(_Context, _Nouns, _Verb) ->
    'false'.

%%------------------------------------------------------------------------------
%% @doc This function determines the verbs that are appropriate for the
%% given Nouns. For example `/accounts/' can only accept `GET' and `PUT'.
%%
%% Failure here returns `405 Method Not Allowed'.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET].

%%------------------------------------------------------------------------------
%% @doc This function determines if the provided list of Nouns are valid.
%% Failure here returns `404 Not Found'.
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

%%------------------------------------------------------------------------------
%% @doc This function determines if the parameters and content are correct
%% for this request
%%
%% Failure here returns 400.
%% @end
%%------------------------------------------------------------------------------

-spec validate(cb_context:context()) ->
          cb_context:context().
validate(Context) ->
    validate_quickroutes(Context, cb_context:req_verb(Context)).

-spec validate_quickroutes(cb_context:context(), http_method()) ->
          cb_context:context().
validate_quickroutes(Context, ?HTTP_GET) ->
    lager:info("getting quickroutes"),
    quickroute_summary(Context).

-spec quickroute_summary(cb_context:context()) -> cb_context:context().
quickroute_summary(Context) ->
    quickroute_result(Context, quickroute_req(Context)).

-type search_result() :: {'ok', kz_json:object()} |
                         {'error', kz_json:object()}.
-spec quickroute_result(cb_context:context(), search_result()) -> cb_context:context().
quickroute_result(Context, {'ok', JObj}) ->
    Routines = [{fun cb_context:set_resp_data/2, JObj}
               ,{fun cb_context:set_resp_status/2, 'success'}
               ],
    cb_context:setters(Context, Routines);
quickroute_result(Context, {'error', Error}) ->
    cb_context:add_system_error('error', Error, Context).

-spec quickroute_req(cb_context:context()) -> search_result().
quickroute_req(Context) ->
    Req = [{<<"Account-ID">>, cb_context:account_id(Context)}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],

    case kz_amqp_worker:call_collect(Req
                                    ,fun kapi_route:publish_query_quickroutes_req/1
                                    ,{'ecallmgr', 'true'}
                                    )
    of
        {'error', _R}=Err -> Err;
        {'ok', JObjs} when is_list(JObjs) -> process_responses(JObjs);
        {'timeout', JObjs} when is_list(JObjs) -> process_responses(JObjs)
    end.

-spec process_responses(kz_json:objects()) -> {'ok', kz_json:object()}.
process_responses(JObjs) ->
    {'ok', extract_quickroutes(JObjs)}.

-spec extract_quickroutes(kz_json:objects()) -> kz_json:object().
extract_quickroutes(JObjs) ->
    lists:foldl(fun extract_quickroute/2, kz_json:new(), JObjs).

extract_quickroute(QuickrouteResp, Acc) ->
    QuickRoutes = kz_json:get_list_value(<<"Quickroutes">>, QuickrouteResp),
    lists:foldl(fun extract_route/2, Acc, QuickRoutes).

extract_route(QuickRoute, Acc) ->
    Number = kz_json:get_ne_binary_value(<<"Number">>, QuickRoute),
    Routes = kz_json:get_list_value(<<"Routes">>, QuickRoute, []),

    kz_json:set_value([Number, <<"endpoints">>]
                     ,[kz_json:get_ne_binary_value(<<"Endpoint-ID">>, Route) || Route <- Routes]
                     ,Acc
                     ).
