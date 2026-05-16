%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2025, 2600Hz
%%% @doc This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_ws_client).

-behaviour(gen_server).

-export([connect/1, connect/2, connect/3
        ,send/2
        ,close/1
        ,recv/1, recv/2
        ,info/1
        ]).

-export([init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_info/2
        ,terminate/2
        ,code_change/3
        ]).

-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kz_types.hrl").

-type conn() :: {pid(), reference()}.

-record(state, {conn :: conn() | 'undefined'
               ,events = queue:new() :: queue:queue(ws_event())
               ,requests = queue:new() :: queue:queue(ws_request())
               ,parent :: {pid(), reference()}
               }).
-type state() :: #state{}.

-type ws_event() :: {'text', binary()} |
                    {'json', kz_json:object()} |
                    {'frame', binary()}.
-type ws_request() :: {kz_term:pid_ref(), timeout(), reference()}.

-type stop_reason() :: {'ws_upgrade_failed', {non_neg_integer(), kz_term:proplist()}} |
                       {'ws_error', any()}.

-spec connect(kz_term:ne_binary()) ->
          {'ok', pid()} |
          {'error', stop_reason()}.
connect(WS) ->
    case kz_http_util:urlsplit(WS) of
        {<<"wss">>,{Host, Port},<<>>,<<>>,<<>>} ->
            connect(Host, Port, #{transport => 'tls'});
        {<<"ws">>,{Host, Port},<<>>,<<>>,<<>>} ->
            connect(Host, Port)
    end.

-spec connect(kz_term:text(), inet:port_number()) ->
          {'ok', pid()} |
          {'error', stop_reason()}.
connect(Host, Port) ->
    connect(Host, Port, #{}).

-spec connect(kz_term:text(), inet:port_number(), map()) ->
          {'ok', pid()} |
          {'error', stop_reason()}.
connect(Host, Port, Options) ->
    case gen_server:start_link(?MODULE, [Host, Port, Options, self()], []) of
        'ignore' ->
            receive
                {'ws_upgrade_failed', _}=Error -> {'error', Error};
                {'ws_error', _}=Error -> {'error', Error}
            after 0 -> {'ws_error', 'undefined'}
            end;
        Ret ->
            lager:info("connected: ~p", [Ret]),
            Ret
    end.

-spec send(pid(), iodata()) -> 'ok'.
send(Pid, Payload) ->
    gen_server:call(Pid, {'send', Payload}).

-spec close(kz_term:api_pid()) -> 'ok'.
close('undefined') -> 'ok';
close(Pid) ->
    gen_server:call(Pid, 'close').

-spec recv(pid()) -> ws_event() | {'error', 'timeout'}.
recv(Pid) ->
    recv(Pid, 0).

-spec recv(pid(), timeout()) -> ws_event() | {'error', 'timeout'}.
recv(Pid, Timeout) ->
    gen_server:call(Pid, {'recv', Timeout}, Timeout + ?MILLISECONDS_IN_SECOND).

-spec info(pid()) -> map().
info(Pid) ->
    gen_server:call(Pid, 'info').

-spec init(list()) ->
          {'ok', state()} | 'ignore'.
init([Host, Port, Options, Parent]) ->
    {UpgradeOptions, GunOptions} =
        case maps:take('upgrade_options', Options) of
            'error' -> {#{compress => 'true'}, Options};
            {UO, GO} -> {UO, GO}
        end,

    lager:info("connecting to ~p with ~p", [Host, GunOptions]),
    {'ok', ConnPid} = gun:open(kz_term:to_list(Host), Port, GunOptions),
    lager:info("started WS gun client(~p) to ~s:~p", [ConnPid, Host, Port]),
    {'ok', 'http'} = gun:await_up(ConnPid),
    lager:info("connection is up"),

    StreamRef = gun:ws_upgrade(ConnPid, "/", [], UpgradeOptions),
    lager:info("upgraded to ws: ~p", [StreamRef]),

    receive
        {'gun_upgrade', ConnPid, StreamRef, [<<"websocket">>], Headers} ->
            lager:info("stream open: ~p(~p): ~p", [ConnPid, StreamRef, Headers]),
            ParentRef = erlang:monitor('process', Parent),
            {'ok', #state{conn={ConnPid, StreamRef}, parent={Parent, ParentRef}}};
        {'gun_response', ConnPid, StreamRef, _IsFin, Status, Headers} ->
            lager:warning("upgrade failed on ~p: ~p", [ConnPid, Status]),
            gun:close(ConnPid),
            Parent ! {'ws_upgrade_failed', {Status, Headers}},
            'ignore';
        {'gun_error', ConnPid, StreamRef, Reason} ->
            lager:warning("ws error on ~p: ~p", [ConnPid, Reason]),
            gun:close(ConnPid),
            Parent ! {'ws_error', Reason},
            'ignore'
    after 2 * ?MILLISECONDS_IN_SECOND ->
            lager:warning("timeout waiting for upgrade"),
            gun:close(ConnPid),
            Parent ! {'ws_error', 'timeout'},
            'ignore'
    end.

-spec handle_call(any(), kz_term:pid_ref(), state()) -> kz_types:handle_call_ret_state(state()).
handle_call({'send', Payload}, _From, #state{conn={ConnPid, _}}=State) ->
    {'reply', gun:ws_send(ConnPid, {'text', Payload}), State};
handle_call({'recv', Timeout}
           ,From
           ,#state{events=Events
                  ,requests=Requests
                  }=State
           ) ->
    case queue:out(Events) of
        {'empty', Events} ->
            TRef = erlang:send_after(Timeout, self(), {'request_timeout', {From, Timeout}}),
            lager:info("waiting to recv event for ~p", [From]),
            UpdatedRequests = queue:in({From, Timeout, TRef}, Requests),
            {'noreply', State#state{requests=UpdatedRequests}};
        {{'value', Event}, UpdatedEvents} ->
            {'reply', Event, State#state{events=UpdatedEvents}}
    end;
handle_call('close', _From, #state{conn={ConnPid, _}}=State) ->
    close_conn(ConnPid),
    {'stop', 'normal', 'ok', State#state{conn='undefined'}};
handle_call('info', _From, #state{conn={ConnPid, _}}=State) ->
    {'reply', gun:info(ConnPid), State}.

-spec handle_cast(any(), state()) -> kz_types:handle_cast_ret_state(state()).
handle_cast(_Req, State) ->
    lager:info("ignoring cast ~p", [_Req]),
    {'noreply', State}.

-spec handle_info(any(), state()) -> kz_types:handle_info_ret_state(state()).
handle_info({'gun_ws', ConnPid, StreamRef, {'text', Binary}}
           ,#state{conn={ConnPid, StreamRef}}=State
           ) ->
    MyBinary = binary:copy(Binary),

    Event =
        case kz_json:decode(MyBinary, [{'default', 'null'}]) of
            'null' ->
                lager:info("no JSON decoded in '~p' ~w", [MyBinary, MyBinary]),
                {'text', MyBinary};
            JObj ->
                lager:info("JSON decoded in '~s'", [MyBinary]),
                {'json', JObj}
        end,
    handle_ws_event(Event, State);
handle_info({'gun_ws', ConnPid, StreamRef, Frame}, #state{conn={ConnPid, StreamRef}}=State) ->
    lager:info("recv frame ~s", [Frame]),
    Event = {'frame', Frame},
    handle_ws_event(Event, State);
handle_info({'request_timeout', {From, _Timeout}}, #state{requests=Requests}=State) ->
    lager:info("timed out waiting ~pms for event for request from ~p", [From, _Timeout]),
    gen_server:reply(From, {'error', 'timeout'}),
    UpdatedRequests = queue:filter(fun({Fr, _TO, _TRef}) -> Fr =/= From end, Requests),
    {'noreply', State#state{requests=UpdatedRequests}};
handle_info({'EXIT', Parent, _Reason}, #state{parent={Parent, _Ref}
                                             ,conn={Conn, _}
                                             }=State) ->
    lager:info("parent ~p down: ~p", [Parent, _Reason]),
    close_conn(Conn),
    {'stop', 'normal', State#state{conn='undefined'}};
handle_info({'DOWN', ParentRef, 'process', Parent, _Reason}
           ,#state{parent={Parent, ParentRef}
                  ,conn={Conn, _}
                  }=State
           ) ->
    lager:info("parent ~p down: ~p", [Parent, _Reason]),
    close_conn(Conn),
    {'stop', 'normal', State};
handle_info(_Msg, State) ->
    lager:info("ignoring msg ~p", [_Msg]),
    {'noreply', State}.

-spec terminate(any(), state()) -> 'ok'.
terminate(_Reason, #state{conn={ConnPid, _}}) ->
    close_conn(ConnPid),
    lager:info("shutdown WS client ~p: ~p", [ConnPid, _Reason]);
terminate(_Reason, #state{}) ->
    lager:info("shutdown: ~p", [_Reason]).

close_conn(Conn) when is_pid(Conn) ->
    gun:ws_send(Conn, 'close'),
    gun:shutdown(Conn).

-spec code_change(any(), state(), any()) -> {'ok', state()}.
code_change(_OldVersion, State, _Extra) ->
    {'ok', State}.

-spec handle_ws_event(ws_event(), state()) -> {'noreply', state()}.
handle_ws_event(Event
               ,#state{events=Events
                      ,requests=Requests
                      }=State
               ) ->
    case queue:out(Requests) of
        {'empty', Requests} ->
            {'noreply', State#state{events=queue:in(Event, Events)}};
        {{'value', {From, _Timeout, TRef}}, UpdatedRequests} ->
            lager:info("recv'd event for ~p", [From]),
            gen_server:reply(From, Event),
            'ok' = erlang:cancel_timer(TRef, [{'async', 'true'}, {'info', 'false'}]),
            {'noreply', State#state{requests=UpdatedRequests}}
    end.
