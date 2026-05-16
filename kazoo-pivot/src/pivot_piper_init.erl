%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pivot_piper_init).
-behaviour(cowboy_handler).

-export([start_link/0
        ,stop/0
        ]).

-export([init/2, terminate/3]).

-export([websocket_proxy_url/2
        ,media_proxy_url/2
        ,should_auth_media_proxy/0
        ,media_proxy_creds/0
        ]).

-include("pivot.hrl").

-define(PROXY_PORT, 34512).
-define(PROXY_PORT_SSL, 34513).
-define(PROXY_WORKERS,  kapps_config:get_integer(?STREAM_CONFIG_CAT, <<"proxy_listeners">>, 25)).
-define(SOCKET_OPTS(IP, PORT), [{'ip', IP}
                               ,{'port', PORT}
                               ,{'send_timeout', kapps_config:get_integer(?STREAM_CONFIG_CAT, <<"send_timeout_ms">>, 5 * ?MILLISECONDS_IN_SECOND)}
                               ]).

-define(AUTH_USERNAME, kapps_config:get_binary(?STREAM_CONFIG_CAT, <<"media_proxy_username">>, kz_binary:rand_hex(8))).
-define(AUTH_PASSWORD, kapps_config:get_binary(?STREAM_CONFIG_CAT, <<"media_proxy_password">>, kz_binary:rand_hex(8))).

%%%=============================================================================
%%% Worker callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec start_link() -> kz_types:startlink_ret().
start_link() ->
    kz_log:put_callid(?DEFAULT_LOG_SYSTEM_ID),

    Dispatch = cowboy_router:compile([{'_', [{<<"/stream/:account_id/:call_id">>, ?MODULE, [{'handler', 'pivot_stream_proxy'}]}
                                            ,{<<"/media/:call_id/:media_id">>, ?MODULE, [{'handler', 'pivot_media_proxy'}]}
                                            ]}
                                     ]),

    IP = kz_network_utils:default_binding_ip(),
    IPAddress = kz_network_utils:get_supported_binding_ip(IP),

    maybe_start_plaintext(Dispatch, IPAddress),
    maybe_start_ssl(Dispatch, IPAddress),

    'ignore'.

-spec stop() -> 'ok'.
stop() ->
    _ = cowboy:stop_listener('pivot_stream_socket'),
    _ = cowboy:stop_listener('pivot_stream_socket_ssl'),
    lager:debug("stopped pivot_stream_socket listeners").

%%%=============================================================================
%%% Cowboy Handler callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Inits the request in all its glory!
%% @end
%%------------------------------------------------------------------------------
-spec init(cowboy_req:req(), kz_term:proplist()) ->
          {'ok' , cowboy_req:req(), kz_term:proplist()} |
          {module(), cowboy_req:req(), any()} |
          {module(), cowboy_req:req(), any(), any()}.
init(Req0, HandlerOpts0) ->
    Req = cowboy_req:set_resp_header(<<"server">>, kz_term:to_binary(?APP_NAME), Req0),
    Handler = props:get_value('handler', HandlerOpts0),

    CallId = cowboy_req:binding('call_id', Req),
    kz_log:put_callid(CallId),

    {ClientIP, ProxyIP} = get_client_ip(Req),
    lager:info("~s: ~s from ~s (proxy ~s)"
              ,[cowboy_req:method(Req)
               ,cowboy_req:path(Req)
               ,ClientIP
               ,ProxyIP
               ]
              ),

    HandlerOpts = [{'call_id', CallId}
                  ,{'client_ip', ClientIP}
                  ,{'handler', Handler}
                  ],
    case authenticate(Handler, Req) of
        'true' ->
            case Handler:init(Req, HandlerOpts) of
                {'ok', _, _}=Ok ->             Ok;
                {_Mod, Req1, Context} ->       {Handler, Req1, Context};
                {_Mod, Req1, Context, Opts} -> {Handler, Req1, Context, Opts}
            end;
        'false' ->
            {'ok', cowboy_req:reply(401, Req), HandlerOpts}
    end.

-spec terminate(any(), cowboy_req:req(), kz_term:proplist() | map())  -> 'ok'.
terminate(Reason, Req, Opts) when is_list(Opts) ->
    Handler = props:get_value('handler', Opts),
    Handler:terminate(Reason, Req, Opts);
terminate(Reason, Req, #{handler := Handler} = Context) ->
    Handler:terminate(Reason, Req, Context).

%%%=============================================================================
%%% Exports
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec websocket_proxy_url(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
websocket_proxy_url(AccountId, CallId) ->
    UseSSL = use_ssl(),
    Scheme = websocket_scheme(UseSSL),
    Host   = proxy_host(),
    Port   = proxy_port(UseSSL),
    kz_binary:join([proxy_base_url(Scheme, Host, Port, <<>>), <<"stream">>, AccountId, CallId], <<"/">>).

-spec media_proxy_url(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
media_proxy_url(CallId, MediaId) ->
    UseSSL = use_ssl(),
    Scheme = http_scheme(UseSSL),
    Host   = proxy_host(),
    Port   = proxy_port(UseSSL),
    Creds  = media_proxy_creds(should_auth_media_proxy()),
    kz_binary:join([proxy_base_url(Scheme, Host, Port, Creds), <<"media">>, CallId, MediaId], <<"/">>).

-spec should_auth_media_proxy() -> boolean().
should_auth_media_proxy() -> kapps_config:is_true(?STREAM_CONFIG_CAT, <<"should_authenticated_media_proxy">>, 'false').

-spec media_proxy_creds() -> {kz_term:ne_binary(), kz_term:ne_binary()}.
media_proxy_creds() ->
    {?AUTH_USERNAME, ?AUTH_PASSWORD}.

-spec proxy_base_url('ws' | 'wss' | 'http' | 'https', kz_term:ne_binary(), pos_integer(), binary()) -> kz_term:ne_binary().
proxy_base_url(Scheme, H, 443, Creds)
  when Scheme =:= 'wss'
       orelse Scheme =:= 'https' ->
    kz_term:to_binary([kz_term:to_binary(Scheme), "://", Creds, kz_term:to_binary(H)]);
proxy_base_url(Scheme, H, 80, Creds)
  when Scheme =:= 'ws'
       orelse Scheme =:= 'http' ->
    kz_term:to_binary([kz_term:to_binary(Scheme), "://", Creds, kz_term:to_binary(H)]);
proxy_base_url(Scheme, H, P, Creds) ->
    kz_term:to_binary([kz_term:to_binary(Scheme), "://", Creds, kz_term:to_binary(H), ":", kz_term:to_binary(P)]).

%%%=============================================================================
%%% Cowboy HTTP server setup
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec maybe_start_plaintext(cowboy_router:dispatch_rules(), inet:ip_address()) -> 'ok'.
maybe_start_plaintext(Dispatch, IP) ->
    case kapps_config:get_is_true(?STREAM_CONFIG_CAT, <<"use_plaintext">>, 'true') of
        'false' ->
            lager:debug("plaintext stream proxy support not enabled");
        'true' ->
            Port = proxy_port('false'),
            lager:info("trying to bind to address ~s port ~b", [inet:ntoa(IP), Port]),

            {'ok', _Pid} = cowboy:start_clear('pivot_stream_socket'
                                             ,#{'socket_opts' => ?SOCKET_OPTS(IP, Port)
                                               ,'num_acceptors' => ?PROXY_WORKERS
                                               }
                                             ,#{'env' => #{'dispatch' => Dispatch}
                                               }
                                             ),
            lager:info("started stream proxy(~p) on port ~p", [_Pid, Port])
    end.

-spec maybe_start_ssl(cowboy_router:dispatch_rules(), inet:ip_address()) -> 'ok'.
maybe_start_ssl(Dispatch, IP) ->
    case use_ssl() of
        'false' ->
            lager:debug("ssl stream proxy support not enabled");
        'true' ->
            RootDir = code:lib_dir(?APP),

            SSLCert = kapps_config:get_string(?STREAM_CONFIG_CAT
                                             ,<<"ssl_cert">>
                                             ,filename:join([RootDir, <<"priv/ssl/stream_proxy.crt">>])
                                             ),
            SSLKey = kapps_config:get_string(?STREAM_CONFIG_CAT
                                            ,<<"ssl_key">>
                                            ,filename:join([RootDir, <<"priv/ssl/stream_proxy.key">>])
                                            ),

            SSLPort = proxy_port('true'),
            SSLPassword = kapps_config:get_string(?STREAM_CONFIG_CAT, <<"ssl_password">>, <<>>),

            lager:info("trying to bind SSL API server to address ~s port ~b", [inet:ntoa(IP), SSLPort]),

            try
                {'ok', _Pid} = cowboy:start_tls('pivot_stream_socket_ssl'
                                               ,#{'socket_opts' => [{'certfile', find_file(SSLCert, RootDir)}
                                                                   ,{'keyfile', find_file(SSLKey, RootDir)}
                                                                   ,{'password', SSLPassword}
                                                                   | ?SOCKET_OPTS(IP, SSLPort)
                                                                   ]
                                                 ,'num_acceptors' => ?PROXY_WORKERS
                                                 }
                                               ,#{'env' => #{'dispatch' => Dispatch}
                                                 }
                                               ),
                lager:info("started ssl stream proxy(~p) on port ~p", [_Pid, SSLPort])
            catch
                'throw':{'invalid_file', _File} ->
                    lager:info("SSL disabled: failed to find ~s (tried prepending ~s too)", [_File, RootDir])
            end
    end.

%%%=============================================================================
%%% General connection setup
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec authenticate(module(), cowboy_req:req()) -> boolean().
authenticate('pivot_media_proxy', Req) ->
    case should_auth_media_proxy() of
        'false' ->
            lager:debug("authentication is not required, allowing the request"),
            'true';
        'true' ->
            basic_authentication(Req)
    end;
authenticate(_Handler, _Req) ->
    'true'.

-spec get_client_ip(cowboy_req:req()) -> {kz_term:ne_binary(), kz_term:ne_binary()}.
get_client_ip(Req) ->
    get_client_ip(cowboy_req:peer(Req), cowboy_req:header(<<"x-forwarded-for">>, Req)).

-spec get_client_ip({inet:ip_address(), inet:port_number()}, kz_term:ne_binary()) ->
          {kz_term:ne_binary(), kz_term:ne_binary()}.
get_client_ip({Peer, _PeerPort}, 'undefined') ->
    IP = kz_network_utils:iptuple_to_binary(Peer),
    {IP, <<"none">>};
get_client_ip({ProxyIP, _ProxyPort}, ForwardIP) ->
    {ForwardIP, kz_network_utils:iptuple_to_binary(ProxyIP)}.

-spec basic_authentication(cowboy_req:req()) -> boolean().
basic_authentication(Req) ->
    case credentials_from_header(Req) of
        {'undefined', 'undefined'} ->
            lager:debug("authentication failed, request did not provide basic authentication", []),
            'false';
        {Username, Password} ->
            basic_authentication(Username, Password)
    end.

-spec basic_authentication(kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
basic_authentication(Username, Password) ->
    {AuthUsername, AuthPassword} = media_proxy_creds(),
    case not kz_term:is_empty(AuthUsername)
        andalso not kz_term:is_empty(AuthPassword)
        andalso Username =:= AuthUsername
        andalso Password =:= AuthPassword
    of
        'true' ->
            'true';
        'false' ->
            lager:debug("autehtnication failed, header creds is not matching to systems creds"),
            'false'
    end.

-spec credentials_from_header(cowboy_req:req()) -> {kz_term:api_binary(), kz_term:api_binary()}.
credentials_from_header(Req) ->
    case cowboy_req:header(<<"authorization">>, Req) of
        'undefined' ->
            {'undefined', 'undefined'};
        Authorization ->
            case binary:split(Authorization, <<$\s>>) of
                [<<"Basic">>, EncodedCredentials] ->
                    decoded_credentials(EncodedCredentials);
                _ ->
                    {'undefined', 'undefined'}
            end
    end.

-spec decoded_credentials(kz_term:ne_binary()) -> {kz_term:api_binary(), kz_term:api_binary()}.
decoded_credentials(EncodedCredentials) ->
    DecodedCredentials = base64:decode(EncodedCredentials),
    case binary:split(DecodedCredentials, <<$:>>) of
        [Username, Password] ->
            {Username, Password};
        _ ->
            {'undefined', 'undefined'}
    end.

%%%=============================================================================
%%% Utilities
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec find_file(string(), string()) -> string().
find_file(File, Root) ->
    case filelib:is_file(File) of
        'true' -> File;
        'false' ->
            FromRoot = filename:join([Root, File]),
            lager:info("failed to find file at ~s, trying ~s", [File, FromRoot]),
            case filelib:is_file(FromRoot) of
                'true' -> FromRoot;
                'false' ->
                    lager:info("failed to find file at ~s", [FromRoot]),
                    throw({'invalid_file', File})
            end
    end.

-spec proxy_host() -> kz_term:ne_binary().
proxy_host() ->
    {'ok', Hostname} = net_adm:dns_hostname(net_adm:localhost()),
    kz_term:to_binary(Hostname).
%% case kapps_config:get_ne_binary(?STREAM_CONFIG_CAT, <<"proxy_hostname">>) of
%%     'undefined' -> ;
%%     ProxyHostname -> ProxyHostname
%% end.

-spec proxy_port(boolean()) -> pos_integer().
proxy_port('true') ->
    kapps_config:get_integer(?STREAM_CONFIG_CAT, <<"proxy_ssl_port">>, ?PROXY_PORT_SSL);
proxy_port('false') ->
    kapps_config:get_integer(?STREAM_CONFIG_CAT, <<"proxy_port">>, ?PROXY_PORT).

-spec media_proxy_creds(boolean()) -> binary().
media_proxy_creds('true') ->
    {Username, Password} = media_proxy_creds(),
    kz_term:to_binary([Username, ":", Password, "@"]);
media_proxy_creds('false') -> <<>>.

-spec websocket_scheme(boolean()) -> 'ws' | 'wss'.
websocket_scheme('true') -> 'wss';
websocket_scheme('false') -> 'ws'.

-spec http_scheme(boolean()) -> 'http' | 'https'.
http_scheme('true') -> 'https';
http_scheme('false') -> 'http'.

-spec use_ssl() -> boolean().
use_ssl() -> kapps_config:get_is_true(?STREAM_CONFIG_CAT, <<"use_ssl">>, 'false').
