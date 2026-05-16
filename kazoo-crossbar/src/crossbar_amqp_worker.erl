%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2018-2026, 2600Hz
%%% @doc AMQP Event Publisher
%%% @author Luis Azedo
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(crossbar_amqp_worker).
-behaviour(gen_listener).

%% API
-export([publish/2]).
-export([call/2, call/3, call/4]).
-export([collect/2, collect/3, collect/4]).

%% START
-export([start_link/0]).

%% gen_listener callbacks
-export([init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_event/2
        ,handle_info/2
        ,terminate/2
        ,code_change/3
        ]).

-include("crossbar.hrl").

-include_lib("kazoo_amqp/include/kz_api.hrl").

-define(BINDINGS, [{'self', []}]).
-define(QUEUE_NAME, <<>>).
-define(QUEUE_OPTIONS, []).
-define(CONSUME_OPTIONS, []).

-define(ARGS, [{'bindings', ?BINDINGS}
              ,{'queue_name', ?QUEUE_NAME}
              ,{'queue_options', ?QUEUE_OPTIONS}
              ,{'consume_options', ?CONSUME_OPTIONS}
              ,{'calling_application', ?APP}
              ]).

-type state() :: map().
-type publish_fun() :: fun((kz_term:api_terms()) -> any()) | fun(() -> 'ok').
-type validate_fun() :: fun((kz_term:api_terms()) -> boolean()).

-type collect_until_acc() :: any().

-type collect_until_acc_fun() :: fun((kz_json:objects(), collect_until_acc()) -> boolean() | {boolean(), collect_until_acc()}).
-type collect_until_fun() :: fun((kz_json:objects()) -> boolean()) |
                             collect_until_acc_fun() |
                             {collect_until_acc_fun(), collect_until_acc()}.

-type whapp() :: atom() | kz_term:ne_binary().

-type collect_until() :: collect_until_fun() |
                         whapp() |
                         {whapp(), validate_fun() | boolean()} | %% {Whapp, VFun | IncludeFederated}
                         {whapp(), validate_fun(), boolean()} |  %% {Whapp, VFun, IncludeFederated}
                         {whapp(), boolean(), boolean()} |       %% {Whapp, IncludeFederated, IsShared}
                         {whapp(), validate_fun(), boolean(), boolean()}. %% {Whapp, VFun, IncludeFederated, IsShared}
-type timeout_or_until() :: timeout() | collect_until().

-type publish_return() :: ok | {error, no_server}.

-type call_return() :: {'ok', kz_json:object()} |
                       {'returned', kz_json:object(), kz_json:object()} |
                       {'timeout', kz_json:objects()} |
                       {'error', any()}.

-type collect_return() :: {'ok', kz_json:object() | kz_json:objects()} |
                          {'returned', kz_json:object(), kz_json:object()} |
                          {'timeout', kz_json:objects()} |
                          {'error', any()}.


-export_type([publish_fun/0
             ,publish_return/0
             ,call_return/0
             ]).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Starts the server.
%% @end
%%------------------------------------------------------------------------------

-spec start_link() -> kz_types:startlink_ret().
start_link() ->
    gen_listener:start_link({local, ?MODULE}, ?MODULE, ?ARGS, []).


-spec publish(kz_term:api_terms(), publish_fun()) -> publish_return().
publish(Req, PubFun) ->
    publish(Req, PubFun, self()).

-spec publish(kz_term:api_terms(), publish_fun(), pid()) -> publish_return().
publish(Req, PubFun, Caller) ->
    case erlang:whereis(?MODULE) of
        undefined -> {error, no_server};
        Pid -> gen_listener:cast(Pid, {publish, {Req, PubFun}, Caller})
    end.

-spec call(kz_term:api_terms(), publish_fun()) -> call_return().
call(Req, PubFun) ->
    call(Req, PubFun, fun kz_term:always_true/1).

-spec call(kz_term:api_terms(), publish_fun(), validate_fun()) -> call_return().
call(Req, PubFun, VFun) ->
    call(Req, PubFun, VFun, default_timeout()).

-spec call(kz_term:api_terms(), publish_fun(), validate_fun(), timeout()) -> call_return().
call(Req, PubFun, VFun, Timeout) ->
    case erlang:whereis(?MODULE) of
        undefined ->
            {error, no_server};
        Pid ->
            {MsgId, Props} = ensure_msg_id(to_proplist(Req)),
            gen_listener:cast(Pid, {publish, {Props, PubFun}, self()}),
            Context = #{msg_id => MsgId, start_time => kz_time:start_time(), timeout => Timeout, vfun => VFun},
            handle_call_reply(Context)
    end.

handle_call_reply(#{timeout := Timeout, msg_id := MsgId} = Context) ->
    receive
        {kapi, {_, _, JObj}} -> handle_call_reply_msg(Context, JObj);
        {amqp_publish, {ok, MsgId}} -> handle_call_reply(Context);
        {amqp_publish, {ok, OtherMsgId}} ->
            lager:error("msg-id not the same ~s / ~s", [MsgId, OtherMsgId]),
            handle_call_reply(Context);
        {amqp_publish, {error, _Err} = Error, _Payload} -> Error;
        {amqp_worker, {return, Reason}} -> {error, Reason};
        {amqp_worker, Other} -> Other
    after
        Timeout ->
            case maps:get(deferred, Context, undefined) of
                undefined -> {error, timeout};
                Deferred -> {ok, Deferred}
            end
    end.

handle_call_reply_msg(Context, JObj) ->
    handle_call_reply_msg(Context, reply_context(JObj), JObj).

reply_context(JObj) ->
    #{msg_id => kz_api:msg_id(JObj)
     ,is_deferred => is_deferred_reply(JObj)
     }.

is_deferred_reply(JObj) ->
    kz_json:is_true(<<"Defer-Response">>, JObj).

handle_call_reply_msg(#{msg_id := MsgId, vfun := VFun} = Context, #{msg_id := MsgId, is_deferred := IsDeferred}, JObj) ->
    case VFun(JObj) of
        true when IsDeferred ->
            lager:debug("deferred response for msg id ~s, waiting for primary response", [kz_api:msg_id(JObj)]),
            handle_call_reply(Context#{deferred => JObj});
        false when IsDeferred ->
            lager:debug("ignoring invalid resp as it was deferred"),
            handle_call_reply(Context#{deferred => JObj});
        true ->
            lager:debug("response for msg id ~s took ~b micro to return", [kz_api:msg_id(JObj), kz_time:elapsed_us(maps:get(start_time, Context))]),
            {ok, JObj};
        false ->
            lager:debug("response failed validator, waiting for more responses"),
            handle_call_reply(Context)
    end;
handle_call_reply_msg(#{msg_id := MsgId} = Context, #{msg_id := OtherMsgId}, _JObj) ->
    lager:error("msg-id not the same ~s / ~s", [MsgId, OtherMsgId]),
    handle_call_reply(Context).

-spec collect(kz_term:api_terms(), publish_fun()) -> collect_return().
collect(Req, PubFun) ->
    collect(Req, PubFun, default_timeout()).

-spec collect(kz_term:api_terms(), publish_fun(), timeout_or_until()) -> collect_return().
collect(Req, PubFun, UntilFun) when is_function(UntilFun) ->
    collect(Req, PubFun, UntilFun, default_timeout());
collect(Req, PubFun, Whapp) when is_atom(Whapp); is_binary(Whapp) ->
    collect(Req, PubFun, Whapp, default_timeout());
collect(Req, PubFun, {_, _}=Until) ->
    collect(Req, PubFun, Until, default_timeout());
collect(Req, PubFun, {_, _, _}=Until) ->
    collect(Req, PubFun, Until, default_timeout());
collect(Req, PubFun, {_, _, _, _}=Until) ->
    collect(Req, PubFun, Until, default_timeout());
collect(Req, PubFun, Timeout) ->
    collect(Req, PubFun, collect_until_timeout(), Timeout).

-spec collect(kz_term:api_terms(), publish_fun(), collect_until(), timeout()) -> collect_return().
collect(_Req, _PubFun, 'undefined', _Timeout) ->
    lager:debug("no VFun, no responses"),
    {'ok', []};
collect(Req, PubFun, {Whapp, IncludeFederated}, Timeout)
  when (is_atom(Whapp)
        orelse is_binary(Whapp)
       )
       andalso is_boolean(IncludeFederated) ->
    CollectFromWhapp = collect_from_whapp(Whapp, IncludeFederated),
    collect(Req, PubFun, CollectFromWhapp, Timeout);
collect(Req, PubFun, {Whapp, VFun}, Timeout)
  when (is_atom(Whapp)
        orelse is_binary(Whapp)
       )
       andalso is_function(VFun) ->
    CollectFromWhapp = collect_from_whapp_or_validate(Whapp, VFun),
    collect(Req, PubFun, CollectFromWhapp, Timeout);
collect(Req, PubFun, {Whapp, IncludeFederated, IsShared}, Timeout)
  when (is_atom(Whapp)
        orelse is_binary(Whapp)
       )
       andalso is_boolean(IncludeFederated)
       andalso is_boolean(IsShared) ->
    CollectFromWhapp = collect_from_whapp(Whapp, IncludeFederated, IsShared),
    collect(Req, PubFun, CollectFromWhapp, Timeout);
collect(Req, PubFun, {Whapp, VFun, IncludeFederated}, Timeout)
  when (is_atom(Whapp)
        orelse is_binary(Whapp)
       )
       andalso is_function(VFun)
       andalso is_boolean(IncludeFederated) ->
    CollectFromWhapp = collect_from_whapp_or_validate(Whapp, VFun, IncludeFederated),
    collect(Req, PubFun, CollectFromWhapp, Timeout);
collect(Req, PubFun, {Whapp, VFun, IncludeFederated, IsShared}, Timeout)
  when (is_atom(Whapp)
        orelse is_binary(Whapp)
       )
       andalso is_function(VFun)
       andalso is_boolean(IncludeFederated)
       andalso is_boolean(IsShared) ->
    CollectFromWhapp = collect_from_whapp_or_validate(Whapp, VFun, IncludeFederated, IsShared),
    collect(Req, PubFun, CollectFromWhapp, Timeout);
collect(Req, PubFun, Whapp, Timeout)
  when is_atom(Whapp)
       orelse is_binary(Whapp) ->
    collect(Req, PubFun, collect_from_whapp(Whapp), Timeout);
collect(Req, PubFun, VFun, Timeout) ->
    case erlang:whereis(?MODULE) of
        undefined ->
            {error, no_server};
        Pid ->
            {MsgId, Props} = ensure_msg_id(to_proplist(Req)),
            gen_listener:cast(Pid, {publish, {Props, PubFun}, self()}),
            Context = setup_collect_context(MsgId, Timeout, VFun),
            handle_collect_reply(Context)
    end.

setup_collect_context(MsgId, Timeout, {UntilFun, Acc}) ->
    maps:put(acc, Acc, setup_collect_context(MsgId, Timeout, UntilFun));
setup_collect_context(MsgId, Timeout, VFun) when is_function(VFun) ->
    #{msg_id => MsgId
     ,start_time => kz_time:start_time()
     ,responses => []
     ,vfun => {erlang:fun_info(VFun, arity), VFun}
     ,timeout => Timeout
     }.

handle_collect_reply(#{timeout := Timeout, msg_id := MsgId} = Context) ->
    receive
        {kapi, {_, _, JObj}} ->
            case handle_collect(kz_api:msg_id(JObj), JObj, Context) of
                {ok, Value} -> {ok, Value};
                ignore -> handle_collect_reply(Context);
                {collect, Ctx} -> handle_collect_reply(Ctx)
            end;
        {amqp_publish, {ok, MsgId}} -> handle_collect_reply(Context);
        {amqp_publish, {ok, OtherMsgId}} ->
            lager:error("msg-id not the same ~s / ~s", [MsgId, OtherMsgId]),
            handle_collect_reply(Context);
        {amqp_publish, {error, _Err} = Error, _Payload} -> Error;
        {amqp_worker, {return, Reason}} -> {error, Reason};
        {amqp_worker, Other} -> Other
    after
        Timeout -> {error, timeout}
    end.

handle_collect(MsgId, JObj, #{msg_id := MsgId
                             ,vfun := {{arity, 2}, VFun}
                             ,responses := Resps
                             ,acc := Acc
                             ,start_time := StartTime
                             } = Context) ->
    Responses = [JObj | Resps],
    try VFun(Responses, Acc) of
        true ->
            lager:debug("responses have apparently met the criteria for the client, returning"),
            lager:debug("response for msg id ~s took ~bμs to return"
                       ,[MsgId, kz_time:elapsed_us(StartTime)]
                       ),
            {ok, Responses};
        {true, Final} ->
            lager:debug("responses have apparently met the criteria for the client, returning"),
            lager:debug("response for msg id ~s took ~bμs to return"
                       ,[MsgId, kz_time:elapsed_us(StartTime)]
                       ),
            {ok, Final};
        false ->
            {collect, Context#{responses => Responses}};
        {false, Acc0} ->
            {collect, Context#{responses => Responses, acc => Acc0}}
    catch
        _E:_R ->
            lager:warning("supplied until_fun crashed: ~s: ~p", [_E, _R]),
            lager:debug("pretending like until_fun returned false"),
            {collect, Context#{responses => Responses}}
    end;
handle_collect(MsgId, JObj, #{msg_id := MsgId
                             ,vfun := {{arity, 1}, VFun}
                             ,responses := Resps
                             ,start_time := StartTime
                             } = Context) ->
    Responses = [JObj | Resps],
    try VFun(Responses) of
        true ->
            lager:debug("responses have apparently met the criteria for the client, returning"),
            lager:debug("response for msg id ~s took ~bμs to return"
                       ,[MsgId, kz_time:elapsed_us(StartTime)]
                       ),
            {ok, Responses};
        false ->
            {collect, Context#{responses => Responses}}
    catch
        _E:_R ->
            lager:warning("supplied until_fun crashed: ~s: ~p", [_E, _R]),
            lager:debug("pretending like until_fun returned false"),
            {collect, Context#{responses => Responses}}
    end;
handle_collect(_MsgId, _JObj, _Context) -> ignore.

-spec collect_until_timeout() -> collect_until_fun().
collect_until_timeout() -> fun kz_term:always_false/1.

-spec collect_from_whapp(kz_term:text()) -> undefined | collect_until_fun().
collect_from_whapp(Whapp) ->
    collect_from_whapp(Whapp, 'false').

-spec collect_from_whapp(kz_term:text(), boolean()) -> undefined | collect_until_fun().
collect_from_whapp(Whapp, IncludeFederated) ->
    collect_from_whapp(Whapp, IncludeFederated, false).

-spec collect_from_whapp(kz_term:text(), boolean(), boolean()) -> undefined | collect_until_fun().
collect_from_whapp(Whapp, IncludeFederated, IsShared) ->
    Count = case {IncludeFederated, IsShared} of
                {true, true} -> kz_nodes:whapp_zone_count(Whapp); %% Get from {0,1} whapp instance per zone
                {false, true} -> 1; %% Get from one whapp instance
                _ -> kz_nodes:whapp_count(Whapp, IncludeFederated) %% Get from all instances, either local or federated
            end,
    lager:debug("attempting to collect ~p responses from ~s", [Count, Whapp]),
    count_fun(Count).

-spec count_fun(non_neg_integer()) -> undefined | collect_until_fun().
count_fun(0) -> undefined;
count_fun(Count) ->
    fun(Responses) -> length(Responses) >= Count end.

-spec collect_from_whapp_or_validate(kz_term:text(), validate_fun()) -> collect_until_fun().
collect_from_whapp_or_validate(Whapp, VFun) ->
    collect_from_whapp_or_validate(Whapp, VFun, false).

-spec collect_from_whapp_or_validate(kz_term:text(),validate_fun(), boolean()) -> collect_until_fun().
collect_from_whapp_or_validate(Whapp, VFun, IncludeFederated) ->
    collect_from_whapp_or_validate(Whapp, VFun, IncludeFederated, false).

-spec collect_from_whapp_or_validate(kz_term:text(),validate_fun(), boolean(), boolean()) -> collect_until_fun().
collect_from_whapp_or_validate(Whapp, VFun, true, true) ->
    Count = kz_nodes:whapp_zone_count(Whapp),
    lager:debug("attempting to collect ~p responses from ~s or the first valid", [Count, Whapp]),
    collect_or_validate_fun(VFun, Count);
collect_from_whapp_or_validate(Whapp, VFun, false, true) ->
    Count = 1,
    lager:debug("attempting to collect ~p responses from ~s or the first valid", [Count, Whapp]),
    collect_or_validate_fun(VFun, Count);
collect_from_whapp_or_validate(Whapp, VFun, IncludeFederated, false) ->
    Count = kz_nodes:whapp_count(Whapp, IncludeFederated),
    lager:debug("attempting to collect ~p responses from ~s or the first valid", [Count, Whapp]),
    collect_or_validate_fun(VFun, Count).

-spec collect_or_validate_fun(validate_fun(), pos_integer()) -> collect_until_fun().
collect_or_validate_fun(VFun, 0) ->
    fun([Response|_]) -> VFun(Response) end;
collect_or_validate_fun(VFun, Count) ->
    fun([Response|_]=Responses) ->
            length(Responses) >= Count
                orelse VFun(Response)
    end.

-spec to_proplist(kz_term:proplist() | kz_json:object()) -> kz_term:proplist().
to_proplist(Req) ->
    case kz_json:is_json_object(Req) of
        true -> kz_json:to_proplist(Req);
        false -> Req
    end.

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the server.
%% @end
%%------------------------------------------------------------------------------
-spec init([]) -> {ok, map()}.
init([]) ->
    {ok, #{is_consuming => false
          ,flow_active => true
          ,pending => queue:new()
          }}.

%%------------------------------------------------------------------------------
%% @doc Handling call messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_call(any(), kz_term:pid_ref(), state()) -> kz_types:handle_call_ret_state(state()).
handle_call(_Request, _From, State) ->
    {'reply', {'error', 'not_implemented'}, State}.

%%------------------------------------------------------------------------------
%% @doc Handling cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_cast(any(), state()) -> kz_types:handle_cast_ret_state(state()).
handle_cast({publish, {Req, PublishFun}, Caller}, #{is_consuming := false} = State) ->
    lager:warning("is_consuming is false, publish failed for ~p (~p) from ~p", [Req, PublishFun, Caller]),
    Caller ! {amqp_worker, {return, not_ready}},
    {noreply, State};
handle_cast({publish, {Req, PublishFun}, Caller}, #{flow_active := false} = State) ->
    lager:warning("flow_active is false, publish failed for ~p (~p) from ~p", [Req, PublishFun, Caller]),
    Caller ! {amqp_worker, {return, flow_inactive}},
    {noreply, State};
handle_cast({publish, {Req, PublishFun}, Caller}, #{is_consuming := true, publish := Fun, queue := Queue} = State) ->
    _ = kz_process:spawn(Fun, [set_server_id(Req, Queue, Caller), PublishFun, Caller]),
    {noreply, State};
handle_cast({gen_listener, {created_queue, Q}}, State) ->
    {noreply, maps:put(queue, Q, State)};
handle_cast({gen_listener,{is_consuming, true}}, State) ->
    {noreply, State#{publish => publish_fun(), is_consuming => true}};
handle_cast({gen_listener,{is_consuming, false}}, State) ->
    {noreply, maps:put(is_consuming, false, maps:without([publish, queue], State))};
handle_cast({gen_listener,{channel_flow_control, Active}}, State) ->
    lager:info("channel flow is ~s", [Active]),
    {noreply, maps:put(flow_active, Active, State)};
handle_cast({gen_listener,{return, Payload, Detail}}, State) ->
    handle_return(Payload, Detail),
    {noreply, State};
handle_cast(_Msg, State) ->
    lager:debug("unhandled cast: ~p", [_Msg]),
    {'noreply', State}.

%%------------------------------------------------------------------------------
%% @doc Handling all non call/cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_info(any(), state()) -> kz_types:handle_info_ret_state(state()).
handle_info(_Info, State) ->
    lager:debug("unhandled message: ~p", [_Info]),
    {'noreply', State}.


%%------------------------------------------------------------------------------
%% @doc This function is called by a `gen_server' when it is about to
%% terminate. It should be the opposite of `Module:init/1' and do any
%% necessary cleaning up. When it returns, the `gen_server' terminates
%% with Reason. The return value is ignored.
%%
%% @end
%%------------------------------------------------------------------------------
-spec terminate(any(), state()) -> 'ok'.
terminate('shutdown', _State) -> 'ok';
terminate(_Reason, _State) ->
    lager:debug("amqp worker terminating: ~p", [_Reason]).

%%------------------------------------------------------------------------------
%% @doc Convert process state when code is changed.
%% @end
%%------------------------------------------------------------------------------
-spec code_change(any(), state(), any()) -> {'ok', state()}.
code_change(_OldVsn, #{is_consuming := true} = State, _Extra) ->
    lager:debug("creating new publish fun"),
    {ok, State#{publish => publish_fun()}};
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.


-spec handle_event(kz_json:object(), state()) -> gen_listener:handle_event_return().
handle_event(_Event, _State) -> {'reply', []}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

publish_fun() ->
    ConsumerChannel = kz_amqp_channel:consumer_channel(),
    ConsumerPID = kz_amqp_channel:consumer_pid(),
    fun(Req, PublishFun, Caller) ->
            kz_amqp_channel:consumer_channel(ConsumerChannel),
            kz_amqp_channel:consumer_pid(ConsumerPID),
            kz_amqp_channel:channel_publish_method(cast),
            kz_log:put_callid(Req),
            try PublishFun(Req) of
                ok -> Caller ! {amqp_publish, {ok, kz_api:msg_id(Req)}};
                {error, _E}=Err -> Caller ! {amqp_publish, Err, Req};
                Other ->
                    lager:error("publisher fun returned ~p instead of 'ok'", [Other]),
                    Caller ! {amqp_publish, {error, Other}, Req}
            catch
                _E:R:ST ->
                    lager:error("error when publishing: ~p:~p", [_E, R]),
                    kz_log:log_stacktrace(ST),
                    Caller ! {amqp_publish, {error, R}, Req}
            end
    end.

-spec ensure_msg_id(kz_term:proplist()) -> {kz_term:ne_binary(), kz_term:proplist()}.
ensure_msg_id(Props) ->
    NewProps = props:insert_value(?KEY_MSG_ID, kz_binary:rand_uuid(), Props),
    {props:get_ne_binary_value(?KEY_MSG_ID, NewProps), NewProps}.

set_server_id(Req, Queue, Caller) ->
    props:set_value(?KEY_SERVER_ID, kapi:encode_pid(Queue, Caller), Req).

-spec default_timeout() -> 2000.
default_timeout() -> 2 * ?MILLISECONDS_IN_SECOND.

-spec handle_return(kz_json:object(), kz_json:object()) -> ok.
handle_return(Payload, Detail) ->
    handle_return(kapi:decode_pid(kz_api:server_id(Payload)), Payload, Detail).

-spec handle_return(pid() | undefined, kz_json:object(), kz_json:object()) -> ok.
handle_return(undefined, _Payload, _Detail) -> ok;
handle_return(Pid, Payload, Detail) ->
    Pid ! {amqp_worker, {returned, Payload, Detail}},
    ok.
