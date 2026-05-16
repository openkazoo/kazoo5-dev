%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2025, 2600Hz
%%% @doc Token auth module
%%% This is a simple auth mechanism, once the user has acquired an
%%% auth token this module will allow access.  This module should be
%%% updated to be FAR more robust.
%%%
%%% @author Karl Anderson
%%% @author James Aimonetti
%%% @author Ben Wann
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(bh_token_auth).

-export([init/0
        ,authenticate/2
        ]).

-include("blackhole.hrl").

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = blackhole_bindings:bind(<<"blackhole.authenticate.*">>, ?MODULE, 'authenticate'),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec authenticate(bh_context:context(), kz_json:object()) -> bh_context:context().
authenticate(Context, _Payload) ->
    case bh_context:authorized(Context) of
        'false' ->
            Token = bh_context:auth_token(Context),
            authenticate_token(Context, Token);
        'true' ->
            Context
    end.

-spec authenticate_token(bh_context:context(), kz_term:api_binary()) -> bh_context:context().
authenticate_token(Context, 'undefined') ->
    lager:debug("failed to authenticate with undefined token"),
    bh_context:add_error(Context, <<"authentication token required">>);
authenticate_token(Context, <<Token/binary>>) ->
    lager:debug("trying to authenticate with token: ~s", [Token]),
    case kz_auth:validate_token(Token) of
        {'ok', JObj} ->
            AccountId = kz_json:get_ne_value(<<"account_id">>, JObj),
            lager:info("token auth is valid, authenticating account is ~s", [AccountId]),
            bh_context:set_auth_account_id(Context, AccountId);
        {'error', R} ->
            lager:debug("failed to authenticate token auth, ~p", [R]),
            bh_context:add_error(Context, <<"failed to authenticate token ", Token/binary>>)
    end.
