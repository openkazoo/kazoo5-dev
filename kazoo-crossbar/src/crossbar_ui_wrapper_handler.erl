%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2023, 2600Hz
%%% @doc Crossbar route handler for Appex UI wrapper apps.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(crossbar_ui_wrapper_handler).
-behaviour(cowboy_handler).

-export([route_path_match/0]).

%% Cowboy Handler callbacks
-export([init/2
        ,upgrade/4
        ,terminate/3
        ]).

-spec init(cowboy_req:req(), map()) ->
          {'ok', cowboy_req:req(), map()} |
          {?MODULE, cowboy_req:req(), kz_term:proplist()}.
init(Req, HandlerOpts) ->
    lager:info("~s: ~s?~s from ~s"
              ,[cowboy_req:method(Req)
               ,cowboy_req:path(Req)
               ,kz_term:to_binary(cowboy_req:qs(Req))
               ,get_client_ip(Req)
               ]
              ),
    PathInfo = [Token || Token <- cowboy_req:path_info(Req),
                         kz_term:is_ne_binary(Token)
               ],
    case get_app_module(PathInfo) of
        'undefined' ->
            not_found(Req, HandlerOpts);
        {Module, NewPathInfo} ->
            {?MODULE, Req#{path_info => NewPathInfo}, [{'module', Module}]}
    end.

-spec upgrade(cowboy_req:req(), cowboy_middleware:env(), any(), any()) -> {'ok', cowboy_req:req(), cowboy_middleware:env()}.
upgrade(Req, Env, _Handler, HandlerOpts) ->
    Module = props:get_value('module', HandlerOpts),
    NewEnv = maps:put('handler', Module, Env),
    cowboy_rest:upgrade(Req, NewEnv, Module, HandlerOpts).

-spec terminate(any(), cowboy_req:req(), any()) -> 'ok'.
terminate(_Reason, _Req, _State) -> 'ok'.

-spec route_path() -> kz_term:ne_binary().
route_path() ->
    kapps_config:get_ne_binary(<<"appex_client">>, <<"ui_wrapper_route_path">>, <<"ui">>).

-spec route_path_match() -> kz_term:ne_binary().
route_path_match() ->
    Path = string:trim(route_path(), 'both', "/"),
    <<"/", Path/binary, "/[...]">>.

get_app_module([AppName, Path | File]) ->
    try
        Mod = kz_term:to_atom(<<AppName/binary, "_cb_router">>),
        {Mod, kz_module:is_exported(Mod, 'init', 2)}
    of
        {Module, 'true'} ->
            {Module, [Path|File]};
        {_, 'false'} ->
            'undefined'
    catch
        _:_ ->
            'undefined'
    end;
get_app_module(_) ->
    'undefined'.

-spec not_found(cowboy_req:req(), State) -> {'ok', cowboy_req:req(), State}.
not_found(Req, State) ->
    Headers = #{<<"content-type">> => <<"text/plain; charset=UTF-8">>},
    Req1 = cowboy_req:reply(404, Headers, <<"404 Not Found">>, Req),
    {'ok', Req1, State}.

-spec get_client_ip(cowboy_req:req()) -> kz_term:ne_binary().
get_client_ip(Req) ->
    {Peer, _PeerPort} = cowboy_req:peer(Req),
    case cowboy_req:header(<<"x-forwarded-for">>, Req) of
        'undefined' -> <<"ip ", (kz_network_utils:iptuple_to_binary(Peer))/binary>>;
        ForwardIP ->
            <<"x-forward-for ", ForwardIP/binary, " and peer ip ", (kz_network_utils:iptuple_to_binary(Peer))/binary>>
    end.
