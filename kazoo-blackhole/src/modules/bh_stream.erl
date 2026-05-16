%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2025, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(bh_stream).

-export([init/0
        ,validate/2
        ,bindings/2
        ]).

-include("blackhole.hrl").

-define(ALL, <<"*">>).
-define(STREAM_EVENTS, [<<"start">>
                       ,<<"stop">>
                       ]
       ).
-define(ACCOUNT_BINDING(Event, AccountId, CallId), kapi_pivot:stream_event_routing_key(Event, AccountId, CallId)).
-define(BINDING(Event, CallId), <<"stream.", Event/binary, ".", CallId/binary>>).
-define(BINDINGS
       ,lists:foldr(fun(Event, Acc) -> [?BINDING(Event, <<"{CALL_ID}">>) | Acc] end, [], [?ALL | ?STREAM_EVENTS])
       ).

-spec init() -> any().
init() ->
    init_bindings(),
    _ = blackhole_bindings:bind(<<"blackhole.events.validate.stream">>, ?MODULE, 'validate'),
    blackhole_bindings:bind(<<"blackhole.events.bindings.stream">>, ?MODULE, 'bindings').

init_bindings() ->
    Bindings = ?BINDINGS,
    case kapps_config:set_default(?CONFIG_CAT, [<<"bindings">>, <<"stream">>], Bindings) of
        {'ok', _} -> lager:debug("initialized stream bindings");
        {'error', _E} -> lager:info("failed to initialize stream bindings: ~p", [_E])
    end.

-spec validate(bh_context:context(), map()) -> bh_context:context().
validate(Context, #{keys := [?ALL, _CallId]}) ->
    Context;
validate(Context, #{keys := [Event, _CallId]}) ->
    case lists:member(Event, ?STREAM_EVENTS) of
        'true' -> Context;
        'false' -> bh_context:add_error(Context, <<"event stream.", Event/binary, " not supported">>)
    end;
validate(Context, #{keys := Keys}) ->
    bh_context:add_error(Context, <<"invalid format for stream subscription : ", (kz_binary:join(Keys))/binary>>).

-spec bindings(bh_context:context(), map()) -> map().
bindings(_Context, #{account_id := AccountId
                    ,keys := [Event, CallId]
                    }=Map) ->
    Map#{requested => ?BINDING(Event, CallId)
        ,subscribed => [?ACCOUNT_BINDING(Event, AccountId, CallId)]
        ,listeners => [{'amqp', 'pivot', bind_options(Event, AccountId, CallId)}]
        }.

-spec bind_options(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:proplist().
bind_options(Event, AccountId, CallId) ->
    [{'restrict_to', [{'stream', [{'event', Event}
                                 ,{'account_id', AccountId}
                                 ,{'call_id', CallId}
                                 ]
                      }
                     ]
     }
    ].
