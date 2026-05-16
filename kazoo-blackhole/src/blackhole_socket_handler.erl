%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2025, 2600Hz
%%% @doc
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(blackhole_socket_handler).

-export([init/2
        ,websocket_init/1
        ,websocket_handle/2
        ,websocket_info/2
        ,terminate/3
        ]).

-include("blackhole.hrl").

-define(IDLE_TIMEOUT, ?MILLISECONDS_IN_HOUR).

-type blackhole_init() :: bh_context:context().
-type init_reply() ::  {'ok' , cowboy_req:req(), cowboy_websocket:opts()} |
                       {'cowboy_websocket', cowboy_req:req(), blackhole_init(), cowboy_websocket:opts()}.
-type init_fun_reply() ::  init_reply() | bh_context:context().

-spec init(cowboy_req:req(), cowboy_websocket:opts()) ->
          {'ok' , cowboy_req:req(), cowboy_websocket:opts()} |
          {'cowboy_websocket', cowboy_req:req(), blackhole_init(), cowboy_websocket:opts()}.
init(Req, HandlerOpts) ->
    InitFuns =  [fun check_subprotocols/3
                ,fun allow_connection/3
                ,fun set_session_id/3
                ,fun authenticate/3
                ],
    init_fold(Req, HandlerOpts, bh_context:new(), InitFuns).

init_fold(Req, _HandlerOpts, Context, []) ->
    {'cowboy_websocket', Req, Context, #{idle_timeout => ?IDLE_TIMEOUT}};
init_fold(Req, HandlerOpts, Context, [Fun | Funs]) ->
    case Fun(Req, HandlerOpts, Context) of
        {'ok', _, _} = Reply -> Reply;
        {'ok', _} = Reply -> Reply;
        Ctx -> init_fold(Req, HandlerOpts, Ctx, Funs)
    end.

-spec check_subprotocols(cowboy_req:req(), cowboy_websocket:opts(), bh_context:context()) ->
          init_fun_reply().
check_subprotocols(Req, HandlerOpts, Context) ->
    case cowboy_req:parse_header(<<"sec-websocket-protocol">>, Req) of
        'undefined' -> Context;
        _SubProtocols ->
            lager:warning("sub-protocols are not supported at the moment: ~p", [_SubProtocols]),
            {'ok', cowboy_req:reply(400, Req), HandlerOpts}
    end.

-spec allow_connection(cowboy_req:req(), cowboy_websocket:opts(), bh_context:context()) ->
          init_fun_reply().
allow_connection(Req, HandlerOpts, Context) ->
    RemoteIP = get_remote_peer(Req),

    MaxConnectionsPerIP = kapps_config:get_integer(?CONFIG_CAT, <<"max_connections_per_ip">>),
    case maybe_allow_connection(RemoteIP
                               ,MaxConnectionsPerIP
                               ,blackhole_tracking:session_count_by_ip(RemoteIP)
                               )
    of
        'true' ->
            bh_context:set_source(Context, RemoteIP);
        'false' ->
            {'ok', cowboy_req:reply(429, Req), HandlerOpts}
    end.

-spec get_remote_peer(cowboy_req:req()) -> kz_term:ne_binary().
get_remote_peer(Req) ->
    get_remote_peer(cowboy_req:peer(Req), cowboy_req:header(<<"x-forwarded-for">>, Req)).

-spec get_remote_peer({inet:ip_address(), inet:port_number()}, kz_term:api_ne_binary()) ->
          kz_term:ne_binary().
get_remote_peer({Peer, _PeerPort}, 'undefined') ->
    lager:info("new connection from peer ~p", [Peer]),
    kz_network_utils:iptuple_to_binary(Peer);
get_remote_peer({_ProxyIP, _ProxyPort}, ForwardIP) ->
    lager:info("new connection from peer ~s (proxy ~p)", [ForwardIP, _ProxyIP]),
    ForwardIP.

maybe_allow_connection(_RemoteIP, 'undefined', _ActiveConns) ->
    %% no max connection limit set
    'true';
maybe_allow_connection(RemoteIP, MaxConns, ActiveConns) when ActiveConns < MaxConns ->
    lager:debug("allowing connection from ~p (~p of ~p up)", [RemoteIP, ActiveConns, MaxConns]),
    'true';
maybe_allow_connection(RemoteIP, _MaxConns, ActiveConns) ->
    lager:warning("connection from ~p denied: max limit ~p reached", [RemoteIP, ActiveConns]),
    'false'.

set_session_id(Req, _HandlerOpts, Context) ->
    bh_context:set_websocket_session_id(Context, session_id(Req)).

authenticate(Req, HandlerOpts, Context) ->
    Token = cowboy_req:parse_header(<<"authorization">>, Req),
    authenticate_token(Req, HandlerOpts, Context, Token).

authenticate_token(_Req, _HandlerOpts, Context, 'undefined') ->
    lager:info("no auth token supplied"),
    Context;
authenticate_token(Req, HandlerOpts, Context, Token) ->
    case kz_auth:validate_token(Token) of
        {'ok', JObj} ->
            lager:info("auth token is valid, authenticated"),
            AccountId = kz_json:get_ne_value(<<"account_id">>, JObj),
            Setters = [{fun bh_context:set_auth_token/2, Token}
                      ,{fun bh_context:set_auth_account_id/2, AccountId}
                      ,fun bh_context:set_authorized/1
                      ],
            bh_context:setters(Context, Setters);
        {'error', R} ->
            lager:debug("failed to authenticate token auth, ~p", [R]),
            {'ok', cowboy_req:reply(403, Req), HandlerOpts}
    end.

-spec maybe_start_keep_alive() -> 'ok' | reference().
maybe_start_keep_alive() ->
    case kz_app_config:get_boolean(?APP, <<"keep_client_alive">>, 'false') of
        'true' -> erlang:send_after(1 * ?MILLISECONDS_IN_MINUTE, self(), 'keep_alive');
        'false' -> 'ok'
    end.

-spec terminate(any(), cowboy_req:req(), bh_context:context() | cowboy_websocket:opts())  -> 'ok'.
terminate(_Reason, Req, Opts) when is_list(Opts) ->
    lager:info("socket for session ~s down early: ~p", [session_id(Req), _Reason]);
terminate(_Reason, Req, Context) ->
    SessionId = session_id(Req),
    _ = blackhole_socket_callback:close(Context),
    lager:info("socket for session ~s down: ~p", [SessionId, _Reason]).

-spec websocket_init(blackhole_init()) -> {'ok', bh_context:context()}.
websocket_init(Context) ->
    lager:info("init from ~p(~p) ~s", [bh_context:source(Context)
                                      ,bh_context:websocket_session_id(Context)
                                      ,bh_context:authorized(Context)
                                      ]),
    Ctx = bh_context:set_websocket_pid(Context, self()),
    _ = maybe_start_keep_alive(),
    {'ok', _NewContext} = blackhole_socket_callback:open(Ctx).

-spec websocket_handle(any(), bh_context:context()) ->
          {'ok', bh_context:context(), 'hibernate'}.
websocket_handle({'text', Data}, Context) ->
    JObj   = kz_json:decode(Data),
    Action = kz_json:get_ne_binary_value(<<"action">>, JObj, <<"noop">>),
    Msg    = kz_json:delete_key(<<"action">>, JObj),

    case blackhole_socket_callback:recv({Action, Msg}, Context) of
        {'ok', NewContext} -> {'ok', NewContext, 'hibernate'};
        'error' -> {'ok', Context, 'hibernate'}
    end;
websocket_handle('ping', Context) ->
    {'ok', Context, 'hibernate'};
websocket_handle('pong', Context) ->
    {'ok', Context, 'hibernate'};
websocket_handle(_Other, Context) ->
    lager:debug("not handling message : ~p", [_Other]),
    {'ok', Context, 'hibernate'}.

-spec websocket_info(any(), bh_context:context()) ->
          {'ok', bh_context:context()} |
          {'reply', {'text', binary()} | 'pong', bh_context:context()}.
websocket_info({'$gen_cast', _}, Context) ->
    {'ok', Context};
websocket_info({'send_data', Data}, Context) ->
    {'reply', {'text', kz_json:encode(Data)}, Context};
websocket_info('pong', Context) ->
    {'reply', 'pong', Context};
websocket_info('keep_alive', Context) ->
    erlang:send_after(1 * ?MILLISECONDS_IN_MINUTE, self(), 'keep_alive'),
    {'reply', 'ping', Context};
websocket_info(Info, Context) ->
    lager:info("unhandled websocket info: ~p", [Info]),
    {'ok', Context}.

-spec session_id(cowboy_req:req()) -> binary().
session_id(Req) ->
    {IP, Port} = cowboy_req:peer(Req),

    BinIP   = kz_network_utils:iptuple_to_binary(IP),
    BinPort = kz_term:to_binary(Port),
    <<BinIP/binary, ":", BinPort/binary>>.
