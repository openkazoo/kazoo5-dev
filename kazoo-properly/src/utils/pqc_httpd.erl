%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2018-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_httpd).
-behaviour(gen_server).

-export([fetch_req/2, fetch_req/3
        ,get_req/2
        ,wait_for_req/2, wait_for_req/3

        ,add_request/3, add_request/4, add_request/5
        ,add_response/4

        ,base_url/1
        ,status/1
        ,stop/1

        ,find_path/3
        ]).

%% gen_server
-export([start_link/0, start_link/1, start_link/2
        ,init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_info/2
        ,code_change/3
        ,terminate/2
        ]).

-include("properly.hrl").

-elvis([{'elvis_style', 'no_debug_call', 'disable'}]).

%% store_headers :: boolean()
%%   when 'true': responses to get_req/fetch_req will return a JSON object
%%     with "body" and "headers" keys - where "body" is the request body
%%     (unparsed) and "headers" is a JSON object of request headers
%%   when 'false': responses to get_req/fetch_req will be the unparsed
%%     request body
-type httpd_options() :: #{'store_headers' := boolean()}.

%% {{Pid, MRef}, TRef, JSONPath | {JSONPath, sender function}}
%% waits are properly test processes that are blocking for a request to arrive
-type wait_path() :: kz_json:path() | {kz_json:path(), fun()}.
-record(wait, {from :: kz_term:pid_ref()
              ,wait_ref :: reference()
              ,wait_path :: wait_path()
              ,server :: pid()
              }
       ).
-type wait() :: #wait{}.
-type waits() :: [wait()].

-record(response, {headers = kz_json:new() :: kz_json:object()
                  ,body = <<>> :: binary()
                  ,path = [] :: kz_json:path()
                  }
       ).
-type response() :: #response{}.
-type responses() :: [response()].

-record(request, {headers = kz_json:new() :: kz_json:object()
                 ,body = <<>> :: binary()
                 ,path = [] :: kz_json:path()
                 ,querystring = [] :: kz_term:proplist()
                 }).
-type request() :: #request{}.
-type requests() :: [request()].

-record(state, {requests = [] :: requests()
               ,responses = [] :: responses()
               ,waits = [] :: waits()
               ,options :: httpd_options()
               ,log_id :: kz_term:ne_binary()
               }).
-type state() :: #state{}.

-spec start_link() -> {'ok', pid()}.
start_link() ->
    start_link(kz_binary:rand_hex(5)).

-spec start_link(kz_term:ne_binary()) -> {'ok', pid()}.
start_link(LogId) ->
    start_link(LogId, #{'store_headers' => 'false'}).

-spec start_link(kz_term:ne_binary(), httpd_options()) ->
          {'ok', pid()} |
          {'error', {'already_started', pid()}}.
start_link(LogId, Options) ->
    gen_server:start_link(?MODULE, [LogId, Options], []).

-spec status(pid() | pqc_cb_api:state()) -> kz_json:object().
status(#{httpd := Pid}) -> status(Pid);
status(Pid) ->
    gen_server:call(Pid, 'status').

-spec stop(pid() | pqc_cb_api:state()) -> 'ok'.
stop(#{httpd := Pid}) -> stop(Pid);
stop(Pid) ->
    gen_server:stop(Pid).

%% @doc fetches the value and removes it from the state if found
-spec fetch_req(pqc_cb_api:state(), kz_json:path()) ->
          {kz_json:object(), binary()} | 'undefined' |
          {'error', 'timeout'}.
fetch_req(API, Path) ->
    fetch_req(API, Path, 'undefined').

%% @doc fetches the value and removes it from the state if found
-spec fetch_req(pqc_cb_api:state() | pid(), kz_json:path(), kz_term:api_pos_integer()) ->
          {kz_json:object(), binary()} | 'undefined' |
          {'error', 'timeout'}.
fetch_req(#{httpd := Pid}, Path, TimeoutMs) ->
    fetch_req(Pid, Path, TimeoutMs);
fetch_req(Pid, Path, TimeoutMs) when is_pid(Pid) ->
    gen_server:call(Pid, {'fetch_req', Path, TimeoutMs}, timeout_or_default(TimeoutMs)).

-spec timeout_or_default(kz_term:api_pos_integer()) -> pos_integer().
timeout_or_default('undefined') -> 5 * ?MILLISECONDS_IN_SECOND;
timeout_or_default(TimeoutMs) when is_integer(TimeoutMs), TimeoutMs > 0 -> TimeoutMs + 500.

%% @doc reads the value and leaves it in the state if found
-spec get_req(pqc_cb_api:state(), kz_json:path()) ->
          {kz_json:object(), binary()} | 'undefined'.
get_req(#{httpd := Pid}, Path) ->
    get_req(Pid, Path);
get_req(Pid, Path) ->
    gen_server:call(Pid, {'get_req', Path}).

%% @doc waits until the request can be fulfilled then returns the value, leaving in state
-spec wait_for_req(pqc_cb_api:state(), kz_json:path()) ->
          {kz_json:object(), binary()} | 'undefined' |
          {'error', 'timeout'}.
wait_for_req(API, Path) when is_list(Path) ->
    wait_for_req(API, Path, 5 * ?MILLISECONDS_IN_SECOND).

-spec wait_for_req(pqc_cb_api:state(), kz_json:path(), pos_integer()) ->
          {kz_json:object(), binary()} | 'undefined' |
          {'error', 'timeout'}.
wait_for_req(#{httpd := Pid}, Path, TimeoutMs) ->
    wait_for_req(Pid, Path, TimeoutMs);
wait_for_req(Pid, Path, TimeoutMs)
  when is_integer(TimeoutMs), TimeoutMs > 0 ->
    gen_server:call(Pid, {'wait_for_req', Path, TimeoutMs}, TimeoutMs + 100).

-spec add_request(pqc_cb_api:state(), kz_json:path(), binary()) -> 'ok'.
add_request(API, Path, <<Content/binary>>) ->
    add_request(API, Path, Content, 'undefined').

%% @doc updates the state to store Content at the Path location
-spec add_request(pqc_cb_api:state(), kz_json:path(), binary(), cowboy:http_headers() | 'undefined') -> 'ok'.
add_request(API, Path, <<Content/binary>>, ReqHeaders) ->
    add_request(API, Path, <<Content/binary>>, ReqHeaders, []).

-spec add_request(pqc_cb_api:state(), kz_json:path(), binary(), kz_term:api_object(), kz_term:proplist()) -> 'ok'.
add_request(#{httpd := Pid}, Path, <<Content/binary>>, ReqHeaders, Querystring) ->
    add_request(Pid, Path, <<Content/binary>>, ReqHeaders, Querystring);
add_request(Pid, Path, <<Content/binary>>, ReqHeaders, Querystring) ->
    Store = try base64:decode(Content) of
                Decoded -> Decoded
            catch
                'error':_ -> Content
            end,
    lager:info("trying to store in ~p: ~p: ~s", [Pid, Path, Store]),
    gen_server:call(Pid, {'add_request', Path, ReqHeaders, Store, Querystring}).

%% @doc add a response for a path to be returned by the HTTP server
-spec add_response(pqc_cb_api:state(), kz_json:get_key(), kz_json:object(), kz_term:ne_binary()) -> 'ok'.
add_response(#{httpd := Pid}, Path, RespHeaders, RespBody) ->
    gen_server:call(Pid, {'add_response', Path, RespHeaders, RespBody}).

-spec init(list()) -> {'ok', state()}.
init([LogId, Options]) ->
    kz_log:put_callid(LogId),
    lager:info("starting HTTPD server"),
    {'ok', _Pid} = pqc_httpd_handler:start_plaintext(LogId),
    lager:info("started HTTPD server(~p) at ~s with log id: ~s", [_Pid, base_url(LogId), LogId]),
    {'ok', #state{options=Options, log_id=LogId}}.

-spec base_url(pqc_cb_api:state() | kz_term:ne_binary()) -> kz_term:ne_binary().
base_url(#{request_id := LogId}) ->
    base_url(LogId);
base_url(LogId) ->
    Port = pqc_httpd_handler:port(LogId),
    Host = kz_network_utils:get_hostname(),
    kz_term:to_binary(["http://", Host, $:, integer_to_list(Port), $/]).

-spec terminate(any(), state()) -> 'ok'.
terminate(_Reason, #state{waits=Waits, log_id=LogId}) ->
    lager:info("terminating: ~p", [_Reason]),
    pqc_httpd_handler:stop_listener(LogId),
    _ = [gen_server:reply(From, 'terminate')
         || #wait{from={Pid, _Ref}=From} <- Waits,
            is_process_alive(Pid)
        ],
    'ok'.

-spec code_change(any(), state(), any()) -> {'ok', state()}.
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.

-spec handle_call(any(), kz_term:pid_ref(), state()) ->
          {'noreply', state()} |
          {'reply', kz_json:api_json_term(), state()}.
handle_call({'add_response', Path, RespHeaders, RespBody}
           ,_From
           ,#state{responses=Responses}=State
           ) ->
    {'reply'
    ,lager:info("setting a response for ~s", [Path])
    ,State#state{responses=new_response(Path, RespHeaders, RespBody, Responses)}
    };
handle_call({'wait_for_req', Path, TimeoutMs}
           ,From
           ,#state{requests=Requests
                  ,waits=Waits
                  }=State
           ) ->
    PathParts = path_parts(Path),
    case find_path(PathParts, #request.path, Requests) of
        'false' ->
            lager:info("waiting for req on ~p for ~p", [PathParts, From]),
            {'noreply', State#state{waits=[new_wait(From, Path, TimeoutMs) | Waits]}};
        #request{headers=Headers, body=Body} ->
            lager:info("no waiting for req on ~p for ~p: ~p", [PathParts, From, Body]),
            {'reply', {Headers, Body}, State}
    end;
handle_call('status', _From, State) ->
    {'reply', State, State};

handle_call({'fetch_req', Path, 'undefined'}, _From, #state{requests=Requests}=State) ->
    PathParts = path_parts(Path),
    case find_path(PathParts, #request.path, Requests) of
        'false' ->
            lager:info("failed to fetch ~p", [PathParts]),
            {'reply', 'undefined', State};
        #request{headers=Headers, body=Body}=Req ->
            lager:info("fetched ~p: ~s", [PathParts, Body]),
            {'reply', {Headers, Body}, State#state{requests=lists:delete(Req, Requests)}}
    end;
handle_call({'fetch_req', Path, TimeoutMs}
           ,From
           ,#state{requests=Requests
                  ,waits=Waits
                  }=State
           ) when is_integer(TimeoutMs) ->
    PathParts = path_parts(Path),
    case find_path(PathParts, #request.path, Requests) of
        'false' ->
            lager:info("new fetch_req waiting for path ~p", [PathParts]),
            {'noreply'
            ,State#state{waits=[new_wait(From, {Path, fun fetch_req/2}, TimeoutMs) | Waits]}
            };
        #request{headers=Headers, body=Body}=Req ->
            lager:info("fetched ~p: ~s", [Path, Body]),
            {'reply', {Headers, Body}, State#state{requests=lists:delete(Req, Requests)}}
    end;

handle_call({'get_req', Path}, _From, #state{requests=Requests
                                            ,responses=Responses
                                            }=State) ->
    lager:info("getting response for path ~p", [Path]),
    {'reply', find_request_or_response(Path, Requests, Responses), State};

handle_call({'add_request', PathInfo, ReqHeaders, ReqBody, QueryString}, _From, State) ->
    NewState = handle_req_update(PathInfo, ReqHeaders, ReqBody, QueryString, State),
    {'reply', 'ok', NewState};
handle_call(_Req, _From, State) ->
    {'noreply', State}.

handle_req_update(PathInfo, ReqHeaders, <<>>, QueryString
                 ,#state{waits=Waits
                        ,requests=Requests
                        }=State
                 ) ->
    PathParts = path_parts(PathInfo),
    State#state{waits=update_waits(PathParts, {kz_json:new(), <<>>}, Waits)
               ,requests=update_requests(PathParts, ReqHeaders, <<>>, QueryString, Requests)
               };
handle_req_update(PathInfo, ReqHeaders, ReqBody, QueryString
                 ,#state{requests=Requests
                        ,waits=Waits
                        }=State
                 ) ->
    PathParts = path_parts(PathInfo),
    lager:info("storing to ~p: ~s", [PathParts, ReqBody]),

    State#state{waits=update_waits(PathParts, {ReqHeaders, ReqBody}, Waits)
               ,requests=update_requests(PathParts, ReqHeaders, ReqBody, QueryString, Requests)
               }.

update_waits(PathParts, Stored, Waits) ->
    {Relays, StillWaiting} =
        lists:splitwith(fun(#wait{wait_path={P, _Fun}}) -> lists:prefix(P, PathParts);
                           (#wait{wait_path=P}) -> lists:prefix(P, PathParts)
                        end
                       ,Waits
                       ),

    _ = relay(Relays, Stored),
    StillWaiting.

-spec handle_cast(any(), state()) -> {'noreply', state()}.
handle_cast(_Msg, State) ->
    {'noreply', State}.

-spec handle_info(any(), state()) -> {'noreply', state()}.
handle_info({'DOWN', MRef, 'process', Pid, _Reason}
           ,#state{waits=Waits}=State
           ) ->
    {'noreply', State#state{waits=[Wait || #wait{from={P, R}}=Wait <- Waits, P =/= Pid, R =/= MRef]}};
handle_info({'EXIT', Pid, _Reason}
           ,#state{waits=Waits}=State
           ) ->
    {'noreply', State#state{waits=[Wait || #wait{from={P, _R}}=Wait <- Waits, P =/= Pid]}};
handle_info({'timeout', TRef, {From, Path}}
           ,#state{waits=Waits}=State
           ) ->
    {Relays, StillWaiting}
        = lists:splitwith(fun(#wait{from=F, wait_ref=T, wait_path=P}) ->
                                  F =:= From
                                      andalso T =:= TRef
                                      andalso (P =:= Path
                                               orelse (is_tuple(P)
                                                       andalso element(1, P) =:= Path
                                                      )
                                              )
                          end
                         ,Waits
                         ),
    _ = relay(Relays, {'error', 'timeout'}),

    {'noreply', State#state{waits=StillWaiting}};
handle_info(_Msg, State) ->
    {'noreply', State}.

-spec relay(waits(), request() | {kz_json:object(), binary()} | {'error', 'timeout'}) -> ['ok' | pid()].
relay(Relays, {'error', _}=Msg) ->
    [begin lager:info("relaying ~p: ~p", [From, Msg]), gen_server:reply(From, Msg) end
     || #wait{from=From} <- Relays
    ];
relay(Relays, {_Headers, _Body}=Msg) ->
    [relay_msg(From, Server, Path, Msg)
     || #wait{from=From, wait_path=Path, server=Server} <- Relays
    ].

relay_msg(From, Server, {Path, Fun}, _Msg) ->
    _P = kz_process:spawn(fun() -> gen_server:reply(From, Fun(Server, Path)) end),
    lager:info("relaying ~p using ~p(~p) in ~p", [From, Fun, Path, _P]);
relay_msg(From, _Server, _Path, Msg) ->
    lager:info("relaying ~p: ~p", [From, Msg]),
    gen_server:reply(From, Msg).

-spec new_wait(kz_term:pid_ref(), kz_json:path() | {kz_json:path(), fun()}, pos_integer()) -> wait().
new_wait(From, Path, TimeoutMs) ->
    TRef = erlang:start_timer(TimeoutMs, self(), {From, Path}),
    #wait{from=From
         ,wait_ref=TRef
         ,wait_path=Path
         ,server=self()
         }.

new_request(PathParts, ReqHeaders, <<ReqBody/binary>>, QueryString) ->
    #request{headers = ReqHeaders
            ,body = ReqBody
            ,path = PathParts
            ,querystring = QueryString
            }.

update_requests(PathParts, ReqHeaders, ReqBody, QueryString, Requests) ->
    case find_path(PathParts, #request.path, Requests) of
        'false' -> [new_request(PathParts, ReqHeaders, ReqBody, QueryString) | Requests];
        #request{body=ReqBody} -> Requests;
        #request{} when ReqBody =:= <<>> -> Requests;
        #request{} ->
            lists:keystore(PathParts
                          ,#request.path
                          ,Requests
                          ,new_request(PathParts, ReqHeaders, ReqBody, QueryString)
                          )
    end.

new_response(<<Path/binary>>, Headers, Body, Responses) ->
    PathParts = path_parts(Path),
    new_response(PathParts, Headers, Body, Responses);
new_response(PathParts, Headers, <<Body/binary>>, Responses) ->
    lager:info("new resp for ~p", [PathParts]),
    [#response{path=PathParts, headers=Headers, body=Body} | Responses].

path_parts(<<Path/binary>>) ->
    lager:info("path parts url: ~s", [Path]),
    binary:split(binary:replace(Path, base_url(Path), <<>>), <<"/">>, ['global', 'trim']);
path_parts(PathParts) when is_list(PathParts) -> PathParts.

%% if the request has come in already (as a POST/PUT) or if explicitly
%% told to respond a certain way (via add_response)
find_request_or_response(Path, Requests, Responses) ->
    PathParts = path_parts(Path),
    case find_path(PathParts, #response.path, Responses) of
        #response{headers=Headers, body=Body}=_Resp ->
            lager:info("found path ~s in response: ~p", [PathParts, _Resp]),
            {Headers, Body};
        'false' ->
            lager:info("no ~p in responses: ~p", [PathParts, Responses]),
            case find_path(PathParts, #request.path, Requests) of
                #request{headers=Headers, body=Body} ->
                    lager:info("path ~p in requests: ~p", [PathParts, Body]),
                    {Headers, Body};
                'false' ->
                    lager:info("path ~p not here", [PathParts]),
                    'undefined'
            end
    end.

-spec find_path(kz_json:path(), pos_integer(), requests() | responses()) ->
          'false' | request() | response().
find_path(PathParts, Index, Records) ->
    lager:info("find ~p at ~p on ~p", [PathParts, Index, Records]),
    case [Record || Record <- Records,
                    lists:prefix(PathParts, element(Index, Record))
         ]
    of
        [] -> 'false';
        [Record|_] -> Record
    end.
