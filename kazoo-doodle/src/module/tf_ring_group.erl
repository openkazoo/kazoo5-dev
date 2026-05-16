%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(tf_ring_group).

-export([handle/2]).


%%------------------------------------------------------------------------------
%% @doc Entry point for this module, attempts to Im an endpoint as defined
%% in the Data payload.  Returns continue if fails to connect or
%% stop when successful.
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_im:im()) -> 'ok'.
handle(Data, Im) ->
    Endpoints = get_endpoints(Data, Im),
    send_sms(Endpoints, Data, Im).

-spec send_sms(kz_json:objects(), kz_json:object(), kapps_im:im()) -> 'ok'.
send_sms([], _Data, Im) ->
    lager:info("group has no endpoints"),
    tf_exe:continue(<<"NO_ENDPOINTS">>, Im);
send_sms(Endpoints, Data, Im) ->
    Strategy = kz_json:get_ne_binary_value(<<"sms_strategy">>, Data, <<"all">>),
    case kapps_im_command:send_sms(Endpoints, Strategy, Im) of
        'ok' -> tf_exe:stop(Im, delivered);
        {'ok', JObj} -> tf_exe:stop(Im, tf_util:delivery_status(JObj));
        {'error', Reason} -> tf_exe:stop(Im, Reason)
    end.

-spec get_endpoints(kz_json:object(), kapps_im:im()) -> kz_json:objects().
get_endpoints(Data, Im) ->
    get_endpoints(Data, Im, kz_json:get_ne_binary_value(<<"group_id">>, Data)).

-spec get_endpoints(kz_json:object(), kapps_im:im(), kz_term:api_ne_binary()) -> kz_json:objects().
get_endpoints(Data, Im, 'undefined') ->
    build_endpoints(Data, Im);
get_endpoints(Data, Im, GroupId) ->
    lager:debug("merging data to group ~s settings", [GroupId]),
    AccountId = kapps_im:account_id(Im),
    case kz_datamgr:open_cache_doc(AccountId, GroupId) of
        {'ok', JObj} ->
            case kz_json:get_json_value(<<"endpoints">>, JObj) of
                undefined ->
                    lager:warning("group ~s doesn't have anypoints", [GroupId]),
                    [];
                EndpointsJObj ->
                    Endpoints = kz_json:foldl(fun(K, V, Acc) -> [ kz_json:set_value(<<"id">>, K, V) | Acc] end, [], EndpointsJObj),
                    build_endpoints(kz_json:set_value(<<"endpoints">>, Endpoints, Data), Im)
            end;
        {'error', _Reason} ->
            lager:warning("unable to open group document ~s: ~p", [GroupId, _Reason]),
            []
    end.

-spec build_endpoints(kz_json:object(), kapps_im:im()) -> kz_json:objects().
build_endpoints(Data, Im) ->
    Members = kz_json:get_list_value(<<"endpoints">>, Data),
    EndpointIds = build_endpoint_ids(Members, Im),
    lists:foldl(build_endpoints_fun(Data, Im), [], EndpointIds).

build_endpoints_fun(Data, Im) ->
    fun(EndpointId, Endpoints) ->
            case build_endpoint(EndpointId, Data, Im) of
                {ok, EPs} -> EPs ++ Endpoints;
                {error, _} -> Endpoints
            end
    end.

build_endpoint(EndpointId, Data, Im) ->
    Params = kz_json:set_value(<<"source">>, kz_term:to_binary(?MODULE), Data),
    case kz_endpoint:get(EndpointId, kapps_im:account_id(Im)) of
        {'ok', Endpoint} -> tf_util:build_im_endpoint(Endpoint, Params, Im);
        {'error', _}=E -> E
    end.

-spec build_endpoint_ids(kz_json:objects(), kapps_im:im()) -> kz_term:ne_binaries().
build_endpoint_ids(Members, Im) ->
    lists:foldl(build_endpoint_ids_fun(Im), [], Members).

-spec build_endpoint_ids_fun(kapps_im:im()) -> fun((kz_json:object(), kz_term:ne_binaries()) -> kz_term:ne_binaries()).
build_endpoint_ids_fun(Im) ->
    fun(Member, EndpointIds) ->
            EndpointIds ++ tf_util:get_im_endpoint_ids(Member, Im)
    end.
