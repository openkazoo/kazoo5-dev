%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc
%%% @author Luis Azedo
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(tf_util).

-include("doodle.hrl").

-export([build_im_endpoint/3
        ,get_im_endpoint_ids/2, get_im_endpoint_ids/3
        ,delivery_status/1
        ]).

-type build_error() :: 'endpoint_disabled' | 'do_not_disturb'.
-type delivery_status() :: 'delivered' | 'failed'.

-export_type([build_error/0
             ,delivery_status/0
             ]).

-define(SIP_MSG_DEVICES, [<<"sip_device">>, <<"softphone">>]).

-spec build_im_endpoint(kz_json:object(), kz_json:object(), kapps_im:im()) -> {'ok', kz_json:objects()} | {'error', build_error()}.
build_im_endpoint(Endpoint, Properties, Im) ->
    case should_create_endpoint(Endpoint, Properties, Im) of
        'ok' -> {'ok', create_im_endpoints(Endpoint, Properties, Im)};
        {'error', _}=E -> E
    end.

-spec should_create_endpoint(kz_json:object(), kz_json:object(), kapps_im:im()) -> 'ok' | {'error', build_error()}.
should_create_endpoint(Endpoint, Properties, Im) ->
    case evaluate_rules_for_creation(Endpoint, Properties, Im) of
        {Endpoint, Properties, Im} -> 'ok';
        {'error', _}=Error -> Error
    end.

-spec evaluate_rules_for_creation(kz_json:object(), kz_json:object(), kapps_im:im()) -> create_ep_acc().
evaluate_rules_for_creation(Endpoint, Properties, Im) ->
    Routines = [fun maybe_endpoint_disabled/3
               ,fun maybe_do_not_disturb/3
               ],
    lists:foldl(fun should_create_endpoint_fold/2
               ,{Endpoint, Properties, Im}
               ,Routines
               ).

-type create_ep_acc() :: {kz_json:object(), kz_json:object(), kapps_im:im()} | {'error', any()}.
-type ep_routine_v() :: fun((kz_json:object(), kz_json:object(), kapps_im:im()) -> 'ok' | _).

-spec should_create_endpoint_fold(ep_routine_v(), create_ep_acc()) -> create_ep_acc().
should_create_endpoint_fold(Routine, {Endpoint, Properties, Im}=Acc)
  when is_function(Routine, 3) ->
    try Routine(Endpoint, Properties, Im) of
        'ok' -> Acc;
        Error -> Error
    catch
        ?CATCH('throw', Error, ST) ->
            ?LOGSTACK(ST),
            Error;
        ?CATCH(_E, _R, ST) ->
            lager:debug("exception ~p:~p", [_E, _R]),
            ?LOGSTACK(ST),
            {'error', 'exception'}
    end;
should_create_endpoint_fold(_Routine, Error) -> Error.

-spec maybe_endpoint_disabled(kz_json:object(), kz_json:object(), kapps_im:im()) -> 'ok' | {'error', 'endpoint_disabled'}.
maybe_endpoint_disabled(Endpoint, _Properties, _Im) ->
    case kz_json:is_false(<<"enabled">>, Endpoint) of
        'false' -> 'ok';
        'true' -> {'error', 'endpoint_disabled'}
    end.

-spec maybe_do_not_disturb(kz_json:object(), kz_json:object(),  kapps_im:im()) -> 'ok' | {'error', 'do_not_disturb'}.
maybe_do_not_disturb(Endpoint, _Properties, _Im) ->
    DND = kz_json:get_json_value(<<"do_not_disturb">>, Endpoint, kz_json:new()),
    case kz_json:is_true(<<"enabled">>, DND) of
        'false' -> 'ok';
        'true' -> {'error', 'do_not_disturb'}
    end.

-spec create_im_endpoints(kz_json:object(), kz_json:object(), kapps_im:im()) -> kz_json:objects().
create_im_endpoints(Endpoint, Properties, Im) ->
    create_im_endpoints(kzd_endpoint:type(Endpoint), Endpoint, Properties, Im).

-spec create_im_endpoints(kz_term:ne_binary(), kz_json:object(), kz_json:object(), kapps_im:im()) -> kz_json:objects().
create_im_endpoints(<<"device">>, Endpoint, Properties, Im) ->
    case kz_doc:id(Endpoint) =/= kapps_im:authorizing_id(Im) of
        true -> [create_im_endpoint(Endpoint, Properties, Im)];
        false -> []
    end;
create_im_endpoints(<<"user">>, Endpoint, Properties, Im) ->
    EndpointIds = get_user_im_devices(kzd_endpoint:id(Endpoint), Im),
    EPs = [kz_endpoint:get(EndpointId, kapps_im:account_id(Im)) || EndpointId <- EndpointIds],
    [create_im_endpoint(EP, Properties, Im) || {'ok', EP} <- EPs];
create_im_endpoints(<<"group">>, Endpoint, Properties, Im) ->
    EndpointIds = lists:usort(get_group_im_members(kzd_endpoint:id(Endpoint), Im)),
    EPs = [kz_endpoint:get(EndpointId, kapps_im:account_id(Im)) || EndpointId <- EndpointIds],
    [create_im_endpoint(EP, Properties, Im) || {'ok', EP} <- EPs];
create_im_endpoints(_, _Endpoint, _Properties, _Im) -> [].


-spec get_im_endpoint_ids(kz_json:object(), kapps_im:im()) -> kz_term:ne_binaries().
get_im_endpoint_ids(Endpoint, Im) ->
    get_im_endpoint_ids(kz_json:get_ne_binary_value(<<"endpoint_type">>, Endpoint), Endpoint, Im).

-spec get_im_endpoint_ids(kz_term:ne_binary(), kz_json:object(), kapps_im:im()) -> kz_term:ne_binaries().
get_im_endpoint_ids(<<"device">>, Endpoint, Im) ->
    case kz_doc:id(Endpoint) =/= kapps_im:authorizing_id(Im) of
        true -> [kz_doc:id(Endpoint)];
        false -> []
    end;
get_im_endpoint_ids(<<"user">>, Endpoint, Im) ->
    get_user_im_devices(kz_doc:id(Endpoint), Im);
get_im_endpoint_ids(<<"group">>, Endpoint, Im) ->
    lists:usort(get_group_im_members(kz_doc:id(Endpoint), Im));
get_im_endpoint_ids(_, _Endpoint, _Im) -> [].

-spec get_user_im_devices(kz_term:ne_binary(), kapps_im:im()) -> kz_term:ne_binaries().
get_user_im_devices(OwnerId, Im) ->
    [kz_doc:id(EP) || EP
                          <- kz_attributes:owned_by_docs(OwnerId, kapps_im:account_id(Im))
                          ,<<"device">> =:= kz_doc:type(EP)
                          ,lists:member(kzd_devices:device_type(EP), ?SIP_MSG_DEVICES)
                          ,kz_doc:id(EP) =/= kapps_im:authorizing_id(Im)
    ].

-spec get_group_im_members(kz_term:ne_binary(), kapps_im:im()) -> kz_term:ne_binaries().
get_group_im_members(GroupId, Im) ->
    AccountId = kapps_im:account_id(Im),
    case kz_datamgr:open_cache_doc(AccountId, GroupId) of
        {'ok', JObj} ->
            get_group_im_member_ids(JObj, Im);
        {'error', _R} ->
            lager:warning("unable to lookup members of group ~s: ~p", [GroupId, _R]),
            []
    end.

get_group_im_member_ids(JObj, Im) ->
    kz_json:foldl(get_group_im_member_ids_fun(Im), [], JObj).

get_group_im_member_ids_fun(Im) ->
    fun(K, V, Acc) ->
            get_group_im_member_id(K, V, Im, Acc)
    end.

get_group_im_member_id(EndpointId, JObj, Im, Acc) ->
    case kz_json:get_ne_binary_value(<<"type">>, JObj) of
        undefined -> Acc;
        <<"user">> -> Acc ++ get_user_im_devices(EndpointId, Im);
        <<"device">> -> [EndpointId | Acc];
        <<"group">> -> Acc ++ get_group_im_members(EndpointId, Im);
        _Other -> Acc
    end.

-spec create_im_endpoint(kz_json:object(), kz_json:object(), kapps_im:im()) -> kz_json:object().
create_im_endpoint(Endpoint, _Properties, Im) ->
    kz_json:from_list(
      [{<<"To-Username">>, kzd_devices:sip_username(Endpoint)}
      ,{<<"To-Realm">>, kzd_devices:sip_realm(Endpoint, kapps_im:account_realm(Im))}
      ,{<<"To-DID">>, kapps_im:to(Im)}
      ,{<<"Endpoint-ID">>, kzd_endpoint:id(Endpoint)}
      ,{<<"Account-ID">>, kzd_endpoint:account_id(Endpoint)}
      ,{<<"Invite-Format">>, kzd_devices:sip_invite_format(Endpoint)}
      ]).

-spec delivery_status(kz_term:api_object()) -> delivery_status().
delivery_status(JObj) ->
    DeliveryCode = kz_json:get_value(<<"Delivery-Result-Code">>, JObj),
    Status = kz_json:get_value(<<"Status">>, JObj),
    delivery_status(DeliveryCode, Status).

-spec delivery_status(kz_term:api_binary(), kz_term:api_binary()) -> delivery_status().
delivery_status(<<"sip:", Code/binary>>, Status) -> delivery_status(Code, Status);
delivery_status(<<"200">>, _) -> 'delivered';
delivery_status(<<"202">>, _) -> 'delivered';
delivery_status(_, <<"Success">>) -> 'delivered';
delivery_status(_, _) -> 'failed'.
