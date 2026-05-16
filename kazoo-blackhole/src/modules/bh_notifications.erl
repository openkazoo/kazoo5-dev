%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2024, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(bh_notifications).

-export([init/0
        ,validate/2
        ,bindings/2
        ]).

-include("blackhole.hrl").

-define(LISTEN_TO
       ,kapps_config:get_ne_binaries(?CONFIG_CAT
                                    ,<<"notification_events">>
                                    ,[<<"missed_call">>]
                                    )
       ).

-define(BINDING_STRING(Category, Name), <<"notifications.", (Category)/binary, ".", (Name)/binary>>).

-spec init() -> any().
init() ->
    init_bindings(),
    _ = blackhole_bindings:bind(<<"blackhole.events.validate.notifications">>, ?MODULE, 'validate'),
    blackhole_bindings:bind(<<"blackhole.events.bindings.notifications">>, ?MODULE, 'bindings').

-spec init_bindings() -> 'ok'.
init_bindings() ->
    DefaultBindings = [kapi_definition:binding(kapi_notifications:api_definition(Evt)) || Evt <- ?LISTEN_TO],
    case kapps_config:set_default(?CONFIG_CAT, [<<"bindings">>, <<"notifications">>], DefaultBindings) of
        {'ok', _} -> lager:debug("initialized notifications bindings");
        {'error', _E} -> lager:info("failed to initialize notifications bindings: ~p", [_E])
    end.

-spec validate(bh_context:context(), map()) -> bh_context:context().
validate(Context, #{keys := [Category, <<"*">>]}) ->
    case lists:member(Category, get_categories(?LISTEN_TO)) of
        'true' -> Context;
        'false' -> bh_context:add_error(Context, <<"event category ", Category/binary, " not supported">>)
    end;
validate(Context, #{keys := [Category, Event]}) ->
    case lists:member(Event, ?LISTEN_TO)
        andalso Category =:= get_category(Event)
    of
        'true' -> Context;
        'false' -> bh_context:add_error(Context, <<"event ", Category/binary, ".", Event/binary, " not supported">>)
    end.

-spec bindings(bh_context:context(), map()) -> map().
bindings(_Context
        ,#{account_id := _AccountId
          ,keys := [Category, <<"*">>]
          }=Map
        ) ->
    Requested = ?BINDING_STRING(Category, <<"*">>),
    Subscribed = category_bindings(Category, ?LISTEN_TO),
    Listeners = [{'amqp', 'notifications', notifications_category_bind_options(Category)}],
    Map#{requested => Requested
        ,subscribed => Subscribed
        ,listeners => Listeners
        };
bindings(_Context
        ,#{account_id := _AccountId
          ,keys := [_Category, Event]
          }=Map
        ) ->
    Requested = kapi_definition:binding(kapi_notifications:api_definition(Event)),
    Subscribed = [kapi_definition:binding(kapi_notifications:api_definition(Event))],
    Listeners = [{'amqp', 'notifications', notifications_bind_options(Event)}],
    Map#{requested => Requested
        ,subscribed => Subscribed
        ,listeners => Listeners
        }.

%% Helpers

-spec get_category(kz_term:ne_binary()) -> kz_term:ne_binary().
get_category(Event) ->
    kapi_definition:category(kapi_notifications:api_definition(Event)).

-spec notifications_bind_options(kz_term:ne_binary()) -> [{atom(), [atom()]}].
notifications_bind_options(Event) ->
    [{'restrict_to', [kapi_definition:restrict_to(kapi_notifications:api_definition(Event))]}
    ,'federate'
    ].

-spec notifications_category_bind_options(kz_term:ne_binary()) -> [{atom(), [atom()]}].
notifications_category_bind_options(Category) ->
    [{'restrict_to', category_restrict_to(Category, ?LISTEN_TO)}
    ,'federate'
    ].

%%------------------------------------------------------------------------------
%% @doc Get categories related to the provided events
%% @end
%%------------------------------------------------------------------------------
get_categories(Events) ->
    SetOfCats = lists:foldl(fun add_event_definition/2, sets:new(), Events),
    sets:to_list(SetOfCats).

add_event_definition(Event, SetOfCats) ->
    Definition = kapi_notifications:api_definition(Event),
    add_definition_category(Definition, SetOfCats).

add_definition_category(Definition, SetOfCats) ->
    sets:add_element(kapi_definition:category(Definition), SetOfCats).

%%------------------------------------------------------------------------------
%% @doc Get category bindings associated with given notification events
%% @end
%%------------------------------------------------------------------------------
-spec category_bindings(kz_term:ne_binary(), kz_term:ne_binaries()) -> kz_term:api_ne_binaries().
category_bindings(Category, Events) ->
    [kapi_definition:binding(Definition)
     || Event <- Events,
        Definition <- [kapi_notifications:api_definition(Event)],
        kapi_definition:category(Definition) =:= Category
    ].

%%------------------------------------------------------------------------------
%% @doc Get category restrict to associated with given notification events
%% @end
%%------------------------------------------------------------------------------
-spec category_restrict_to(kz_term:ne_binary(), kz_term:ne_binaries()) -> kz_term:api_atoms().
category_restrict_to(Category, Events) ->
    [kapi_definition:restrict_to(Definition)
     || Event <- Events,
        Definition <- [kapi_notifications:api_definition(Event)],
        kapi_definition:category(Definition) =:= Category
    ].
