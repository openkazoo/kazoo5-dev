%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_devices).

-export([seq/0
        ,seq_help_18712/0
        ,seq_kcro_1114/0
        ,seq_kzoo_310/0
        ,cleanup/0
        ,new_device/0, new_device/1
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-spec seq() -> 'ok'.
seq() ->
    lists:foreach(fun run_fun/1
                 ,[fun seq_crud/0
                  ,fun seq_help_18712/0
                  ,fun seq_kcro_1114/0
                  ,fun seq_kzoo_310/0
                  ]
                 ).

run_fun(F) -> F().

seq_crud() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_devices']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_devices:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    DeviceJObj = new_device(),
    CreateResp = pqc_cb_devices:create(API, AccountId, DeviceJObj),
    lager:info("created device ~s", [CreateResp]),
    CreatedDevice = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    DeviceId = kz_doc:id(CreatedDevice),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_devices:patch(API, AccountId, DeviceId, Patch),
    lager:info("patched to ~s", [PatchResp]),

    SummaryResp = pqc_cb_devices:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryDevice] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    DeviceId = kz_doc:id(SummaryDevice),

    DeleteResp = pqc_cb_devices:delete(API, AccountId, DeviceId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_devices:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED DEVICE SEQ").

-spec seq_help_18712() -> 'ok'.
seq_help_18712() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_devices']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    BadDevice = kz_doc:setters(new_device()
                              ,[{fun kzd_devices:set_provision_combo_keys/2
                                ,[kz_json:from_list([{<<"type">>, <<"none">>}])]
                                }
                               ]
                              ),
    {'error', ErrorResp} = pqc_cb_devices:create(API, AccountId, BadDevice),
    lager:info("expected error: ~s", [ErrorResp]),
    Error = kz_json:decode(ErrorResp),
    'true' = kz_json:is_defined([<<"data">>, <<"provision.combo_keys">>], Error),
    400 = kz_json:get_integer_value(<<"error">>, Error),
    <<"validation error">> = kz_json:get_ne_binary_value(<<"message">>, Error),
    <<"error">> = kz_json:get_ne_binary_value(<<"status">>, Error),

    cleanup(API, [AccountId]),
    lager:info("FINISHED COMBO_KEYS").

%% @doc ensure provisioner brand is lowercased
-spec seq_kcro_1114() -> 'ok'.
seq_kcro_1114() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_devices']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    Brand = kz_binary:rand_hex(7),

    BadDevice = kz_doc:setters(new_device()
                              ,[{fun kzd_devices:set_provision_endpoint_brand/2
                                ,kz_term:to_upper_binary(Brand)
                                }
                               ]
                              ),
    CreateResp = pqc_cb_devices:create(API, AccountId, BadDevice),
    lager:info("created device: ~s", [CreateResp]),

    'true' = (kz_term:to_lower_binary(Brand)
              =:= kz_json:get_ne_binary_value([<<"data">>, <<"provision">>, <<"endpoint_brand">>], kz_json:decode(CreateResp))
             ),

    cleanup(API, [AccountId]),
    lager:info("FINISHED PROVISIONER BRAND").

%% Make sure devices may contain an emergency address. If addresses.emergency key is set in the
%% request, all the required emergency address' fields should be present.
-spec seq_kzoo_310() -> 'ok'.
seq_kzoo_310() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_devices']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    %% When addresses.emergency is set and all the required fields are present, the request must succeed.
    AddrFields = [{Field, kz_binary:rand_hex(4)}
                  || Field <- [<<"country">>
                              ,<<"locality">>
                              ,<<"name">>
                              ,<<"postal_code">>
                              ,<<"region">>
                              ,<<"street">>
                              ]
                 ] ++ [{<<"house_number">>, kz_term:rand_integer(1, 10)}],
    EmerAddr = kz_json:from_list_recursive([{<<"emergency">>, AddrFields}]),
    DeviceJObj = kzd_devices:set_addresses(new_device(), EmerAddr),
    CreateResp = pqc_cb_devices:create(API, AccountId, DeviceJObj),
    lager:info("created device ~s", [CreateResp]),
    CreatedDevice = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    kz_json:are_equal(kzd_devices:addresses(CreatedDevice), EmerAddr),

    %% When any of the required emergency address' fields is missing, the request should fail.
    [{FirstKey, _} | AddrFields2] = AddrFields,
    EmerAddr2 = kz_json:from_list_recursive([{<<"emergency">>, AddrFields2}]),
    DeviceJObj2 = kzd_devices:set_addresses(new_device(), EmerAddr2),
    _FailResp = {'error', ErrorRespEnc} = pqc_cb_devices:create(API, AccountId, DeviceJObj2),
    lager:info("expected failure response: ~p", [_FailResp]),

    ErrorRespData = kz_json:get_json_value(<<"data">>, kz_json:decode(ErrorRespEnc)),
    FirstKey = kz_json:get_ne_binary_value([<<"addresses.emergency.", FirstKey/binary>>, <<"required">>, <<"value">>], ErrorRespData),
    <<"Field is required but missing">> = kz_json:get_ne_binary_value([<<"addresses.emergency.", FirstKey/binary>>, <<"required">>, <<"message">>], ErrorRespData),


    cleanup(API, [AccountId]),
    lager:info("FINISHED KZOO_310 SEQ").

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = properly_maintenance:cleanup_module_accounts(?MODULE),
    cleanup_system().

cleanup(API, AccountIds) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, AccountIds),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.

-spec create_account(pqc_cb_api:state(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_account(API, AccountName) ->
    AccountResp = properly_accountant:create_account(API, AccountName),
    lager:info("created account: ~s", [AccountResp]),

    kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)).

-spec new_device() -> kzd_devices:doc().
new_device() ->
    new_device(kz_json:new()).

-spec new_device(kzd_devices:doc()) -> kzd_devices:doc().
new_device(DeviceJObj) ->
    kz_doc:public_fields(
      kzd_devices:set_name(kz_json:merge(DeviceJObj, kzd_devices:new())
                          ,kz_binary:rand_hex(4)
                          )
     ).
