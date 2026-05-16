%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2025, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(blackhole_data_emitter).

-include("blackhole.hrl").

-export([event/4]).
-export([reply/3, reply/4]).
-export([send/2]).

-define(MAX_QUEUED_MESSAGES, kapps_config:get_integer(?CONFIG_CAT, <<"max_queued_messages">>, 50)).

-spec event(map(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> 'ok'.
event(#{subscribed_key := SubscribedKey
       ,subscription_key := SubscriptionKey
       ,session_pid := SessionPid
       }
     ,RK, Name, Data
     ) ->
    Msg = [{<<"action">>, <<"event">>}
          ,{<<"subscribed_key">>, SubscribedKey}
          ,{<<"subscription_key">>, SubscriptionKey}
          ,{<<"name">>, Name}
          ,{<<"routing_key">>, RK}
          ,{<<"data">>, Data}
          ],
    lager:debug("sending event with routing key ~s to session PID ~p", [RK, SessionPid]),
    maybe_send(SessionPid, kz_json:from_list(Msg)).

-spec reply(pid(), kz_term:ne_binary(), kz_json:object()) -> 'ok'.
reply(SessionPid, RequestId, Data) ->
    reply(SessionPid, RequestId, 'undefined', Data).

-spec reply(pid(), kz_term:ne_binary(), kz_term:api_ne_binary(), kz_json:object()) -> 'ok'.
reply(SessionPid, RequestId, Status, Data) ->
    lager:debug("sending reply data: ~s : ~s : ~p", [RequestId, Status, Data]),
    Msg = [{<<"action">>, <<"reply">>}
          ,{<<"request_id">>, RequestId}
          ,{<<"status">>, Status}
          ,{<<"data">>, Data}
          ],
    maybe_send(SessionPid, kz_json:from_list(Msg)).

-spec send(pid(), kz_json:object()) -> 'ok'.
send(SessionPid, Data) ->
    maybe_send(SessionPid, Data).

maybe_send(SessionPid, Data) ->
    maybe_send(SessionPid, Data, process_info(SessionPid, 'message_queue_len')).

maybe_send(SessionPid, Data, {'message_queue_len', QueueLen}) ->
    maybe_send(SessionPid, Data, QueueLen, ?MAX_QUEUED_MESSAGES);
maybe_send(_SessionPid, _Data, 'undefined') ->
    lager:info("failed to find session ~p, dropping data").

maybe_send(SessionPid, _Data, QueueLen, MaxLen) when QueueLen > MaxLen ->
    lager:error("~p queue length ~p (max: ~p), dropping event", [SessionPid, QueueLen, MaxLen]);
maybe_send(SessionPid, Data, _QueueLen, _MaxLen) ->
    SessionPid ! {'send_data', Data},
    'ok'.
