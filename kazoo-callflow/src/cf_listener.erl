%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Listener for route requests that can be fulfilled by Callflows.
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_listener).
-behaviour(gen_listener).

-export([start_link/2]).
-export([init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_info/2
        ,handle_event/3
        ,terminate/2
        ,code_change/3
        ]).

-include("callflow.hrl").

-type state() :: map().

-define(SERVER, ?MODULE).

-define(RESPONDERS, []).

-define(CALLFLOW_HASHED_EXCHANGE, <<"callflow.route">>).

-define(HASHED_EXCHANGE_HASH_HEADER(A), maps:get(hash_header, A, <<"call-id">>)).
-define(HASHED_EXCHANGE_HASH(A), {<<"hash-header">>, 'longstr', ?HASHED_EXCHANGE_HASH_HEADER(A)}).
-define(HASHED_EXCHANGE_ARGS(A), [?HASHED_EXCHANGE_HASH(A)]).
-define(HASHED_EXCHANGE_OPTIONS(A), [{'auto_delete', 'true'}
                                    ,{'arguments', ?HASHED_EXCHANGE_ARGS(A)}
                                    ]).
-define(HASHED_EXCHANGE_ROUTE_BINDING_KEYS, [<<"route.req.audio.*">>
                                            ,<<"route.req.video.*">>
                                            ]).
-define(HASHED_EXCHANGE_ROUTE_BINDING, [{source, ?EXCHANGE_CALLMGR}
                                       ,{routings, ?HASHED_EXCHANGE_ROUTE_BINDING_KEYS}
                                       ]).
-define(HASHED_EXCHANGE_BINDINGS, [{route, ?HASHED_EXCHANGE_ROUTE_BINDING}]).
-define(HASHED_EXCHANGE(A), [{'name', ?CALLFLOW_HASHED_EXCHANGE}
                            ,{'type', <<"x-consistent-hash">>}
                            ,{'options', ?HASHED_EXCHANGE_OPTIONS(A)}
                            ,{'bindings', ?HASHED_EXCHANGE_BINDINGS}
                            ]).
-define(HASHED_ROUTING(A), <<"20">>).
%%-define(HASHED_ROUTING(A), kz_term:to_binary(maps:get(sequence, A, 20) * 5)).
-define(HASHED_BIND(A), [{'exchange', ?HASHED_EXCHANGE(A)}
                        ,{'routing', ?HASHED_ROUTING(A)}
                        ]).
-define(HASHED_BINDINGS(A), [{'bind', ?HASHED_BIND(A)}]).

-define(HASHED_QUEUE_NAME, <<"">>).
-define(HASHED_QUEUE_OPTIONS, []).
-define(HASHED_QUEUE_CONSUME_OPTIONS, []).
-define(HASHED_QUEUE_PARAMS, [{'queue_options', ?HASHED_QUEUE_OPTIONS}
                             ,{'consume_options', ?HASHED_QUEUE_CONSUME_OPTIONS}
                             ]).

-define(SHARED_BINDINGS, [{'route', [{'types', ?RESOURCE_TYPES_HANDLED}
                                    ,{'restrict_to', ['account']}
                                    ]
                          }
                         ]).

-define(SHARED_QUEUE_NAME, <<"callflow_shared_route">>).
-define(SHARED_QUEUE_OPTIONS, [{'exclusive', 'false'}]).
-define(SHARED_QUEUE_CONSUME_OPTIONS, [{'exclusive', 'false'}]).
-define(SHARED_QUEUE_PARAMS, [{'queue_options', ?SHARED_QUEUE_OPTIONS}
                             ,{'consume_options', ?SHARED_QUEUE_CONSUME_OPTIONS}
                             ]).

-define(NODE_BINDINGS, [{'self', []}
                       ,{'dialplan', []}
                       ]).

-define(BINDINGS, [{'route', [{'types', ?RESOURCE_TYPES_HANDLED}
                             ,{'restrict_to', ['account']}
                             ]
                   }
                  ,{'self', []}
                  ,{'dialplan', []}
                  ]).

-define(QUEUE_NAME(I), <<"callflow_route_", I/binary>>).
-define(QUEUE_OPTIONS, [{'exclusive', 'false'}]).
-define(CONSUME_OPTIONS, [{'exclusive', 'false'}]).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Starts the server.
%% @end
%%------------------------------------------------------------------------------
-spec start_link(map(), integer()) -> kz_types:startlink_ret().
start_link(Map, Seq) ->
    gen_listener:start_link(?SERVER, initial_bindings(Map), [Map#{sequence => Seq}]).

initial_bindings(#{instance := Instance, shared := 'false'}) ->
    [{'responders', ?RESPONDERS}
    ,{'bindings', ?BINDINGS}
    ,{'queue_name', ?QUEUE_NAME(Instance)}
    ,{'queue_options', ?QUEUE_OPTIONS}
    ,{'consume_options', ?CONSUME_OPTIONS}
    ];
initial_bindings(#{instance := Instance, shared := 'true'}) ->
    [{'responders', ?RESPONDERS}
    ,{'bindings', ?NODE_BINDINGS}
    ,{'queue_name', ?QUEUE_NAME(Instance)}
    ,{'queue_options', ?QUEUE_OPTIONS}
    ,{'consume_options', ?CONSUME_OPTIONS}
    ].

%%%=============================================================================
%%% gen_listener callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the server.
%% @end
%%------------------------------------------------------------------------------
-spec init(list()) -> {'ok', state()}.
init([#{instance := Instance} = Map]) ->
    {'ok', Map#{instance_queue => ?QUEUE_NAME(Instance)}}.

%%------------------------------------------------------------------------------
%% @doc Handling call messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_call(any(), kz_term:pid_ref(), state()) -> kz_types:handle_call_ret_state(state()).
handle_call(_Msg, _From, State) ->
    {'noreply', State}.

%%------------------------------------------------------------------------------
%% @doc Handling cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_cast(any(), state()) -> kz_types:handle_cast_ret_state(state()).
handle_cast({'gen_listener', {'created_queue', Q}}
           ,#{instance_queue := Q, shared := 'false'} = State
           ) ->
    lager:debug("started instance queue ~s", [Q]),
    {'noreply', State};
handle_cast({'gen_listener', {'created_queue', Q}}
           ,#{instance_queue := Q, shared := 'true', share_type := 'hashed'} = State
           ) ->
    lager:debug("started instance queue ~s, starting hashed shared queue", [Q]),
    gen_server:cast(self(), {'add_queue', ?HASHED_QUEUE_NAME, ?HASHED_QUEUE_PARAMS, ?HASHED_BINDINGS(State)}),
    {'noreply', State};
handle_cast({'gen_listener', {'created_queue', Q}}
           ,#{instance_queue := Q, shared := 'true', share_type := 'queue'} = State
           ) ->
    lager:debug("started instance queue ~s, starting shared queue", [Q]),
    gen_server:cast(self(), {'add_queue', ?SHARED_QUEUE_NAME, ?SHARED_QUEUE_PARAMS, ?SHARED_BINDINGS}),
    {'noreply', State};
handle_cast({'gen_listener', {'is_consuming', _IsConsuming}}, State) ->
    {'noreply', State};
handle_cast({'gen_listener', {'return', JObj, Returned}}, State) ->
    ServerId = kz_api:server_id(JObj),
    lager:debug("returned: ~p", [ServerId]),
    Pid = kapi:decode_pid(ServerId),
    lager:debug("returned: ~p", [Pid]),
    Pid ! {'amqp_return', JObj, Returned},
    {'noreply', State};
handle_cast(_Msg, State) ->
    lager:debug("unhandled cast: ~p", [_Msg]),
    {'noreply', State}.

%%------------------------------------------------------------------------------
%% @doc Handling all non call/cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_info(any(), state()) -> kz_types:handle_info_ret_state(state()).
handle_info({'forward', Msg}, #{queue := Queue}=State) ->
    handle_msg(Msg, [{'queue', Queue}], State),
    {'noreply', State};

handle_info(_Info, State) ->
    lager:info("unhandled message: ~p", [_Info]),
    {'noreply', State}.

%%------------------------------------------------------------------------------
%% @doc Handling AMQP event objects
%% @end
%%------------------------------------------------------------------------------
-spec handle_event(kz_json:object(), kz_term:proplist(), state()) -> gen_listener:handle_event_return().
handle_event(JObj, Props, #{instance_queue := Q} = State) ->
    Msg = kapi:delivery_message(JObj, Props),
    handle_msg(Msg, props:set_value('queue', Q, Props), State).

%%------------------------------------------------------------------------------
%% @doc This function is called by a `gen_listener' when it is about to
%% terminate. It should be the opposite of `Module:init/1' and do any
%% necessary cleaning up. When it returns, the `gen_listener' terminates
%% with Reason. The return value is ignored.
%%
%% @end
%%------------------------------------------------------------------------------
-spec terminate(any(), any()) -> 'ok'.
terminate(_Reason, _State) ->
    lager:info("callflow listener ~p termination", [_Reason]).

%%------------------------------------------------------------------------------
%% @doc Convert process state when code is changed.
%% @end
%%------------------------------------------------------------------------------
-spec code_change(any(), state(), any()) -> {'ok', state()}.
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle_msg(term(), kz_term:proplist(), state()) -> gen_listener:handle_event_return().
handle_msg({_, {'dialplan', 'route_req'}, JObj}, Props, _State) ->
    lager:debug("new route request"),
    %% TODO
    %% if the cf_exe started, monitor and add it to the state (maybe a map)
    %% that will get us the count
    %% that can be used to decide whch instance will provide a pid
    %% instead of the current randomness in cf_listener_sup
    _ = cf_exe_sup:new(JObj, [{'channel', kz_amqp_channel:consumer_channel()} | Props], fun cf_route_req:handle_req/2),
    'ignore';

handle_msg({_, {'callflow', 'resume'}, JObj}, Props, _State) ->
    %% TODO
    %% look above
    _ = cf_exe_sup:new(JObj, [{'channel', kz_amqp_channel:consumer_channel()} | Props], fun cf_route_resume:handle_req/2),
    'ignore';

handle_msg(_Msg, _Props, _State) ->
    lager:debug("unhandled message => ~p", [_Msg]),
    'ignore'.
