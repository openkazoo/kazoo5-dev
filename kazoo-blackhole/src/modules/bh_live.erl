%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(bh_live).

-export([init/0
        ,authorize/2
        ,validate/2
        ,bindings/2
        ]).

-include("blackhole.hrl").

-define(CATEGORY, <<"conference">>).

-define(LIVE_EVENTS
       ,[<<"array">>
        ,<<"broadcast">>
        ,<<"caption">>
        ,<<"info">>
        ,<<"chat">>
        ]).

-define(ACCOUNT_BINDING(AccountId, Event, Id)
       ,kz_binary:join(["live", ?CATEGORY, AccountId, Event, Id], <<".">>)
       ).

-define(BINDING(Event, Id)
       ,kz_binary:join(["live", ?CATEGORY, Event, Id], <<".">>)
       ).

-define(EVENT_BINDINGS(Id)
       ,lists:foldl(fun(Event, Acc) -> [?BINDING(Event, Id) | Acc] end, [], ?LIVE_EVENTS)
       ).

-define(ALL, <<"*">>).

-define(LIVE_SCOPES(C), [<<"live:all">>, <<"live:", C/binary>>]).

-spec init() -> any().
init() ->
    init_bindings(),
    _ = blackhole_bindings:bind(<<"blackhole.events.authorize.live">>, ?MODULE, 'authorize'),
    _ = blackhole_bindings:bind(<<"blackhole.events.validate.live">>, ?MODULE, 'validate'),
    _ = blackhole_bindings:bind(<<"blackhole.events.bindings.live">>, ?MODULE, 'bindings').

init_bindings() ->
    Bindings = ?EVENT_BINDINGS(<<"*">>),
    case kapps_config:set_default(?CONFIG_CAT, [<<"bindings">>, <<"live">>], Bindings) of
        {'ok', _} -> lager:debug("initialized live bindings");
        {'error', _E} -> lager:info("failed to initialize conference bindings: ~p", [_E])
    end.

-spec authorize(bh_context:context(), map()) -> bh_context:context().
authorize(Context, _) -> Context.

-spec validate(bh_context:context(), map()) -> bh_context:context().
validate(Context, #{keys := [?CATEGORY, ?ALL, _]}) ->
    Context;
validate(Context, #{keys := [?CATEGORY, Event, _]}) ->
    case lists:member(Event, ?LIVE_EVENTS) of
        'false' ->
            bh_context:add_error(Context, <<"Unsupported live event ",Event/binary>>);
        'true' -> Context
    end;
validate(Context, #{keys := Keys}) ->
    bh_context:add_error(Context, <<"invalid format for live subscription : ", (kz_binary:join(Keys))/binary>>).

-spec bindings(bh_context:context(), map()) -> map().
bindings(_Context, #{account_id := AccountId
                    ,keys := [?CATEGORY, Event, Id]
                    }=Map) ->
    Requested = ?BINDING(Event, Id),
    Subscribed = [?ACCOUNT_BINDING(AccountId, Event, Id)],
    Listeners = [{'amqp', 'bind', event_binding_options(AccountId, Event, Id)}],
    Map#{requested => Requested
        ,subscribed => Subscribed
        ,listeners => Listeners
        }.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec event_binding_options(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:proplist().
event_binding_options(AccountId, Event, Id) ->
    [{'exchange', [{'name', <<"live">>}, {'type', <<"topic">>}]}
    ,{'routing', kz_binary:join(["live", ?CATEGORY, AccountId, Event, Id], <<".">>)}
    ,'federate'
    ].
