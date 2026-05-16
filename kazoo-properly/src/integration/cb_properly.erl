%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023, 2600Hz
%%% @doc Testing Crossbar API
%%%
%%% The intent with this "testing" API is to have a way to test Crossbar replies.
%%% Allows to check that Crossbar is actually using the given HTTP status code
%%% when replying to requests (some PUT requests only, for now).
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_properly).

-export([init/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,validate/1, validate/2
        ,put/1, put/2
        ]).

-include_lib("crossbar/src/crossbar.hrl").

-define(ALLOWED_PATH_TOKENS, [<<"return_200">>
                             ,<<"return_202">>
                             ,<<"return_400">>
                             ,<<"return_401">>
                             ,<<"return_402">>
                             ,<<"return_404">>
                             ,<<"return_500">>
                             ]).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    Bindings = [{<<"*.allowed_methods.properly">>, 'allowed_methods'}
               ,{<<"*.resource_exists.properly">>, 'resource_exists'}
               ,{<<"*.validate.properly">>, 'validate'}
               ,{<<"*.execute.put.properly">>, 'put'}
               ],
    cb_modules_util:bind(?MODULE, Bindings).

%%------------------------------------------------------------------------------
%% @doc This function determines the verbs that are appropriate for the
%% given Nouns. For example `/accounts/' can only accept `GET' and `PUT'.
%%
%% Failure here returns `405 Method Not Allowed'.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_) ->
    [?HTTP_PUT].

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
    cb_context:set_resp_status(Context, 'success').

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, PathToken) ->
    case lists:member(PathToken, ?ALLOWED_PATH_TOKENS) of
        'true' -> cb_context:set_resp_status(Context, 'success');
        'false' -> cb_context:add_system_error('bad_identifier', Context)
    end.

-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_util:response(kz_json:new(), Context). %% Return 201.

-spec put(cb_context:context(), path_token()) -> cb_context:context().
put(Context, <<"return_200">>) ->
    crossbar_util:response_200(kz_json:from_list([{<<"ok">>, <<"success">>}]), Context);
put(Context, <<"return_202">>) ->
    crossbar_util:response_202(<<"processing">>, Context);
put(Context, <<"return_400">>) ->
    Resp = kz_json:from_list([{<<"bad">>, <<"request">>}]),
    crossbar_util:response_400(<<"invalid request">>, Resp, Context);
put(Context, <<"return_401">>) ->
    crossbar_util:response_401(Context);
put(Context, <<"return_402">>) ->
    crossbar_util:response_402(kz_json:from_list([{<<"payment">>, <<"required">>}]), Context);
put(Context, <<"return_404">>) ->
    crossbar_util:response_bad_identifier(<<"invalid-id">>, Context);
put(Context, <<"return_500">>) ->
    crossbar_util:response('error', <<"something went wrong">>, 500, kz_json:new(), Context).
