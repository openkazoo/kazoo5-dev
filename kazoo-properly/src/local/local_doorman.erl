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
-module(local_doorman).

-export([local/0
        ,local_ps_137/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).

-spec local() -> 'ok'.
local() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun local_ps_137/0]
                 ).

%% Test doorman demo
-spec local_ps_137() -> 'ok'.
local_ps_137() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts', 'cb_devices', 'cb_callflows']),

    RequestData = kz_json:from_list([{<<"name">>, ?ACCOUNT_NAME}
                                    ,{<<"realm">>, <<"compy64.com">>}
                                    ]),
    AccountResp = properly_accountant:create_account(API, RequestData),
    lager:info("created account ~s", [AccountResp]),

    <<AccountId/binary>> = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    _CallerDeviceId = create_device(API, AccountId, <<"caller">>),
    CalleeDeviceId = create_device(API, AccountId, <<"callee">>),

    Extension = <<"2600">>,
    _ = create_doorman_callflow(API, AccountId, CalleeDeviceId, Extension),

    lager:info("created doorman demo at ext ~s", [Extension]).

create_device(API, AccountId, SIPCred) ->
    DeviceJObj = kz_doc:setters(seq_devices:new_device()
                               ,[{fun kzd_devices:set_sip_username/2, SIPCred}
                                ,{fun kzd_devices:set_sip_password/2, SIPCred}
                                ]
                               ),
    Resp = pqc_cb_devices:create(API, AccountId, DeviceJObj),
    lager:info("created device: ~s", [Resp]),
    <<_/binary>> = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(Resp)).

create_doorman_callflow(API, AccountId, CalleeDeviceId, Extension) ->
    %% toggle call forwarding
    DoormanCallflow = kz_json:from_list([{<<"numbers">>, [Extension]}
                                        ,{<<"patterns">>, []}
                                        ,{<<"name">>, <<"Doorman demo">>}
                                        ,{<<"flow">>
                                         ,kz_json:from_list([{<<"module">>, <<"doorman">>}
                                                            ,{<<"data">>, kz_json:from_list([{<<"id">>, CalleeDeviceId}])}
                                                            ])
                                         }
                                        ]),
    DoormanResp = pqc_cb_callflows:create(API, AccountId, DoormanCallflow),
    lager:info("doorman callflow at ~s ready: ~s", [Extension, DoormanResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(DoormanResp)).

-spec cleanup() -> 'ok'.
cleanup() ->
    properly_maintenance:cleanup_module_accounts(?MODULE).

%% -spec cleanup(pqc_cb_api:state(), kz_term:ne_binaries()) -> 'ok'.
%% cleanup(API, AccountIds) ->
%%     lager:info("CLEANUP TIME, EVERYBODY HELPS"),
%%     _ = seq_accounts:cleanup_accounts(API, AccountIds),
%%     _ = pqc_cb_api:cleanup(API),
%%     'ok'.
