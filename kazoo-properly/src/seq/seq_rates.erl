%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_rates).

-export([seq/0
        ,seq_normal/0
        ,seq_sup_33/0

        ,cleanup/0

        ,ratedeck_service_plan/1
        ,service_plan_id/1
        ,rate_doc/2
        ]).

-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(RATE_IDS
       ,[<<"PROPERLY-1222">>
        ,<<"PROPERLY-1333">>
        ,<<"PROPERLY-1444">>
        ,<<"PROPERLY-1555">>
        ,<<"PROPERLY-3334">>
        ,<<"PROPERLY-4141">>
        ,<<"PROPERLY-4449">>

        ,<<"PROPERLY-2600">> % seq_normal uses this
        ]
       ).
-define(RATEDECK_NAMES, [?KZ_RATES_DB, <<"custom">>]).
-define(PHONE_NUMBERS, [<<"+12223334444">>, <<"+2600424242">>]).

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-spec rate_doc(kz_term:ne_binary() | proper_types:type(), number() | proper_types:type()) ->
          kzd_rates:doc().
rate_doc(RatedeckId, Cost) ->
    rate_doc(RatedeckId, Cost, 1222).

-spec rate_doc(kz_term:ne_binary() | proper_types:type(), number() | proper_types:type(), integer()) ->
          kzd_rates:doc().
rate_doc(RatedeckId, Cost, Prefix) ->
    kzd_rates:from_map(#{<<"prefix">> => Prefix
                        ,<<"rate_cost">> => Cost
                        ,<<"ratedeck_id">> => RatedeckId
                        ,<<"direction">> => <<"inbound">>
                        ,<<"iso_country_code">> => <<"PROPERLY">>
                        }
                      ).

rate_doc_with_route(RatedeckId, Cost) ->
    kz_json:set_value(<<"routes">>, <<"^\\+?1333.+\$">>, rate_doc(RatedeckId, Cost, 1333)).

rate_doc_with_routes(RatedeckId, Cost) ->
    %% json encoded array for upload
    kz_json:set_value(<<"routes">>, kz_json:encode([<<"^\\+?1444.+\$">>]), rate_doc(RatedeckId, Cost, 1444)).

-spec cleanup() -> 'ok'.
cleanup() ->
    properly_maintenance:cleanup_module_accounts(?MODULE),
    API = pqc_cb_api:authenticate(),
    {P, S} = properly_util:seq_functions(?MODULE),
    _ = [pqc_cb_services:delete_service_plan(API, service_plan_id(RatedeckId))
         || {RatedeckId, _Arity} <- P ++ S
        ],
    'ok'.

-spec cleanup(pqc_cb_api:state(), kz_term:ne_binaries(), kz_json:objects()) -> 'ok'.
cleanup(API, AccountIds, RateDocs) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = [pqc_cb_rates:delete_rate(API, kz_doc:id(RateDoc), kzd_rates:ratedeck_id(RateDoc), 'false')
         || RateDoc <- RateDocs,
            'undefined' =/= kz_doc:id(RateDoc)
        ],
    _ = seq_accounts:cleanup_accounts(API, AccountIds),
    _ = [pqc_cb_services:delete_service_plan(API, service_plan_id(kzd_rates:ratedeck_id(RateDoc)))
         || RateDoc <- RateDocs
        ],
    _ = pqc_cb_services:cleanup(),
    _ = pqc_cb_api:cleanup(API),
    'ok'.

-spec service_plan_id(kz_term:ne_binary() | atom()) -> kz_term:ne_binary().
service_plan_id(RatedeckId) ->
    <<"plan_ratedeck_", (kz_term:to_binary(RatedeckId))/binary>>.

-spec initial_state(kz_term:ne_binary()) -> {pqc_cb_api:state(), kz_term:ne_binary()}.
initial_state(AccountName) ->
    API = pqc_cb_api:init_api(['crossbar','hotornot','tasks']
                             ,['cb_tasks','cb_rates','cb_accounts']
                             ),
    AccountResp = properly_accountant:create_account(API, AccountName),
    lager:info("create account resp: ~p", [AccountResp]),
    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    _ = case is_binary(AccountId) of
            'true' -> lager:info("created account ~s~n", [AccountId]);
            'false' ->
                lager:info("failed to get account id from ~s~n", [AccountResp]),
                throw('no_account_id')
        end,
    {API, AccountId}.

-spec seq() -> any().
seq() ->
    Funs = [fun seq_normal/0
           ,fun seq_sup_33/0
           ],
    lists:foreach(fun(Fun) -> Fun() end, Funs).

-spec seq_normal() -> 'ok'.
seq_normal() ->
    {API, AccountId} = initial_state(?ACCOUNT_NAME),
    RatedeckId = kz_term:to_binary(?FUNCTION_NAME),

    RateDoc = rate_doc(RatedeckId, 1.0, 2600),

    RateCost = kz_currency:units_to_dollars(
                 kapps_call_util:base_call_cost(kzd_rates:rate_cost(RateDoc)
                                               ,kzd_rates:rate_minimum(RateDoc, 60)
                                               ,kzd_rates:rate_surcharge(RateDoc)
                                               )
                ),
    lager:info("rate cost from doc: ~p", [RateCost]),

    RateDocWithRoute = rate_doc_with_route(RatedeckId, 2.0),
    RateDocWithRoutes = rate_doc_with_routes(RatedeckId, 3.0),

    {'ok', TaskId} = pqc_cb_rates:upload_rates(API, [RateDoc, RateDocWithRoute, RateDocWithRoutes]),
    lager:info("uploaded rates in task ~s~n", [TaskId]),

    'true' = lists:all(fun(D) -> validate_rate_upload(D, API) end
                      ,[RateDoc, RateDocWithRoute, RateDocWithRoutes]
                      ),

    PhoneNumber = <<"+2600424242">>,
    ListByPrefixResp = pqc_cb_rates:get_rates_by_prefix(API, PhoneNumber, RatedeckId),
    lager:info("listed by prefix: ~s", [ListByPrefixResp]),
    [Listed] = kz_json:get_list_value(<<"data">>, kz_json:decode(ListByPrefixResp)),
    'true' = kz_doc:id(Listed) =:= kz_doc:id(RateDoc),

    GetResp = pqc_cb_rates:get_rate(API, RateDoc),
    lager:info("get rate: ~s", [GetResp]),
    GetJObj = kz_json:decode(GetResp),
    RateJObj = kz_json:get_json_value(<<"data">>, GetJObj),
    lager:info("get rate: ~p~n", [RateJObj]),
    'true' = kz_doc:id(RateDoc) =:= kz_doc:id(RateJObj),

    RateCost = pqc_cb_rates:rate_did(API, kzd_rates:ratedeck_id(RateDoc), PhoneNumber),
    lager:info("successfully rated ~p using global ratedeck", [PhoneNumber]),

    'ok' = create_service_plan(API, kzd_rates:ratedeck_id(RateDoc)),
    lager:info("created service plan for ratedeck"),

    timer:sleep(1000),

    RatedeckId = kzd_rates:ratedeck_id(RateDoc),
    ServicePlanId = service_plan_id(RatedeckId),

    AssignedResp = pqc_cb_rates:assign_service_plan(API, AccountId, RatedeckId),
    lager:info("assigned service plan ~s to account ~s: ~s", [ServicePlanId, AccountId, AssignedResp]),
    AssignedJObj = kz_json:decode(AssignedResp),

    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, AssignedJObj),

    {'ok', MasterAccountId} = kapps_util:get_master_account_id(),

    MasterAccountId = kz_json:get_ne_binary_value([<<"data">>, ServicePlanId, <<"vendor_id">>], AssignedJObj),
    lager:info("assigned service plan to account ~s~n", [AccountId]),

    RateCost = pqc_cb_rates:rate_account_did(API, AccountId, PhoneNumber),
    lager:info("rated DID ~s in account ~s", [PhoneNumber, AccountId]),

    DeletedRateDoc = pqc_cb_rates:delete_rate(API, RateDoc),
    lager:info("deleted rate ~s: ~p", [kz_doc:id(RateDoc), kz_json:get_json_value(<<"data">>, kz_json:decode(DeletedRateDoc))]),

    lager:info("COMPLETED SUCCESSFULLY!"),
    _ = cleanup(API, [AccountId], [kzd_rates:set_ratedeck_id(kz_json:new(), RatedeckId)]).

-spec seq_sup_33() -> 'ok'.
seq_sup_33() ->
    {API, AccountId} = initial_state(?ACCOUNT_NAME),

    RatedeckId = kz_term:to_binary(?FUNCTION_NAME),
    Rate1 = rate_doc(RatedeckId, 0.14, 1222),
    Rate2 = rate_doc(RatedeckId, 0.7 , 4449),
    Rate3 = rate_doc(RatedeckId, 0.04, 3334),
    Rate4 = rate_doc(RatedeckId, 0.8 , 4141),
    Rate5 = rate_doc(RatedeckId, 1.8 , 1555),

    lager:info("testing import, delete and re-import rates using tasks API"),

    {'ok', _Task1} = pqc_cb_rates:upload_rates(API, [Rate1, Rate2]),
    lager:info("imported Rate1,2 with task ~s", [_Task1]),
    check_rates_existence(API, RatedeckId, [], [Rate1, Rate2]),

    {'ok', _Task2} = pqc_cb_rates:delete_rates_task(API, [Rate2]),
    lager:info("deleted Rate2 ~s with task ~s", [_Task2, Rate2]),
    check_rates_existence(API, RatedeckId, [Rate2], [Rate1]),

    {'ok', _Task3} = pqc_cb_rates:upload_rates(API, [Rate1, Rate2, Rate3]),
    lager:info("re-imported Rate1,2 and a new Rate3 rates with task ~s", [_Task3]),
    check_rates_existence(API, RatedeckId, [], [Rate1, Rate2, Rate3]),

    DeleteResp1 = pqc_cb_rates:delete_rate(API, Rate1, 'true'),
    lager:info("soft-deleted a single Rate1 ~s: ~p", [Rate1, DeleteResp1]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(DeleteResp1)),
    DeleteResp2 = pqc_cb_rates:delete_rate(API, Rate3, 'false'),
    lager:info("hard-deleted a single Rate3 ~s: ~p", [Rate3, DeleteResp2]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(DeleteResp2)),
    check_rates_existence(API, RatedeckId, [Rate1, Rate3], [Rate2]),

    {'ok', _Task4} = pqc_cb_rates:upload_rates(API, [Rate1, Rate2, Rate3, Rate4]),
    lager:info("re-imported Rate1,2,3 and a new Rate4 rates with task ~s", [_Task4]),
    check_rates_existence(API, RatedeckId, [], [Rate1, Rate2, Rate3, Rate4]),

    {'ok', _Task5} = pqc_cb_rates:delete_rates_task(API, [Rate1, Rate2, Rate3, Rate4]),
    lager:info("deleted Rate1,2,3,4 rates ~p with task ~p", [[Rate1, Rate2, Rate3, Rate4], _Task5]),
    check_rates_existence(API, RatedeckId, [Rate1, Rate2, Rate3, Rate4], []),

    lager:info("testing import, soft-delete and re-import rates using cb_rates API"),

    Rate1NewCost = kzd_rates:set_rate_cost(Rate1, 1.3),
    CreatedRate1 = pqc_cb_rates:create_rate(API, Rate1NewCost),
    lager:info("re-created Rate1 with new cost 1.3: ~p", [CreatedRate1]),
    CreateJObj1 = kz_json:decode(CreatedRate1),
    'true' = kz_json:get_ne_binary_value(<<"status">>, CreateJObj1) =:= <<"success">>,
    'true' = kz_doc:id(Rate1NewCost) =:= kz_doc:id(kz_json:get_json_value(<<"data">>, CreateJObj1)),
    'true' = kzd_rates:rate_cost(kz_json:get_json_value(<<"data">>, CreateJObj1)) =:= 1.3,

    DeleteResp3 = pqc_cb_rates:delete_rate(API, Rate1, 'true'),
    lager:info("soft-deleted a single Rate1: ~p", [DeleteResp3]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(DeleteResp3)),

    check_rates_existence(API, RatedeckId, [Rate1, Rate2, Rate3, Rate4, Rate1NewCost], []),

    lager:info("testing import, delete and re-import a compeletly new rate using cb_rates API"),
    CreateNewRate2 = pqc_cb_rates:create_rate(API, Rate5),
    lager:info("created Rate5 single rate: ~p", [CreateNewRate2]),
    'true' = lists:all(fun(D) -> validate_rate_upload(D, API) end, [Rate5]),

    DeleteResp4 = pqc_cb_rates:delete_rate(API, Rate5, 'false'),
    lager:info("hard-deleted a single Rate5: ~p", [DeleteResp4]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(DeleteResp4)),

    check_rates_existence(API, RatedeckId, [Rate1, Rate2, Rate3, Rate4, Rate5], []),

    lager:info("COMPLETED SUCCESSFULLY!"),
    _ = kz_datamgr:del_docs(?KZ_RATES_DB, [Rate1, Rate2, Rate3, Rate4]),
    _ = cleanup(API, [AccountId], [Rate1, Rate2, Rate3, Rate4, Rate5]).

check_rates_existence(API, RatedeckId, ShouldBeDeleted, ShouldBeExists) ->
    DeletedIds = [kz_doc:id(J) || J <- ShouldBeDeleted],
    ExistsIds = [kz_doc:id(J) || J <- ShouldBeExists],
    SummaryResp = pqc_cb_rates:get_rates(API, RatedeckId),
    lager:info("rate summary resp: ~s~n", [SummaryResp]),
    SummaryIds = [kz_doc:id(JObj)
                  || JObj <- kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp))
                 ],

    lager:info("check ~s rates are deleted", [kz_binary:join(DeletedIds)]),
    'true' = lists:all(fun(Id) -> not lists:member(Id, SummaryIds) end, DeletedIds),

    lager:info("check ~s exist in ~s and are not deleted"
              ,[kz_binary:join(ExistsIds), kz_binary:join(SummaryIds)]
              ),
    'true' = lists:all(fun(Id) -> lists:member(Id, SummaryIds) end, ExistsIds).

validate_rate_upload(RateDoc, API) ->
    GetResp = pqc_cb_rates:get_rate(API, RateDoc),
    GetJObj = kz_json:decode(GetResp),
    RateJObj = kz_json:get_json_value(<<"data">>, GetJObj),
    kz_doc:id(RateDoc) =:= kz_doc:id(RateJObj)
        andalso are_equal(RateDoc, RateJObj).

are_equal(RateDoc, RateJObj) ->
    lists:all(fun(<<"routes">>) ->
                      case kz_json:get_value(<<"routes">>, RateDoc) of
                          'undefined' ->
                              kzd_rates:default_routes(RateDoc) =:= kzd_rates:routes(RateJObj);
                          <<"[", _/binary>>=JSON ->
                              kz_json:decode(JSON) =:= kzd_rates:routes(RateJObj);
                          <<Route/binary>> ->
                              [Route] =:= kzd_rates:routes(RateJObj)
                      end;
                 (Key) ->
                      kz_json:get_value(Key, RateDoc) =:= kz_json:get_value(Key, RateJObj)
              end
             ,kz_json:get_keys(kz_doc:public_fields(RateDoc, 'false'))
             ).

-spec ratedeck_service_plan(kz_term:ne_binary() | kzd_rates:doc()) -> kzd_service_plan:doc().
ratedeck_service_plan(<<_/binary>> = RatedeckId) ->
    Plan = kz_json:from_list([{<<"ratedeck">>
                              ,kz_json:from_list([{RatedeckId, kz_json:new()}])
                              }
                             ]),
    Funs = [{fun kzd_service_plan:set_plan/2, Plan}],

    lists:foldl(fun({F, V}, Acc) -> F(Acc, V) end
               ,kz_json:from_list([{<<"_id">>, service_plan_id(RatedeckId)}
                                  ,{<<"pvt_type">>, <<"service_plan">>}
                                  ,{<<"name">>, <<RatedeckId/binary, " Ratedeck Service Plan">>}
                                  ])
               ,Funs
               );
ratedeck_service_plan(RateDoc) ->
    ratedeck_service_plan(kzd_rates:ratedeck_id(RateDoc)).

-spec create_service_plan(pqc_cb_api:state(), kz_term:ne_binary() | proper_types:type()) ->
          'ok' | {'error', 'no_ratedeck'}.
create_service_plan(API, RatedeckId) ->
    RatesResp = pqc_cb_rates:get_rates(API, RatedeckId),
    lager:info("rate resp: ~s~n", [RatesResp]),
    case kz_json:get_list_value(<<"data">>, kz_json:decode(RatesResp), []) of
        [] ->
            lager:info("no rates in ratedeck ~s, not creating service plan", [RatedeckId]),
            {'error', 'no_ratedeck'};
        _Rates ->
            lager:info("creating service plan for ~s", [RatedeckId]),
            {'ok', _Created} = pqc_cb_services:create_service_plan(API, ratedeck_service_plan(RatedeckId)),
            lager:info("created service plan: ~p" ,[_Created])
    end.
