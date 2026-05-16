%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2025, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(bh_events).

-export([init/0
        ,event/3
        ,validate/2
        ,subscribe/2
        ,unsubscribe/2
        ,close/1
        ,authorize/2
        ]).

-spec init() -> 'ok'.
init() ->
    _ = blackhole_bindings:bind(<<"blackhole.authorize.subscribe">>, ?MODULE, 'authorize'),
    _ = blackhole_bindings:bind(<<"blackhole.validate.subscribe">>, ?MODULE, 'validate'),
    _ = blackhole_bindings:bind(<<"blackhole.validate.unsubscribe">>, ?MODULE, 'validate'),
    _ = blackhole_bindings:bind(<<"blackhole.command.subscribe">>, ?MODULE, 'subscribe'),
    _ = blackhole_bindings:bind(<<"blackhole.command.unsubscribe">>, ?MODULE, 'unsubscribe'),
    _ = blackhole_bindings:bind(<<"blackhole.session.close">>, ?MODULE, 'close'),
    'ok'.

bindings(Payload) ->
    Bindings = case kz_json:get_ne_binary_value([<<"data">>, <<"binding">>], Payload) of
                   'undefined' -> [];
                   Binding -> [Binding]
               end,
    kz_json:get_list_value([<<"data">>, <<"bindings">>], Payload, Bindings).

account_id(Context, Payload) ->
    AccountId = bh_context:auth_account_id(Context),
    kz_json:get_ne_binary_value([<<"data">>, <<"account_id">>], Payload, AccountId).

-spec authorize(bh_context:context(), kz_json:object()) -> bh_context:context().
authorize(Context, Payload) ->
    AccountId = account_id(Context, Payload),
    Bindings = bindings(Payload),
    authorize(Context, AccountId, Bindings).

authorize(Context, _AccountId, []) -> Context;
authorize(Context, AccountId, [Binding | Bindings]) ->
    Ctx = authorize_binding(Binding, AccountId, Context),
    case bh_context:success(Ctx) of
        'true' -> authorize(Ctx, AccountId, Bindings);
        'false' -> Ctx
    end.

authorize_binding(Binding, AccountId, Context) ->
    [Key | Keys] = binary:split(Binding, <<".">>, ['global']),
    Event = <<"blackhole.events.authorize.", Key/binary>>,
    Map = #{account_id => AccountId
           ,key => Key
           ,keys => Keys
           },
    Res = blackhole_bindings:fold(Event, [Context, Map]),
    validate_result(Context, Res).

-spec validate(bh_context:context(), kz_json:object()) -> bh_context:context().
validate(Context, Payload) ->
    case bindings(Payload) of
        [] -> bh_context:add_error(Context, <<"empty subscription">>);
        Bindings -> validate_subscription(Context, account_id(Context, Payload), Bindings)
    end.

-spec validate_subscription(bh_context:context(), kz_term:ne_binary(), kz_term:ne_binaries()) -> bh_context:context().
validate_subscription(Context, _AccountId, []) -> Context;
validate_subscription(Context, AccountId, [Binding | Bindings]) ->
    Ctx = validate_binding(Context, AccountId, Binding),
    case bh_context:success(Ctx) of
        'true' -> validate_subscription(Ctx, AccountId, Bindings);
        'false' -> Ctx
    end.

validate_binding(Context, AccountId, Binding) ->
    [Key | Keys] = binary:split(Binding, <<".">>, ['global']),
    Event = <<"blackhole.events.validate.", Key/binary>>,
    Map = #{account_id => AccountId
           ,key => Key
           ,keys => Keys
           },
    Res = blackhole_bindings:map(Event, [Context, Map]),
    validate_result(Context, Res).

-spec validate_result(bh_context:context(), kz_term:ne_binaries()) -> bh_context:context().
validate_result(Context, []) -> Context;
validate_result(Context, Res) ->
    case blackhole_bindings:failed(Res) of
        [Ctx | _] -> Ctx;
        [] -> case blackhole_bindings:succeeded(Res) of
                  [] -> Context;
                  [Ctx | _] -> Ctx
              end
    end.

-spec subscribe(bh_context:context(), kz_json:object()) -> bh_context:context().
subscribe(Context, Payload) ->
    AccountId = account_id(Context, Payload),
    Bindings = bindings(Payload),
    case subscribe(Context, AccountId, Bindings) of
        {Ctx, EventBindings} ->
            add_event_bindings(Ctx, EventBindings);
        Ctx ->
            Ctx
    end.

subscribe(Context, AccountId, Bindings) ->
    subscribe(Context, AccountId, Bindings, []).

subscribe(Context, _AccountId, [], Acc) -> {Context, Acc};
subscribe(Context, AccountId, [Binding | Bindings], Acc) ->
    [Key | Keys] = binary:split(Binding, <<".">>, ['global']),
    Event = <<"blackhole.events.bindings.", Key/binary>>,
    Map = #{account_id => AccountId
           ,key => Key
           ,keys => Keys
           },
    MapResults = blackhole_bindings:map(Event, [Context, Map]),
    case blackhole_bindings:succeeded(MapResults) of
        [] ->
            bh_context:add_error(Context, <<"no available subscriptions to requested binding">>);
        EvtBindings ->
            subscribe(Context, AccountId, Bindings, Acc ++ EvtBindings)
    end.

-spec unsubscribe(bh_context:context(), kz_json:object()) -> bh_context:context().
unsubscribe(Context, Payload) ->
    AccountId = account_id(Context, Payload),
    Bindings = bindings(Payload),
    case unsubscribe(Context, AccountId, Bindings) of
        {Ctx, EventBindings} ->
            remove_event_bindings(Ctx, EventBindings);
        Ctx ->
            Ctx
    end.

unsubscribe(Context, AccountId, Bindings) ->
    unsubscribe(Context, AccountId, Bindings, []).

unsubscribe(Context, _AccountId, [], Acc) -> {Context, Acc};
unsubscribe(Context, AccountId, [Binding | Bindings], Acc) ->
    [Key | Keys] = binary:split(Binding, <<".">>, ['global']),
    Event = <<"blackhole.events.bindings.", Key/binary>>,
    Map = #{account_id => AccountId
           ,key => Key
           ,keys => Keys
           },
    MapResults = blackhole_bindings:map(Event, [Context, Map]),
    case blackhole_bindings:succeeded(MapResults) of
        [] ->
            bh_context:add_error(Context, <<"no available subscriptions to requested binding">>);
        EvtBindings ->
            unsubscribe(Context, AccountId, Bindings, Acc ++ EvtBindings)
    end.

-spec event(map(), kz_term:ne_binary(), kz_json:object()) -> 'ok'.
event(Binding, RK, EventJObj) ->
    kz_log:put_callid(EventJObj),
    Name = kz_api:event_name(EventJObj),
    NormJObj = kz_json:normalize_jobj(
                 kz_api:public_fields(EventJObj)
                ),
    blackhole_data_emitter:event(Binding, RK, Name, NormJObj).

add_event_bindings(Context, BindingResults) ->
    {Ctx, Subscribed} = lists:foldl(fun add_event_bindings_fold/2, {Context, []}, BindingResults),
    Data = kz_json:from_list([{<<"subscribed">>, [S || {S, _} <- Subscribed]}
                             ,{<<"subscriptions">>, bh_context:client_bindings(Ctx)}
                             ]),
    bh_context:set_resp_data(Ctx, Data).

add_event_bindings_fold(#{requested := ClientBinding
                         ,subscribed := AMQPBindings
                         ,listeners := Listeners
                         } = Bindings
                       ,{Context, Subs}
                       ) ->
    Module = maps:get('module', Bindings, ?MODULE),
    SessionBindings = bh_context:bindings(Context),
    Subscribe = [{ClientBinding, AMQPBindings}] -- SessionBindings,
    NewListeners = Listeners -- bh_context:listeners(Context),

    lists:foreach(fun(S) -> bh_bind(Context, Module, S) end, Subscribe),
    blackhole_listener:add_bindings(NewListeners),
    Ctx = bh_context:add_listeners(Context, NewListeners),
    {bh_context:set_bindings(Ctx, SessionBindings ++ Subscribe), Subs ++ Subscribe}.

bh_bind(Context, Module, ClientBinding, AMQPBinding) ->
    SessionPid = bh_context:websocket_pid(Context),
    SessionId = bh_context:websocket_session_id(Context),
    Binding =  #{subscribed_key => ClientBinding
                ,subscription_key => AMQPBinding
                ,session_pid => SessionPid
                ,session_id => SessionId
                },
    BHBinding = <<"blackhole.event.", AMQPBinding/binary>>,
    blackhole_bindings:bind(BHBinding, Module, 'event', Binding).

bh_bind(Context, Module, {ClientBinding, AMQPBindings}) ->
    lists:foreach(fun(B) -> bh_bind(Context, Module, ClientBinding, B) end, AMQPBindings).

-spec remove_event_bindings(bh_context:context(), [map(),...]) -> bh_context:context().
remove_event_bindings(Context, BindingResults) ->
    {Ctx, UnSubscribed} = lists:foldl(fun remove_event_bindings_fold/2
                                     ,{Context, []}
                                     ,BindingResults
                                     ),

    Data = kz_json:from_list([{<<"unsubscribed">>, [U || {U, _} <- UnSubscribed]}
                             ,{<<"subscriptions">>, bh_context:client_bindings(Ctx)}
                             ]),
    bh_context:set_resp_data(Ctx, Data).

-spec remove_event_bindings_fold(map(), {bh_context:context(), kz_term:ne_binaries()}) ->
          {bh_context:context(), kz_term:ne_binaries()}.
remove_event_bindings_fold(#{requested := ClientBinding
                            ,subscribed := AMQPBindings
                            ,listeners := Listeners
                            }
                          ,{Context, Subs}
                          ) ->
    SessionBindings = bh_context:bindings(Context),
    Removed = [{ClientBinding, AMQPBindings}],

    bh_unbind(Context, {ClientBinding, AMQPBindings}),
    blackhole_listener:remove_bindings(Listeners),
    Ctx = bh_context:remove_listeners(Context, Listeners),

    {bh_context:set_bindings(Ctx, SessionBindings -- Removed), Subs ++ Removed}.

bh_unbind(Context, ClientBinding, AMQPBinding) ->
    BHBinding = <<"blackhole.event.", AMQPBinding/binary>>,
    SessionPid = bh_context:websocket_pid(Context),
    SessionId = bh_context:websocket_session_id(Context),
    Binding =  #{subscribed_key => ClientBinding
                ,subscription_key => AMQPBinding
                ,session_pid => SessionPid
                ,session_id => SessionId
                },
    blackhole_bindings:unbind(BHBinding, ?MODULE, 'event', Binding).

bh_unbind(Context, {ClientBinding, AMQPBindings}) ->
    lists:foreach(fun(B) -> bh_unbind(Context, ClientBinding, B) end, AMQPBindings).

-spec close(bh_context:context()) -> bh_context:context().
close(Context) ->
    Listeners = bh_context:listeners(Context),
    blackhole_listener:remove_bindings(Listeners),
    Bindings = bh_context:bindings(Context),
    lists:foreach(fun(B) -> bh_unbind(Context, B) end, Bindings),
    Routines = [{fun bh_context:remove_listeners/2, Listeners}
               ,{fun bh_context:remove_bindings/2, Bindings}
               ],
    bh_context:setters(Context, Routines).
