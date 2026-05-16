%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2025, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pivot_stream_proxy).
-behaviour(cowboy_websocket).

-export([init/2
        ,upgrade/4
        ,websocket_init/1
        ,websocket_handle/2
        ,websocket_info/2
        ,terminate/3
        ]).

-include("pivot.hrl").

-define(IDLE_TIMEOUT, ?MILLISECONDS_IN_HOUR).

-define(DATA_TIMEOUT_MS, 5 * ?MILLISECONDS_IN_SECOND). %% Timeout in seconds waiting to receive JSON connect payload from FreeSWITCH
-define(GUN_CONNECT_TIMEOUT_MS, 5 * ?MILLISECONDS_IN_SECOND). %% Timeout in ms waiting for connecting to remote ws server

-define(DEFAULT_WAIT_MS, 5 * ?MILLISECONDS_IN_SECOND).

-define(PLAYBACK_MEDIA_TYPES, [<<"audio/x-wav">>
                              ,<<"audio/wav">>
                              ,<<"audio/mpeg">>
                              ,<<"audio/mp3">>
                              ]).

-type buffer() :: #{name => kz_term:ne_binary()
                   ,mark_name => kz_term:ne_binary()
                   ,noop_id => kz_term:ne_binary()
                   ,file => kz_term:ne_binary()
                   ,fd => pid()
                   ,size => integer()
                   ,content_type => kz_term:ne_binary()
                   }.
-type context() :: #{account_id => kz_term:ne_binary()
                    ,audio_codec => kz_term:ne_binary()
                    ,buffer => buffer()
                    ,call => kapps_call:call()
                    ,call_id => kz_term:api_ne_binary()
                    ,data => kz_json:object()
                    ,data_timeout_ref => kz_term:api_reference()
                    ,handler => module()
                    ,id => kz_term:ne_binary()
                    ,media_chunk => non_neg_integer()
                    ,name => kz_term:ne_binary()
                    ,pivot_node => node()
                    ,pivot_pid => pid()
                    ,pivot_rpc => 'undefined' | {pid(), reference(), reference()}
                    ,play_buffers => [buffer()]
                    ,proxy_pid => kz_term:api_pid()
                    ,remote_conn => 'undefined' | {'upgrading', pid(), reference() | [reference()]} | {pid(), reference() | [reference()]}
                    ,remote_conn_timeout_ref => kz_term:api_reference()
                    ,remote_uri => remote_uri()
                    ,sequence_number => pos_integer()
                    ,start => kz_time:start_time()
                    ,type => 'raw' | 'unidirectional' | 'bidirectional'
                    ,error => kz_term:api_ne_binary()
                    ,stop_reason => kz_term:api_ne_binary()
                    }.

-type remote_uri() :: {Scheme :: binary(), Host :: string(), Port :: inet:port_number(), Path :: binary()}.
-type event() :: 'connect' | 'start' | 'stop' | 'media' | 'dtmf' | 'mark' | 'clear'.

%%%=============================================================================
%%% Cowboy Websocket callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Inits the request in all its glory!
%% @end
%%------------------------------------------------------------------------------
-spec init(cowboy_req:req(), kz_term:proplist()) ->
          {'ok' , cowboy_req:req(), context()} |
          {'cowboy_websocket', cowboy_req:req(), context(), cowboy_websocket:opts()}.
init(Req, HandlerOpts) ->
    Context = #{call_id => props:get_value('call_id', HandlerOpts)
               ,account_id => cowboy_req:binding('account_id', Req)
               ,handler => ?MODULE
               ,audio_codec => cowboy_req:header(<<"x-audio-codec">>, Req, <<"L16">>)
               },
    case cowboy_req:parse_header(<<"sec-websocket-protocol">>, Req, []) of
        [] ->
            {?MODULE, Req, Context};
        SubProtocols ->
            case lists:member(<<"kazoo.audio.fork">>, SubProtocols) of
                'true' ->
                    Req1 = cowboy_req:set_resp_header(<<"sec-websocket-protocol">>, <<"kazoo.audio.fork">>, Req),
                    {?MODULE, Req1, Context};
                'false' ->
                    lager:warning("sub-protocols not supported at the moment: ~p", [SubProtocols]),
                    {'ok', cowboy_req:reply(400, Req), Context}
            end
    end.

-spec upgrade(cowboy_req:req(), cowboy_middleware:env(), module(), context()) ->
          {'ok', cowboy_req:req(), cowboy_middleware:env()}.
upgrade(Req, Env, _Handler, Context) ->
    NewEnv = maps:put('handler', ?MODULE, Env),
    cowboy_websocket:upgrade(Req, NewEnv, ?MODULE, Context, #{idle_timeout => ?IDLE_TIMEOUT}).

-spec terminate(any(), cowboy_req:req(), context() | cowboy_websocket:opts())  -> 'ok'.
terminate(Reason, Req, Opts) when is_list(Opts) ->
    lager:debug("socket for session ~s down early: ~p", [cowboy_req:binding('call_id', Req), Reason]);
terminate(Reason, _Req, Context) ->
    Ctx0 = clear_buffers(Context),
    Ctx = increment_seq(Ctx0),
    thanks_fish(Ctx),
    publish_stop(Reason, Ctx),
    lager:debug("terminating  with reason ~p", [Reason]).

-spec websocket_init(context()) -> {'ok', context()}.
websocket_init(#{call_id := CallId}=Context) ->
    kz_log:put_callid(CallId),
    kz_monitor:track_me(),
    TRef = erlang:send_after(?DATA_TIMEOUT_MS, self(), {'timeout', 'no_data'}),
    {'ok', Context#{proxy_pid => self(), data_timeout_ref => TRef}}.

-spec websocket_handle(any(), context()) ->
          {cowboy_websocket:commands(), context()} |
          {cowboy_websocket:commands(), context(), 'hibernate'}.
websocket_handle({'binary', Bin}, #{remote_conn := {_, _}}=Context) ->
    Ctx = increment_chunk(Context),
    relay_ws_event_to_remote(Ctx, stream_event('media', Bin, Ctx)),
    {[], Ctx, 'hibernate'};
websocket_handle({'binary', _Data}, Context) ->
    lager:debug("remote not connected, ignoring media binary..."),
    {[], Context, 'hibernate'};
websocket_handle({'text', Data}, Context) ->
    Ctx = cancel_data_timer(Context),
    JObj = kz_json:decode(Data),
    handle_freeswitch_data(JObj, Ctx);
websocket_handle('ping', Context) ->
    {[], Context, 'hibernate'};
websocket_handle('pong', Context) ->
    {[], Context, 'hibernate'};
websocket_handle(_Other, Context) ->
    lager:debug("not handling message : ~p", [_Other]),
    {[], Context, 'hibernate'}.

-spec cancel_data_timer(context()) -> context().
cancel_data_timer(#{data_timeout_ref := 'undefined'}=Context) ->
    Context;
cancel_data_timer(#{data_timeout_ref := TRef}=Context) ->
    _ = erlang:cancel_timer(TRef),
    Context#{data_timeout_ref => 'undefined'}.

-define(GUN_MSGS, ['gun_up', 'gun_down', 'gun_upgrade', 'gun_error' %% connection
                  ,'gun_push', 'gun_inform', 'gun_response', 'gun_data', 'gun_trailers' %% response
                  ,'gun_ws' %% websocket
                  ]).

-spec websocket_info(any(), context()) ->
          {cowboy_websocket:commands(), context()} |
          {cowboy_websocket:commands(), context(), 'hibernate'}.
websocket_info({'timeout', 'no_data'}, #{}=Context) ->
    lager:debug("timeout waiting for freeswitch to gives us the remote websocket info"),
    {['close'], Context#{error => <<"audio timeout">>}};
websocket_info({'timeout', 'get_call'}, #{}=Context) ->
    lager:debug("timeout waiting for pivot to respond"),
    Ctx = Context#{error => <<"call info acquiring timeout">>},
    {[{'close', 1011, <<"rpc failed: timeout waiting for pivot">>}], Ctx};
websocket_info({'timeout', 'ws_gun', ConnPid}, #{}=Context) ->
    lager:debug("timeout waiting to upgrading remote websocket"),
    gun:close(ConnPid),
    Ctx = Context#{remote_conn => 'undefined', error => <<"connection upgrade timeout">>},
    {[{'close', 1000, <<"unable to connect to remote">>}], Ctx};
websocket_info({'send_data', Data}, Context) ->
    {['text', kz_json:encode(Data)], Context, 'hibernate'};
websocket_info({'amqp_msg', JObj}, Context) ->
    handle_call_event(JObj, Context);
websocket_info({'get_call', Pid, Ref, Result}, #{pivot_rpc := {Pid, Ref, _TRef}}=Context) ->
    handle_pivot_get_call(Result, Context);
websocket_info(Info, Context) when is_tuple(Info) ->
    case lists:member(element(1, Info), ?GUN_MSGS) of
        'true' ->
            handle_gun_message(Info, Context);
        'false' ->
            lager:debug("unhandled websocket info: ~p", [Info]),
            {[], Context, 'hibernate'}
    end;
websocket_info(Info, Context) ->
    lager:debug("unhandled websocket info: ~p", [Info]),
    {[], Context, 'hibernate'}.

handle_pivot_get_call('not_found', #{pivot_rpc := {_Pid, _Ref, TRef}}=Context) ->
    _ = erlang:cancel_timer(TRef),
    lager:debug("stream not found in pivot"),
    Ctx = Context#{error => <<"no call">>, pivot_rpc => 'undefined'},
    {[{'close', 1011, <<"rpc failed: stream not found">>}], Ctx};
handle_pivot_get_call('no_id', Context) ->
    lager:debug("pivot has not recevied stream id yet, waiting more..."),
    {[], Context, 'hibernate'};
handle_pivot_get_call({Call, StreamId}, #{pivot_rpc := {_Pid, _Ref, TRef}}=Context) ->
    _ = erlang:cancel_timer(TRef),
    lager:debug("got call and stream id from pivot: ~s", [StreamId]),
    connect_remote_ws(Context#{call => Call, id => StreamId, pivot_rpc => 'undefined'}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
handle_gun_message({'gun_ws', ConnPid, StreamRef, {'text', Bin}}
                  ,#{remote_conn := {ConnPid, StreamRef}, type := 'bidirectional'}=Context
                  ) ->
    handle_bidirectional_msg(kz_json:decode(Bin, [{'default', 'undefined'}, 'return_maps']), Context);
handle_gun_message({'gun_ws', ConnPid, StreamRef, {Type, _Frame}}, #{remote_conn := {ConnPid, StreamRef}}=Context)
  when Type =:= 'text'
       orelse Type =:= 'binary' ->
    lager:debug("received unexpected ~s frame from remote, but stream is not bidirectional", [Type]),
    {[], Context, 'hibernate'};
handle_gun_message({'gun_ws', ConnPid, _StreamRef, 'close'}, Context) ->
    lager:debug("remote ~p(~p) is closing the connection, going down", [ConnPid, _StreamRef]),
    gun:close(ConnPid),
    cancel_gun_timer(Context),
    {['close'], Context#{remote_conn => 'undefined', stop_reason => <<"connection closed">>}};
handle_gun_message({'gun_ws', ConnPid, _StreamRef, {'close', _Code, _Payload}}, Context) ->
    lager:debug("remote ~p(~p) is closing the connection, going down, code: ~p payload: ~p"
               ,[ConnPid, _StreamRef, _Code, _Payload]
               ),
    gun:close(ConnPid),
    cancel_gun_timer(Context),
    {['close'], Context#{remote_conn => 'undefined', stop_reason => <<"connection closed">>}};
handle_gun_message({'gun_down', ConnPid, _ProtocolName, _Reason, _}, #{remote_conn := {ConnPid, _StreamRef}}=Context) ->
    lager:debug("remote ~p(~p) connection lost, going down: ~p", [ConnPid, _StreamRef, _Reason]),
    cancel_gun_timer(Context),
    {['close'], Context#{remote_conn => 'undefined', stop_reason => <<"connection closed">>}};
handle_gun_message({'gun_down', _ConnPid, _ProtocolName, _Reason, _}, Context) ->
    lager:debug("remote ~p(~p) connection lost early, going down: ~p", [_ConnPid, _Reason]),
    cancel_gun_timer(Context),
    {['close'], Context#{remote_conn => 'undefined', stop_reason => <<"connection closed">>}};

handle_gun_message({'gun_upgrade', ConnPid, StreamRef, [<<"websocket">>], _Headers}
                  ,#{remote_conn := {'upgrading', ConnPid, StreamRef}}=Context
                  ) ->
    cancel_gun_timer(Context),
    lager:debug("stream open: ~p(~p)", [ConnPid, StreamRef]),
    NewCtx = Context#{remote_conn => {ConnPid, StreamRef}
                     ,start => kz_time:start_time()
                     ,sequence_number => 1
                     ,media_chunk => 0
                     ,buffer => #{}
                     ,play_buffers => []
                     },
    stream_started(NewCtx);
handle_gun_message({'gun_response', ConnPid, _StreamRef, _IsFin, _Status, _Headers}, Context) ->
    lager:warning("upgrade failed on ~p(~p): ~p", [ConnPid, _StreamRef, _Status]),
    cancel_gun_timer(Context),
    gun:close(ConnPid),
    Error = kz_binary:format("connection failed with status code ~p", [_Status]),
    {[{'close', 1000, <<"unable to connect to remote">>}], Context#{error => Error}};
handle_gun_message({'gun_error', ConnPid, _StreamRef, Reason}, Context) ->
    lager:warning("ws error on ~p(~p): ~p", [ConnPid, _StreamRef, Reason]),
    cancel_gun_timer(Context),
    gun:close(ConnPid),
    {[{'close', 1000, <<>>}], Context#{error => <<"websocket error">>}};
handle_gun_message(GunMsg, Context) ->
    lager:debug("unhandled gun message: ~p", [GunMsg]),
    {[], Context, 'hibernate'}.

cancel_gun_timer(#{remote_conn_timeout_ref := Ref}) when is_reference(Ref) ->
    _ = erlang:cancel_timer(Ref),
    'ok';
cancel_gun_timer(_) ->
    'ok'.

%%%=============================================================================
%%% Stream handling
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Sends frame(s) to remote WS server.
%% @end
%%------------------------------------------------------------------------------
-spec relay_ws_event_to_remote(context(), gun:ws_frame() | [gun:ws_frame()]) -> 'ok'.
relay_ws_event_to_remote(#{remote_conn := {ConnPid, StreamRef}}, Frames) ->
    gun:ws_send(ConnPid, StreamRef, Frames);
relay_ws_event_to_remote(_Context, _Frames) ->
    'ok'.

-spec handle_call_event(kz_call_event:payload(), context()) ->
          {cowboy_websocket:commands(), context()} |
          {cowboy_websocket:commands(), context(), 'hibernate'}.
handle_call_event(_JObj, #{type := 'raw'}=Context) ->
    Ctx = increment_seq(Context),
    {[], Ctx, 'hibernate'};
handle_call_event(JObj, Context) ->
    Ctx = increment_seq(Context),
    case kapps_call_command:get_event_type(JObj) of
        {<<"call_event">>, <<"CHANNEL_DESTROY">>, _} ->
            lager:debug("caller channel destroyed, going down..."),
            thanks_fish(Ctx),
            {['close'], Ctx#{remote_conn => 'undefined', stop_reason => <<"hangup">>}};
        {<<"call_event">>, <<"DTMF">>, _} ->
            lager:debug("relaying dtmf event"),
            relay_ws_event_to_remote(Ctx, stream_event('dtmf', JObj, Ctx)),
            {[], Ctx, 'hibernate'};
        {<<"call_event">>, <<"CHANNEL_EXECUTE_COMPLETE">>, <<"noop">>} ->
            NoopId = kz_call_event:application_response(JObj),
            maybe_send_media_mark(NoopId, Context);
        {_Cat, _Evt, _App} ->
            {[], Context, 'hibernate'}
    end.

-spec maybe_send_media_mark(kz_term:api_ne_binary(), context()) ->
          {cowboy_websocket:commands(), context(), 'hibernate'}.
maybe_send_media_mark(NoopId, #{play_buffers := Buffers}=Context) ->
    case lists:partition(fun (#{noop_id := NId}) when NId =:= NoopId -> 'true';
                             (_) -> 'false'
                         end
                        ,Buffers
                        )
    of
        {[], _} ->
            {[], Context, 'hibernate'};
        {[#{}=Buffer|_], Plays} ->
            {[], clear_play_buffer(Buffer, Context#{play_buffers => Plays}), 'hibernate'}
    end.

-spec thanks_fish(context()) -> 'ok'.
thanks_fish(#{remote_conn := {ConnPid, _}, type := 'raw'}) ->
    gun:close(ConnPid);
thanks_fish(#{remote_conn := {ConnPid, StreamRef}}=Context) ->
    Ctx = increment_seq(Context),
    gun:ws_send(ConnPid, StreamRef, stream_event('stop', kz_json:new(), Ctx)),
    gun:close(ConnPid);
thanks_fish(_) ->
    'ok'.

-spec increment_seq(context()) -> context().
increment_seq(#{sequence_number := Seq}=Context) ->
    Context#{sequence_number => Seq +1};
increment_seq(#{}=Context) ->
    Context.

-spec increment_chunk(context()) -> context().
increment_chunk(#{sequence_number := Seq, media_chunk := Chunk}=Context) ->
    Context#{sequence_number => Seq + 1, media_chunk => Chunk + 1};
increment_chunk(#{}=Context) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc Handling payload received from FreeSWITCH and try to connect to remote
%% WebSocket server.
%% @end
%%------------------------------------------------------------------------------
-spec handle_freeswitch_data(kz_json:object(), context()) ->
          {cowboy_websocket:commands(), context()} |
          {cowboy_websocket:commands(), context(), 'hibernate'}.
handle_freeswitch_data(JObj, Context) ->
    case parse_url(kz_json:get_ne_binary_value(<<"url">>, JObj)) of
        {'ok', Uri} ->
            get_stream_call(Context#{data => JObj, remote_uri => Uri});
        {'error', _Reason} ->
            lager:debug("unable to parse  url: ~ts", [_Reason]),
            {[{'close', 1003, <<"bad or missing ws/wss url">>}], Context#{error => <<"invalid websocket url">>}}
    end.

-spec get_stream_call(context()) ->
          {cowboy_websocket:commands(), context()} |
          {cowboy_websocket:commands(), context(), 'hibernate'}.
get_stream_call(#{data := Data}=Context) ->
    %% TODO: maybe monitor pivot process?
    StreamName = kz_json:get_ne_binary_value(<<"name">>, Data),
    AMQPListner = kz_term:to_pid(kz_json:get_ne_binary_value(<<"amqp_listener">>, Data)),
    AMQPConsumer = kz_term:to_pid(kz_json:get_ne_binary_value(<<"amqp_consumer">>, Data)),
    Node = kz_term:to_atom(kz_json:get_ne_binary_value(<<"node">>, Data)),

    _ = kz_amqp_channel:consumer_pid(AMQPConsumer),

    Pid = self(),
    Ref = make_ref(),

    warn_no_dist(Node, node()),
    AMQPListner ! {'get_call', Pid, Ref, node(), StreamName},
    TRef = erlang:send_after(?DEFAULT_WAIT_MS, self(), {'timeout', 'get_call'}),
    NewCtx = Context#{pivot_pid => AMQPListner
                     ,pivot_node => Node
                     ,pivot_rpc => {Pid, Ref, TRef}
                     ,name => StreamName
                     },
    {[], NewCtx, 'hibernate'}.

-spec warn_no_dist(atom(), atom()) -> 'ok'.
warn_no_dist(Node, Node) -> 'ok';
warn_no_dist(_OtherNode, _MyNode) ->
    lager:debug("send messssage to another node is not supported yet, using local node for now").

%%------------------------------------------------------------------------------
%% @doc Handling payload received from FreeSWITCH and try to connect to remote
%% WebSocket server.
%% @end
%%------------------------------------------------------------------------------
-spec connect_remote_ws(context()) ->
          {cowboy_websocket:commands(), context()} |
          {cowboy_websocket:commands(), context(), 'hibernate'}.
connect_remote_ws(#{remote_uri := {Scheme, Host, Port, Path}}=Context) ->
    lager:debug("connecting to host ~s://~s:~b", [Scheme, Host, Port]),
    GunOpts = #{retry => 2
               ,retry_timeout => 2 * ?MILLISECONDS_IN_SECOND
               ,protocols => preferred_protocol(Scheme)
                %% uncomment when find a safe way to support ws with http/2
                %% ,http2_opts => #{notify_settings_changed => 'true'}
               },
    {'ok', ConnPid} = gun:open(Host, Port, maybe_tls(Scheme, GunOpts)),
    lager:debug("started WS gun client(~p) in", [ConnPid]),
    %% waits 5ms
    case wait_for_connection(ConnPid) of
        {'ok', _Protocol} ->
            StreamRef = gun:ws_upgrade(ConnPid, Path, [], #{}),
            lager:debug("upgrading to ws at path ~s", [Path]),

            ConnTRef = erlang:send_after(?GUN_CONNECT_TIMEOUT_MS, self(), {'timeout', 'gun_ws', ConnPid}),

            NewCtx = Context#{remote_conn => {'upgrading', ConnPid, StreamRef}
                             ,remote_conn_timeout_ref => ConnTRef
                             },
            {[], NewCtx, 'hibernate'};
        {'error', Error} ->
            {['close'], Context#{error => Error}}
    end.

-spec preferred_protocol(kz_term:ne_binary()) -> kz_term:atoms().
preferred_protocol(<<"ws">>) ->
    ['http'];
preferred_protocol(<<"wss">>) ->
    %% Websocket over http/2 is not good idea, requires RFC8441 "SETTINGS_ENABLE_CONNECT_PROTOCOL"
    %% and in general is overlapping with http/2 push. (only Chrome defaults to ws over http/2)
    %% See also: https://daniel.haxx.se/blog/2016/06/15/no-WebSockets-over-http2/
    %%
    %% Lets use http/1 for websocket, and if needed find a way to support http/2 in future.
    %%
    %% For example apparantly ngrok.io does not support CONNECT protocol, and gun:ws_upgrade will fail
    %% with "Stream reset by server." error.
    %%
    %% gun will default to [http2, http] for tls transport.
    %% Fun fact: curl refuses to use http/2 for websocket :)
    ['http'].

-spec maybe_tls(kz_term:ne_binary(), gun:opts()) -> gun:opts().
maybe_tls(<<"wss">>, Opts) ->
    Opts#{transport => 'tls'
         ,tls_opts => kz_ssl:ssl_opts([{'customize_hostname_check', [{'match_fun', public_key:pkix_verify_hostname_match_fun('https')}]}])
         };
maybe_tls(_Scheme, Opts) ->
    Opts.

-spec wait_for_connection(pid()) ->
          {'ok', atom()} |
          {'error', kz_term:ne_binary()}.
wait_for_connection(ConnPid) ->
    case gun:await_up(ConnPid) of
        {'ok', Protocol} ->
            do_await_enable_connect_protocol(Protocol, ConnPid);
        {'error', {'down', Error}} ->
            lager:debug("connection ~p failed: ~p", [ConnPid, Error]),
            {'error', kz_binary:format("connect failed~s", [connection_reason(Error)])};
        {'error', 'timeout'} ->
            lager:debug("connection ~p timeout", [ConnPid]),
            gun:close(ConnPid),
            {'error', <<"connect timeout">>}
    end.

%% Technically currently this has no effect since we don't preferred http2, but still
%% have this code here to avoid future headache of hunting down how to use gun with websocket over http/2.
%% FYI, you must set enable_connect_protocol to true in protocol option if you are using
%% Cowboy2 server.
-spec do_await_enable_connect_protocol(atom(), pid()) ->
          {'ok', atom()} |
          {'error', kz_term:ne_binary()}.
do_await_enable_connect_protocol('http', _) ->
    {'ok', 'http'};
do_await_enable_connect_protocol('http2', ConnPid) ->
    %% we cannot do a CONNECT :protocol request until the server tells us we can.
    case gun_await(ConnPid) of
        {'notify', 'settings_changed', #{enable_connect_protocol := 'true'}} ->
            lager:debug("connected with protocol http2"),
            {'ok', 'http2'};
        _Other ->
            lager:info("connected with protocol http/2, server does not support SETTINGS_ENABLE_CONNECT_PROTOCOL. ws_upgrade will fail"),
            {'error', <<"http/2 server does not support SETTINGS_ENABLE_CONNECT_PROTOCOL (RFC8441)">>}
    end.

-dialyzer([{nowarn_function, gun_await/1}]).
gun_await(ConnPid) ->
    %% when the upstream dev recommend hack your way into dialyzer /shrug
    gun:await(ConnPid, 'undedfined').

-spec connection_reason(any()) -> binary().
connection_reason({'shutdown', Reason}) when is_atom(Reason) ->
    <<": ", (kz_term:to_binary(Reason))/binary>>;
connection_reason(_) ->
    <<>>.

-spec stream_started(context()) ->
          {cowboy_websocket:commands(), context()} |
          {cowboy_websocket:commands(), context(), 'hibernate'}.
stream_started(#{data := Data
                ,id := Id
                ,name := Name
                ,call_id := CallId
                ,account_id := AccountId
                }=Context) ->
    Type = kz_json:get_ne_binary_value(<<"type">>, Data, <<"raw">>),
    Props = [{<<"Stream-ID">>, Id}
            ,{<<"Stream-Name">>, Name}
            ,{<<"Call-ID">>, CallId}
            ,{<<"Account-ID">>, AccountId}
            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
            ],
    Ctx = Context#{type => kz_term:to_atom(Type)},
    _ = kz_amqp_worker:cast(Props, fun kapi_pivot:publish_stream_start/1),
    maybe_send_connect_events(Data, Ctx).

%%------------------------------------------------------------------------------
%% @doc If connection is TwiML style, sends connect and start event first.
%% @end
%%------------------------------------------------------------------------------
-spec maybe_send_connect_events(kz_json:object(), context()) ->
          {cowboy_websocket:commands(), context(), 'hibernate'}.
maybe_send_connect_events(_Data, #{type := 'raw'}=Context) ->
    {[], Context, 'hibernate'};
maybe_send_connect_events(Data, Context) ->
    InitEvents = [stream_event('connect', Data, Context)
                 ,stream_event('start', Data, Context)
                 ],
    relay_ws_event_to_remote(Context, InitEvents),
    {[], Context, 'hibernate'}.

%%------------------------------------------------------------------------------
%% @doc Handles message for bidirectional stream.
%% @end
%%------------------------------------------------------------------------------
-spec handle_bidirectional_msg('undefined' | map(), context()) ->
          {cowboy_websocket:commands(), context()} |
          {cowboy_websocket:commands(), context(), 'hibernate'}.
handle_bidirectional_msg('undefined', Context) ->
    lager:debug("got invalid text frame from remote"),
    {[], Context, 'hibernate'};
handle_bidirectional_msg(#{<<"streamSid">> := Sid}, #{id := Id}=Context) when Sid =/= Id ->
    lager:debug("expected a frame with stream id ~s from remote but got ~s", [Id, Sid]),
    {[], Context, 'hibernate'};
handle_bidirectional_msg(#{<<"event">> := <<"media">>, <<"media">> := #{}=Media},Context) ->
    Audio = decode_playback_media(maps:get(<<"payload">>, Media, <<>>)),
    Buffer = set_playback_media_type(Media, Context),
    handle_playback_media(Audio, Buffer, Context);
handle_bidirectional_msg(#{<<"event">> := <<"mark">>, <<"mark">> := #{}=Mark}, Context) ->
    finish_buffer_and_play(Mark, Context);
handle_bidirectional_msg(#{<<"event">> := <<"clear">>}, #{call := Call}=Context) ->
    %% can we flush just play commands? there nothing in ecallmgr to flush a Group-ID.
    _ = kapps_call_command:flush(Call),
    {[], clear_buffers(Context), 'hibernate'};
handle_bidirectional_msg(_, Context) ->
    lager:debug("got invalid text frame from remote"),
    {[], Context, 'hibernate'}.

-spec handle_playback_media(binary(), buffer(), context()) ->
          {cowboy_websocket:commands(), context()} |
          {cowboy_websocket:commands(), context(), 'hibernate'}.
handle_playback_media(<<>>, _Buffer, Context) ->
    {[], Context, 'hibernate'};
handle_playback_media(Audio, #{content_type := _CT}=Buffer, Context) ->
    write_to_buffer(Audio, Buffer, Context);
handle_playback_media(_Audio, _Buffer, Context) ->
    {[], Context, 'hibernate'}.

-spec set_playback_media_type(map(), context()) -> buffer().
set_playback_media_type(_Media, #{buffer := #{content_type := _CT}=Buffer}) ->
    Buffer;
set_playback_media_type(Media, #{buffer := Buffer}) ->
    ContentType = kz_maps:get([<<"format">>, <<"encoding">>], Media, <<"audio/wav">>),
    case lists:member(ContentType, ?PLAYBACK_MEDIA_TYPES) of
        'true' ->
            Buffer#{content_type => ContentType};
        'false' ->
            Buffer
    end.

-spec decode_playback_media(kz_term:api_binary()) -> binary().
decode_playback_media('undefined') ->
    <<>>;
decode_playback_media(<<Media/binary>>) ->
    try base64:decode(Media)
    catch _:_ ->
            lager:debug("unabled to decode received playback media"),
            <<>>
    end;
decode_playback_media(_) ->
    lager:debug("received invalid playback media"),
    <<>>.

%%------------------------------------------------------------------------------
%% @doc Gets the received media stream and write it to the current buffer, if
%% no buffer yet inits the new buffer by creating a temporary file.
%% @end
%%------------------------------------------------------------------------------
-spec write_to_buffer(binary(), buffer(), context()) ->
          {cowboy_websocket:commands(), context()} |
          {cowboy_websocket:commands(), context(), 'hibernate'}.
write_to_buffer(<<>>, _Buffer, Context) ->
    {[], Context, 'hibernate'};
write_to_buffer(Bin, #{fd := Fd, size := Size, file := File}=Buffer, Context) ->
    BinSize = byte_size(Bin),
    lager:debug("writing ~b bytes to playback buffer file", [BinSize]),
    case file:write(Fd, Bin) of
        'ok' ->
            {[], Context#{buffer => Buffer#{size => Size + BinSize}}, 'hibernate'};
        {'error', _Reason} ->
            lager:error("failed to write playback buffer to file ~s: ~p", [File, _Reason]),
            {['close'], clear_buffers(Context#{buffer => Buffer, error => <<"media buffer failed">>})}
    end;
write_to_buffer(Bin, Buffer0, #{call_id := CallId, id := Id}=Context) ->
    ContentType = maps:get('content_type', Buffer0),
    File = pivot_media_proxy:media_path(CallId, Id, ContentType),
    lager:debug("creating file ~s to buffer playback media", [File]),
    case file:open(File, ['write']) of
        {'ok', Fd} ->
            Buffer = Buffer0#{fd => Fd, file => File, size => 0},
            write_to_buffer(Bin, Buffer, Context#{buffer => Buffer0});
        {'error', _Reason} ->
            lager:error("failed to create file ~s to write receiving media: ~p", [File, _Reason]),
            {['close'], clear_buffers(Context#{error => <<"media buffer failed">>})}
    end.

%%------------------------------------------------------------------------------
%% @doc Closes the current opened buffer if there is any and sends the play
%% call command, saves its Noop Id. The current buffer will be reset to
%% empty map and the newly marked buffer moves to play_buffers waiting for
%% its noop id to arrive later.
%% @end
%%------------------------------------------------------------------------------
-spec finish_buffer_and_play(map(), context()) ->
          {cowboy_websocket:commands(), context()} |
          {cowboy_websocket:commands(), context(), 'hibernate'}.
finish_buffer_and_play(Mark, #{buffer := #{fd := Fd, file := _File}=Buffer}=Context) ->
    MarkName = maps:get(<<"name">>, Mark, <<"mediaPlayed">>),
    NewBuffer = Buffer#{mark_name => MarkName},
    Ctx = Context#{buffer => NewBuffer},
    case file:close(Fd) of
        'ok' ->
            play_media(NewBuffer, Ctx#{buffer => #{}});
        {'error', _Reason} ->
            lager:error("failed to close file ~s of receiving media: ~p", [_File, _Reason]),
            play_media(NewBuffer, Ctx#{buffer => #{}})
    end;
finish_buffer_and_play(Mark, Context) ->
    MarkName = maps:get(<<"name">>, Mark, <<"unknown">>),
    Ctx = increment_seq(Context),
    relay_ws_event_to_remote(Ctx, stream_event('mark', MarkName, Ctx)),
    Ctx.

-spec play_media(buffer(), context()) ->
          {cowboy_websocket:commands(), context(), 'hibernate'}.
play_media(#{file := File, mark_name := MarkName}=Buffer
          ,#{call := Call, call_id := CallId, play_buffers := Plays}=Context
          ) ->
    MediaName = pivot_piper_init:media_proxy_url(CallId, filename:basename(File)),

    Terminators = kapps_call_command:play_terminators('undefined'),
    NoopId = kapps_call_command:play(MediaName, Terminators, Call),
    lager:debug("playing media ~s / ~s / ~s ", [kz_log:redactor(MediaName), MarkName, NoopId]),

    {[], Context#{play_buffers => [Buffer#{noop_id => NoopId} | Plays]}, 'hibernate'}.

%%------------------------------------------------------------------------------
%% @doc Clears all current buffer and play buffers if there are any, by deleting
%% their respective files and resets both buffer and play_buffer in context.
%% @end
%%------------------------------------------------------------------------------
-spec clear_buffers(context()) -> context().
clear_buffers(Context) ->
    clear_play_buffers(clear_buffer(Context)).

-spec clear_buffer(context()) -> context().
clear_buffer(#{fd := Fd, file := File}=Context) ->
    _ = file:close(Fd),
    _ = file:delete(File),
    Context#{buffer => #{}};
clear_buffer(Context) ->
    Context.

-spec clear_play_buffers(context()) -> context().
clear_play_buffers(#{play_buffers := Buffers}=Context) ->
    Ctx = lists:foldr(fun(Buffer, CtxAcc) -> clear_play_buffer(Buffer, CtxAcc) end, Context, Buffers),
    Ctx#{play_buffers => []};
clear_play_buffers(Context) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc Deletes the played buffer file from file system and notifies the remote
%% by sending the mark message.
%% @end
%%------------------------------------------------------------------------------
-spec clear_play_buffer(buffer(), context()) -> context().
clear_play_buffer(#{file := File, mark_name := Name}, Context) ->
    _ = file:delete(File),
    NewCtx = increment_seq(Context),
    relay_ws_event_to_remote(NewCtx, stream_event('mark', Name, NewCtx)),
    NewCtx.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec parse_url(kz_term:api_binary() | uri_string:uri_map() | uri_string:error()) ->
          {'ok', remote_uri()} |
          {'error', kz_term:ne_binary()}.
parse_url('undefined') ->
    {'error', <<"url is not defined">>};
parse_url(<<Url/binary>>) ->
    parse_url(uri_string:parse(Url));
parse_url(#{scheme := Scheme, host := Host, path := Path}=Url) when Scheme =:= <<"ws">>; Scheme =:= <<"wss">> ->
    {'ok', parse_url(Scheme, Host, Path, maps:get('port', Url, 'undefined'))};
parse_url({'error', _, _}=Error) ->
    {'error', kz_binary:format(<<"inavlid wesocket url: ~tp">>, [Error])};
parse_url(Url) ->
    {'error', kz_binary:format("not a websocket url ~tp", [Url])}.

-spec parse_url(binary(), binary(), binary(), non_neg_integer() | 'undefined') -> remote_uri().
parse_url(<<"ws">> = Scheme, Host, Path, 'undefined') ->
    parse_url(Scheme, Host, Path, 80);
parse_url(<<"wss">> = Scheme, Host, Path, 'undefined') ->
    parse_url(Scheme, Host, Path, 443);
parse_url(Scheme, Host, <<>>, Port) ->
    parse_url(Scheme, Host, <<"/">>, Port);
parse_url(Scheme, Host, Path, Port) ->
    {Scheme, kz_term:to_list(Host), Port, Path}.


%%------------------------------------------------------------------------------
%% @doc Creates the frame data to be send to remote Websocket.
%% @end
%%------------------------------------------------------------------------------
-spec stream_event(event(), kz_json:object() | binary() | any(), context()) -> cow_ws:frame().
stream_event(_media, Data, #{type := 'raw'}) ->
    {'binary', Data};
stream_event('connect', _Data, _Context) ->
    JObj = [{<<"event">>, <<"connected">>}
           ,{<<"protocol">>, <<"Call">>}
           ,{<<"version">>, <<"1.0.0">>}
           ],
    {'text', kz_json:encode(kz_json:from_list(JObj))};
stream_event('start', Data, Context) ->
    #{account_id := AccountId
     ,call_id := CallId
     ,id := StreamId
     ,name := Name
     } = Context,
    MediaFormat = [{<<"encoding">>, audio_codec_to_encoding(Context)}
                  ,{<<"sampleRate">>, sample_rate_to_int(Data)}
                  ,{<<"channels">>, channels_from_mix(Data)}
                  ],
    Start = [{<<"accountSid">>, AccountId}
            ,{<<"callSid">>, CallId}
            ,{<<"tracks">>, expand_tracks(Data)}
            ,{<<"mediaFormat">>, kz_json:from_list(MediaFormat)}
            ,{<<"customParameters">>, kz_json:get_json_value(<<"custom_params">>, Data)}
            ],
    JObj = [{<<"event">>, <<"start">>}
           ,{<<"sequenceNumber">>, 1}
           ,{<<"start">>, kz_json:from_list(Start)}
           ,{<<"streamSid">>, StreamId}
           ,{<<"streamName">>, Name}
           ],
    {'text', kz_json:encode(kz_json:from_list(JObj))};
stream_event('stop', _Data, Context) ->
    #{account_id := AccountId
     ,call_id := CallId
     ,id := StreamId
     ,sequence_number := SeqNum
     } = Context,
    Stop = [{<<"accountSid">>, AccountId}
           ,{<<"callSid">>, CallId}
           ],
    JObj = [{<<"event">>, <<"stop">>}
           ,{<<"sequenceNumber">>, SeqNum}
           ,{<<"stop">>, kz_json:from_list(Stop)}
           ,{<<"streamSid">>, StreamId}
           ],
    {'text', kz_json:encode(kz_json:from_list(JObj))};
stream_event('media', Data, Context) ->
    #{start := Start
     ,id := StreamId
     ,sequence_number := SeqNum
     ,media_chunk := MediaChunk
     ,data := StreamData
     } = Context,

    Media = [{<<"track">>, kz_json:get_ne_binary_value(<<"track">>, StreamData, <<"inbound_track">>)}
            ,{<<"chunk">>, MediaChunk}
            ,{<<"timestamp">>, kz_term:to_binary(kz_time:elapsed_ms(Start))}
            ,{<<"payload">>, base64:encode(Data)}
            ],
    JObj = [{<<"event">>, <<"media">>}
           ,{<<"sequenceNumber">>, SeqNum}
           ,{<<"media">>, kz_json:from_list(Media)}
           ,{<<"streamSid">>, StreamId}
           ],
    {'text', kz_json:encode(kz_json:from_list(JObj))};
stream_event('dtmf', ChannelEvent, Context) ->
    #{id := StreamId
     ,sequence_number := SeqNum
     } = Context,

    DTMF = [{<<"track">>, <<"inbound_track">>}
           ,{<<"digit">>, kz_call_event:dtmf_digit(ChannelEvent, <<>>)}
           ],
    JObj = [{<<"event">>, <<"dtmf">>}
           ,{<<"sequenceNumber">>, SeqNum}
           ,{<<"dtmf">>, kz_json:from_list(DTMF)}
           ,{<<"streamSid">>, StreamId}
           ],
    {'text', kz_json:encode(kz_json:from_list(JObj))};
stream_event('mark', Name, Context) ->
    #{id := StreamId
     ,sequence_number := SeqNum
     } = Context,

    Mark = [{<<"name">>, Name}],
    JObj = [{<<"event">>, <<"mark">>}
           ,{<<"sequenceNumber">>, SeqNum}
           ,{<<"mark">>, kz_json:from_list(Mark)}
           ,{<<"streamSid">>, StreamId}
           ],
    {'text', kz_json:encode(kz_json:from_list(JObj))}.

-spec expand_tracks(kz_json:object()) -> kz_term:ne_binaries().
expand_tracks(Data) ->
    case kz_json:get_ne_binary_value(<<"track">>, Data, <<"inbound_track">>) of
        <<"both_tracks">> -> [<<"inbound">>, <<"outbound">>];
        Track ->
            [re:replace(Track, <<"_track$">>, <<>>)]
    end.

-spec channels_from_mix(kz_json:object()) -> integer().
channels_from_mix(Data) ->
    case kz_json:get_ne_binary_value(<<"mix">>, Data) of
        <<"stereo">> -> 2;
        _ -> 1
    end.

-spec sample_rate_to_int(kz_json:object()) -> integer().
sample_rate_to_int(Data) ->
    SampleRate = kz_json:get_ne_binary_value(<<"sample_rate">>, Data, <<"8000">>),
    case kz_binary:reverse(SampleRate) of
        <<"k", Etar/binary>> ->
            RateInt = kz_term:safe_cast(kz_binary:reverse(Etar), 'undefined', fun kz_term:to_integer/1),
            safe_sample_rate(SampleRate, RateInt, 1000);
        _ ->
            RateInt = kz_term:safe_cast(SampleRate, 'undefined', fun kz_term:to_integer/1),
            safe_sample_rate(SampleRate, RateInt, 1)
    end.

-spec safe_sample_rate(kz_term:ne_binary(), kz_term:api_integer(), integer()) -> integer().
safe_sample_rate(_Value, 'undefined', _) -> 8000;
safe_sample_rate(_Value, RateInt, Multiply1K) -> (RateInt * Multiply1K).

-spec audio_codec_to_encoding(context()) -> kz_term:ne_binary().
audio_codec_to_encoding(Context) ->
    case kz_term:to_lower_binary(maps:get(audio_codec, Context, <<"L16">>)) of
        <<"pcmu">> -> <<"audio/x-mulaw">>;
        _ -> <<"audio/L16">>
    end.

%% keep in mind, the first argument, the reason of terminate, is
%% the connection to freeswitch, not the remote connection.
-spec publish_stop(any(), context()) -> 'ok'.
publish_stop('stop', #{error := _Error}=Ctx) ->
    do_publish_stop(Ctx#{stop_reason => <<"error">>});
publish_stop({'crash', _Class, _Reason}, Ctx) ->
    do_publish_stop(Ctx#{error => <<"internal_error">>, stop_reason => <<"error">>});
publish_stop({'error', 'badencoding'}, Ctx) ->
    do_publish_stop(Ctx#{error => <<"internal_error">>, stop_reason => <<"error">>});
publish_stop({'error', 'closed'}, Ctx) ->
    %% brutal close is still a close, right?
    Reason = maps:get('stop_reason', Ctx, <<"hangup">>),
    do_publish_stop(Ctx#{stop_reason => Reason, error => 'undefined'});
publish_stop({'error', _Reason}, Ctx) ->
    do_publish_stop(Ctx#{error => <<"internal_error">>, stop_reason => <<"error">>});

publish_stop('timeout', Ctx) ->
    Reason = maps:get('stop_reason', Ctx, <<"connection_inactivity">>),
    do_publish_stop(Ctx#{stop_reason => Reason, error => 'undefined'});
publish_stop(_, Ctx) ->
    Reason = maps:get('stop_reason', Ctx, <<"closed_or_hangup">>),
    do_publish_stop(Ctx#{stop_reason => Reason}).

-spec do_publish_stop(context()) -> 'ok'.
do_publish_stop(#{call_id := CallId, account_id := AccountId}=Context) ->
    Props = [{<<"Stream-ID">>, maps:get('id', Context, <<"unknown_id">>)}
            ,{<<"Stream-Name">>, maps:get('id', Context, <<"unknown_name">>)}
            ,{<<"Call-ID">>, CallId}
            ,{<<"Account-ID">>, AccountId}
            ,{<<"Reason">>, maps:get('stop_reason', Context, 'undefined')}
            ,{<<"Error-Message">>, maps:get('error', Context, 'undefined')}
            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
            ],
    kz_amqp_worker:cast(Props, fun kapi_pivot:publish_stream_stop/1).
