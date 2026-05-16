%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2025, 2600Hz
%%%
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(webhooks_stream).

-behaviour(gen_webhook).

-export([init/0
        ,bindings_and_responders/0
        ,account_bindings/1
        ,handle_stream/2
        ]).

-include("webhooks.hrl").

-define(ID, kz_term:to_binary(?MODULE)).
-define(HOOK_NAME, <<"stream">>).
-define(TYPE_MODIFIER
       ,kz_json:from_list(
          [{<<"type">>, <<"array">>}
          ,{<<"description">>, <<"A list of Stream event types to handle">>}
          ,{<<"items">>, [<<"all">>, <<"stream_start">>, <<"stream_stop">>]}
          ]
         )
       ).
-define(METADATA
       ,kz_json:from_list(
          [{<<"_id">>, ?ID}
          ,{<<"name">>, <<"Pivot Stream">>}
          ,{<<"description">>, <<"Receive notifications when a call media stream to a Websocket server is started or stopped">>}
          ,{<<"modifiers">>, kz_json:from_list([{<<"type">>, ?TYPE_MODIFIER}])}
          ]
         )
       ).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    webhooks_util:init_metadata(?ID, ?METADATA).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec bindings_and_responders() -> {gen_listener:bindings(), listener_utils:responder_start_params()}.
bindings_and_responders() ->
    Bindings = [{'pivot', [{'restrict_to', [{'stream', []}]}
                          ]
                }
               ],
    Responders = [{{?MODULE, 'handle_stream'}, [{<<"pivot">>, <<"stream_start">>}
                                               ,{<<"pivot">>, <<"stream_stop">>}
                                               ]
                  }
                 ],
    {Bindings, Responders}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec account_bindings(kz_term:ne_binary()) -> gen_listener:bindings().
account_bindings(_AccountId) -> [].

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle_stream(kz_json:object(), kz_term:proplist()) -> 'ok'.
handle_stream(Payload, _Props) ->
    kz_log:put_callid(Payload),

    EventName = kz_api:event_name(Payload),

    'true' = assert_valid(Payload, EventName),
    AccountId = kz_api:account_id(Payload),

    Hooks = [Hook || Hook <- webhooks_util:find_webhooks(?HOOK_NAME, AccountId), match_action_type(Hook, EventName)],
    maybe_handle_stream(Payload, Hooks).

-spec maybe_handle_stream(kz_json:object(), webhooks()) -> 'ok'.
maybe_handle_stream(Payload, []) ->
    AccountId = kz_api:account_id(Payload),
    lager:debug("no hooks to handle ~s for ~s", [kz_api:event_name(Payload), AccountId]);
maybe_handle_stream(Payload, Hooks) ->
    EventName = kz_api:event_name(Payload),
    Event = format_event(EventName, Payload),
    V2Event = format_v2_event(EventName, Payload),
    webhooks_util:fire_hooks(Event, V2Event, Hooks).

-spec assert_valid(kz_json:object(), kz_term:ne_binary()) -> 'true'.
assert_valid(Payload, EventName) ->
    EventDefinition = kapi_pivot:api_definition(EventName),

    Validate = kapi_definition:validate_fun(EventDefinition),
    'true' = Validate(Payload).

-spec match_action_type(webhook(), kz_term:api_binary()) -> boolean().
match_action_type(#webhook{hook_event = ?HOOK_NAME
                          ,custom_data='undefined'
                          }, _EventName) ->
    'true';
match_action_type(#webhook{hook_event = ?HOOK_NAME
                          ,custom_data = CustomData
                          }, EventName) ->
    Type = kz_json:get_ne_binary_value(<<"type">>, CustomData),
    Type =:= EventName
        orelse Type =:= <<"all">>;
match_action_type(#webhook{}=_W, _EventName) ->
    'true'.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec format_event(kz_term:api_ne_binary(), kz_json:object()) -> kz_json:object().
format_event(EventName, Payload) ->
    kz_json:from_list(
      [{<<"event_name">>, EventName}
      ,{<<"account_id">>, kz_api:account_id(Payload)}
      ,{<<"call_id">>, kz_api:call_id(Payload)}
      ,{<<"error_message">>, kz_json:get_ne_binary_value(<<"Error-Message">>, Payload)}
      ,{<<"reason">>, kz_json:get_ne_binary_value(<<"Reason">>, Payload)}
      ,{<<"stream_id">>, kz_json:get_ne_binary_value(<<"Stream-ID">>, Payload)}
      ,{<<"stream_name">>, kz_json:get_ne_binary_value(<<"Stream-Name">>, Payload)}
      ,{<<"timestamp">>, kz_time:now_s()}
      ]).

-spec format_v2_event(kz_term:ne_binary(), kz_call_event:payload()) ->
          kz_json:object().
format_v2_event(EventName, Payload) ->
    Msg = [{<<"action">>, <<"event">>}
          ,{<<"name">>, EventName}
          ,{<<"data">>, format_event('undefined', Payload)}
          ],
    kz_json:from_list(Msg).
