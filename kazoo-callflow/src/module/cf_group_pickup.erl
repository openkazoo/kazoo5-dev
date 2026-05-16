%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2013-2023, 2600Hz
%%% @doc Pickup a call in the specified group.
%%%
%%% <h4>Data options:</h4>
%%% <dl>
%%%   <dt>`approved_device_id'</dt>
%%%   <dd>Device ID.</dd>
%%%
%%%   <dt>`approved_user_id'</dt>
%%%   <dd>User ID.</dd>
%%%
%%%   <dt>`approved_group_id'</dt>
%%%   <dd>Group ID.</dd>
%%% </dl>
%%%
%%% One of the three, `group_id', `user_id' or `owner_id', must be defined on
%%% the data payload. Preference is given by most restrictive option set,
%%% so `device_id' is checked for first, then `user_id', and finally `group_id'.
%%%
%%% `device_id' will only steal a channel currently ringing that device
%%% `user_id' will only steal a channel currently ringing any of the user's devices*.
%%% `group_id' will steal a channel from any devices or users in a group*.
%%%
%%%  * No guarantees on which if multiple inbound calls are ringing.
%%%
%%%
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_group_pickup).

-behaviour(gen_cf_action).

-include("callflow.hrl").

-export([handle/2]).

-type acc_channels() :: {kz_json:objects(), kz_json:objects()}.

%%------------------------------------------------------------------------------
%% @doc Entry point for this module sends an arbitrary response back to the
%% call originator.
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> any().
handle(Data, Call) ->
    _ = case maybe_allowed_to_intercept(Data, Call) of
            'true' ->
                case find_sip_endpoints(Data, Call) of
                    [] -> no_users_in_group(Call);
                    DeviceIds -> connect_to_ringing_channel(DeviceIds, Call)
                end;
            'false' -> no_permission_to_intercept(Call)
        end,
    cf_exe:stop(Call).

-spec maybe_allowed_to_intercept(kz_json:object(), kapps_call:call()) -> boolean().
maybe_allowed_to_intercept(Data, Call) ->
    case kz_json:get_ne_binary_value(<<"approved_device_id">>, Data) of
        'undefined' ->
            case kz_json:get_ne_binary_value(<<"approved_user_id">>, Data) of
                'undefined' ->
                    case kz_json:get_ne_binary_value(<<"approved_group_id">>, Data) of
                        'undefined' -> 'true';
                        GroupId -> maybe_belongs_to_group(GroupId, Call)
                    end;
                UserId -> maybe_belongs_to_user(UserId, Call)
            end;
        DeviceId ->
            %% Compare approved device_id with calling one
            DeviceId == kapps_call:authorizing_id(Call)
    end.

-spec maybe_belongs_to_user(kz_term:ne_binary(), kapps_call:call()) -> boolean().
maybe_belongs_to_user(UserId, Call) ->
    lists:member(kapps_call:authorizing_id(Call), find_user_endpoints([UserId],[],Call)).

-spec maybe_belongs_to_group(kz_term:ne_binary(), kapps_call:call()) -> boolean().
maybe_belongs_to_group(GroupId, Call) ->
    lists:member(kapps_call:authorizing_id(Call), find_group_endpoints(GroupId, Call)).

-spec connect_to_ringing_channel(kz_term:ne_binaries(), kapps_call:call()) -> 'ok'.
connect_to_ringing_channel(DeviceIds, Call) ->
    _ = case find_channels(DeviceIds) of
            [] -> no_channels_ringing(Call);
            Channels -> connect_to_a_channel(Channels, Call)
        end,
    'ok'.

-spec connect_to_a_channel(kz_json:objects(), kapps_call:call()) -> 'ok'.
connect_to_a_channel(Channels, Call) ->
    MyUUID = kapps_call:call_id(Call),
    MyMediaServer = kapps_call:switch_nodename(Call),

    lager:debug("looking for channels on my node ~s that aren't me", [MyMediaServer]),

    case sort_channels(Channels, MyUUID, MyMediaServer) of
        {[], []} ->
            lager:debug("no channels available to pickup"),
            no_channels_ringing(Call);
        {[], [RemoteChannel|_Remote]} ->
            lager:debug("no unanswered calls on my media server, trying ~s", [channel_uuid(RemoteChannel)]),
            intercept_call(RemoteChannel, Call);
        {[LocalChannel|_Local], _} ->
            lager:debug("found a call (~s) on my media server", [channel_uuid(LocalChannel)]),
            intercept_call(LocalChannel, Call)
    end.

-spec sort_channels(kz_json:objects(), kz_term:ne_binary(), kz_term:ne_binary()) -> acc_channels().
sort_channels(Channels, MyUUID, MyMediaServer) ->
    sort_channels(Channels, MyUUID, MyMediaServer, {[], []}).

-spec sort_channels(kz_json:objects(), kz_term:ne_binary(), kz_term:ne_binary(), acc_channels()) -> acc_channels().
sort_channels([], _MyUUID, _MyMediaServer, Acc) -> Acc;
sort_channels([Channel|Channels], MyUUID, MyMediaServer, Acc) ->
    lager:debug("channel: c: ~s a: ~s n: ~s oleg: ~s", [kz_json:get_ne_binary_value(<<"uuid">>, Channel)
                                                       ,kz_json:is_true(<<"answered">>, Channel)
                                                       ,kz_json:get_ne_binary_value(<<"node">>, Channel)
                                                       ,kz_json:get_ne_binary_value(<<"other_leg">>, Channel)
                                                       ]),
    case channel_is_answered(Channel) of
        'true' ->
            sort_channels(Channels, MyUUID, MyMediaServer, Acc);
        'false' ->
            sort_channels(Channels, MyUUID, MyMediaServer, maybe_add_unanswered_leg(MyUUID, MyMediaServer, Acc, Channel))
    end.

-spec maybe_add_unanswered_leg(kz_term:ne_binary(), kz_term:ne_binary(), acc_channels(), kz_json:object()) -> acc_channels().
maybe_add_unanswered_leg(MyUUID, MyMediaServer, Acc, Channel) ->
    maybe_add_unanswered_leg(MyUUID, MyMediaServer, channel_uuid(Channel), Acc, Channel).

-spec maybe_add_unanswered_leg(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), acc_channels(), kz_json:object()) -> acc_channels().
maybe_add_unanswered_leg(MyUUID, _MyMediaServer, MyUUID, Acc, _Channel) -> Acc;
maybe_add_unanswered_leg(_MyUUID, MyMediaServer, _UUID, {Local, Remote}, Channel) ->
    case channel_node(Channel) of
        MyMediaServer ->
            {[Channel | Local], Remote};
        _OtherMediaServer ->
            {Local, [Channel | Remote]}
    end.

-spec channel_interaction_id(kz_json:object()) -> kz_term:api_ne_binary().
channel_interaction_id(Channel) ->
    kz_json:get_ne_binary_value(<<"interaction_id">>, Channel).

-spec channel_node(kz_json:object()) -> kz_term:api_ne_binary().
channel_node(Channel) ->
    kz_json:get_ne_binary_value(<<"node">>, Channel).

-spec channel_uuid(kz_json:object()) -> kz_term:api_ne_binary().
channel_uuid(Channel) ->
    kz_json:get_ne_binary_value(<<"uuid">>, Channel).

-spec channel_is_answered(kz_json:object()) -> boolean().
channel_is_answered(Channel) ->
    kz_json:is_true(<<"answered">>, Channel).

-spec intercept_call(kz_json:object(), kapps_call:call()) -> 'ok'.
intercept_call(Channel, Call0) ->
    Call = cf_util:maybe_start_recording_to(Call0, <<"onnet">>),
    UUID = channel_uuid(Channel),
    kapps_call_command:set(kz_json:from_list([{<<?CALL_INTERACTION_ID>>, channel_interaction_id(Channel)}]), Call),
    _ = kapps_call_command:send_command(pickup_cmd(UUID), Call),
    case wait_for_pickup(Call) of
        {'error', _E} ->
            lager:debug("failed to pickup ~s: ~p", [UUID, _E]);
        'ok' ->
            lager:debug("call picked up"),
            _ = kapps_call_command:wait_for_hangup(),
            lager:debug("hangup recv")
    end.

-spec pickup_cmd(kz_term:ne_binary()) -> kz_term:proplist().
pickup_cmd(TargetCallId) ->
    [{<<"Application-Name">>, <<"call_pickup">>}
    ,{<<"Target-Call-ID">>, TargetCallId}
    ,{<<"Unbridged-Only">>, 'true'}
    ].

-spec wait_for_pickup(kapps_call:call()) ->
          'ok' |
          {'error', 'failed'} |
          {'error', 'timeout'}.
wait_for_pickup(Call) ->
    case kapps_call_command:receive_event(10 * ?MILLISECONDS_IN_SECOND) of
        {'ok', Evt} ->
            pickup_event(Call, kz_api:event_type(Evt), Evt);
        {'error', 'timeout'}=E ->
            lager:debug("timed out"),
            E
    end.

-spec pickup_event(kapps_call:call(), {kz_term:ne_binary(), kz_term:ne_binary()}, kz_json:object()) ->
          {'error', 'failed' | 'timeout'} |
          'ok'.
pickup_event(_Call, {<<"error">>, <<"dialplan">>}, Evt) ->
    lager:debug("error in dialplan: ~s", [kz_json:get_ne_binary_value(<<"Error-Message">>, Evt)]),
    {'error', 'failed'};
pickup_event(Call, {<<"call_event">>,<<"CHANNEL_BRIDGE">>}, Event) ->
    publish_usurp(Call, Event),
    lager:debug("channel bridged to ~s", [kz_json:get_ne_binary_value(<<"Other-Leg-Call-ID">>, Event)]);
pickup_event(Call, _Type, _Evt) ->
    lager:debug("unhandled evt ~p", [_Type]),
    wait_for_pickup(Call).

publish_usurp(Call, Event) ->
    CallId = kz_json:get_ne_binary_value(<<"Other-Leg-Call-ID">>, Event),
    FetchId = kapps_call:fetch_id(Call),
    Usurp = [{<<"Call-ID">>, CallId}
            ,{<<"Fetch-ID">>, FetchId}
            ,{<<"Reason">>, <<"intercepted">>}
            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
            ],
    lager:debug("sending control usurp for fetch-id ~s(~s)", [FetchId, CallId]),
    cf_exe:amqp_send(Call, Usurp, fun(P) -> kapi_call:publish_usurp_control(CallId, P) end).

-spec find_channels(kz_term:ne_binaries()) -> kz_json:objects().
find_channels(DeviceIds) ->
    lager:debug("finding channels for devices ids ~p", [DeviceIds]),
    Req = [{<<"Authorizing-IDs">>, DeviceIds}
          ,{<<"Active-Only">>, 'false'}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    case kz_amqp_worker:call_collect(Req
                                    ,fun kapi_call:publish_query_user_channels_req/1
                                    ,{'ecallmgr', 'true'}
                                    )
    of
        {'error', _E} ->
            lager:debug("failed to get channels: ~p", [_E]),
            [];
        {_, JObjs} ->
            channels_from_replies(JObjs)
    end.

channels_from_replies(JObjs) ->
    Channels = lists:foldl(fun channels_from_replies/2, [], JObjs),
    lists:filter(fun filter_outbound_channels/1, Channels).

channels_from_replies(JObj, Channels) ->
    kz_json:get_value(<<"Channels">>, JObj, []) ++ Channels.

-spec filter_outbound_channels(kz_json:object()) -> boolean().
filter_outbound_channels(JObj) ->
    kz_json:get_ne_binary_value(<<"direction">>, JObj) =:= <<"outbound">>.

-spec find_sip_endpoints(kz_json:object(), kapps_call:call()) ->
          kz_term:ne_binaries().
find_sip_endpoints(Data, Call) ->
    case kz_json:get_ne_binary_value(<<"device_id">>, Data) of
        'undefined' ->
            case kz_json:get_ne_binary_value(<<"user_id">>, Data) of
                'undefined' ->
                    find_sip_users(kz_json:get_ne_binary_value(<<"group_id">>, Data), Call);
                UserId -> find_user_endpoints([UserId], [], Call)
            end;
        DeviceId -> [DeviceId]
    end.

-spec find_sip_users(kz_term:api_binary(), kapps_call:call()) -> kz_term:ne_binaries().
find_sip_users(GroupId, Call) when is_binary(GroupId) ->
    find_group_endpoints(GroupId, Call).

-spec find_group_endpoints(kz_term:ne_binary(), kapps_call:call()) -> kz_term:ne_binaries().
find_group_endpoints(GroupId, Call) ->
    GroupsJObj = kz_attributes:groups(Call),
    case [kz_json:get_value(<<"value">>, JObj)
          || JObj <- GroupsJObj,
             kz_doc:id(JObj) =:= GroupId
         ]
    of
        [] -> [];
        [GroupEndpoints] ->
            Ids = kz_json:get_keys(GroupEndpoints),
            find_endpoints(Ids, GroupEndpoints, Call)
    end.

-spec find_endpoints(kz_term:ne_binaries(), kz_json:object(), kapps_call:call()) ->
          kz_term:ne_binaries().
find_endpoints(Ids, GroupEndpoints, Call) ->
    {DeviceIds, UserIds} =
        lists:partition(fun(Id) ->
                                kz_json:get_ne_binary_value([Id, <<"type">>], GroupEndpoints) =:= <<"device">>
                        end, Ids),
    find_user_endpoints(UserIds, lists:sort(DeviceIds), Call).

-spec find_user_endpoints(kz_term:ne_binaries(), kz_term:ne_binaries(), kapps_call:call()) ->
          kz_term:ne_binaries().
find_user_endpoints([], DeviceIds, _) -> DeviceIds;
find_user_endpoints(UserIds, DeviceIds, Call) ->
    UserDeviceIds = kz_attributes:owned_by(UserIds, <<"device">>, Call),
    lists:merge(lists:sort(UserDeviceIds), DeviceIds).

-spec no_users_in_group(kapps_call:call()) -> any().
no_users_in_group(Call) ->
    kapps_call_command:answer(Call),
    kapps_call_command:b_play(<<"system_media/pickup-no_users">>, Call).

-spec no_channels_ringing(kapps_call:call()) -> any().
no_channels_ringing(Call) ->
    kapps_call_command:answer(Call),
    kapps_call_command:b_play(<<"system_media/pickup-no_channels">>, Call).

-spec no_permission_to_intercept(kapps_call:call()) -> any().
%% TODO: please convert to system_media file (say is not consistent on deployments)
no_permission_to_intercept(Call) ->
    kapps_call_command:answer(Call),
    kapps_call_command:b_say(<<"you have no permission to intercept this call">>, Call).
