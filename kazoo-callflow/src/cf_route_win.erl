%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Handler for route wins, bootstraps callflow execution.
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_route_win).

-export([execute_callflow/1]).

-include("callflow.hrl").

-define(TO_JSON(L), kz_json:from_list(L)).

-define(DEFAULT_SERVICES
       ,?TO_JSON([{<<"audio">>, ?TO_JSON([{<<"enabled">>, 'true'}])}
                 ,{<<"video">>, ?TO_JSON([{<<"enabled">>, 'true'}])}
                 ,{<<"sms">>, ?TO_JSON([{<<"enabled">>, 'true'}])}
                 ]
                )
       ).

-spec execute_callflow(kapps_call:call()) ->
          {'ok' | 'restricted', kapps_call:call()}.
execute_callflow(Call) ->
    case should_restrict_call(Call) of
        'true' ->
            lager:debug("endpoint is restricted from making this call, terminate", []),
            _ = kapps_call_command:answer(Call),
            _ = kapps_call_command:prompt(<<"cf-unauthorized_call">>, Call),
            _ = kapps_call_command:queued_hangup(Call),
            {'restricted', Call};
        'false' ->
            lager:info("setting initial information about the call"),
            {'ok', bootstrap_callflow_executer(Call)}
    end.

-spec should_restrict_call(kapps_call:call()) -> boolean().
should_restrict_call(Call) ->
    should_restrict_call(cf_util:get_endpoint_id(Call), Call).

-spec should_restrict_call(kz_term:api_ne_binary(), kapps_call:call()) -> boolean().
should_restrict_call('undefined', _Call) -> 'false';
should_restrict_call(EndpointId, Call) ->
    case kz_endpoint:get(EndpointId, Call) of
        {'error', _R} -> 'false';
        {'ok', EndpointJObj} -> maybe_service_unavailable(EndpointJObj, Call)
    end.

-spec maybe_service_unavailable(kz_json:object(), kapps_call:call()) -> boolean().
maybe_service_unavailable(EndpointJObj, Call) ->
    Id = kz_doc:id(EndpointJObj),
    Services = get_services(EndpointJObj),
    case kz_json:is_true([<<"audio">>,<<"enabled">>], Services, 'true') of
        'true' ->
            maybe_account_service_unavailable(EndpointJObj, Call);
        'false' ->
            lager:debug("device ~s does not have audio service enabled", [Id]),
            'true'
    end.

-spec get_services(kz_json:object()) -> kz_json:object().
get_services(EndpointJObj) ->
    kz_json:merge(kz_json:get_json_value(<<"services">>, EndpointJObj, ?DEFAULT_SERVICES)
                 ,kz_json:get_json_value(<<"pvt_services">>, EndpointJObj, kz_json:new())
                 ).

-spec maybe_account_service_unavailable(kz_json:object(), kapps_call:call()) -> boolean().
maybe_account_service_unavailable(EndpointJObj, Call) ->
    AccountId = kapps_call:account_id(Call),
    {'ok', AccountDoc} = kzd_accounts:fetch(AccountId),
    Services = get_services(AccountDoc),

    case kz_json:is_true([<<"audio">>,<<"enabled">>], Services, 'true') of
        'true' ->
            maybe_closed_group_restriction(EndpointJObj, Call);
        'false' ->
            lager:debug("account ~s does not have audio service enabled", [AccountId]),
            'true'
    end.

-spec maybe_closed_group_restriction(kz_json:object(), kapps_call:call()) ->
          boolean().
maybe_closed_group_restriction(EndpointJObj, Call) ->
    case kz_json:get_value([<<"call_restriction">>, <<"closed_groups">>, <<"action">>], EndpointJObj) of
        <<"deny">> -> enforce_closed_groups(EndpointJObj, Call);
        _Else -> maybe_classification_restriction(EndpointJObj, Call)
    end.

-spec maybe_classification_restriction(kz_json:object(), kapps_call:call()) ->
          boolean().
maybe_classification_restriction(EndpointJObj, Call) ->
    Number = maybe_normalize_number(EndpointJObj, Call),
    Classification = knm_converters:classify(Number),
    lager:debug("classified number ~s as ~s, testing for call restrictions"
               ,[Number, Classification]
               ),
    kz_json:get_value([<<"call_restriction">>, Classification, <<"action">>], EndpointJObj) =:= <<"deny">>.

-spec maybe_normalize_number(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
maybe_normalize_number(EndpointJObj, Call) ->
    AccountId = kapps_call:account_id(Call),
    DialPlan = kz_json:get_json_value(<<"dial_plan">>, EndpointJObj, kz_json:new()),
    Request = find_request(Call),

    case kz_json:is_empty(DialPlan)
        andalso kapps_call:kvs_fetch('cf_capture_group', Call) =:= 'undefined'
    of
        'true' ->
            lager:debug("no dial plan or capture group, using original dialed number '~s'", [Request]),
            Request;
        'false' ->
            lager:debug("normalizing number '~s'", [Request]),
            knm_converters:normalize(Request, AccountId, DialPlan)
    end.

-spec find_request(kapps_call:call()) -> kz_term:ne_binary().
find_request(Call) ->
    case kapps_call:kvs_fetch('cf_capture_group', Call) of
        'undefined' ->
            kapps_call:request_user(Call);
        CaptureGroup ->
            lager:debug("capture group ~s being used instead of request ~s"
                       ,[CaptureGroup, kapps_call:request_user(Call)]
                       ),
            CaptureGroup
    end.

-spec enforce_closed_groups(kz_json:object(), kapps_call:call()) -> boolean().
enforce_closed_groups(EndpointJObj, Call) ->
    case get_callee_extension_info(Call) of
        'undefined' ->
            lager:info("dialed number is not an extension, using classification restrictions"),
            maybe_classification_restriction(EndpointJObj, Call);
        {<<"user">>, CalleeId} ->
            lager:info("dialed number is user ~s extension, checking groups", [CalleeId]),
            Groups = kz_attributes:groups(Call),
            CallerGroups = get_caller_groups(Groups, EndpointJObj, Call),
            CalleeGroups = get_group_associations(CalleeId, Groups),
            sets:size(sets:intersection(CallerGroups, CalleeGroups)) =:= 0;
        {<<"device">>, CalleeId} ->
            lager:info("dialed number is device ~s extension, checking groups", [CalleeId]),
            Groups = kz_attributes:groups(Call),
            CallerGroups = get_caller_groups(Groups, EndpointJObj, Call),
            maybe_device_groups_intersect(CalleeId, CallerGroups, Groups, Call)
    end.

-spec get_caller_groups(kz_json:objects(), kz_json:object(), kapps_call:call()) -> sets:set().
get_caller_groups(Groups, EndpointJObj, Call) ->
    Ids = [kapps_call:authorizing_id(Call)
          ,kz_json:get_ne_binary_value(<<"owner_id">>, EndpointJObj)
          | kz_json:get_keys([<<"hotdesk">>, <<"users">>], EndpointJObj)
          ],
    lists:foldl(fun('undefined', Set) -> Set;
                   (Id, Set) -> get_group_associations(Id, Groups, Set)
                end
               ,sets:new()
               ,Ids
               ).

-spec maybe_device_groups_intersect(kz_term:ne_binary(), sets:set(), kz_json:objects(), kapps_call:call()) -> boolean().
maybe_device_groups_intersect(CalleeId, CallerGroups, Groups, Call) ->
    CalleeGroups = get_group_associations(CalleeId, Groups),
    case sets:size(sets:intersection(CallerGroups, CalleeGroups)) =:= 0 of
        'false' -> 'false';
        'true' ->
            %% In this case the callee-id is a device id, find out if
            %% the owner of the device shares any groups with the caller
            UserIds = kz_attributes:owner_ids(CalleeId, Call),
            UsersGroups = lists:foldl(fun(UserId, Set) ->
                                              get_group_associations(UserId, Groups, Set)
                                      end
                                     ,sets:new()
                                     ,UserIds
                                     ),
            sets:size(sets:intersection(CallerGroups, UsersGroups)) =:= 0
    end.

-spec get_group_associations(kz_term:ne_binary(), kz_json:objects()) -> sets:set().
get_group_associations(Id, Groups) ->
    get_group_associations(Id, Groups, sets:new()).

-spec get_group_associations(kz_term:ne_binary(), kz_json:objects(), sets:set()) -> sets:set().
get_group_associations(Id, Groups, Set) ->
    lists:foldl(fun(Group, S) ->
                        case kz_json:get_value([<<"value">>, Id], Group) of
                            'undefined' -> S;
                            _Else -> sets:add_element(kz_doc:id(Group), S)
                        end
                end, Set, Groups).

-spec get_callee_extension_info(kapps_call:call()) -> {kz_term:ne_binary(), kz_term:ne_binary()} | 'undefined'.
get_callee_extension_info(Call) ->
    Flow = kapps_call:kvs_fetch('cf_flow', Call),
    FirstModule = kz_json:get_ne_binary_value(<<"module">>, Flow),
    FirstId = kz_json:get_ne_binary_value([<<"data">>, <<"id">>], Flow),
    SecondModule = kz_json:get_ne_binary_value([?DEFAULT_CHILD_KEY, <<"module">>], Flow),
    case (FirstModule =:= <<"device">>
              orelse FirstModule =:= <<"user">>
         )
        andalso (SecondModule =:= <<"voicemail">>
                     orelse SecondModule =:= 'undefined'
                )
        andalso FirstId =/= 'undefined'
    of
        'true' -> {FirstModule, FirstId};
        'false' -> 'undefined'
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec bootstrap_callflow_executer(kapps_call:call()) -> kapps_call:call().
bootstrap_callflow_executer(Call) ->
    Routines = [fun store_owner_id/1
               ,fun set_language/1
               ,fun include_denied_call_restrictions/1
               ,fun maybe_start_recording/1
               ,fun store_execute_callflow/1
               ,fun maybe_start_metaflow/1
               ],
    kapps_call:exec(Routines, Call).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec store_owner_id(kapps_call:call()) -> kapps_call:call().
store_owner_id(Call) ->
    OwnerId = kz_attributes:owner_id(Call),
    kapps_call:kvs_store('owner_id', OwnerId, Call).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec set_language(kapps_call:call()) -> kapps_call:call().
set_language(Call) ->
    Default = kz_media_util:prompt_language(kapps_call:account_id(Call)),
    case kz_endpoint:get(Call) of
        {'ok', Endpoint} ->
            Language = kzd_endpoint:language(Endpoint, Default),
            lager:debug("setting language '~s' for this call", [Language]),
            kapps_call:set_language(Language, Call);
        {'error', _E} ->
            lager:debug("no source endpoint for this call, setting language to default ~s", [Default]),
            kapps_call:set_language(Default, Call)
    end.

-spec maybe_start_metaflow(kapps_call:call()) -> kapps_call:call().
maybe_start_metaflow(Call) ->
    maybe_start_metaflow(Call, kapps_call:custom_channel_var(<<"Metaflow-App">>, Call)).

-spec maybe_start_metaflow(kapps_call:call(), kz_term:api_binary()) -> kapps_call:call().
maybe_start_metaflow(Call, 'undefined') ->
    maybe_start_endpoint_metaflow(Call, kapps_call:authorizing_id(Call)),
    Call;
maybe_start_metaflow(Call, App) ->
    lager:debug("metaflow app ~s", [App]),
    Call.

-spec maybe_start_endpoint_metaflow(kapps_call:call(), kz_term:api_binary()) -> 'ok'.
maybe_start_endpoint_metaflow(_Call, 'undefined') -> 'ok';
maybe_start_endpoint_metaflow(Call, EndpointId) ->
    lager:debug("looking up endpoint for ~s", [EndpointId]),
    case kz_endpoint:get(EndpointId, Call) of
        {'ok', Endpoint} ->
            lager:debug("trying to send metaflow for a-leg endpoint ~s", [EndpointId]),
            kz_endpoint:maybe_start_metaflow(Call, Endpoint);
        {'error', _E} -> 'ok'
    end.

-spec maybe_start_recording(kapps_call:call()) -> kapps_call:call().
maybe_start_recording(Call) ->
    %% NOTE: endpoint inbound recording is handled by {@see kz_endpoint_v5:maybe_record_endpoint/1}
    %% NOTE: account/endpoint outbound recording is handled individually by cf modules via {@see cf_util:maybe_start_recording_to/2}
    FromNetwork = kapps_call:inception_type(Call),
    case kz_endpoint:get(kapps_call:account_id(Call), Call) of
        {'ok', Endpoint} ->
            kz_account_recording:maybe_record_inbound(FromNetwork, Endpoint, Call);
        {'error', _E} ->
            Call
    end.

-spec include_denied_call_restrictions(kapps_call:call()) -> kapps_call:call().
include_denied_call_restrictions(Call) ->
    case kz_endpoint:get(cf_util:get_endpoint_id(Call), Call) of
        {'error', _R} -> Call;
        {'ok', JObj} ->
            CallRestriction = kz_json:get_json_value(<<"call_restriction">>, JObj, kz_json:new()),
            Denied = kz_json:filter(fun filter_action/1, CallRestriction),
            kapps_call:kvs_store('denied_call_restrictions', Denied, Call)
    end.

-spec filter_action({any(), kz_json:object()}) -> boolean().
filter_action({_, Action}) ->
    <<"deny">> =:= kz_json:get_ne_binary_value(<<"action">>, Action).

%%------------------------------------------------------------------------------
%% @doc executes the found call flow by starting a new cf_exe process under the
%% cf_exe_sup tree.
%% @end
%%------------------------------------------------------------------------------
-spec store_execute_callflow(kapps_call:call()) -> kapps_call:call().
store_execute_callflow(Call) ->
    lager:info("call has been setup, beginning to process the call"),
    kapps_call:kvs_store('cf_exe_pid', self(), Call).
