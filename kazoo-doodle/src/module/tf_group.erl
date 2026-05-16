%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(tf_group).

-export([handle/2]).

%%------------------------------------------------------------------------------
%% @doc Entry point for this module, attempts to Im an endpoint as defined
%% in the Data payload.  Returns continue if fails to connect or
%% stop when successful.
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_im:im()) -> 'ok'.
handle(Data, Im) ->
    case kz_json:get_list_value(<<"endpoints">>, Data, []) of
        [] -> attempt_group(Data, Im);
        _Else -> tf_ring_group:handle(Data, Im)
    end.

-spec attempt_group(kz_json:object(), kapps_im:im()) -> 'ok'.
attempt_group(Data, Im) ->
    GroupId = kz_json:get_ne_binary_value(<<"id">>, Data),
    AccountId = kapps_im:account_id(Im),
    case kz_datamgr:open_cache_doc(AccountId, GroupId) of
        {'ok', JObj} -> attempt_endpoints(JObj, Data, Im);
        {'error', _R} ->
            lager:debug("unable to open group document ~s in ~s", [GroupId, AccountId]),
            tf_exe:continue(Im)
    end.

-spec attempt_endpoints(kz_json:object(), kz_json:object(), kapps_im:im()) -> 'ok'.
attempt_endpoints(JObj, Data, Im) ->
    Members = kz_json:to_proplist(<<"endpoints">>, JObj),
    Endpoints = build_endpoints(Members, Data, Im),
    send_sms(Endpoints, Data, Im).

-spec send_sms(kz_json:objects(), kz_json:object(), kapps_im:im()) -> 'ok'.
send_sms([], _Data, Im) ->
    lager:info("group has no endpoints"),
    tf_exe:continue(Im);
send_sms(Endpoints, Data, Im) ->
    Strategy = kz_json:get_ne_binary_value(<<"sms_strategy">>, Data, <<"all">>),
    case kapps_im_command:send_sms(Endpoints, Strategy, Im) of
        {'ok', JObj} -> tf_exe:stop(Im, tf_util:delivery_status(JObj));
        {'error', Reason} -> tf_exe:stop(Im, Reason)
    end.

-spec build_endpoints(kz_term:proplist(),  kz_json:object(), kapps_im:im()) -> kz_json:objects().
build_endpoints(Members, Data, Im) ->
    lists:foldl(build_endpoint_fun(Data, Im), [], Members).

build_endpoint_fun(Data, Im) ->
    fun({MemberId, Member}, Endpoints) ->
            case get_member_endpoints(MemberId, Member, Data, Im) of
                {ok, []} -> Endpoints;
                {ok, MemberEndpoints} -> Endpoints ++ MemberEndpoints;
                {error, _} -> Endpoints
            end
    end.

get_member_endpoints(MemberId, _Member, Data, Im) ->
    Params = kz_json:set_value(<<"source">>, kz_term:to_binary(?MODULE), Data),
    case kz_endpoint:get(MemberId, kapps_im:account_id(Im)) of
        {'ok', Endpoint} -> tf_util:build_im_endpoint(Endpoint, Params, Im);
        {'error', _}=E -> E
    end.
