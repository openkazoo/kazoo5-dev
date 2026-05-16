%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2025, 2600Hz
%%% @doc Callflow resource.
%%%
%%% <h4>Data options:</h4>
%%% <dl>
%%%   <dt>`to_did'</dt>
%%%   <dd>Statically dial DID</dd>
%%%
%%%   <dt>`media'</dt>
%%%   <dd>"Media ID</dd>
%%%
%%%   <dt>`ringback'</dt>
%%%   <dd>Ringback ID</dd>
%%%
%%%   <dt>`format_from_did'</dt>
%%%   <dd>`boolean()'</dd>
%%%
%%%   <dt>`timeout'</dt>
%%%   <dd>`integer()'</dd>
%%%
%%%   <dt>`do_not_normalize'</dt>
%%%   <dd>`boolean()'</dd>
%%%
%%%   <dt>`bypass_e164'</dt>
%%%   <dd>`boolean()'</dd>
%%%
%%%   <dt>`from_uri_realm'</dt>
%%%   <dd>Realm</dd>
%%%
%%%   <dt>`caller_id_type'</dt>
%%%   <dd>Can use custom caller id properties on endpoints, e.g. `external'.</dd>
%%%
%%%   <dt>`use_local_resources'</dt>
%%%   <dd>`boolean()'</dd>
%%%
%%%   <dt>`hunt_account_id'</dt>
%%%   <dd>Use this account's local carriers instead of current account.</dd>
%%%
%%%   <dt>`emit_account_id'</dt>
%%%   <dd>`boolean()', puts account ID in SIP header `X-Account-ID'</dd>
%%%
%%%   <dt>`custom_sip_headers'</dt>
%%%   <dd>`{"header":"value",...}'</dd>
%%%
%%%   <dt>`ignore_early_media'</dt>
%%%   <dd>`boolean()'</dd>
%%%
%%%   <dt>`resource_type'</dt>
%%%   <dd>`string()'</dd>
%%%
%%%   <dt>`outbound_flags'</dt>
%%%   <dd>`["flag_1","flag_2"]', used to match flags on carrier docs</dd>
%%% </dl>
%%%
%%% @author Karl Anderson
%%% @author Sponsored by Raffel Internet B.V. Implemented by Voyager Internet Ltd.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_resources).
-behaviour(gen_cf_action).

-export([handle/2]).

-include("callflow.hrl").
-include_lib("kazoo_amqp/include/kapi_offnet_resource.hrl").

-define(DEFAULT_EVENT_WAIT, 10000).
-define(RES_CONFIG_CAT, <<?CF_CONFIG_CAT/binary, ".resources">>).

%%------------------------------------------------------------------------------
%% @doc Entry point for this module
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call0) ->
    Call = cf_util:maybe_start_recording_to(Call0, <<"offnet">>),
    OffnetReq = build_offnet_request(Data, Call),
    'ok' = kapi_offnet_resource:publish_req(OffnetReq),
    case wait_for_stepswitch(Call) of
        {<<"SUCCESS">>, _} ->
            lager:info("completed successful offnet request"),
            cf_exe:stop(Call);
        {<<"TRANSFER">>, _} ->
            lager:info("completed successful offnet request"),
            cf_exe:transfer(Call);
        {<<"NORMAL_CLEARING">>, <<"sip:200">>} ->
            lager:info("completed successful offnet request"),
            cf_exe:stop(Call);
        {<<"NORMAL_CLEARING">>, 'undefined'} ->
            lager:info("completed successful offnet request"),
            cf_exe:stop(Call);
        {Cause, Code} -> handle_bridge_failure(Cause, Code, Call)
    end.

-spec handle_bridge_failure(kz_term:api_binary(), kz_term:api_binary(), kapps_call:call()) -> 'ok'.
handle_bridge_failure(Cause, Code, Call) ->
    handle_bridge_failure(kapps_call:is_call_forward(Call), Cause, Code, Call).

-spec handle_bridge_failure(boolean(), kz_term:api_binary(), kz_term:api_binary(), kapps_call:call()) -> 'ok'.
handle_bridge_failure('false', Cause, Code, Call) ->
    lager:info("offnet request error, attempting to find failure branch for ~s:~s", [Code, Cause]),
    case cf_util:handle_bridge_failure(Cause, Code, Call) of
        'ok' -> lager:debug("found bridge failure child");
        'not_found' ->
            cf_util:send_default_response(Cause, Call),
            cf_exe:hard_stop(Call)
    end;
handle_bridge_failure('true', Cause, _Code, Call) ->
    Response = kz_call_response:get_response(Cause, Call),
    _ = kz_call_response:send(kapps_call:call_id(Call)
                             ,kapps_call:control_queue(Call)
                             ,kz_json:get_value(<<"Code">>, Response)
                             ,Cause
                             ),
    cf_exe:hard_stop(Call).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec build_offnet_request(kz_json:object(), kapps_call:call()) -> kapi_offnet_resource:req().
build_offnet_request(Data, Call) ->
    {ECIDNum, ECIDName} = kz_attributes:caller_id(<<"emergency">>, Call),

    {AssertedNumber, AssertedName, AssertedRealm} =
        get_asserted_identity(Data, Call),

    {CIDNumber, CIDName} = get_caller_id(Data, Call),

    PrivacyFlags = get_privacy_flags(Call),

    kz_json:from_list(
      [{?KEY_ACCOUNT_ID, kapps_call:account_id(Call)}
      ,{?KEY_ACCOUNT_REALM, kapps_call:account_realm(Call)}
      ,{?KEY_APPLICATION_NAME, ?APPLICATION_BRIDGE}
      ,{?KEY_BYPASS_E164, get_bypass_e164(Data)}
      ,{?KEY_B_LEG_EVENTS, [<<"DTMF">>]}
      ,{?KEY_CALL_ID, cf_exe:callid(Call)}
      ,{?KEY_CCVS, get_channel_vars(Call)}
      ,{?KEY_CAVS, kapps_call:custom_application_vars(Call)}
      ,{?KEY_REQUESTOR_CCVS, kapps_call:custom_channel_vars(Call)}
      ,{?KEY_CONTROL_QUEUE, cf_exe:control_queue(Call)}
      ,{?KEY_CSHS, get_sip_headers(Data, Call)}
      ,{?KEY_REQUESTOR_CSHS, kapps_call:custom_sip_headers(Call)}
      ,{?KEY_E_CALLER_ID_NAME, ECIDName}
      ,{?KEY_E_CALLER_ID_NUMBER, ECIDNum}
      ,{?KEY_FLAGS, get_flags(Data, Call)}
      ,{?KEY_FORMAT_FROM_URI, kz_json:is_true(<<"format_from_uri">>, Data)}
      ,{?KEY_FROM_URI_REALM, get_from_uri_realm(Data, Call)}
      ,{?KEY_HUNT_ACCOUNT_ID, get_hunt_account_id(Data, Call)}
      ,{?KEY_IGNORE_EARLY_MEDIA, get_ignore_early_media(Data)}
      ,{?KEY_INCEPTION, get_inception(Call)}
      ,{?KEY_MEDIA, kz_json:get_first_defined([<<"media">>, <<"Media">>], Data)}
      ,{?KEY_MSG_ID, kz_binary:rand_hex(6)}
      ,{?KEY_OUTBOUND_CALLER_ID_NAME, CIDName}
      ,{?KEY_OUTBOUND_CALLER_ID_NUMBER, CIDNumber}
      ,{?KEY_PRESENCE_ID, maybe_presence_id(Call)}
      ,{?KEY_ASSERTED_IDENTITY_NAME, AssertedName}
      ,{?KEY_ASSERTED_IDENTITY_NUMBER, AssertedNumber}
      ,{?KEY_ASSERTED_IDENTITY_REALM, AssertedRealm}
      ,{?KEY_RINGBACK, kz_json:get_ne_binary_value(<<"ringback">>, Data)}
      ,{?KEY_T38_ENABLED, get_t38_enabled(Call)}
      ,{?KEY_TIMEOUT, kz_json:get_integer_value(<<"timeout">>, Data)}
      ,{?KEY_TO_DID, get_to_did(Data, Call)}
      ,{?KEY_DENIED_CALL_RESTRICTIONS, kapps_call:kvs_fetch('denied_call_restrictions', Call)}
      ,{?KEY_OUTBOUND_ACTIONS, kapps_call:kvs_fetch('outbound_actions', Call)}
      ,{?KEY_PRIVACY_METHOD, props:get_value(?KEY_PRIVACY_METHOD, PrivacyFlags)}
      ,{?KEY_PRIVACY_HIDE_NAME, props:get_value(?KEY_PRIVACY_HIDE_NAME, PrivacyFlags)}
      ,{?KEY_PRIVACY_HIDE_NUMBER, props:get_value(?KEY_PRIVACY_HIDE_NUMBER, PrivacyFlags)}
      ,{?KEY_SIP_DIVERSIONS, kapps_call:bridge_diversions(Call)}
      ,{?KEY_EMERGENCY_ADDRESS, get_emergency_address(Data, Call)}
      | add_headers(Data, Call)
      ]).

%%------------------------------------------------------------------------------
%% @doc Data object's emergency address takes precedence (if defined) over
%% endpoint's emergency address.
%% @end
%%------------------------------------------------------------------------------
-spec get_emergency_address(kz_json:object(), kapps_call:call()) -> kz_json:api_object().
get_emergency_address(Data, Call) ->
    DataEmergencyAddress = kz_json:get_json_value([<<"addresses">>, <<"emergency">>], Data),
    case kz_term:is_empty(DataEmergencyAddress) of
        'true' ->
            get_emergency_address_from_endpoint(Call);
        'false' ->
            lager:debug("found emergency address within Data object, using it"),
            DataEmergencyAddress
    end.

%%------------------------------------------------------------------------------
%% @doc Device also has its own order of precedence when emergency address
%% attribute is being merged as part of the endpoint building process.
%% @end
%%------------------------------------------------------------------------------
-spec get_emergency_address_from_endpoint(kapps_call:call()) -> kz_json:api_object().
get_emergency_address_from_endpoint(Call) ->
    lager:debug("getting emergency address from endpoint"),
    get_emergency_address_from_endpoint(Call, kz_endpoint:get(Call)).

-spec get_emergency_address_from_endpoint(kapps_call:call(), kz_endpoint:std_return()) -> kz_json:api_object().
get_emergency_address_from_endpoint(_Call, {'ok', Endpoint}) ->
    EmergencyAddress = kzd_endpoint:addresses_emergency(Endpoint),
    case kz_term:is_empty(EmergencyAddress) of
        'true' ->
            lager:debug("emergency address not found within Endpoint object"),
            'undefined';
        'false' ->
            lager:debug("found emergency address within Endpoint, using it"),
            EmergencyAddress
    end;
get_emergency_address_from_endpoint(_Call, _Err) ->
    'undefined'.

-spec add_headers(kz_json:object(), kapps_call:call()) -> kz_term:proplist().
add_headers(Data, Call) ->
    add_resource_type(Data) ++ kz_api:default_headers(cf_exe:queue_name(Call), ?APP_NAME, ?APP_VERSION).

-spec add_resource_type(kz_json:object()) -> kz_term:proplist().
add_resource_type(Data) ->
    case kz_json:get_ne_binary_value(<<"resource_type">>, Data) of
        'undefined' -> [{?KEY_RESOURCE_TYPE, ?RESOURCE_TYPE_AUDIO}];
        ?RESOURCE_TYPE_AUDIO -> [{?KEY_RESOURCE_TYPE, ?RESOURCE_TYPE_AUDIO}];
        Type ->
            [{?KEY_RESOURCE_TYPE, Type}
            ,{?KEY_ORIGINAL_RESOURCE_TYPE, ?RESOURCE_TYPE_AUDIO}
            ]
    end.

-spec get_channel_vars(kapps_call:call()) -> kz_json:object().
get_channel_vars(Call) ->
    GetterFuns = [fun maybe_require_ignore_early_media/2
                 ,fun maybe_require_single_fail/2
                 ,fun maybe_set_bridge_generate_comfort_noise/2
                 ,fun maybe_call_forward/2
                 ],
    Fun = fun(F, Acc) -> F(Call, Acc) end,
    CCVs = lists:foldl(Fun, [], GetterFuns),
    kz_json:from_list(CCVs).

-spec maybe_presence_id(kapps_call:call()) -> kz_term:api_ne_binary().
maybe_presence_id(Call) ->
    case kapps_call:is_call_forward(Call) of
        'true' -> kz_attributes:presence_id(Call);
        'false' -> 'undefined'
    end.

-spec maybe_require_ignore_early_media(kapps_call:call(), kz_term:proplist()) -> kz_term:proplist().
maybe_require_ignore_early_media(Call, Acc) ->
    [{<<"Require-Ignore-Early-Media">>, kapps_call:custom_channel_var(<<"Require-Ignore-Early-Media">>, Call)} | Acc].

-spec maybe_require_single_fail(kapps_call:call(), kz_term:proplist()) -> kz_term:proplist().
maybe_require_single_fail(Call, Acc) ->
    [{<<"Require-Fail-On-Single-Reject">>, kapps_call:custom_channel_var(<<"Require-Fail-On-Single-Reject">>, Call)} | Acc].

-spec maybe_call_forward(kapps_call:call(), kz_term:proplist()) -> kz_term:proplist().
maybe_call_forward(Call, Acc) ->
    case kapps_call:is_call_forward(Call) of
        'false' -> Acc;
        'true' -> call_forward_vars(Call, Acc)
    end.

call_forward_vars(Call, Vars) ->
    Routines = [fun call_forward_basic_vars/2
               ,fun call_forward_export_vars/2
               ],
    Fun = fun(F, Acc) -> F(Call, Acc) end,
    lists:usort(lists:foldl(Fun, Vars, Routines)).

call_forward_basic_vars(Call, Acc) ->
    [{<<"Authorizing-ID">>, kapps_call:authorizing_id(Call)}
    ,{<<"Authorizing-Type">>, kapps_call:authorizing_type(Call)}
    ,{<<"Owner-ID">>, kapps_call:owner_id(Call)}
    ,{<<"Application-Other-Leg-UUID">>, kapps_call:custom_channel_var(<<"Call-Forward-For-UUID">>, Call)}
    ,{<<"Call-Forward">>, 'true'}
    ,{<<"Call-Forward-From">>, kapps_call:custom_channel_var(<<"Call-Forward-From">>, Call)}
    ,{<<"Is-Failover">>, kapps_call:custom_channel_var(<<"Is-Failover">>, Call)}
    | Acc
    ].

call_forward_export_vars(Call, Acc) ->
    case kapps_call:custom_channel_var(<<"Call-Forward-Exports">>, Call) of
        'undefined' -> Acc;
        Exports -> call_forward_export_vars(Call, Acc, Exports)
    end.

call_forward_export_vars(Call, CCVs, Exports) ->
    Vars = binary:split(Exports, <<"|">>, ['global']),
    Fun = fun(Var, Acc) -> call_forward_export_var(Call, Acc, Var) end,
    lists:foldl(Fun, CCVs, Vars).

call_forward_export_var(Call, Acc, Var) ->
    case kapps_call:custom_channel_var(Var, Call) of
        'undefined' -> Acc;
        Value -> [{Var, Value} | Acc]
    end.

-spec get_privacy_flags(kapps_call:call()) -> kz_term:proplist().
get_privacy_flags(Call) ->
    CCVs = kapps_call:custom_channel_vars(Call),
    case kapps_call:kvs_fetch(<<"use_endpoint_privacy">>, 'true', Call)
        andalso not kz_json:is_true(<<"Retain-CID">>, CCVs)
    of
        'false' -> kz_privacy:flags(CCVs);
        'true' -> get_endpoint_privacy_flags(Call, CCVs)
    end.

-spec get_endpoint_privacy_flags(kapps_call:call(), kz_json:object()) -> kz_term:proplist().
get_endpoint_privacy_flags(Call, CCVs) ->
    case get_endpoint(Call) of
        {'error', _R} -> kz_privacy:flags(CCVs);
        {'ok', Endpoint} ->
            [{?KEY_PRIVACY_METHOD
             ,kz_privacy:get_method(CCVs)
             }
            ,{?KEY_PRIVACY_HIDE_NAME
             ,kz_privacy:should_hide_name(Endpoint)
              orelse kz_privacy:should_hide_name(CCVs)
             }
            ,{?KEY_PRIVACY_HIDE_NUMBER
             ,kz_privacy:should_hide_number(Endpoint)
              orelse kz_privacy:should_hide_number(CCVs)
             }
            ]
    end.

-spec get_bypass_e164(kz_json:object()) -> boolean().
get_bypass_e164(Data) ->
    kz_json:is_true(<<"do_not_normalize">>, Data)
        orelse kz_json:is_true(<<"bypass_e164">>, Data).

-spec get_from_uri_realm(kz_json:object(), kapps_call:call()) -> kz_term:api_binary().
get_from_uri_realm(Data, Call) ->
    case kz_json:get_ne_binary_value(<<"from_uri_realm">>, Data) of
        'undefined' -> maybe_get_call_from_realm(Call);
        Realm -> Realm
    end.

-spec maybe_get_call_from_realm(kapps_call:call()) -> kz_term:api_ne_binary().
maybe_get_call_from_realm(Call) ->
    case kapps_call:from_realm(Call) of
        <<"norealm">> ->
            kzd_accounts:fetch_realm(kapps_call:account_id(Call));
        Realm -> Realm
    end.

-spec maybe_set_bridge_generate_comfort_noise(kapps_call:call(), kz_term:proplist()) -> kz_term:proplist().
maybe_set_bridge_generate_comfort_noise(Call, Acc) ->
    case get_endpoint(Call) of
        {'ok', Endpoint} ->
            maybe_has_comfort_noise_option_enabled(Endpoint, Acc);
        {'error', _E} ->
            lager:debug("error acquiring originating endpoint information"),
            Acc
    end.

-spec maybe_has_comfort_noise_option_enabled(kz_json:object(), kz_term:proplist()) -> kz_term:proplist().
maybe_has_comfort_noise_option_enabled(Endpoint, Acc) ->
    case kz_json:is_true([<<"media">>, <<"bridge_generate_comfort_noise">>], Endpoint) of
        'true' -> [{<<"Bridge-Generate-Comfort-Noise">>, 'true'} | Acc];
        'false' -> Acc
    end.

-spec get_caller_id(kz_json:object(), kapps_call:call()) ->
          {kz_term:api_binary(), kz_term:api_binary()}.
get_caller_id(Data, Call) ->
    Type = kz_json:get_value(<<"caller_id_type">>, Data, <<"external">>),
    kz_attributes:caller_id(Type, Call).

-spec get_asserted_identity(kz_json:object(), kapps_call:call()) ->
          {kz_term:api_binary(), kz_term:api_binary(), kz_term:api_binary()}.
get_asserted_identity(_Data, Call) ->
    case get_endpoint(Call) of
        {'error', _E} ->
            {'undefined', 'undefined', 'undefined'};
        {'ok', Endpoint} ->
            maybe_asserted_identity(Endpoint, Call, should_set_asserted_on_call_fwd(Endpoint, Call))
    end.

-spec maybe_asserted_identity(kz_endpoint:endpoint(), kapps_call:call(), boolean()) ->
          {kz_term:api_binary(), kz_term:api_binary(), kz_term:api_binary()}.
maybe_asserted_identity(_, _Call, 'false') ->
    {'undefined', 'undefined', 'undefined'};
maybe_asserted_identity(Endpoint, Call, 'true') ->
    CallerId = kzd_devices:caller_id(Endpoint),
    {DefaultNumber, DefaultName, DefaultRealm} =
        maybe_default_asserted_identity(Endpoint, Call),
    {kzd_caller_id:asserted_number(CallerId, DefaultNumber)
    ,kzd_caller_id:asserted_name(CallerId, DefaultName)
    ,kzd_caller_id:asserted_realm(CallerId, DefaultRealm)
    }.

-spec maybe_default_asserted_identity(kz_endpoint:endpoint(), kapps_call:call()) ->
          {kz_term:api_binary(), kz_term:api_binary(), kz_term:api_binary()}.
maybe_default_asserted_identity(Endpoint, Call) ->
    CallerId = kzd_devices:caller_id(Endpoint),
    case kapps_config:get_is_true(?RES_CONFIG_CAT, <<"default_asserted_identity">>, 'false') of
        'false' -> {'undefined', 'undefined', 'undefined'};
        'true' ->
            {kzd_caller_id:external_number(CallerId)
            ,get_asserted_default_name(CallerId, Call)
            ,kapps_call:account_realm(Call)
            }
    end.

-spec should_set_asserted_on_call_fwd(kz_endpoint:endpoint(), kapps_call:call()) -> boolean().
should_set_asserted_on_call_fwd(Endpoint, Call) ->
    not (kapps_call:is_call_forward(Call)
         andalso kzd_call_forward:keep_caller_id(kzd_devices:call_forward(Endpoint, kz_json:new()))
        ).

-spec get_asserted_default_name(kz_json:object(), kapps_call:call()) -> kz_term:api_binary().
get_asserted_default_name(CallerId, Call) ->
    case kzd_caller_id:external_name(CallerId) of
        'undefined' ->
            AccountId = kapps_call:account_id(Call),
            kzd_accounts:fetch_name(AccountId);
        Name -> Name
    end.

-spec get_hunt_account_id(kz_json:object(), kapps_call:call()) -> kz_term:api_binary().
get_hunt_account_id(Data, Call) ->
    case kz_json:is_true(<<"use_local_resources">>, Data, 'true') of
        'false' -> 'undefined';
        'true' ->
            AccountId = default_hunt_account_id(Call),
            kz_json:get_ne_binary_value(<<"hunt_account_id">>, Data, AccountId)
    end.

-spec default_hunt_account_id(kapps_call:call()) -> kz_term:api_binary().
default_hunt_account_id(Call) ->
    case kapps_call:hunt_account_id(Call) of
        'undefined' -> kapps_call:account_id(Call);
        AccountId -> AccountId
    end.

-spec get_to_did(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
get_to_did(Data, Call) ->
    case kz_json:get_ne_binary_value(<<"to_did">>, Data) of
        'undefined' -> get_request_did(Data, Call);
        ToDID -> ToDID
    end.

-spec get_request_did(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
get_request_did(Data, Call) ->
    case kz_json:is_true(<<"do_not_normalize">>, Data) of
        'true' -> get_original_request_user(Call);
        'false' -> maybe_bypass_e164(Data, Call)
    end.

-spec maybe_bypass_e164(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
maybe_bypass_e164(Data, Call) ->
    case kz_json:is_true(<<"bypass_e164">>, Data) of
        'true' -> get_original_request_user(Call);
        'false' -> kapps_call:request_user(Call)
    end.

-spec get_original_request_user(kapps_call:call()) -> kz_term:ne_binary().
get_original_request_user(Call) ->
    Request = kapps_call:request(Call),
    [RequestUser, _] = binary:split(Request, <<"@">>),
    RequestUser.

-spec remove_diversions(kz_json:json_kv()) -> boolean().
remove_diversions({<<"Diversion", _/binary>>, _V}) -> 'false';
remove_diversions(_KV) -> 'true'.

-spec endpoint_outbound_sip_headers(kapps_call:call()) -> kz_json:object().
endpoint_outbound_sip_headers(Call) ->
    case kz_endpoint:get(Call) of
        {'ok', Endpoint} ->
            kzd_devices:custom_sip_headers_outbound(Endpoint, kz_json:new());
        {'error', _E} ->
            kz_json:new()
    end.

-spec flow_outbound_sip_headers(kz_json:object()) -> kz_json:object().
flow_outbound_sip_headers(Data) ->
    case kz_json:get_json_value(<<"custom_sip_headers">>, Data) of
        'undefined' -> kz_json:new();
        CSHs -> CSHs
    end.

-spec get_sip_headers(kz_json:object(), kapps_call:call()) -> kz_term:api_object().
get_sip_headers(Data, Call) ->
    AuthEndCSH = endpoint_outbound_sip_headers(Call),
    CSH = flow_outbound_sip_headers(Data),
    Headers = kz_json:filter(fun remove_diversions/1, kz_json:merge(AuthEndCSH, CSH)),
    Routines = [fun(J) -> maybe_emit_account_id(J, Data, Call) end
               ],
    JObj = lists:foldl(fun(F, J) -> F(J) end, Headers, Routines),
    case kz_term:is_empty(JObj) of
        'true' -> 'undefined';
        'false' -> JObj
    end.

-spec maybe_emit_account_id(kz_json:object(), kz_json:object(), kapps_call:call()) ->
          kz_json:object().
maybe_emit_account_id(JObj, Data, Call) ->
    Default = kapps_config:get_is_true(?RES_CONFIG_CAT, <<"default_emit_account_id">>, 'false'),
    case kz_json:is_true(<<"emit_account_id">>, Data, Default) of
        'false' -> JObj;
        'true' ->
            kz_json:set_value(<<"X-Account-ID">>, kapps_call:account_id(Call), JObj)
    end.

-spec get_ignore_early_media(kz_json:object()) -> kz_term:api_binary().
get_ignore_early_media(Data) ->
    kz_term:to_binary(kz_json:is_true(<<"ignore_early_media">>, Data, 'false')).

-spec get_t38_enabled(kapps_call:call()) -> kz_term:api_boolean().
get_t38_enabled(Call) ->
    case kz_endpoint:get(Call) of
        {'ok', JObj} -> kz_json:is_true([<<"media">>, <<"fax_option">>], JObj);
        {'error', _} -> 'undefined'
    end.

-spec get_flags(kz_json:object(), kapps_call:call()) -> kz_term:api_binaries().
get_flags(Data, Call) ->
    Flags = kz_attributes:get_flags(?APP_NAME, Call),
    Routines = [fun get_flow_flags/3
               ,fun get_flow_dynamic_flags/3
               ],
    lists:uniq(lists:foldl(fun(F, A) -> F(Data, Call, A) end, Flags, Routines)).

-spec get_flow_flags(kz_json:object(), kapps_call:call(), kz_term:ne_binaries()) ->
          kz_term:ne_binaries().
get_flow_flags(Data, _Call, Flags) ->
    case kz_json:get_list_value(<<"outbound_flags">>, Data, []) of
        [] -> Flags;
        FlowFlags -> FlowFlags ++ Flags
    end.

-spec get_flow_dynamic_flags(kz_json:object(), kapps_call:call(), kz_term:ne_binaries()) ->
          kz_term:ne_binaries().
get_flow_dynamic_flags(Data, Call, Flags) ->
    case kz_json:get_list_value(<<"dynamic_flags">>, Data) of
        'undefined' -> Flags;
        DynamicFlags -> kz_attributes:process_dynamic_flags(DynamicFlags, Flags, Call)
    end.

-spec get_inception(kapps_call:call()) -> kz_term:api_binary().
get_inception(Call) ->
    kz_json:get_value(<<"Inception">>, kapps_call:custom_channel_vars(Call)).


-spec get_endpoint(kapps_call:call()) -> kz_endpoint:std_return().
get_endpoint(Call) ->
    AuthId = kapps_call:authorizing_id(Call),
    EndpointId = kapps_call:kvs_fetch(?RESTRICTED_ENDPOINT_KEY, AuthId, Call),
    kz_endpoint:get(EndpointId, kapps_call:account_db(Call)).

%%------------------------------------------------------------------------------
%% @doc Consume Erlang messages and return on offnet response
%% @end
%%------------------------------------------------------------------------------
-spec wait_for_stepswitch(kapps_call:call()) -> {kz_term:ne_binary(), kz_term:api_binary()}.
wait_for_stepswitch(Call) ->
    case kapps_call_command:receive_event(?DEFAULT_EVENT_WAIT, 'true') of
        {'ok', JObj} ->
            case kz_api:event_type(JObj) of
                {<<"resource">>, <<"offnet_resp">>} ->
                    {kz_call_event:response_message(JObj)
                    ,kz_call_event:response_code(JObj)
                    };
                {<<"call_event">>, <<"CHANNEL_DESTROY">>} ->
                    handle_channel_destroy(JObj);
                {_Cat, _Evt} ->
                    wait_for_stepswitch(Call)
            end;
        _ -> wait_for_stepswitch(Call)
    end.

handle_channel_destroy(JObj) ->
    handle_channel_destroy(kz_json:get_value(<<"Channel-Name">>, JObj), JObj).

handle_channel_destroy(<<"loopback", _/binary>>, _JObj) ->
    {<<"TRANSFER">>, 'ok'};
handle_channel_destroy(_, JObj) ->
    {kz_call_event:hangup_cause(JObj), kz_call_event:hangup_code(JObj)}.
