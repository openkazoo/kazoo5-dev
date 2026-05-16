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
-module(seq_ips).

-export([cleanup/0, cleanup/1
        ,seq/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<"account_for_ips">>]).

-define(ADDRESS, <<"1.2.3.4">>).
-define(HOSTNAME, <<"a.host.com">>).
-define(ZONE, <<"zone-1">>).
-define(IP, ?DEDICATED(?ADDRESS, ?HOSTNAME, ?ZONE)).

-spec cleanup() -> any().
cleanup() ->
    cleanup(pqc_cb_api:authenticate()).

-spec cleanup(pqc_cb_api:state()) -> any().
cleanup(API) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    kz_data_tracing:clear_all_traces(),

    _ = pqc_cb_ips:delete_ip(API, ?IP),
    _ = seq_accounts:cleanup_accounts(API, ?ACCOUNT_NAMES),

    pqc_cb_api:cleanup(API).

init() ->
    _ = kz_data_tracing:clear_all_traces(),
    _ = [kapps_controller:start_app(App) ||
            App <- ['crossbar']
        ],
    _ = [crossbar_maintenance:start_module(Mod) ||
            Mod <- ['cb_ips', 'cb_accounts']
        ],
    lager:info("INIT FINISHED").

-spec seq() -> 'ok'.
seq() ->
    _ = init(),
    Model = pqc_ips:initial_state(),
    API = pqc_kazoo_model:api(Model),

    {'ok', Created} = pqc_cb_ips:create_ip(API, ?IP),
    lager:info("created ip ~p", [Created]),

    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    AccountId = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),
    lager:info("created account ~s", [AccountId]),

    {'ok', [IPResp]} = pqc_cb_ips:list_ips(API),
    lager:info("ip available: ~p", [IPResp]),
    ?ADDRESS = kz_json:get_value(<<"ip">>, IPResp),
    ?ZONE = kz_json:get_value(<<"zone">>, IPResp),

    {'ok', Assigned} = pqc_cb_ips:assign_ip(API, AccountId, ?IP),
    lager:info("assigned ~p: ~p", [?IP, Assigned]),

    Successes = kz_json:get_json_value(<<"success">>, Assigned),
    SuccessIP = kz_json:get_value(?ADDRESS, Successes),
    _ = validate_ip(AccountId, SuccessIP),

    {'ok', Fetched} = pqc_cb_ips:fetch_ip(API, AccountId, ?IP),
    lager:info("fetched ~p: ~p", [?IP, Fetched]),
    _ = validate_ip(AccountId, Fetched),

    {'ok', Hosts} = pqc_cb_ips:fetch_hosts(API),
    lager:info("hosts: ~p", [Hosts]),
    [?HOSTNAME] = Hosts,

    {'ok', Zones} = pqc_cb_ips:fetch_zones(API),
    lager:info("zones: ~p", [Zones]),
    [?ZONE] = Zones,

    {'ok', [AssignedIP]} = pqc_cb_ips:fetch_assigned(API, AccountId),
    lager:info("assigned ip: ~p", [AssignedIP]),
    ?ADDRESS = kz_json:get_value(<<"ip">>, SuccessIP),
    ?ZONE = kz_json:get_value(<<"zone">>, SuccessIP),

    _ = cleanup(API),
    lager:info("FINISHED SEQ IPS").

validate_ip(AccountId, SuccessIP) ->
    ?ADDRESS = kz_json:get_value(<<"ip">>, SuccessIP),
    ?ZONE = kz_json:get_value(<<"zone">>, SuccessIP),
    ?HOSTNAME = kz_json:get_value(<<"host">>, SuccessIP),
    AccountId = kz_json:get_value(<<"assigned_to">>, SuccessIP),
    <<"assigned">> = kz_json:get_value(<<"status">>, SuccessIP),
    <<"dedicated_ip">> = kz_json:get_value(<<"type">>, SuccessIP).
