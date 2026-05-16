%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_phone_numbers).

-export([init_seq/1
        ,seq/0
        ,seq_kcro_48/0
        ,seq_kcro_97/0
        ,seq_kzoo_316/0
        ,seq_kcro_191/0

        ,cleanup/0
        ]).

-include_lib("kazoo_numbers/include/knm_phone_number.hrl"). %% ?NUMBER_STATE_* and ?CARRIER_* macros
-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-define(NUMBER_PREFIX, <<"+1999">>).

-define(CONFIG_CAT, <<"number_manager">>).

-spec seq() -> 'ok'.
seq() ->
    _ = init(),
    seq_kzoo_41(),
    seq_kcro_48(),
    seq_kcro_42(),
    seq_kcro_43(),
    seq_kcro_44(),
    seq_kcro_45(),
    seq_kcro_97(),
    seq_kzoo_316(),
    seq_kcro_191().

-spec init_seq(kz_term:ne_binary()) -> {pqc_cb_api:state(), kz_term:ne_binary()}.
init_seq(AccountName) ->
    Model = pqc_phone_numbers:initial_state(),
    API = pqc_kazoo_model:api(Model),

    AccountResp = properly_accountant:create_account(API, AccountName),
    AccountId = kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),
    lager:info("created account ~s: ~s", [AccountId, AccountResp]),
    {API, AccountId}.

seq_kzoo_41() ->
    {API, AccountId} = init_seq(?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_phone_numbers:summary(API, AccountId),
    lager:info("empty summary: ~s", [EmptySummaryResp]),
    'true' = kz_json:is_empty(kz_json:get_json_value([<<"data">>, <<"numbers">>], kz_json:decode(EmptySummaryResp))),

    PhoneNumber = new_phone_number(),

    CreateResp = pqc_cb_phone_numbers:add_number(API, AccountId, PhoneNumber, kz_json:from_list([{<<"carrier_name">>, <<"knm_other">>}])),
    lager:info("create resp ~p", [CreateResp]),
    NumberDoc = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    <<PhoneNumber/binary>> = kz_doc:id(NumberDoc),

    SummaryResp = pqc_cb_phone_numbers:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    SummaryJObj = kz_json:get_json_value([<<"data">>, <<"numbers">>, PhoneNumber], kz_json:decode(SummaryResp)),
    'false' = kz_json:is_empty(SummaryJObj),

    RemoveResp = pqc_cb_phone_numbers:remove_number(API, AccountId, PhoneNumber),
    lager:info("removed resp: ~s", [RemoveResp]),

    EmptyAgainResp = pqc_cb_phone_numbers:summary(API, AccountId),
    lager:info("empty again: ~s", [EmptyAgainResp]),
    EmptyData = kz_json:get_json_value([<<"data">>, <<"numbers">>], kz_json:decode(EmptyAgainResp)),
    'true' = kz_json:is_empty(EmptyData),

    cleanup(API, [AccountId], PhoneNumber).

-spec seq_kcro_48() -> 'ok'.
seq_kcro_48() ->
    {API, AccountId} = init_seq(?ACCOUNT_NAME),

    InvalidAccountId = kz_binary:rand_hex(16),
    Number = new_phone_number(),
    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([401], ExpectedHeaders)],
    F = fun(PL) -> pqc_cb_api:create_envelope(kz_json:from_list_recursive(PL)) end,

    %% GET /v2/accounts/{INVALID_ACCOUNT_ID}/phone_numbers/{PHONE_NUMBER}/identify
    check_error_response(pqc_cb_phone_numbers:identify_number(API, InvalidAccountId, Number, Expectations)),

    %% PUT /v2/accounts/{INVALID_ACCOUNT_ID}/phone_numbers/{PHONE_NUMBER}/port
    check_error_response(pqc_cb_phone_numbers:port_number(API, InvalidAccountId, Number, F([{<<"blip">>, 432}]), Expectations)),

    %% PUT /v2/accounts/{INVALID_ACCOUNT_ID}/phone_numbers/{PHONE_NUMBER}/activate
    ReqEnvelope0 = pqc_cb_api:create_envelope(kz_json:new()),
    check_error_response(pqc_cb_phone_numbers:activate_number(API, InvalidAccountId, Number, ReqEnvelope0, Expectations)),

    %% DELETE /v2/accounts/{INVALID_ACCOUNT_ID}/phone_numbers/{PHONE_NUMBER}
    check_error_response(pqc_cb_phone_numbers:remove_number(API, InvalidAccountId, Number, Expectations)),

    %% POST /v2/accounts/{INVALID_ACCOUNT_ID}/phone_numbers/{PHONE_NUMBER}
    ReqData0 = [{<<"my_own_field">>, <<"some Value">>}
               ,{<<"cnam">>, [{<<"display_name">>, <<"Red">>}
                             ,{<<"inbound_lookup">>, 'true'}
                             ]}
               ],
    check_error_response(pqc_cb_phone_numbers:update_number(API, InvalidAccountId, Number, F(ReqData0), Expectations)),

    %% POST /v2/accounts/{INVALID_ACCOUNT_ID}/phone_numbers/check
    ReqData1 = [{<<"numbers">>, [<<"+15852046266">>, <<"+15852046440">>]}],
    check_error_response(pqc_cb_phone_numbers:check_numbers(API, InvalidAccountId, F(ReqData1), Expectations)),

    %% PUT /v2/accounts/{INVALID_ACCOUNT_ID}/phone_numbers/collection/activate
    ReqData2 = [{<<"numbers">>, [<<"+15852042750">>, <<"+15853619398">>]}],
    check_error_response(pqc_cb_phone_numbers:check_numbers(API, InvalidAccountId, F(ReqData2), Expectations)),

    cleanup(API, [AccountId], Number).

-spec check_error_response(pqc_cb_api:response()) -> 'ok'.
check_error_response(<<Resp/binary>>) ->
    RespJObj = kz_json:decode(Resp),
    <<"error">> = kz_json:get_ne_binary_value(<<"status">>, RespJObj),
    'ok'.

seq_kcro_42() ->
    InitSeq = {API, AccountId} = init_seq(?ACCOUNT_NAME),
    PhoneNumber = new_phone_number(),
    To = ?NUMBER_STATE_RESERVED,

    Test = fun(From, Matches) ->
                   create_change_verify_and_remove(InitSeq, PhoneNumber, From, To, Matches)
           end,

    lager:debug("update phone number from discovery to reserved state"),
    _ = Test(?NUMBER_STATE_DISCOVERY, reserved_matches(PhoneNumber)),

    lager:debug("update phone number from reserved to reserved state"),
    _ = Test(?NUMBER_STATE_RESERVED, no_change_required_matches()),

    lager:debug("update non-existing phone number to reserved state"),
    _ = verify_matches(change_number_state(API, AccountId, PhoneNumber, To), bad_identifier_matches()),

    lager:debug("update phone number from aging to reserved state"),
    _ = Test(?NUMBER_STATE_AGING, invalid_state_transition_matches(?NUMBER_STATE_AGING, To)),

    lager:debug("update phone number from port-in to reserved state"),
    _ = Test(?NUMBER_STATE_PORT_IN, invalid_state_transition_matches(?NUMBER_STATE_PORT_IN, To)),

    cleanup(API, [AccountId], PhoneNumber).

seq_kcro_43() ->
    InitSeq = {API, AccountId} = init_seq(?ACCOUNT_NAME),
    PhoneNumber = new_phone_number(),
    ToState = ?NUMBER_STATE_PORT_IN,

    Test = fun(FromState, Matches) ->
                   create_change_verify_and_remove(InitSeq, PhoneNumber, FromState, ToState, Matches)
           end,

    lager:debug("update phone number from discovery to port-in state"),
    _ = Test(?NUMBER_STATE_IN_SERVICE, number_exists_matches(PhoneNumber)),

    lager:debug("update phone number from aging to port-in state"),
    _ = Test(?NUMBER_STATE_AGING, invalid_state_transition_matches(?NUMBER_STATE_AGING, ToState)),

    lager:debug("update invalid phone number to port-in state"),
    _ = verify_matches(change_number_state(API, AccountId, <<"123_&">>, ToState)
                      ,not_reconcilable_matches(<<"123_&">>)
                      ),

    lager:debug("update phone number from reserved to port-in state"),
    _ = Test(?NUMBER_STATE_RESERVED, number_exists_matches(PhoneNumber)),

    cleanup(API, [AccountId], PhoneNumber).

seq_kcro_44() ->
    {API, AccountId} = init_seq(?ACCOUNT_NAME),

    lager:debug("activating invalid phone number"),
    verify_matches(pqc_cb_phone_numbers:activate_number(API, AccountId, <<"+190932147671234_&">>)
                  ,not_reconcilable_matches(<<"+190932147671234_&">>)
                  ),

    cleanup(API, [AccountId], 'undefined').

seq_kcro_45() ->
    {API, AccountId} = init_seq(?ACCOUNT_NAME),
    PhoneNumber = new_phone_number(),

    verify_matches(create_number_with_state(API, AccountId, PhoneNumber, ?NUMBER_STATE_IN_SERVICE, ?CARRIER_INVENTORY)
                  ,created_matches(PhoneNumber)
                  ), %% make sure it was created
    verify_matches(pqc_cb_phone_numbers:remove_number(API, AccountId, PhoneNumber), deleted_matches(PhoneNumber, API)), %% make sure it was deleted

    lager:debug("deleting an already deleted phone number"),

    ConfigResp = pqc_cb_system_configs:get_default_config(API, ?CONFIG_CAT),
    Released = kz_json:get_binary_value([<<"data">>, <<"default">>, <<"released_state">>]
                                       ,kz_json:decode(ConfigResp)
                                       ),
    verify_matches(pqc_cb_phone_numbers:remove_number(API, AccountId, PhoneNumber)
                  ,invalid_state_transition_matches(Released, Released)
                  ),

    lager:debug("deleting invalid phone number"),
    verify_matches(pqc_cb_phone_numbers:remove_number(API, AccountId, <<"+19094547519&(__+">>)
                  ,not_reconcilable_matches(<<"+19094547519&(__+">>)
                  ),

    cleanup(API, [AccountId], PhoneNumber).

-spec seq_kcro_97() -> 'ok'.
seq_kcro_97() ->
    {API, AccountId} = init_seq(?ACCOUNT_NAME),
    PhoneNumber = new_phone_number(),

    lager:debug("metadata must exists on number create response"),
    CreateResp = pqc_cb_phone_numbers:add_number(API, AccountId, PhoneNumber),
    lager:info("create resp ~p", [CreateResp]),
    'true' = has_metadata(CreateResp),

    lager:debug("metadata must exists on number update response"),
    UpdateResp = pqc_cb_phone_numbers:update_number(API, AccountId, PhoneNumber, kz_json:decode(CreateResp)),
    lager:info("update resp ~p", [UpdateResp]),
    'true' = has_metadata(UpdateResp),

    lager:debug("metadata must exists on number delete response"),
    RemoveResp = pqc_cb_phone_numbers:remove_number(API, AccountId, PhoneNumber),
    lager:info("remove resp: ~s", [RemoveResp]),
    'true' = has_metadata(RemoveResp),

    cleanup(API, [AccountId], PhoneNumber).

%% @doc testing if consumed token bucket for activating phone_number
%% is reported properly.
%%
%% This tests if merge_buckets mechanism in api_utils is collecting
%% and merging consumed tokens from all modules.
%% @end
-spec seq_kzoo_316() -> 'ok'.
seq_kzoo_316() ->
    {API, AccountId} = init_seq(?ACCOUNT_NAME),
    CurrentTokenCosts = pqc_cb_api:get_current_token_costs(API),
    pqc_cb_api:patch_token_costs(API, 1),

    Resp = pqc_cb_phone_numbers:activate_number(API, AccountId, <<"+190932147671234_&lollololol">>),

    lager:info("token bucket phone_number activate resp: ~s", [Resp]),

    pqc_cb_api:patch_token_costs(API, CurrentTokenCosts),

    JObj = kz_json:decode(Resp),

    Remaining = kz_json:get_integer_value([<<"tokens">>, <<"remaining">>], JObj),
    Consumed = kz_json:get_integer_value([<<"tokens">>, <<"consumed">>], JObj),

    case is_integer(Consumed)
        andalso Consumed >= 1
    of
        'true' ->
            lager:info("consumed ~p tokens, remaining: ~p", [Consumed, Remaining]),
            cleanup(API, [AccountId], 'undefined');
        'false' ->
            lager:error("wrong consumed tokens bucket amount ~p, expected at least 1 token bucket, remaining amount: ~p"
                       ,[Consumed, Remaining]
                       ),
            throw({'error', 'wrong_consume_tokens'})
    end.

%% @doc Tests NPANXX queries (available numbers) return only numbers matching given prefix.
%% @end
-spec seq_kcro_191() -> 'ok'.
seq_kcro_191() ->
    {API, AccountId} = init_seq(?ACCOUNT_NAME),

    PhoneNumbers = [<<?NUMBER_PREFIX/binary, "333", (pqc_util:create_number(4))/binary>>
                   ,<<?NUMBER_PREFIX/binary, "333", (pqc_util:create_number(4))/binary>>
                   ,<<?NUMBER_PREFIX/binary, "222", (pqc_util:create_number(4))/binary>>
                   ],
    Payload = kz_json:from_list([{<<"carrier_name">>, ?CARRIER_LOCAL}
                                ,{<<"numbers">>, PhoneNumbers}
                                ,{<<"create_with_state">>, ?NUMBER_STATE_AVAILABLE}
                                ]),

    CreateResp = pqc_cb_phone_numbers:add_numbers(API, AccountId, Payload),
    lager:info("create numbers resp ~p", [CreateResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(CreateResp)),

    %% Search Prefix 1
    SPrefix1 = <<(binary_part(?NUMBER_PREFIX, 2, 3))/binary, "333">>, %% 999333
    %% Search Prefix 2
    SPrefix2 = <<(binary_part(?NUMBER_PREFIX, 2, 3))/binary, "222">>, %% 999222

    %% First test {
    %% Should only return 1 number because of the given quantity.
    Nums1 = kcro191_query_and_return_data(API, AccountId, kcro191_qs(SPrefix1, <<"1">>)),
    1 = length(Nums1),
    %% Returned number must start with the given prefix.
    <<"+1", SPrefix1:6/binary, _/binary>> = kz_json:get_ne_binary_value(<<"number">>, hd(Nums1)),
    %% }

    %% Second test {
    %% Should only return 2 numbers because there are only 2 matching numbers.
    Nums2 = kcro191_query_and_return_data(API, AccountId, kcro191_qs(SPrefix1, <<"20">>)),
    %% Returned numbers must start with the given prefix.
    [N1, N2] = Nums2,
    <<"+1", SPrefix1:6/binary, _/binary>> = kz_json:get_ne_binary_value(<<"number">>, N1),
    <<"+1", SPrefix1:6/binary, _/binary>> = kz_json:get_ne_binary_value(<<"number">>, N2),
    %% }

    %% Third test {
    %% Should only return 1 number because there is only 1 matching number.
    Nums3 = kcro191_query_and_return_data(API, AccountId, kcro191_qs(SPrefix2, <<"20">>)),
    1 = length(Nums3),
    %% Returned number must start with the given prefix.
    <<"+1", SPrefix2:6/binary, _/binary>> = kz_json:get_ne_binary_value(<<"number">>, hd(Nums3)),
    %% }

    %% Fourth test {
    %% Should return an empty list as there are not matching numbers.
    [] = kcro191_query_and_return_data(API, AccountId, kcro191_qs(<<"111111">>, <<"20">>)),
    %% }

    cleanup(API, [AccountId], PhoneNumbers),
    lager:info("FINISHED KCRO_191 SEQ").

%% =======================================================================================
%% Helpers
%% =======================================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec create_change_verify_and_remove({pqc_cb_api:state(), kz_term:ne_binary()}, kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:proplist()) ->
          pqc_cb_api:response().
create_change_verify_and_remove({API, AccountId}, PhoneNumber, FromState, ToState, Matches) ->
    _ = create_number_with_state(API, AccountId, PhoneNumber, FromState),
    _ = verify_matches(change_number_state(API, AccountId, PhoneNumber, ToState), Matches),
    pqc_cb_phone_numbers:remove_number(API, AccountId, PhoneNumber).

-spec create_number_with_state(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          knm_pipe:collection() |
          pqc_cb_api:response().
create_number_with_state(_API, AccountId, PhoneNumber, ?NUMBER_STATE_DISCOVERY = State) ->
    lager:debug("creating number with ~s state", [?NUMBER_STATE_DISCOVERY]),
    Options = [{'assign_to', AccountId}, {'state', State}],
    Setters = [fun knm_phone_number:new/1
              ,fun knm_phone_number:save/1
              ],
    Result = knm_pipe:pipe(knm_pipe:new(Options, [PhoneNumber]), Setters),
    lager:info("added: ~p", [Result]),
    Result;
create_number_with_state(API, AccountId, PhoneNumber, FromState) ->
    create_number_with_state(API, AccountId, PhoneNumber, FromState, ?CARRIER_LOCAL).

-spec create_number_with_state(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
create_number_with_state(API, AccountId, PhoneNumber, FromState, Carrier) ->
    lager:debug("creating number with ~s state and carrier ~p", [FromState, Carrier]),
    ReqData = kz_json:from_list([{<<"create_with_state">>, FromState}, {<<"carrier_name">>, Carrier}]),
    Added = pqc_cb_phone_numbers:add_number(API, AccountId, PhoneNumber, ReqData),
    lager:info("added: ~p", [Added]),
    Added.

-spec change_number_state(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
change_number_state(API, AccountId, PhoneNumber, ?NUMBER_STATE_RESERVED) ->
    lager:debug("moving number state to ~s", [?NUMBER_STATE_RESERVED]),
    Reserve = pqc_cb_phone_numbers:reserve_number(API, AccountId, PhoneNumber),
    lager:info("reserved: ~s", [Reserve]),
    Reserve;
change_number_state(API, AccountId, PhoneNumber, ?NUMBER_STATE_PORT_IN) ->
    lager:debug("moving number state to ~s", [?NUMBER_STATE_PORT_IN]),
    PortNumber = pqc_cb_phone_numbers:port_number(API, AccountId, PhoneNumber),
    lager:info("porting: ~s", [PortNumber]),
    PortNumber.

-spec verify_matches(kz_term:ne_binary(), kz_term:proplist()) -> boolean().
verify_matches(Resp, Matches) ->
    JObj = kz_json:decode(Resp),
    lager:debug("verifying ~p     MATCHES     ~p", [JObj, Matches]),
    'true' = lists:all(fun({K, V}) -> V =:= kz_json:get_binary_value(K, JObj) end, Matches).

-spec bad_identifier_matches() -> kz_term:proplist().
bad_identifier_matches() ->
    [{[<<"data">>, <<"message">>], <<"bad identifier">>}
    ,{[<<"data">>, <<"not_found">>], <<"The number could not be found">>}
    ,{<<"error">>, <<"404">>}
    ,{<<"message">>, <<"bad_identifier">>}
    ,{<<"status">>, <<"error">>}
    ].

-spec no_change_required_matches() -> kz_term:proplist().
no_change_required_matches() ->
    [{[<<"data">>, <<"code">>], <<"400">>}
    ,{[<<"data">>, <<"error">>], <<"no_change_required">>}
    ,{[<<"data">>, <<"message">>], <<"no change required">>}
    ,{<<"error">>, <<"400">>}
    ,{<<"message">>, <<"no_change_required">>}
    ,{<<"status">>, <<"error">>}
    ].

-spec invalid_state_transition_matches(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:proplist().
invalid_state_transition_matches(From, To) ->
    [{[<<"data">>, <<"code">>], <<"400">>}
    ,{[<<"data">>, <<"error">>], <<"invalid_state_transition">>}
    ,{[<<"data">>, <<"cause">>], <<"from ", From/binary, " to ", To/binary>>}
    ,{[<<"data">>, <<"message">>], <<"invalid state transition">>}
    ,{<<"error">>, <<"400">>}
    ,{<<"message">>, <<"invalid_state_transition">>}
    ,{<<"status">>, <<"error">>}
    ].

-spec number_exists_matches(kz_term:ne_binary()) -> kz_term:proplist().
number_exists_matches(Number) ->
    [{[<<"data">>, <<"code">>], <<"409">>}
    ,{[<<"data">>, <<"error">>], <<"number_exists">>}
    ,{[<<"data">>, <<"cause">>], Number}
    ,{[<<"data">>, <<"message">>], <<"number ", Number/binary, " already exists">>}
    ,{<<"error">>, <<"409">>}
    ,{<<"message">>, <<"number_exists">>}
    ,{<<"status">>, <<"error">>}
    ].

-spec not_reconcilable_matches(kz_term:ne_binary()) -> kz_term:proplist().
not_reconcilable_matches(Number) ->
    [{[<<"data">>, <<"code">>], <<"400">>}
    ,{[<<"data">>, <<"error">>], <<"not_reconcilable">>}
    ,{[<<"data">>, <<"cause">>], Number}
    ,{[<<"data">>, <<"message">>], <<"number ", Number/binary, " is not reconcilable">>}
    ,{<<"error">>, <<"400">>}
    ,{<<"message">>, <<"not_reconcilable">>}
    ,{<<"status">>, <<"error">>}
    ].

-spec created_matches(kz_term:ne_binary()) -> kz_term:proplist().
created_matches(Number) ->
    [{[<<"data">>, <<"id">>], Number}
    ,{<<"status">>, <<"success">>}
    ].

-spec reserved_matches(kz_term:ne_binary()) -> kz_term:proplist().
reserved_matches(Number) ->
    [{[<<"data">>, <<"id">>], Number}
    ,{[<<"data">>, <<"state">>], ?NUMBER_STATE_RESERVED}
    ,{<<"status">>, <<"success">>}
    ].

-spec deleted_matches(kz_term:ne_binary(), pqc_cb_api:state()) -> kz_term:proplist().
deleted_matches(Number, API) ->
    ConfigResp = pqc_cb_system_configs:get_default_config(API, ?CONFIG_CAT),
    Released = kz_json:get_binary_value([<<"data">>, <<"default">>, <<"released_state">>]
                                       ,kz_json:decode(ConfigResp)
                                       ),
    [{[<<"data">>, <<"id">>], Number}
    ,{[<<"data">>, <<"state">>], Released}
    ,{<<"status">>, <<"success">>}
    ].

-spec has_metadata(kz_term:ne_binary()) -> boolean().
has_metadata(EncResp) ->
    Resp = kz_json:decode(EncResp),
    Metadata = kz_json:get_json_value(<<"metadata">>, Resp),
    lists:all(fun(Key) -> kz_json:is_defined(Key, Metadata) end
             ,[<<"id">>, <<"created">>, <<"modified">>]
             ).

-spec kcro191_qs(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
kcro191_qs(Prefix, Quantity) ->
    <<"?prefix=", Prefix/binary, "&quantity=", Quantity/binary>>.

-spec kcro191_query_and_return_data(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          kz_json:objects().
kcro191_query_and_return_data(API, AccountId, QS) ->
    GetResp = pqc_cb_phone_numbers:available_numbers(API, AccountId, QS),
    lager:info("GET phone_numbers/~p resp ~p", [QS, GetResp]),
    kz_json:get_list_value([<<"data">>], kz_json:decode(GetResp)).

init() ->
    _ = kz_data_tracing:clear_all_traces(),
    _ = [kapps_controller:start_app(App) ||
            App <- ['crossbar']
        ],
    _ = [crossbar_maintenance:start_module(Mod) ||
            Mod <- ['cb_phone_numbers']
        ],
    lager:info("INIT FINISHED").

-spec cleanup() -> any().
cleanup() ->
    lager:info("CLEANUP ALL THE THINGS"),

    properly_maintenance:cleanup_module_accounts(?MODULE),

    NumberDb = knm_converters:to_db(?NUMBER_PREFIX),
    {'ok', Docs} = kz_datamgr:all_docs(NumberDb),
    _D = kz_datamgr:del_docs(NumberDb, Docs),
    lager:info("deleted numbers ~p: ~p", [_D, Docs]).

-spec cleanup(pqc_cb_api:state(), kz_term:ne_binaries(), kz_term:api_ne_binary() | kz_term:ne_binaries()) -> 'ok'.
cleanup(API, AccountIds, 'undefined') ->
    cleanup_accounts(API, AccountIds),
    pqc_cb_api:cleanup(API);
cleanup(API, AccountIds, <<PhoneNumber/binary>>) ->
    cleanup(API, AccountIds, [PhoneNumber]);
cleanup(API, AccountIds, PhoneNumbers) ->
    cleanup_accounts(API, AccountIds),
    _ = cleanup_numbers(API, PhoneNumbers),
    pqc_cb_api:cleanup(API).

cleanup_accounts(API, AccountIds) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, AccountIds).

cleanup_numbers(API, PhoneNumbers) ->
    knm_numbers:delete(lists:filter(fun erlang:is_binary/1, PhoneNumbers)
                      ,[{'auth_by', pqc_cb_api:auth_account_id(API)}]
                      ).

new_phone_number() ->
    Number = pqc_util:create_number(7),
    <<?NUMBER_PREFIX/binary, Number/binary>>.
