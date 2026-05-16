%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2025, 2600Hz
%%% @doc
%%% @author Karl Anderson
%%% @author James Aimonetti
%%% @author Sponsored by Conversant Ltd, Implemented by SIPLABS, LLC (Ilya Ashchepkov)
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_util).

-export([presence_probe/2]).
-export([presence_mwi_query/2]).
-export([notification_register/2]).
-export([unsolicited_owner_mwi_update/2]).
-export([unsolicited_endpoint_mwi_update/2]).
-export([alpha_to_dialpad/1]).

-export([handle_bridge_failure/2, handle_bridge_failure/3
        ,get_call_termination_reason/1
        ,should_call_forward_after_failure/2
        ]).
-export([send_default_response/2]).

-export([get_operator_callflow/1, get_operator_callflow/2]).
-export([endpoint_id_by_sip_username/2]).
-export([owner_ids_by_sip_username/2]).
-export([apply_dialplan/2]).

-export([sip_users_from_device_ids/2]).

-export([caller_belongs_to_group/2
        ,maybe_belongs_to_group/3
        ,caller_belongs_to_user/2
        ,find_endpoints/3
        ,find_channels/2
        ,find_user_endpoints/3
        ,find_group_endpoints/2
        ,check_value_of_fields/4
        ,get_timezone/2
        ]).

-export([wait_for_noop/2]).
-export([start_task/3]).
-export([start_event_listener/3
        ,event_listener_name/2
        ]).

-export([flush_control_queue/1
        ,b_flush_control_queue/1
        ]).

-export([normalize_capture_group/1, normalize_capture_group/2]).

-export([token_check/2]).

-export([maybe_start_recording_to/2

        ,get_endpoint_id/1
        ]).

-include("callflow.hrl").
-include_lib("kazoo_stdlib/include/kazoo_json.hrl").

-define(SIP_USER_OWNERS_KEY(Db, User), {?MODULE, 'sip_user_owners', Db, User}).
-define(SIP_ENDPOINT_ID_KEY(Db, User), {?MODULE, 'sip_endpoint_id', Db, User}).
-define(PARKING_PRESENCE_KEY(Db, Request), {?MODULE, 'parking_callflow', Db, Request}).
-define(OPERATOR_KEY, kapps_config:get_ne_binary(?CF_CONFIG_CAT, <<"operator_key">>, <<"0">>)).

-define(VM_CACHE_KEY(Db, Id), {?MODULE, 'vmbox', Db, Id}).

-type network() :: kapps_call:inception_type().

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec token_check(kapps_call:call(), kz_json:object()) -> boolean().
token_check(Call, Flow) ->
    case kapps_config:get_is_true(?CF_CONFIG_CAT, <<"calls_consume_tokens">>, 'true') of
        'false' ->
            %% If configured to not consume tokens then don't block the call
            'true';
        'true' ->
            {Name, Cost} = bucket_info(Call, Flow),
            DryRun = kapps_config:get_is_true(?CF_CONFIG_CAT, <<"should_dry_run_token_restrictions">>, 'false'),

            case kz_buckets:consume_tokens(?APP_NAME, Name, Cost) of
                'true' -> 'true';
                'false' when DryRun ->
                    lager:info("dry-run: bucket ~s does not have enough tokens(~b needed) for this call", [Name, Cost]),
                    'true';
                'false' ->
                    lager:warning("bucket ~s does not have enough tokens(~b needed) for this call", [Name, Cost]),
                    'false'
            end
    end.

-spec bucket_info(kapps_call:call(), kz_json:object()) ->
          {kz_term:ne_binary(), pos_integer()}.
bucket_info(Call, Flow) ->
    case kz_json:get_value(<<"pvt_bucket_name">>, Flow) of
        'undefined' -> {bucket_name_from_call(Call, Flow), bucket_cost(Flow)};
        Name -> {Name, bucket_cost(Flow)}
    end.

-spec bucket_name_from_call(kapps_call:call(), kz_json:object()) -> kz_term:ne_binary().
bucket_name_from_call(Call, Flow) ->
    FlowId = case kz_doc:id(Flow) of
                 'undefined' -> <<"cf_exe_", (kz_term:to_binary(self()))/binary>>;
                 FlowIdVal   -> FlowIdVal
             end,

    <<(kapps_call:account_id(Call))/binary, ":", (FlowId)/binary>>.

-spec bucket_cost(kz_json:object()) -> pos_integer().
bucket_cost(Flow) ->
    Min = kapps_config:get_integer(?CF_CONFIG_CAT, <<"min_bucket_cost">>, 5),
    case kz_json:get_integer_value(<<"pvt_bucket_cost">>, Flow) of
        'undefined' -> Min;
        N when N < Min -> Min;
        N -> N
    end.

-spec presence_probe(kz_json:object(), kz_term:proplist()) -> any().
presence_probe(JObj, _Props) ->
    'true' = kapi_presence:probe_v(JObj),
    Username = kz_json:get_value(<<"Username">>, JObj),
    Realm = kz_json:get_value(<<"Realm">>, JObj),
    ProbeRepliers = [fun manual_presence/2
                    ,fun presence_parking_slot/2
                    ],
    lists:takewhile(fun(Fun) -> Fun(Username, Realm) =:= 'not_found' end
                   ,ProbeRepliers
                   ).

-spec presence_parking_slot(kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok' | 'not_found'.
presence_parking_slot(Username, Realm) ->
    case kapps_util:get_account_by_realm(Realm) of
        {'ok', AccountDb} ->
            maybe_presence_parking_slot_resp(Username, Realm, AccountDb);
        _E -> 'not_found'
    end.

-spec maybe_presence_parking_slot_resp(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok' | 'not_found'.
maybe_presence_parking_slot_resp(Username, Realm, AccountDb) ->
    case kz_cache:fetch_local(?CACHE_NAME, ?PARKING_PRESENCE_KEY(AccountDb, Username)) of
        {'ok', 'false'} -> 'not_found';
        {'ok', SlotNumber} ->
            presence_parking_slot_resp(Username, Realm, AccountDb, SlotNumber);
        {'error', 'not_found'} ->
            maybe_presence_parking_flow(Username, Realm, AccountDb)
    end.

-spec maybe_presence_parking_flow(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok' | 'not_found'.
maybe_presence_parking_flow(Username, Realm, AccountDb) ->
    AccountId = kzs_util:format_account_id(AccountDb),
    _ = cf_flow:lookup(Username, AccountId),
    case kz_cache:fetch_local(?CACHE_NAME, ?CF_FLOW_CACHE_KEY(Username, AccountDb)) of
        {'error', 'not_found'} -> 'not_found';
        {'ok', Flow} ->
            case kz_json:get_value([<<"flow">>, <<"module">>], Flow) of
                <<"park">> ->
                    SlotNumber = kz_json:get_ne_value(<<"capture_group">>, Flow, Username),
                    kz_cache:store_local(?CACHE_NAME, ?PARKING_PRESENCE_KEY(AccountDb, Username), SlotNumber),
                    presence_parking_slot_resp(Username, Realm, AccountDb, SlotNumber);
                _Else ->
                    kz_cache:store_local(?CACHE_NAME, ?PARKING_PRESENCE_KEY(AccountDb, Username), 'false'),
                    'not_found'
            end
    end.

-spec presence_parking_slot_resp(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
presence_parking_slot_resp(Username, Realm, AccountDb, SlotNumber) ->
    cf_park:update_presence(SlotNumber, <<Username/binary, "@", Realm/binary>>, AccountDb).

-spec manual_presence(kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok' | 'not_found'.
manual_presence(Username, Realm) ->
    case kapps_util:get_account_by_realm(Realm) of
        {'ok', AccountDb} -> fetch_manual_presence_doc(Username, Realm, AccountDb);
        _E -> 'not_found'
    end.

-spec fetch_manual_presence_doc(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok' | 'not_found'.
fetch_manual_presence_doc(Username, Realm, AccountDb) ->
    PresenceId = <<Username/binary, "@", Realm/binary>>,
    case kzd_presence:fetch_presence(AccountDb, PresenceId) of
        {'ok', JObj} ->
            manual_presence_resp(PresenceId, JObj);
        {'error', _} -> 'not_found'
    end.

-spec manual_presence_resp(kz_term:ne_binary(), kz_json:object()) -> 'ok' | 'not_found'.
manual_presence_resp(PresenceId, JObj) ->
    case kz_json:get_value(PresenceId, JObj) of
        'undefined' -> 'not_found';
        State -> kapps_call_command:presence(State, PresenceId)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec presence_mwi_query(kz_json:object(), kz_term:proplist()) -> 'ok'.
presence_mwi_query(JObj, _Props) ->
    'true' = kapi_presence:mwi_query_v(JObj),
    _ = kz_log:put_callid(JObj),
    mwi_query(JObj).

-spec notification_register(kz_json:object(), kz_term:proplist()) -> 'ok'.
notification_register(JObj, _Props) ->
    'true' = kapi_notifications:register_v(JObj),
    _ = kz_log:put_callid(JObj),
    mwi_query(JObj).

-spec mwi_query(kz_json:object()) -> 'ok'.
mwi_query(JObj) ->
    Realm = kz_json:get_value(<<"Realm">>, JObj),
    case kapps_util:get_account_by_realm(Realm) of
        {'ok', AccountDb} ->
            lager:debug("replying to mwi query"),
            Username = kz_json:get_value(<<"Username">>, JObj),
            maybe_vm_mwi_resp(Username, AccountDb);
        _Else -> 'ok'
    end.

-spec maybe_vm_mwi_resp(kz_term:api_binary(), kz_term:ne_binary()) -> 'ok'.
maybe_vm_mwi_resp('undefined', _AccountDb) -> 'ok';
maybe_vm_mwi_resp(<<VMNumber/binary>>, AccountDb) ->
    case mailbox(AccountDb, VMNumber) of
        {'ok', Doc} -> kvm_mwi:notify_vmbox(AccountDb, kz_doc:id(Doc), 'true');
        {'error', _} -> mwi_resp(VMNumber, AccountDb)
    end.

-spec mwi_resp(kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
mwi_resp(Username, AccountDb) ->
    case endpoint_id_by_sip_username(AccountDb, Username) of
        {'ok', EndpointId} -> kvm_mwi:notify_endpoint(AccountDb, EndpointId);
        _Else -> 'ok'
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec unsolicited_owner_mwi_update(kz_term:api_binary(), kz_term:api_binary()) ->
          'ok' |
          {'error', atom()} |
          kz_datamgr:data_error().
unsolicited_owner_mwi_update(AccountDb, OwnerId) ->
    kvm_mwi:notify_owner(AccountDb, OwnerId).

-spec unsolicited_endpoint_mwi_update(kz_term:api_binary(), kz_term:api_binary()) ->
          'ok' | {'error', any()}.
unsolicited_endpoint_mwi_update(AccountDb, EndpointId) ->
    kvm_mwi:notify_endpoint(AccountDb, EndpointId).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec alpha_to_dialpad(kz_term:ne_binary()) -> kz_term:ne_binary().
alpha_to_dialpad(Value) ->
    << <<(dialpad_digit(C))>> || <<C>> <= kz_term:to_lower_binary(Value), is_alpha(C) >>.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec is_alpha(char()) -> boolean().
is_alpha(Char) ->
    Char =< $z
        andalso Char >= $a.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec dialpad_digit(97..122) -> 50..57.
dialpad_digit(ABC) when ABC =:= $a
                        orelse ABC =:= $b
                        orelse ABC =:= $c -> $2;
dialpad_digit(DEF) when DEF =:= $d
                        orelse DEF =:= $e
                        orelse DEF =:= $f -> $3;
dialpad_digit(GHI) when GHI =:= $g
                        orelse GHI =:= $h
                        orelse GHI =:= $i -> $4;
dialpad_digit(JKL) when JKL =:= $j
                        orelse JKL =:= $k
                        orelse JKL =:= $l -> $5;
dialpad_digit(MNO) when MNO =:= $m
                        orelse MNO =:= $n
                        orelse MNO =:= $o -> $6;
dialpad_digit(PQRS) when PQRS =:= $p
                         orelse PQRS =:= $q
                         orelse PQRS =:= $r
                         orelse PQRS =:= $s -> $7;
dialpad_digit(TUV) when TUV =:= $t
                        orelse TUV =:= $u
                        orelse TUV =:= $v -> $8;
dialpad_digit(WXYZ) when WXYZ =:= $w
                         orelse WXYZ =:= $x
                         orelse WXYZ =:= $y
                         orelse WXYZ =:= $z -> $9.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec owner_ids_by_sip_username(kz_term:ne_binary(), kz_term:ne_binary()) ->
          {'ok', kz_term:ne_binaries()} |
          {'error', any()}.
owner_ids_by_sip_username(AccountDb, Username) ->
    case kz_cache:peek_local(?CACHE_NAME, ?SIP_USER_OWNERS_KEY(AccountDb, Username)) of
        {'ok', _}=Ok -> Ok;
        {'error', 'not_found'} ->
            get_owner_ids_by_sip_username(AccountDb, Username)
    end.

-spec get_owner_ids_by_sip_username(kz_term:ne_binary(), kz_term:ne_binary()) ->
          {'ok', kz_term:ne_binaries()} |
          {'error', any()}.
get_owner_ids_by_sip_username(AccountDb, Username) ->
    ViewOptions = [{'key', Username}],
    case kz_datamgr:get_single_result(AccountDb, <<"attributes/sip_username">>, ViewOptions) of
        {'ok', JObj} ->
            EndpointId = kz_doc:id(JObj),
            OwnerIds = kz_json:get_value(<<"value">>, JObj, []),
            CacheProps = [{'origin', {'db', AccountDb, EndpointId}}],
            kz_cache:store_local(?CACHE_NAME, ?SIP_USER_OWNERS_KEY(AccountDb, Username), OwnerIds, CacheProps),
            {'ok', OwnerIds};
        {'error', _R}=E ->
            lager:warning("unable to lookup sip username ~s for owner ids: ~p", [Username, _R]),
            E
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec endpoint_id_by_sip_username(kz_term:ne_binary(), kz_term:ne_binary()) ->
          {'ok', kz_term:ne_binary()} |
          {'error', 'not_found'}.
endpoint_id_by_sip_username(AccountDb, Username) ->
    case kz_cache:peek_local(?CACHE_NAME, ?SIP_ENDPOINT_ID_KEY(AccountDb, Username)) of
        {'ok', _}=Ok -> Ok;
        {'error', 'not_found'} ->
            get_endpoint_id_by_sip_username(AccountDb, Username)
    end.

-spec get_endpoint_id_by_sip_username(kz_term:ne_binary(), kz_term:ne_binary()) ->
          {'ok', kz_term:ne_binary()} |
          {'error', 'not_found'}.
get_endpoint_id_by_sip_username(AccountDb, Username) ->
    ViewOptions = [{'key', Username}],
    case kz_datamgr:get_single_result(AccountDb, <<"attributes/sip_username">>, ViewOptions) of
        {'ok', JObj} ->
            EndpointId = kz_doc:id(JObj),
            CacheProps = [{'origin', {'db', AccountDb, EndpointId}}],
            kz_cache:store_local(?CACHE_NAME, ?SIP_ENDPOINT_ID_KEY(AccountDb, Username), EndpointId, CacheProps),
            {'ok', EndpointId};
        {'error', _R} ->
            lager:warning("lookup sip username ~s for owner ids failed: ~p", [Username, _R]),
            {'error', 'not_found'}
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec get_operator_callflow(kz_term:ne_binary()) ->
          {'ok', kz_json:object()} |
          {'error', any()}.
get_operator_callflow(Account) -> get_operator_callflow(Account, 'undefined').

-spec get_operator_callflow(kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          {'ok', kz_json:object()} |
          {'error', any()}.
get_operator_callflow(Account, 'undefined') ->
    get_operator_callflow(Account, ?OPERATOR_KEY);
get_operator_callflow(Account, OpNum) ->
    case cf_flow:lookup(OpNum, Account) of
        {'ok', _, 'true'} ->
            lager:warning("unable to find operator callflow in ~s: lookup only returned no_match", [Account]),
            {'error', 'no_match'};
        {'ok', JObj, _} ->
            {'ok', kz_json:get_json_value(<<"flow">>, JObj, kz_json:new())};
        {'error', _R}=E ->
            lager:warning("unable to find operator callflow in ~s: ~p", [Account, _R]),
            E
    end.

%%------------------------------------------------------------------------------
%% @doc Look for children branches to handle the failure replies of
%% certain actions, like {@link cf_offnet} and {@link cf_resources}.
%% @end
%%------------------------------------------------------------------------------
-spec handle_bridge_failure({'fail', kz_json:object()} | kz_term:api_ne_binary(), kapps_call:call()) ->
          'ok' | 'not_found'.
handle_bridge_failure({'fail', Reason}, Call) ->
    {Response, Cause, Code} = get_call_termination_reason(Reason),
    handle_bridge_failure_codes([Response, Cause, Code], Call);
handle_bridge_failure('undefined', _) ->
    'not_found';
handle_bridge_failure(<<Failure/binary>>, Call) ->
    handle_bridge_failure_code(Failure, Call).

-spec handle_bridge_failure(kz_term:api_binary(), kz_term:api_binary(), kapps_call:call()) ->
          'ok' | 'not_found'.
handle_bridge_failure(Cause, Code, Call) ->
    handle_bridge_failure_codes([Cause, Code], Call).

-spec handle_bridge_failure_codes(kz_term:api_ne_binaries(), kapps_call:call()) ->
          'ok' | 'not_found'.
handle_bridge_failure_codes(Codes, Call) ->
    lager:info("attempting to find failure branch for ~s", [kz_binary:join(Codes)]),
    case lists:any(handle_bridge_failure_fun(Call), Codes) of
        'true' -> 'ok';
        'false' -> 'not_found'
    end.

handle_bridge_failure_fun(Call) ->
    fun(Code) ->
            handle_bridge_failure_code(Code, Call) =:= 'ok'
    end.

handle_bridge_failure_code(<<"sip:487">>, Call) -> cf_exe:stop(Call);
handle_bridge_failure_code(<<"ORIGINATOR_CANCEL">>, Call) -> cf_exe:stop(Call);
handle_bridge_failure_code(<<"NORMAL_CLEARING">>, _Call) -> 'ignore';
handle_bridge_failure_code(Failure, Call) ->
    case cf_exe:attempt(Failure, Call) of
        {'attempt_resp', 'ok'} ->
            lager:info("found child branch to handle failure: ~s", [Failure]);
        {'attempt_resp', _} ->
            'not_found'
    end.

-spec get_call_termination_reason(kz_json:object()) -> {kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()}.
get_call_termination_reason(JObj) ->
    {kz_call_event:application_response(JObj, <<"UNSPECIFIED">>)
    ,kz_call_event:hangup_cause(JObj, <<"UNSPECIFIED">>)
    ,kz_call_event:hangup_code(JObj, <<"sip:600">>)
    }.

-spec should_call_forward_after_failure({'fail', kz_json:object()} | kz_term:api_ne_binary(), kzd_endpoint:doc()) ->
          {'true', kzd_call_forward:doc()} | 'false'.
should_call_forward_after_failure('undefined', _Endpoint) ->
    'false';
should_call_forward_after_failure({'fail', ReasonJObj}, Endpoint) ->
    {Response, Cause, Code} = get_call_termination_reason(ReasonJObj),
    should_use_call_forward([Response, Cause, Code], kzd_endpoint:call_forward(Endpoint));
should_call_forward_after_failure(Failure, Endpoint) ->
    should_use_call_forward([Failure], Endpoint).

should_use_call_forward([], _Endpoint) ->
    'false';
should_use_call_forward(_Fails, 'undefined') ->
    'false';
should_use_call_forward([<<"sip:480">> | _Fails], CallForward) ->
    NoAnswer = no_answer_call_forward(CallForward),
    use_call_forward_if_enabled(NoAnswer);
should_use_call_forward([<<"NO_ANSWER">> | _Fails], CallForward) ->
    NoAnswer = no_answer_call_forward(CallForward),
    use_call_forward_if_enabled(NoAnswer);
should_use_call_forward([<<"sip:486">> | _Fails], CallForward) ->
    Busy = busy_call_forward(CallForward),
    use_call_forward_if_enabled(Busy);
should_use_call_forward([<<"USER_BUSY">> | _Fails], CallForward) ->
    Busy = busy_call_forward(CallForward),
    use_call_forward_if_enabled(Busy);
should_use_call_forward([<<"sip:603">> | _Fails], CallForward) ->
    Busy = busy_call_forward(CallForward),
    use_call_forward_if_enabled(Busy);
should_use_call_forward([<<"CALL_REJECTED">> | _Fails], CallForward) ->
    Busy = busy_call_forward(CallForward),
    use_call_forward_if_enabled(Busy);
should_use_call_forward([_Fail | Fails], CallForward) ->
    lager:debug("skipping failure reason ~s", [_Fail]),
    should_use_call_forward(Fails, CallForward).

use_call_forward_if_enabled(CallForward) ->
    case kzd_call_forward:enabled(CallForward) of
        'true' -> {'true', CallForward};
        'false' -> 'false'
    end.

no_answer_call_forward(CallForward) ->
    case kzd_call_forward:no_answer_enabled(CallForward, 'false') of
        'false' -> kz_json:new();
        'true' ->
            kzd_call_forward:merged(CallForward, fun kzd_call_forward:no_answer/1, kz_json:new())
    end.

busy_call_forward(CallForward) ->
    case kzd_call_forward:busy_enabled(CallForward, 'false') of
        'false' -> kz_json:new();
        'true' ->
            kzd_call_forward:merged(CallForward, fun kzd_call_forward:busy/1, kz_json:new())
    end.

%%------------------------------------------------------------------------------
%% @doc Send and wait for a call failure cause response.
%% @end
%%------------------------------------------------------------------------------
-spec send_default_response(kz_term:ne_binary(), kapps_call:call()) -> 'ok'.
send_default_response(Cause, Call) ->
    case cf_exe:wildcard_is_empty(Call) of
        'false' -> lager:debug("non-empty wildcard; not sending ~s", [Cause]);
        'true' ->
            case kz_call_response:send_default(Call, Cause) of
                {'error', 'no_response'} ->
                    lager:debug("failed to send default response for ~s", [Cause]);
                {'ok', NoopId} ->
                    _ = kapps_call_command:wait_for_noop(Call, NoopId, 2 * ?MILLISECONDS_IN_SECOND),
                    lager:debug("sent default response for ~s (~s)", [Cause, NoopId])
            end
    end.

-spec apply_dialplan(kz_term:ne_binary(), kz_term:api_object()) -> kz_term:ne_binary().
apply_dialplan(N, 'undefined') -> N;
apply_dialplan(Number, DialPlan) ->
    case kz_json:get_keys(DialPlan) of
        [] -> Number;
        Regexps -> maybe_apply_dialplan(Regexps, DialPlan, Number)
    end.

-spec maybe_apply_dialplan(kz_json:path(), kz_json:object(), kz_term:ne_binary()) -> kz_term:ne_binary().
maybe_apply_dialplan([], _, Number) ->
    lager:info("no dialplans affect number ~s", [Number]),
    Number;
maybe_apply_dialplan([<<"system">>], DialPlan, Number) ->
    SystemDialPlans = load_system_dialplans(kz_json:get_value(<<"system">>, DialPlan)),
    SystemRegexs = lists:sort(kz_json:get_keys(SystemDialPlans)),
    maybe_apply_dialplan(SystemRegexs, SystemDialPlans, Number);
maybe_apply_dialplan([<<"system">>|Regexs], DialPlan, Number) ->
    maybe_apply_dialplan(Regexs ++ [<<"system">>], DialPlan, Number);
maybe_apply_dialplan([Key|_]=Keys, DialPlan, Number) ->
    case kz_json:get_value([Key, <<"regex">>], DialPlan) of
        'undefined' -> apply_dialplan(Key, Keys, DialPlan, Number);
        Regex -> apply_dialplan(Regex, Keys, DialPlan, Number)
    end.

-spec apply_dialplan(kz_term:ne_binary(), kz_json:path(), kz_json:object(), kz_term:ne_binary()) ->
          kz_term:ne_binary().
apply_dialplan(Regex, [Key|Keys], DialPlan, Number) ->
    case re:run(Number, Regex, [{'capture', 'all_but_first', 'binary'}]) of
        'nomatch' ->
            maybe_apply_dialplan(Keys, DialPlan, Number);
        {'match', []} ->
            lager:info("regex ~s matched number ~s", [Regex, Number]),
            Number;
        {'match', Captures} ->
            Root = lists:last(Captures),
            Prefix = kz_json:get_binary_value([Key, <<"prefix">>], DialPlan, <<>>),
            Suffix = kz_json:get_binary_value([Key, <<"suffix">>], DialPlan, <<>>),
            N = <<Prefix/binary, Root/binary, Suffix/binary>>,
            lager:info("applied dialplan ~s: ~s / ~s / ~s", [Regex, Prefix, Root, Suffix]),

            InnerDialplan = kz_json:get_value([Key, <<"dialplan">>], DialPlan),
            maybe_apply_inner_dialplan(Keys, DialPlan, N, InnerDialplan)
    end.

maybe_apply_inner_dialplan(Keys, Dialplan, N, 'undefined') ->
    maybe_apply_dialplan(Keys, Dialplan, N);
maybe_apply_inner_dialplan(Keys, Dialplan, N, InnerPlan) ->
    InnerRegexs = kz_json:get_keys(InnerPlan),
    N1 = maybe_apply_dialplan(InnerRegexs, InnerPlan, N),
    maybe_apply_dialplan(Keys, Dialplan, N1).

-spec load_system_dialplans(kz_term:ne_binaries()) -> kz_json:object().
load_system_dialplans(Names) ->
    LowerNames = [kz_term:to_lower_binary(Name) || Name <- Names],
    Plans = kapps_config:get_all_kvs(<<"dialplans">>),
    lists:foldl(fold_system_dialplans(LowerNames), kz_json:new(), Plans).

-spec fold_system_dialplans(kz_term:ne_binaries()) ->
          fun(({kz_term:ne_binary(), kz_json:object()}, kz_json:object()) -> kz_json:object()).
fold_system_dialplans(Names) ->
    fun({Key, Val}, Acc) when is_list(Val) ->
            lists:foldl(fun(ValElem, A) -> maybe_dialplan_suits({Key, ValElem}, A, Names) end, Acc, Val);
       ({Key, Val}, Acc) ->
            maybe_dialplan_suits({Key, Val}, Acc, Names)
    end.

-spec maybe_dialplan_suits({kz_term:ne_binary(), kz_json:object()} ,kz_json:object(), kz_term:ne_binaries()) -> kz_json:object().
maybe_dialplan_suits({Key, Val}=KV, Acc, Names) ->
    Name = kz_term:to_lower_binary(kz_json:get_value(<<"name">>, Val)),
    case lists:member(Name, Names) of
        'true' -> kz_json:set_value(Key, Val, Acc);
        'false' -> maybe_system_dialplan_name(KV, Acc, Names)
    end.

-spec maybe_system_dialplan_name({kz_term:ne_binary(), kz_json:object()} ,kz_json:object(), kz_term:ne_binaries()) -> kz_json:object().
maybe_system_dialplan_name({Key, Val}, Acc, Names) ->
    Name = kz_term:to_lower_binary(Key),
    case lists:member(Name, Names) of
        'true' ->
            N = kz_term:to_binary(index_of(Name, Names)),
            kz_json:set_value(<<N/binary, "-", Key/binary>>, Val, Acc);
        'false' -> Acc
    end.

-spec index_of(kz_term:ne_binary(), list()) -> kz_term:api_integer().
index_of(Value, List) ->
    Map = lists:zip(List, lists:seq(1, length(List))),
    case dict:find(Value, dict:from_list(Map)) of
        {'ok', Index} -> Index;
        'error' -> 'undefined'
    end.

-spec start_event_listener(kapps_call:call(), atom(), list()) ->
          {'ok', pid()} | {'error', any()}.
start_event_listener(Call, Mod, Args) ->
    lager:debug("starting evt listener ~p", [Mod]),
    Name = event_listener_name(Call, Mod),
    try cf_event_handler_sup:new(Name, Mod, [kapps_call:clear_helpers(Call) | Args]) of
        {'ok', P} -> {'ok', P};
        _E -> lager:debug("error starting event listener ~p: ~p", [Mod, _E]),
              {'error', _E}
    catch
        _:_R ->
            lager:info("failed to spawn ~p: ~p", [Mod, _R]),
            {'error', _R}
    end.

-spec event_listener_name(kapps_call:call(), atom() | kz_term:ne_binary()) -> kz_term:ne_binary().
event_listener_name(Call, Module) ->
    <<(kapps_call:call_id_direct(Call))/binary, "-", (kz_term:to_binary(Module))/binary>>.

-spec caller_belongs_to_group(kz_term:ne_binary(), kapps_call:call()) -> boolean().
caller_belongs_to_group(GroupId, Call) ->
    maybe_belongs_to_group(kapps_call:authorizing_id(Call), GroupId, Call).

-spec maybe_belongs_to_group(kz_term:ne_binary(), kz_term:ne_binary(), kapps_call:call()) -> boolean().
maybe_belongs_to_group(TargetId, GroupId, Call) ->
    lists:member(TargetId, find_group_endpoints(GroupId, Call)).

-spec caller_belongs_to_user(kz_term:ne_binary(), kapps_call:call()) -> boolean().
caller_belongs_to_user(UserId, Call) ->
    lists:member(kapps_call:authorizing_id(Call), find_user_endpoints([UserId],[],Call)).

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
                                kz_json:get_value([Id, <<"type">>], GroupEndpoints) =:= <<"device">>
                        end, Ids),
    find_user_endpoints(UserIds, lists:sort(DeviceIds), Call).

-spec find_user_endpoints(kz_term:ne_binaries(), kz_term:ne_binaries(), kapps_call:call()) ->
          kz_term:ne_binaries().
find_user_endpoints([], DeviceIds, _) -> DeviceIds;
find_user_endpoints(UserIds, DeviceIds, Call) ->
    UserDeviceIds = kz_attributes:owned_by(UserIds, <<"device">>, Call),
    lists:merge(lists:sort(UserDeviceIds), DeviceIds).

-spec find_channels(kz_term:ne_binary() | kz_term:ne_binaries(), kapps_call:call() | kz_term:ne_binary()) ->
          kz_json:objects().
find_channels([_|_]=Usernames, <<Realm/binary>>) ->
    lager:debug("finding channels for realm ~s, usernames ~p", [Realm, Usernames]),
    Req = [{<<"Realm">>, Realm}
          ,{<<"Usernames">>, Usernames}
          ,{<<"Active-Only">>, 'true'}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    handle_user_channels_resp(make_user_channels_query(Req));
find_channels(<<Username/binary>>, <<Realm/binary>>) ->
    lager:debug("finding channels for realm ~s, username ~s", [Realm, Username]),
    Req = [{<<"Realm">>, Realm}
          ,{<<"Username">>, Username}
          ,{<<"Active-Only">>, 'true'}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    handle_user_channels_resp(make_user_channels_query(Req));
find_channels(Usernames, Call) ->
    <<Realm/binary>> = kzd_accounts:fetch_realm(kapps_call:account_id(Call)),
    find_channels(Usernames, Realm).

make_user_channels_query(Req) ->
    %% we want to collect ALL responses from ecallmgr before extracting channel information
    kz_amqp_worker:call_collect(Req
                               ,fun kapi_call:publish_query_user_channels_req/1
                               ,{'ecallmgr', 'true'}
                               ).

handle_user_channels_resp({'ok', ChannelResps}) -> extract_channels(ChannelResps);
handle_user_channels_resp({'error', _E}) ->
    lager:debug("failed to get channels: ~p", [_E]),
    [];
handle_user_channels_resp({'timeout', ChannelResps}) ->
    extract_channels(ChannelResps).

-spec extract_channels(kz_json:objects()) -> kz_json:objects().
extract_channels(ChannelResps) ->
    lists:usort(lists:foldl(fun extract_channels_fold/2, [], ChannelResps)).

-spec extract_channels_fold(kz_json:object(), kz_json:objects()) -> kz_json:objects().
extract_channels_fold(ChannelResp, Channels) ->
    kz_json:get_list_value(<<"Channels">>, ChannelResp, []) ++ Channels.

-spec check_value_of_fields(kz_term:proplist(), boolean(), kz_json:object(), kapps_call:call()) ->
          boolean().
check_value_of_fields(Perms, Def, Data, Call) ->
    case lists:dropwhile(fun({K, _F}) ->
                                 kz_json:get_value(K, Data) =:= 'undefined'
                         end
                        ,Perms
                        )
    of
        [] -> Def;
        [{K, F}|_] -> F(kz_json:get_value(K, Data), Call)
    end.

-spec sip_users_from_device_ids(kz_term:ne_binaries(), kapps_call:call()) -> kz_term:ne_binaries().
sip_users_from_device_ids(EndpointIds, Call) ->
    lists:foldl(fun(EID, Acc) -> sip_users_from_device_id(EID, Acc, Call) end
               ,[]
               ,EndpointIds
               ).

-spec sip_users_from_device_id(kz_term:ne_binary(), kz_term:ne_binaries(), kapps_call:call()) ->
          kz_term:ne_binaries().
sip_users_from_device_id(EndpointId, Acc, Call) ->
    case sip_user_from_device_id(EndpointId, Call) of
        'undefined' -> Acc;
        Username -> [Username|Acc]
    end.

-spec sip_user_from_device_id(kz_term:ne_binary(), kapps_call:call()) -> kz_term:api_binary().
sip_user_from_device_id(EndpointId, Call) ->
    case kz_endpoint:get(EndpointId, Call) of
        {'error', _} -> 'undefined';
        {'ok', Endpoint} ->
            kzd_devices:sip_username(Endpoint)
    end.

-spec wait_for_noop(kapps_call:call(), kz_term:ne_binary()) ->
          {'ok', kapps_call:call()} |
          {'error', 'channel_hungup' | kz_json:object()}.
wait_for_noop(Call, NoopId) ->
    case kapps_call_command:receive_event(?MILLISECONDS_IN_DAY) of
        {'ok', JObj} ->
            process_event(Call, NoopId, JObj);
        {'error', 'timeout'} ->
            lager:debug("timed out waiting for noop(~s) to complete", [NoopId]),
            {'ok', Call}
    end.

-spec process_event(kapps_call:call(), kz_term:ne_binary(), kz_json:object()) ->
          {'ok', kapps_call:call()} |
          {'error', any()}.
process_event(Call, NoopId, JObj) ->
    MsgId = kz_api:msg_id(JObj),
    case kapps_call_command:get_event_type(JObj) of
        {<<"call_event">>, <<"CHANNEL_DESTROY">>, _} ->
            lager:debug("channel was destroyed"),
            {'error', 'channel_hungup'};
        {<<"error">>, _, <<"noop">>} ->
            lager:debug("channel execution error while waiting for ~s: ~s", [NoopId, kz_json:encode(JObj)]),
            {'error', JObj};
        {<<"call_event">>, <<"CHANNEL_EXECUTE_COMPLETE">>, <<"noop">>}
          when NoopId =:= MsgId ->
            lager:debug("noop ~s received", [NoopId]),
            {'ok', Call};
        {<<"call_event">>, <<"CHANNEL_EXECUTE_COMPLETE">>, <<"noop">>} ->
            case kz_json:get_ne_binary_value(<<"Application-Response">>, JObj) of
                NoopId ->
                    lager:debug("noop ~s received", [NoopId]),
                    {'ok', Call};
                _Resp ->
                    lager:debug("ignoring noop ~s(~s) (waiting for ~s)", [MsgId, _Resp, NoopId]),
                    wait_for_noop(Call, NoopId)
            end;
        {<<"call_event">>, <<"DTMF">>, _} ->
            DTMF = kz_json:get_value(<<"DTMF-Digit">>, JObj),
            lager:debug("recv DTMF ~s, adding to default", [DTMF]),
            Call1 = kapps_call:add_to_dtmf_collection(DTMF, Call),
            cf_exe:set_call(Call1),
            wait_for_noop(Call1, NoopId);
        _Ignore ->
            wait_for_noop(Call, NoopId)
    end.

-spec get_timezone(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
get_timezone(JObj, Call) ->
    case kz_json:get_ne_binary_value(<<"timezone">>, JObj) of
        'undefined'   -> kzd_accounts:timezone(kapps_call:account_id(Call));
        <<"inherit">> -> kzd_accounts:timezone(kapps_call:account_id(Call)); %% UI-1808
        TZ -> TZ
    end.

-spec start_task(fun(), list(), kapps_call:call()) -> 'ok'.
start_task(Fun, Args, Call) ->
    SpawnInfo = {'cf_task', [Fun, Args]},
    cf_exe:add_event_listener(Call, SpawnInfo).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec mailbox(kz_term:ne_binary(), kz_term:ne_binary()) -> {'ok', kz_json:object()} |
          {'error', any()}.
mailbox(AccountDb, VMNumber) ->
    try kz_term:to_integer(VMNumber) of
        Number -> maybe_cached_mailbox(AccountDb, Number)
    catch
        _E:_R ->  {'error', 'not_found'}
    end.

-spec maybe_cached_mailbox(kz_term:ne_binary(), integer()) -> {'ok', kz_json:object()} |
          {'error', any()}.
maybe_cached_mailbox(AccountDb, VMNumber) ->
    case kz_cache:peek_local(?CACHE_NAME, ?VM_CACHE_KEY(AccountDb, VMNumber)) of
        {'ok', _}=Ok -> Ok;
        {'error', 'not_found'} -> get_mailbox(AccountDb, VMNumber)
    end.

-spec get_mailbox(kz_term:ne_binary(), integer()) -> {'ok', kz_json:object()} |
          {'error', any()}.
get_mailbox(AccountDb, VMNumber) ->
    ViewOptions = [{'key', VMNumber}, 'include_docs'],
    case kz_datamgr:get_single_result(AccountDb, <<"vmboxes/listing_by_mailbox">>, ViewOptions) of
        {'ok', JObj} ->
            Doc = kz_json:get_value(<<"doc">>, JObj),
            EndpointId = kz_doc:id(Doc),
            CacheProps = [{'origin', {'db', AccountDb, EndpointId}}],
            kz_cache:store_local(?CACHE_NAME, ?VM_CACHE_KEY(AccountDb, VMNumber), Doc, CacheProps),
            {'ok', Doc};
        {'error', 'multiple_results'} ->
            lager:debug("multiple voicemail boxes with same number (~b)  in account db ~s", [VMNumber, AccountDb]),
            {'error', 'not_found'};
        {'error', _R}=E ->
            lager:warning("unable to lookup voicemail number ~b in account ~s: ~p", [VMNumber, AccountDb, _R]),
            E
    end.

-spec flush_control_queue(kapps_call:call()) -> kz_term:ne_binary().
flush_control_queue(Call) ->
    ControlQueue = kapps_call:control_queue_direct(Call),
    CallId = kapps_call:call_id_direct(Call),

    NoopId = kz_datamgr:get_uuid(),
    Command = [{<<"Application-Name">>, <<"noop">>}
              ,{<<"Msg-ID">>, NoopId}
              ,{<<"Insert-At">>, <<"flush">>}
              ,{<<"Call-ID">>, CallId}
              | kz_api:default_headers(<<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    lager:debug("flushing with ~p", [Command]),
    kz_amqp_worker:cast(Command, fun(C) -> kapi_dialplan:publish_command(ControlQueue, C) end),
    NoopId.

-spec b_flush_control_queue(kapps_call:call()) ->
          {'ok', kapps_call:call()} |
          {'error', 'channel_hungup' | kz_json:object()}.
b_flush_control_queue(Call) ->
    wait_for_noop(Call, flush_control_queue(Call)).

%% @equiv normalize_capture_group(CaptureGroup, 'undefined')
-spec normalize_capture_group(kz_term:api_binary()) -> kz_term:api_ne_binary().
normalize_capture_group(CaptureGroup) ->
    normalize_capture_group(CaptureGroup, 'undefined').

%%------------------------------------------------------------------------------
%% @doc Normalize CaptureGroup number.
%%
%% If a module is using capture group as destination number, it should normalize
%% the number before continue/branch callflow or lookup callflow for the number.
%%
%% @param CaptureGroup the capture group number.
%% @param Call {@link kapps_call:call()} object or Account ID or undefined
%% to use system default normalizer.
%% @end
%%------------------------------------------------------------------------------
-spec normalize_capture_group(kz_term:api_binary(), kapps_call:call() | kz_term:api_ne_binary()) -> kz_term:api_ne_binary().
normalize_capture_group('undefined', _) ->
    'undefined';
normalize_capture_group(<<>>, _) ->
    'undefined';
normalize_capture_group(CaptureGroup, 'undefined') ->
    knm_converters:normalize(CaptureGroup);
normalize_capture_group(CaptureGroup, <<AccountId/binary>>) ->
    knm_converters:normalize(CaptureGroup, AccountId);
normalize_capture_group(CaptureGroup, Call) ->
    normalize_capture_group(CaptureGroup, kapps_call:account_id(Call)).

%% @doc check endpoint configs for starting recording to ToNetwork
%% (using inception_type from Call as FromNetwork).
-spec maybe_start_recording_to(kapps_call:call(), network()) -> kapps_call:call().
maybe_start_recording_to(Call, ToNetwork) ->
    FromNetwork = kapps_call:inception_type(Call), % onnet or offnet
    Routines = [{fun maybe_start_account_recording/2, ToNetwork}
               ,{fun maybe_start_endpoint_recording/3, FromNetwork, ToNetwork}
               ],
    cf_exe:update_call(kapps_call:exec(Routines, Call)).

-spec maybe_start_account_recording(network(), kapps_call:call()) -> kapps_call:call().
maybe_start_account_recording(ToNetwork, Call) ->
    {'ok', Endpoint} = kz_endpoint:get(kapps_call:account_id(Call), Call),

    %% Inbound account recording is already being taken care of within cf_route_win module.
    kz_account_recording:maybe_record_outbound(ToNetwork, Endpoint, Call).

-spec maybe_start_endpoint_recording(network(), network(), kapps_call:call()) ->
          kapps_call:call().
maybe_start_endpoint_recording(FromNetwork, ToNetwork, Call) ->
    EndpointId = get_endpoint_id(Call),
    case kz_endpoint:get(EndpointId, Call) of
        {'ok', Endpoint} ->
            IsCallForward = kapps_call:is_call_forward(Call),
            maybe_start_endpoint_recording(FromNetwork, ToNetwork, Endpoint, IsCallForward, Call);
        {'error', _} -> Call
    end.

-spec maybe_start_endpoint_recording(network()
                                    ,network()
                                    ,kz_endpoint:endpoint()
                                    ,boolean()
                                    ,kapps_call:call()
                                    ) -> kapps_call:call().
maybe_start_endpoint_recording(_, _, Endpoint, 'true', Call) ->
    maybe_start_call_forwarded_endpoint(Call, Endpoint);
maybe_start_endpoint_recording(<<"onnet">>, ToNetwork, Endpoint, 'false', Call) ->
    kz_endpoint_recording:maybe_record_outbound(ToNetwork, Endpoint, Call);
maybe_start_endpoint_recording(<<"offnet">>, _, _, 'false', Call) ->
    %% If the call isn't call-forwarded, and the endpoint is known,
    %% `kz_endpoint' will set up recording on answer
    Call.

-spec maybe_start_call_forwarded_endpoint(kapps_call:call(), kz_endpoint:endpoint()) ->
          kapps_call:call().
maybe_start_call_forwarded_endpoint(Call, Endpoint) ->
    FromNetwork = kapps_call:custom_channel_var(<<"Call-Forward-From">>, Call),
    case kz_endpoint_recording:maybe_record_inbound(FromNetwork, Endpoint, Call) of
        'false' -> Call;
        {'true', {ActionKey, ActionApp}} ->
            NewActions = kz_json:set_value(ActionKey, ActionApp, kz_json:new()),
            kapps_call:kvs_store('outbound_actions', NewActions, Call)
    end.

-spec get_endpoint_id(kapps_call:call()) -> kz_term:api_ne_binary().
get_endpoint_id(Call) ->
    DefaultEndpointId = kapps_call:authorizing_id(Call),
    kapps_call:kvs_fetch(?RESTRICTED_ENDPOINT_KEY, DefaultEndpointId, Call).
