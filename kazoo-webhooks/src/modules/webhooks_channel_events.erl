%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%% Process channel events and send to configured webhooks
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(webhooks_channel_events).

-behaviour(gen_webhook).

-export([init/0
        ,bindings_and_responders/0
        ]).

-export([handle_event/2]).
-export([maybe_handle_channel_event/3]).

-ifdef(TEST).
-export([is_fireable_hook/2]).
-endif.

-include("webhooks.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(DEFAULT_EVENTS
       ,[{<<"CHANNEL_CREATE">>, <<"This webhook is triggered when a new channel is created">>}
        ,{<<"CHANNEL_ANSWER">>, <<"This webhook is triggered when a channel establishes two-way audio, such as a voicemail box or the called party answering">>}
        ,{<<"CHANNEL_BRIDGE">>, <<"This webhook is triggered when two channels are bridged together, such as two users/devices connected together">>}
        ,{<<"CHANNEL_DESTROY">>, <<"This webhook is triggered when a channel is destroyed, usually as a result of a hangup">>}

        ,{<<"CHANNEL_HOLD">>, <<"This webhook is triggered when an established call gets put on hold">>}
        ,{<<"CHANNEL_UNHOLD">>, <<"This webhook is triggered when an established call gets taken off hold">>}
        ]
       ).

-define(EVENTS
       ,kapps_config:get_json(?APP_NAME, <<"channel_events">>, kz_json:from_list(?DEFAULT_EVENTS))
       ).

-spec init() -> 'ok'.
init() ->
    kz_json:foreach(fun init_event/1, ?EVENTS).

init_event({EventName, Description}) ->
    Id = event_id(EventName),
    webhooks_util:init_metadata(Id, metadata(EventName, Description, Id)).

event_id(EventName) ->
    list_to_binary(["webhooks_", kz_term:to_lower_binary(EventName)]).

metadata(EventName, Description, Id) ->
    kz_json:from_list([{<<"_id">>, Id}
                      ,{<<"name">>, event_name(EventName)}
                      ,{<<"description">>, Description}
                      ]).

event_name(EventName) ->
    [Channel, Event] = binary:split(kz_term:to_lower_binary(EventName), <<"_">>),
    list_to_binary([kz_binary:ucfirst(Channel), " ", kz_binary:ucfirst(Event)]).

-spec bindings_and_responders() -> {gen_listener:bindings()
                                   ,listener_utils:responder_start_params()
                                   }.
bindings_and_responders() ->
    {bindings(), responders()}.

-spec bindings() -> gen_listener:bindings().
bindings() ->
    bindings(?EVENTS).

bindings(JObj) ->
    RestrictTo = kz_json:foldl(fun event_to_binding/3, [], JObj),
    [{'call', [{'restrict_to', RestrictTo}]}].

event_to_binding(EventName, _Desc, Acc) ->
    [kz_term:to_atom(EventName, 'true') | Acc].

-spec responders() -> listener_utils:responder_start_params().
responders() ->
    [{{'webhooks_channel_events', 'handle_event'}
     ,[{<<"call_event">>, <<"*">>}]
     }
    ].

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

event_init_test_() ->
    EventName = <<"CHANNEL_DESTROY">>,

    [?_assertEqual(<<"webhooks_channel_destroy">>, event_id(EventName))
    ,?_assertEqual(<<"Channel Destroy">>, event_name(EventName))
    ].

-endif.


-spec handle_event(kz_call_event:payload(), kz_term:proplist()) -> 'ok'.
handle_event(CallEvent, _Props) ->
    HookEvent = hook_event_name(kz_api:event_name(CallEvent)),
    maybe_handle_channel_event(kz_call_event:account_id(CallEvent), HookEvent, CallEvent).

-spec maybe_handle_channel_event(kz_term:api_ne_binary(), kz_term:ne_binary(), kz_call_event:payload()) -> 'ok'.
maybe_handle_channel_event('undefined', HookEvent, CallEvent) ->
    case find_account_in_event(CallEvent) of
        'undefined' ->
            lager:debug("no account identifiable in event ~p", [CallEvent]);
        <<AccountId/binary>> ->
            maybe_handle_channel_event(AccountId, HookEvent, CallEvent)
    end;
maybe_handle_channel_event(<<AccountId/binary>>, <<HookEvent/binary>>, CallEvent) ->
    lager:debug("evt ~s for ~s", [HookEvent, AccountId]),
    case webhooks_util:find_webhooks(kz_term:to_lower_binary(HookEvent), AccountId) of
        [] -> lager:debug("no hooks to handle ~s for ~s", [HookEvent, AccountId]);
        Hooks ->
            maybe_fire_event(AccountId, HookEvent, CallEvent, Hooks)
    end.

-spec maybe_fire_event(kz_term:ne_binary(), kz_term:ne_binary(), kz_call_event:payload(), webhooks()) -> 'ok'.
maybe_fire_event(AccountId, HookEvent, CallEvent, Hooks) ->
    FireAbleHooks = fireable_hooks(CallEvent, Hooks),
    webhooks_util:fire_hooks(format_event(CallEvent, AccountId, HookEvent)
                            ,format_v2_event(CallEvent, HookEvent)
                            ,FireAbleHooks
                            ).

-spec fireable_hooks(kz_call_event:payload(), webhooks()) -> webhooks().
fireable_hooks(CallEvent, Hooks) ->
    [Hook || #webhook{}=Hook <- Hooks,
             is_fireable_hook(CallEvent, Hook)
    ].

-spec is_fireable_hook(kz_call_event:payload(), webhook()) -> boolean().
is_fireable_hook(_CallEvent, #webhook{include_loopback='true'}) -> 'true';
is_fireable_hook(CallEvent, #webhook{include_loopback='false'
                                    ,id=_Id
                                    }) ->
    case is_loopback_channel_name(kz_call_event:channel_name(CallEvent))
        orelse kz_json:is_true(<<"Channel-Is-Loopback">>, CallEvent, 'false')
    of
        'false' -> 'true';
        'true' ->
            lager:debug("channel is loopback, filtering hook ~s", [_Id]),
            'false'
    end.

-spec is_loopback_channel_name(kz_term:api_ne_binary()) -> boolean().
is_loopback_channel_name(<<"loopback/", _/binary>>=_N) -> 'true';
is_loopback_channel_name(_N) -> 'false'.

-spec hook_event_name(kz_term:ne_binary()) -> kz_term:ne_binary().
hook_event_name(<<"CHANNEL_DISCONNECTED">>) -> <<"CHANNEL_DESTROY">>;
hook_event_name(Event) -> Event.

-spec format_event(kz_call_event:payload(), kz_term:api_binary(), kz_term:ne_binary()) ->
          kz_json:object().
format_event(CallEvent, AccountId, <<"CHANNEL_CREATE">>) ->
    kz_json:set_value(<<"hook_event">>
                     ,<<"channel_create">>
                     ,base_hook_event(CallEvent, AccountId)
                     );
format_event(CallEvent, AccountId, <<"CHANNEL_ANSWER">>) ->
    kz_json:set_value(<<"hook_event">>
                     ,<<"channel_answer">>
                     ,base_hook_event(CallEvent, AccountId)
                     );
format_event(CallEvent, AccountId, <<"CHANNEL_HOLD">>) ->
    kz_json:set_value(<<"hook_event">>
                     ,<<"channel_hold">>
                     ,base_hook_event(CallEvent, AccountId)
                     );
format_event(CallEvent, AccountId, <<"CHANNEL_UNHOLD">>) ->
    kz_json:set_value(<<"hook_event">>
                     ,<<"channel_unhold">>
                     ,base_hook_event(CallEvent, AccountId)
                     );
format_event(CallEvent, AccountId, <<"CHANNEL_BRIDGE">>) ->
    base_hook_event(CallEvent
                   ,AccountId
                   ,[{<<"hook_event">>, <<"channel_bridge">>}
                    ,{<<"original_number">>, ccv(CallEvent, <<"Original-Number">>)}
                    ,{<<"other_leg_destination_number">>, kz_call_event:other_leg_destination_number(CallEvent)}
                    ]
                   );
format_event(CallEvent, AccountId, <<"CHANNEL_DESTROY">>) ->
    base_hook_event(CallEvent
                   ,AccountId
                   ,[{<<"hook_event">>, <<"channel_destroy">>}
                    ,{<<"hangup_cause">>, kz_call_event:hangup_cause(CallEvent)}
                    ,{<<"hangup_code">>, kz_call_event:hangup_code(CallEvent)}
                    ,{<<"duration_seconds">>, kz_call_event:duration_seconds(CallEvent)}
                    ,{<<"ringing_seconds">>, kz_call_event:ringing_seconds(CallEvent)}
                    ,{<<"billing_seconds">>, kz_call_event:billing_seconds(CallEvent)}
                    ]
                   );
format_event(CallEvent, AccountId, HookEvent) ->
    kz_json:set_value(<<"hook_event">>
                     ,kz_term:to_lower_binary(HookEvent)
                     ,base_hook_event(CallEvent, AccountId)
                     ).

-spec base_hook_event(kz_call_event:payload(), kz_term:api_binary()) -> kz_json:object().
base_hook_event(CallEvent, AccountId) ->
    base_hook_event(CallEvent, AccountId, []).

-spec base_hook_event(kz_call_event:payload(), kz_term:api_binary(), kz_term:proplist()) -> kz_json:object().
base_hook_event(CallEvent, AccountId, Acc) ->
    WasGlobal = kz_term:is_true(ccv(CallEvent, <<"Global-Resource">>)),

    kz_json:from_list(
      [{<<"account_id">>, ccv(CallEvent, <<"Account-ID">>, AccountId)}
      ,{<<"authorizing_id">>, kz_call_event:authorizing_id(CallEvent)}
      ,{<<"authorizing_type">>, kz_call_event:authorizing_type(CallEvent)}
      ,{<<"call_direction">>, kz_call_event:call_direction(CallEvent)}
      ,{<<"call_forwarded">>, kz_call_event:is_call_forwarded(CallEvent)}
      ,{<<"call_id">>, kz_call_event:call_id(CallEvent)}
      ,{<<"callee_id_name">>, kz_call_event:callee_id_name(CallEvent)}
      ,{<<"callee_id_number">>, kz_call_event:callee_id_number(CallEvent)}
      ,{<<"caller_id_name">>, kz_call_event:caller_id_name(CallEvent)}
      ,{<<"caller_id_number">>, kz_call_event:caller_id_number(CallEvent)}
      ,{<<"custom_channel_vars">>, non_reserved_ccvs(CallEvent)}
      ,{<<"custom_application_vars">>, cavs(CallEvent)}
      ,{<<"custom_sip_headers">>, kz_call_event:custom_sip_headers(CallEvent)}
      ,{<<"emergency_resource_used">>, kz_term:is_true(ccv(CallEvent, <<"Emergency-Resource">>))}
      ,{<<"from">>, kz_json:get_value(<<"From">>, CallEvent)}
      ,{<<"inception">>, kz_json:get_value(<<"Inception">>, CallEvent)}
      ,{<<"local_resource_id">>, resource_used(WasGlobal, CallEvent)}
      ,{<<"local_resource_used">>, (not WasGlobal)}
      ,{<<"is_internal_leg">>, kz_json:is_true(<<"Channel-Is-Loopback">>, CallEvent)}
      ,{<<"other_leg_call_id">>, kz_call_event:other_leg_call_id(CallEvent)}
      ,{<<"owner_id">>, kz_call_event:owner_id(CallEvent)}
      ,{<<"request">>, kz_json:get_value(<<"Request">>, CallEvent)}
      ,{<<"reseller_id">>, kz_services_reseller:get_id(AccountId)}
      ,{<<"timestamp">>, kz_call_event:timestamp(CallEvent)}
      ,{<<"to">>, kz_json:get_value(<<"To">>, CallEvent)}
      | Acc
      ]).

-spec resource_used(boolean(), kz_call_event:payload()) -> kz_term:api_binary().
resource_used('true', _CallEvent) -> 'undefined';
resource_used('false', CallEvent) -> ccv(CallEvent, <<"Resource-ID">>).

-spec ccv(kz_call_event:payload(), kz_json:key()) ->
          kz_term:api_ne_binary().
ccv(CallEvent, Key) ->
    ccv(CallEvent, Key, 'undefined').

-spec ccv(kz_call_event:payload(), kz_json:key(), Default) ->
          kz_term:ne_binary() | Default.
ccv(CallEvent, Key, Default) ->
    kz_call_event:custom_channel_var(CallEvent, Key, Default).

-spec non_reserved_ccvs(kz_call_event:payload()) -> kz_term:api_object().
non_reserved_ccvs(CallEvent) ->
    CCVs = kz_call_event:custom_channel_vars(CallEvent, kz_json:new()),
    non_reserved_ccvs(CCVs, kapps_config:get_ne_binaries(<<"call_command">>, <<"reserved_ccv_keys">>)).

-spec non_reserved_ccvs(kz_json:object(), kz_term:api_ne_binaries()) -> kz_term:api_object().
non_reserved_ccvs(_CCVs, 'undefined') -> 'undefined';
non_reserved_ccvs(CCVs, Keys) ->
    kz_json:filter(fun({K, _}) -> not lists:member(K, Keys) end, CCVs).

-spec cavs(kz_call_event:payload()) -> kz_term:api_object().
cavs(CallEvent) -> kz_call_event:custom_application_vars(CallEvent).

-spec format_v2_event(kz_call_event:payload(), kz_term:ne_binary()) ->
          kz_json:object().
format_v2_event(CallEvent, HookEvent) ->
    NormJObj = webhooks_util:sanitize_event(CallEvent),
    Msg = [{<<"action">>, <<"event">>}
          ,{<<"name">>, HookEvent}
          ,{<<"data">>, NormJObj}
          ],
    kz_json:from_list(Msg).

-spec find_account_in_event(kz_call_event:payload()) -> kz_term:api_ne_binary().
find_account_in_event(CallEvent) ->
    Finders = [{fun account_id_from_sip_uri/1
               ,kz_json:get_ne_binary_value(<<"Request">>, CallEvent)
               }
              ,{fun account_id_from_sip_uri/1
               ,kz_json:get_ne_binary_value(<<"To">>, CallEvent)
               }
              ],
    find_account(Finders).

-spec find_account([{fun(), kz_term:api_ne_binary()}]) -> kz_term:api_ne_binary().
find_account([]) -> 'undefined';
find_account([{FinderFun, FinderValue} | Finders]) ->
    case FinderFun(FinderValue) of
        'undefined' -> find_account(Finders);
        AccountId -> AccountId
    end.

-spec account_id_from_sip_uri(kz_term:api_ne_binary()) -> kz_term:api_ne_binary().
account_id_from_sip_uri('undefined') -> 'undefined';
account_id_from_sip_uri(Request) ->
    case ersip_uri:parse(<<"sip:", Request/binary>>) of
        {'error', _} -> 'undefined';
        {'ok', URI} ->
            account_id_from_sip_realm(ersip_uri:host(URI))
    end.

-spec account_id_from_sip_realm(ersip_host:host() | kz_term:ne_binary()) -> kz_term:api_ne_binary().
account_id_from_sip_realm({'hostname', Realm}) ->
    account_id_from_sip_realm(Realm);
account_id_from_sip_realm(<<Realm/binary>>) ->
    ViewOptions = [{'key', kz_term:to_lower_binary(Realm)}],
    case kz_datamgr:get_results(?KZ_ACCOUNTS_DB, <<"accounts/listing_by_realm">>, ViewOptions) of
        {'ok', [ViewResult]} ->
            lager:debug("found account id by realm: ~s", [Realm]),
            kz_doc:id(ViewResult);
        _ -> 'undefined'
    end;
account_id_from_sip_realm(_Realm) -> 'undefined'.
