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
-module(local_quickroutes).

-export([local/0
        ,cleanup/0, cleanup/1
        ]).

-include("properly.hrl").
-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec local() -> 'ok'.
local() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun local_ps_55/0]
                 ).

-spec local_ps_55() -> 'ok'.
local_ps_55() ->
    API = pqc_cb_api:init_api(['crossbar', 'ecallmgr'], ['cb_quickroutes']),

    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    lager:info("created account ~s", [AccountResp]),
    AccountId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    DeviceId = create_device(API, AccountId),

    DeviceNumber = <<"+1", (pqc_util:create_number(10))/binary>>,

    publish_quickroute(AccountId, [DeviceId], DeviceNumber),
    timer:sleep(60), % wait for propagation

    QRResp = pqc_cb_quickroutes:summary(API, AccountId),
    lager:info("qr summary: ~s", [QRResp]),
    Quickroutes = kz_json:get_json_value(<<"data">>, kz_json:decode(QRResp)),

    [DeviceId] = kz_json:get_list_value([DeviceNumber, <<"endpoints">>], Quickroutes),

    {UserId, UserDeviceId} = create_user(API, AccountId),
    UserNumber = <<"+1", (pqc_util:create_number(10))/binary>>,
    publish_quickroute(AccountId, [UserDeviceId, UserId], UserNumber),
    timer:sleep(60), % wait for propagation

    UserQRResp = pqc_cb_quickroutes:summary(API, AccountId),
    lager:info("qr summary again: ~s", [UserQRResp]),
    UserQuickroutes = kz_json:get_json_value(<<"data">>, kz_json:decode(UserQRResp)),

    [DeviceId] = kz_json:get_list_value([DeviceNumber, <<"endpoints">>], UserQuickroutes),
    [UserDeviceId, UserId] = kz_json:get_list_value([UserNumber, <<"endpoints">>], UserQuickroutes),

    cleanup(API).

-spec cleanup() -> 'ok'.
cleanup() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),
    cleanup(API).

-spec cleanup(pqc_cb_api:state()) -> 'ok'.
cleanup(API) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, ?ACCOUNT_NAMES),
    _ = pqc_cb_api:cleanup(API),
    'ok'.

create_user(API, AccountId) ->
    User = kz_doc:setters(kzd_users:new()
                         ,[{fun kzd_users:set_first_name/2, kz_binary:rand_hex(5)}
                          ,{fun kzd_users:set_last_name/2, kz_binary:rand_hex(5)}
                          ]),
    CreateResp = pqc_cb_users:create(API, AccountId, User),
    lager:info("created user in ~s: ~s", [AccountId, CreateResp]),

    UserId = kz_doc:id(kz_json:get_json_value(<<"metadata">>, kz_json:decode(CreateResp))),

    DeviceId = create_device(API, AccountId, UserId),
    {UserId, DeviceId}.

create_device(API, AccountId) ->
    create_device(API, AccountId, 'undefined').

create_device(API, AccountId, OwnerId) ->
    Device = kz_doc:setters(kzd_devices:new()
                           ,[{fun kzd_devices:set_name/2, kz_binary:rand_hex(5)}
                            ,{fun kzd_devices:set_owner_id/2, OwnerId}
                            ]
                           ),
    CreateResp = pqc_cb_devices:create(API, AccountId, Device),
    lager:info("created device in ~s: ~s", [AccountId, CreateResp]),

    kz_doc:id(kz_json:get_json_value(<<"metadata">>, kz_json:decode(CreateResp))).

publish_quickroute(AccountId, EndpointIds, Number) ->
    API = [{<<"Number">>, Number}
          ,{<<"Endpoints">>
           ,[kz_json:from_list([{<<"Endpoint-ID">>, EndpointId}
                               ,{<<"Account-ID">>, AccountId}
                               ]
                              )
             || EndpointId <- EndpointIds
            ]
           }
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    'ok' = kz_amqp_worker:cast(API, fun kapi_route:publish_quickroute/1),
    lager:info("published quickroute for ~s", [Number]).
