%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2023, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%% @author Peter Defebvre
%%% @author Ben Wann
%%% @author Roman Galeev
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(bh_conference).

-export([init/0
        ,authorize/2
        ,validate/2
        ,bindings/2
        ]).

-include("blackhole.hrl").

-define(CONFERENCE_EVENTS, [<<"*">> | kapi_conference:events()]).

-define(ACCOUNT_BINDING(Event, AccountId, ConferenceId, CallId)
       ,<<"conference.event.",Event/binary,".", AccountId/binary, ".", ConferenceId/binary, ".", CallId/binary>>
       ).

-define(BINDING(Event, ConferenceId, CallId)
       ,<<"conference.event.", Event/binary, ".", ConferenceId/binary, ".", CallId/binary>>
       ).

-define(COMMAND(ConferenceId)
       ,<<"conference.command.", ConferenceId/binary>>
       ).
-define(EVENT_BINDINGS(ConferenceId, CallId)
       ,lists:foldl(fun(E, Acc) -> [?BINDING(E, ConferenceId, CallId) | Acc] end, [], ?CONFERENCE_EVENTS)
       ).
-define(ALL, <<"*">>).


-spec init() -> any().
init() ->
    init_bindings(),
    _ = blackhole_bindings:bind(<<"blackhole.events.authorize.conference">>, ?MODULE, 'authorize'),
    _ = blackhole_bindings:bind(<<"blackhole.events.validate.conference">>, ?MODULE, 'validate'),
    blackhole_bindings:bind(<<"blackhole.events.bindings.conference">>, ?MODULE, 'bindings').

init_bindings() ->
    Bindings = [?COMMAND(<<"{CONFERENCE_ID}">>)
               ] ++ ?EVENT_BINDINGS(<<"{CONFERENCE_ID}">>, <<"{CALL_ID}">>),
    case kapps_config:set_default(?CONFIG_CAT, [<<"bindings">>, <<"conference">>], Bindings) of
        {'ok', _} -> lager:debug("initialized conference bindings");
        {'error', _E} -> lager:info("failed to initialize conference bindings: ~p", [_E])
    end.

-spec authorize(bh_context:context(), map()) -> bh_context:context().
authorize(Context, #{keys := [<<"command">>, ?ALL]}) ->
    case bh_context:is_superduper_admin(Context) of
        'true' -> Context;
        'false' -> bh_context:add_error(Context, <<"unauthorized wildcard for conference id">>)
    end;
authorize(Context, #{keys := [<<"event">>, _, ?ALL, _]}) ->
    case bh_context:is_superduper_admin(Context) of
        'true' -> Context;
        'false' -> bh_context:add_error(Context, <<"unauthorized wildcard for conference id">>)
    end;
authorize(Context, _) -> Context.

-spec validate(bh_context:context(), map()) -> bh_context:context().
validate(Context, #{keys := [<<"command">>, _]}) ->
    Context;
validate(Context, #{keys := [<<"event">>, Event, _, _]}) ->
    case lists:member(Event, ?CONFERENCE_EVENTS) of
        'false' ->
            bh_context:add_error(Context, <<"Unsupported conference event ",Event/binary>>);
        'true' -> Context
    end;
validate(Context, #{keys := Keys}) ->
    bh_context:add_error(Context, <<"invalid format for conference subscription : ", (kz_binary:join(Keys))/binary>>).

-spec bindings(bh_context:context(), map()) -> map().
bindings(_Context, #{account_id := _AccountId
                    ,keys := [<<"command">>, ConferenceId]
                    }=Map) ->
    Requested = ?COMMAND(ConferenceId),
    Subscribed = [?COMMAND(ConferenceId)],
    Listeners = [{'amqp', 'conference', command_binding_options(ConferenceId)}],
    Map#{requested => Requested
        ,subscribed => Subscribed
        ,listeners => Listeners
        };
bindings(_Context, #{account_id := AccountId
                    ,keys := [<<"event">>, Event, ConferenceId, CallId]
                    }=Map) ->
    Requested = ?BINDING(Event, ConferenceId, CallId),
    Subscribed = [?ACCOUNT_BINDING(Event, AccountId, ConferenceId, CallId)],
    Listeners = [{'amqp', 'conference', event_binding_options(Event, AccountId, ConferenceId, CallId)}],
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
-spec command_binding_options(kz_term:ne_binary()) -> kz_term:proplist().
command_binding_options(ConfId) ->
    [{'restrict_to', [{'command', ConfId}]}
    ,'federate'
    ].

-spec event_binding_options(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:proplist().
event_binding_options(Event, AccountId, ConferenceId, CallId) ->
    [{'restrict_to', [{'event', [{'event', Event}
                                ,{'account_id', AccountId}
                                ,{'conference_id', ConferenceId}
                                ,{'call_id', CallId}
                                ]
                      }]
     }
    ,'federate'
    ].
