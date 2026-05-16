%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%% Process cdr events and send to configured webhooks
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(webhooks_cdr).

-behaviour(gen_webhook).

-export([init/0
        ,bindings_and_responders/0
        ]).

-export([handle_event/2]).
-export([maybe_handle_cdr/3]).

-include("webhooks.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(ID, kz_term:to_binary(?MODULE)).
-define(HOOK_NAME, <<"cdr">>).
-define(NAME, <<"CDR">>).
-define(DESC, <<"Receive notifications when sms is received">>).

-define(METADATA
       ,kz_json:from_list(
          [{<<"_id">>, ?ID}
          ,{<<"name">>, ?NAME}
          ,{<<"description">>, ?DESC}
          ]
         )
       ).

-spec init() -> 'ok'.
init() ->
    webhooks_util:init_metadata(?ID, ?METADATA).

-spec bindings_and_responders() -> {gen_listener:bindings()
                                   ,listener_utils:responder_start_params()
                                   }.
bindings_and_responders() ->
    {bindings(), responders()}.

-spec bindings() -> gen_listener:bindings().
bindings() ->
    [{'cdr', [{'restrict_to', ['report']}]}].

-spec responders() -> listener_utils:responder_start_params().
responders() ->
    [{{?MODULE, 'handle_event'}
     ,[{?HOOK_NAME, <<"report">>}]
     }
    ].

-spec handle_event(kz_call_event:payload(), kz_term:proplist()) -> 'ok'.
handle_event(CDREvent, _Props) ->
    HookEvent = kz_api:event_category(CDREvent),
    maybe_handle_cdr(kz_call_event:account_id(CDREvent), HookEvent, CDREvent).

-spec maybe_handle_cdr(kz_term:api_ne_binary(), kz_term:ne_binary(), kz_call_event:payload()) -> 'ok'.
maybe_handle_cdr('undefined', _HookEvent, CDREvent) ->
    lager:debug("no account identifiable in event ~p", [CDREvent]);
maybe_handle_cdr(<<AccountId/binary>>, <<HookEvent/binary>>, CDREvent) ->
    lager:debug("evt ~s for ~s", [HookEvent, AccountId]),
    case webhooks_util:find_webhooks(kz_term:to_lower_binary(HookEvent), AccountId) of
        [] -> lager:debug("no hooks to handle ~s for ~s", [HookEvent, AccountId]);
        Hooks ->
            maybe_fire_event(AccountId, HookEvent, CDREvent, Hooks)
    end.

-spec maybe_fire_event(kz_term:ne_binary(), kz_term:ne_binary(), kz_call_event:payload(), webhooks()) -> 'ok'.
maybe_fire_event(AccountId, HookEvent, CDREvent, Hooks) ->
    webhooks_util:fire_hooks(format_event(CDREvent, AccountId, HookEvent)
                            ,format_v2_event(CDREvent, HookEvent)
                            ,Hooks
                            ).

-spec format_event(kz_call_event:payload(), kz_term:api_binary(), kz_term:ne_binary()) ->
          kz_json:object().
format_event(CDREvent, AccountId, HookEvent) ->
    kz_json:set_value(<<"hook_event">>
                     ,kz_term:to_lower_binary(HookEvent)
                     ,base_hook_event(CDREvent, AccountId)
                     ).

-spec base_hook_event(kz_call_event:payload(), kz_term:api_binary()) -> kz_json:object().
base_hook_event(CDREvent, AccountId) ->
    base_hook_event(CDREvent, AccountId, []).

-spec base_hook_event(kz_call_event:payload(), kz_term:api_binary(), kz_term:proplist()) -> kz_json:object().
base_hook_event(CDREvent, AccountId, Acc) ->
    WasGlobal = kz_term:is_true(ccv(CDREvent, <<"Global-Resource">>)),

    kz_json:from_list(
      [{<<"account_id">>, ccv(CDREvent, <<"Account-ID">>, AccountId)}
      ,{<<"authorizing_id">>, kz_call_event:authorizing_id(CDREvent)}
      ,{<<"authorizing_type">>, kz_call_event:authorizing_type(CDREvent)}
      ,{<<"call_direction">>, kz_call_event:call_direction(CDREvent)}
      ,{<<"call_forwarded">>, kz_call_event:is_call_forwarded(CDREvent)}
      ,{<<"call_id">>, kz_call_event:call_id(CDREvent)}
      ,{<<"callee_id_name">>, kz_call_event:callee_id_name(CDREvent)}
      ,{<<"callee_id_number">>, kz_call_event:callee_id_number(CDREvent)}
      ,{<<"caller_id_name">>, kz_call_event:caller_id_name(CDREvent)}
      ,{<<"caller_id_number">>, kz_call_event:caller_id_number(CDREvent)}
      ,{<<"emergency_resource_used">>, kz_term:is_true(ccv(CDREvent, <<"Emergency-Resource">>))}
      ,{<<"from">>, kz_json:get_value(<<"From">>, CDREvent)}
      ,{<<"is_internal_leg">>, kz_json:is_true(<<"Channel-Is-Loopback">>, CDREvent)}
      ,{<<"local_resource_used">>, (not WasGlobal)}
      ,{<<"other_leg_call_id">>, kz_call_event:other_leg_call_id(CDREvent)}
      ,{<<"owner_id">>, kz_call_event:owner_id(CDREvent)}
      ,{<<"request">>, kz_json:get_value(<<"Request">>, CDREvent)}
      ,{<<"reseller_id">>, kz_services_reseller:get_id(AccountId)}
      ,{<<"timestamp">>, kz_call_event:timestamp(CDREvent)}
      ,{<<"to">>, kz_json:get_value(<<"To">>, CDREvent)}
      | Acc
      ]).

-spec ccv(kz_call_event:payload(), kz_json:key()) ->
          kz_term:api_ne_binary().
ccv(CDREvent, Key) ->
    ccv(CDREvent, Key, 'undefined').

-spec ccv(kz_call_event:payload(), kz_json:key(), Default) ->
          kz_term:ne_binary() | Default.
ccv(CDREvent, Key, Default) ->
    kz_call_event:custom_channel_var(CDREvent, Key, Default).

-spec format_v2_event(kz_call_event:payload(), kz_term:ne_binary()) ->
          kz_json:object().
format_v2_event(CDREvent, HookEvent) ->
    NormJObj = webhooks_util:sanitize_event(CDREvent),
    Msg = [{<<"action">>, <<"event">>}
          ,{<<"name">>, HookEvent}
          ,{<<"data">>, NormJObj}
          ],
    kz_json:from_list(Msg).
