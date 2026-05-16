%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_task).

-behaviour(gen_server).

-export([start_link/3]).
-export([init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_info/2
        ,terminate/2
        ,code_change/3
        ]).

-include("callflow.hrl").

-define(SERVER, ?MODULE).

-record(state, {call :: kapps_call:call()
               ,callback :: fun()
                               ,args :: list()
                               ,pid :: kz_term:api_pid()
                               ,ref :: kz_term:api_reference()
                               ,queue :: kz_term:api_binary()
                               }).
-type state() :: #state{}.

%%------------------------------------------------------------------------------
%% @doc Starts the listener and binds to the call channel destroy events.
%% @end
%%------------------------------------------------------------------------------
-spec start_link(kapps_call:call(), fun(), list()) -> kz_types:startlink_ret().
start_link(Call, Fun, Args) ->
    gen_server:start_link(?SERVER, [Call, Fun, Args], []).


%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the listener, and sends the init hook.
%% @end
%%------------------------------------------------------------------------------
-spec init([fun()]) -> {'ok', state()}.
init([Call, Callback, Args]) ->
    _ = kapps_call:put_callid(Call),
    kz_events:bind_call_id(kapps_call:call_id_direct(Call)),
    Channel = kapps_call:kvs_fetch('consumer_channel', Call),
    Queue = kapi:decode_queue(kapps_call:controller_queue(Call)),
    ControllerQ = kapi:encode_pid(Queue, self()),
    kz_amqp_channel:consumer_channel(Channel),
    lager:debug("started event listener for cf_task"),
    gen_server:cast(self(), 'launch_task'),
    {'ok', #state{call=kapps_call:set_controller_queue(ControllerQ, Call)
                 ,callback=Callback
                 ,args=Args
                 }}.

%%------------------------------------------------------------------------------
%% @doc Handle call messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_call(any(), any(), state()) ->
          {'reply', {'error', 'not_implemented'}, state()}.
handle_call(_Request, _From, State) ->
    {'reply', {'error', 'not_implemented'}, State}.

%%------------------------------------------------------------------------------
%% @doc Handle cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_cast(any(), state()) ->
          {'noreply', state()} |
          {'stop', 'normal', state()}.
handle_cast('launch_task', State) ->
    {'noreply', launch_task(State)};
handle_cast('stop', State) ->
    {'stop', 'normal', State};
handle_cast(_Msg, State) ->
    lager:debug("unhandled cast: ~p", [_Msg]),
    {'noreply', State}.

%%------------------------------------------------------------------------------
%% @doc Handling all non call/cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_info(any(), state()) -> {'noreply', state()}.
handle_info({'DOWN', Ref, 'process', Pid, Reason}
           ,#state{ref=Ref
                  ,pid=Pid
                  }=State
           ) ->
    lager:debug("task in ~p (~p) exited with reason: ~p", [Pid, Ref, Reason]),
    {'stop', 'normal', State};
handle_info({'kapi', _}, #state{pid='undefined'} = State) ->
    {'noreply', State};
handle_info({'kapi', {_, _, JObj}}, #state{pid=Pid} = State) ->
    kapps_call_command:relay_event(Pid, JObj),
    {'noreply', State};
handle_info(Info, State) ->
    lager:debug("unhandled message: ~p", [Info]),
    {'noreply', State}.

%%------------------------------------------------------------------------------
%% @doc This function is called by a `gen_server' when it is about to
%% terminate. It should be the opposite of `Module:init/1' and do any
%% necessary cleaning up. When it returns, the `gen_server' terminates
%% with Reason. The return value is ignored.
%% @end
%%------------------------------------------------------------------------------
-spec terminate(any(), state()) -> any().
terminate(_Reason, _State) ->
    lager:debug("callflow task terminating: ~p", [_Reason]).

%%------------------------------------------------------------------------------
%% @doc Convert process state when code is changed.
%% @end
%%------------------------------------------------------------------------------
-spec code_change(any(), state(), any()) -> {'ok', state()}.
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.

-spec launch_task(state()) -> state().
launch_task(#state{call=Call
                  ,callback=Callback
                  ,args=Args
                  }=State
           ) ->
    {Pid, Ref} = kz_process:spawn_monitor(fun task_launched/4, [Call, Callback, Args, self()]),
    lager:debug("watching task execute in ~p (~p)", [Pid, Ref]),
    State#state{pid=Pid, ref=Ref}.

-spec task_launched(kapps_call:call(), fun(), list(), pid()) -> any().
task_launched(Call, Callback, Args, Parent) ->
    kapps_call:put_callid(Call),
    _ = kz_amqp_channel:consumer_pid(Parent),
    Funs = [{fun kapps_call:kvs_store/3, 'consumer_pid', Parent}
           ],
    apply(Callback, Args ++ [kapps_call:exec(Funs, Call)]).
