%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc
%%% @author Karl Anderson
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_group).

-behaviour(gen_cf_action).

-include("callflow.hrl").
-include_lib("kazoo_amqp/src/api/kapi_dialplan.hrl").

-export([handle/2]).

-define(HARD_STOP_KEY, <<"hard_stop_after_successful_group">>).

%%------------------------------------------------------------------------------
%% @doc Entry point for this module, attempts to call an endpoint as defined
%% in the Data payload.  Returns continue if fails to connect or
%% stop when successful.
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    case kz_json:get_list_value(<<"endpoints">>, Data, []) of
        [] -> attempt_group(Data, Call);
        _Else -> cf_ring_group:handle(Data, Call)
    end.

-spec attempt_group(kz_json:object(), kapps_call:call()) -> 'ok'.
attempt_group(Data, Call) ->
    GroupId = kz_json:get_ne_binary_value(<<"id">>, Data),
    AccountId = kapps_call:account_id(Call),
    AccountDb = kzs_util:format_account_db(AccountId),
    case kz_datamgr:open_cache_doc(AccountDb, GroupId) of
        {'ok', JObj} -> attempt_endpoints(JObj, Data, Call);
        {'error', _R} ->
            lager:debug("unable to open group document ~s in ~s", [GroupId, AccountId]),
            cf_exe:continue(Call)
    end.

-spec attempt_endpoints(kz_json:object(), kz_json:object(), kapps_call:call()) -> 'ok'.
attempt_endpoints(JObj, Data, Call) ->
    Endpoints = build_endpoints(JObj, Call),

    attempt_endpoints(JObj, Data, Call, Endpoints).

attempt_endpoints(_JObj, _Data, Call, []) ->
    lager:info("group has no endpoints"),
    cf_exe:continue(Call);
attempt_endpoints(JObj, Data, Call0, Endpoints) ->
    Call = cf_util:maybe_start_recording_to(Call0, <<"onnet">>),

    Timeout = kz_term:to_integer(
                kz_json:find(<<"timeout">>, [JObj, Data], ?DEFAULT_TIMEOUT_S)
               ),
    Strategy = kz_term:to_binary(
                 kz_json:find(<<"strategy">>, [JObj, Data], ?DIAL_METHOD_SIMUL)
                ),
    IgnoreForward = kz_term:to_binary(
                      kz_json:find(<<"ignore_forward">>, [JObj, Data], <<"true">>)
                     ),
    Ringback = kz_term:to_binary(
                 kz_json:find(<<"ringback">>, [JObj, Data])
                ),
    IgnoreEarlyMedia = ignore_early_media(Data, Call),
    lager:info("attempting group of ~b members with strategy ~s", [length(Endpoints), Strategy]),
    _ = kapps_call_command:b_answer(Call),
    case kapps_call_command:b_bridge(Endpoints, Timeout, Strategy, IgnoreEarlyMedia, Ringback, 'undefined', IgnoreForward, set_presence(Data, Call)) of
        {'ok', Reply} ->
            lager:info("completed successful bridge to the group - call finished normally"),
            after_success_bridge(Call, kz_call_event:channel_answer_state(Reply), should_hard_stop(Call, Data));
        {'fail', _}=F ->
            case cf_util:handle_bridge_failure(F, Call) of
                'ok' -> lager:debug("bridge failure handled");
                'not_found' -> cf_exe:continue(Call)
            end;
        {'error', _R} ->
            lager:info("error bridging to group: ~p"
                      ,[kz_json:get_value(<<"Error-Message">>, _R)]
                      ),
            cf_exe:continue(Call)
    end.

-spec should_hard_stop(kapps_call:call(), kz_json:object()) -> boolean().
should_hard_stop(Call, Data) -> kz_json:is_true(?HARD_STOP_KEY, Data, should_hard_stop_default(Call)).

-spec should_hard_stop_default(kapps_call:call()) -> boolean().
should_hard_stop_default(Call) ->
    AccountId = kapps_call:account_id(Call),
    kapps_account_config:get_global(AccountId, ?CF_CONFIG_CAT, ?HARD_STOP_KEY, 'true').

-spec after_success_bridge(kapps_call:call(), kz_term:api_ne_binary(), boolean()) -> 'ok'.
after_success_bridge(Call, <<"hangup">>, _) ->
    cf_exe:hard_stop(Call);
after_success_bridge(Call, _AnswerState, 'true') ->
    kapps_call_command:queued_hangup(Call),
    cf_exe:hard_stop(Call);
after_success_bridge(Call, _, _) ->
    cf_exe:stop(Call).

-spec build_endpoints(kz_json:object(), kapps_call:call()) -> kz_json:objects().
build_endpoints(JObj, Call) ->
    Members = kz_json:to_proplist(<<"endpoints">>, JObj),
    Routines = [fun build_device_endpoints/3
               ,fun build_user_endpoints/3
               ],
    lists:flatten(
      [Endpoint
       || {_, {'ok', Endpoint}} <-
              lists:foldl(fun(F, E) -> F(E, Members, Call) end
                         ,[]
                         ,Routines
                         )
      ]
     ).

-type endpoints_acc() :: [{kz_term:ne_binary(), {'ok', kz_json:objects()}}].

-spec build_device_endpoints(endpoints_acc(), kz_term:proplist(), kapps_call:call()) ->
          endpoints_acc().
build_device_endpoints(Endpoints, [], _) -> Endpoints;
build_device_endpoints(Endpoints, [{MemberId, Member} | Members], Call) ->
    case kz_json:get_value(<<"type">>, Member, <<"device">>) =:= <<"device">>
        andalso props:get_value(MemberId, Endpoints) =:= 'undefined'
        andalso MemberId =/= kapps_call:authorizing_id(Call)
    of
        'true' ->
            M = kz_json:set_value(<<"source">>, kz_term:to_binary(?MODULE), Member),
            E = [{MemberId, kz_endpoint:build(MemberId, M, Call)}|Endpoints],
            build_device_endpoints(E, Members, Call);
        'false' -> build_device_endpoints(Endpoints, Members, Call)
    end.

-spec build_user_endpoints(endpoints_acc(), kz_term:proplist(), kapps_call:call()) -> endpoints_acc().
build_user_endpoints(Endpoints, [], _) -> Endpoints;
build_user_endpoints(Endpoints, [{MemberId, Member} | Members], Call) ->
    case <<"user">> =:= kz_json:get_value(<<"type">>, Member, <<"user">>) of
        'false' -> build_user_endpoints(Endpoints, Members, Call);
        'true' ->
            DeviceIds = kz_attributes:owned_by(MemberId, <<"device">>, Call),
            M = kz_json:set_values([{<<"source">>, kz_term:to_binary(?MODULE)}
                                   ,{<<"type">>, <<"device">>}
                                   ]
                                  ,Member
                                  ),
            E = build_device_endpoints(Endpoints
                                      ,[{DeviceId, M} || DeviceId <- DeviceIds]
                                      ,Call
                                      ),
            build_user_endpoints(E, Members, Call)
    end.

default_ignore_early_media(Call) ->
    kz_app_config:get_boolean({?APP, kapps_call:account_id(Call)}, <<"ring_group.ignore_early_media">>, true).

ignore_early_media(Data, Call) ->
    case kz_json:is_true(<<"ignore_early_media">>, Data, undefined) of
        undefined -> default_ignore_early_media(Call);
        Value -> Value
    end.

-spec is_sca_enabled(kz_json:object()) -> boolean().
is_sca_enabled(Data) ->
    kz_json:is_true([<<"sca">>, <<"enabled">>], Data).

-spec clean_name(kz_term:ne_binary()) -> kz_term:api_ne_binary().
clean_name(Name) ->
    case kz_binary:clean(Name) of
        <<>> -> undefined;
        Cleaned -> Cleaned
    end.

-spec group_name(kz_json:object()) -> kz_term:api_ne_binary().
group_name(Data) ->
    case kz_json:get_ne_binary_value(<<"group_name">>, Data) of
        undefined -> undefined;
        Name -> clean_name(Name)
    end.

-spec presence_alias(kz_json:object()) -> kz_term:api_ne_binary().
presence_alias(Data) ->
    case group_name(Data) of
        undefined -> undefined;
        Name -> list_to_binary(["sca.group.", Name])
    end.

-spec add_presence_alias(kz_json:object(), kapps_call:call()) -> kapps_call:call().
add_presence_alias(Data, Call) ->
    case presence_alias(Data) of
        undefined -> Call;
        Alias -> kapps_call:add_presence_alias(Alias, Call)
    end.

-spec set_presence(kz_json:object(), kapps_call:call()) -> kapps_call:call().
set_presence(Data, Call) ->
    case is_sca_enabled(Data) of
        true -> add_presence_alias(Data, Call);
        false -> Call
    end.
