%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Crossbar internationalization API module.
%%%
%%% @author Hesaam Farhang
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_i18n).

-export([init/0
        ,allowed_methods/1
        ,resource_exists/1
        ,validate_resource/2
        ,validate/2
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
    _ = crossbar_bindings:bind(<<"*.allowed_methods.i18n">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.i18n">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.i18n">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.validate_resource.i18n">>, ?MODULE, 'validate_resource'),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_LANGUAGE) ->
    [?HTTP_GET].

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists(path_token()) -> 'true'.
resource_exists(_LANGUAGE) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_resource(cb_context:context(), path_token()) -> cb_context:context().
validate_resource(Context, Language) ->
    cb_context:store(Context, 'i18n_lang', Language).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, Language) ->
    Setters = [{fun cb_context:set_resp_data/2, kz_term:to_lower_binary(Language)}
              ,{fun cb_context:set_resp_status/2, 'success'}
              ],
    cb_context:setters(Context, Setters).
