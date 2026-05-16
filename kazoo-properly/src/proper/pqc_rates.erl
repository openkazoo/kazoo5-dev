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
-module(pqc_rates).
-behaviour(proper_statem).

-export([command/1
        ,initial_state/0
        ,next_state/3
        ,postcondition/3
        ,precondition/2

        ,correct/0
        ,correct_parallel/0
        ]).

-include_lib("proper/include/proper.hrl").
-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-elvis([{elvis_style, no_debug_call, disable}]).

-define(RATEDECK_NAMES, [?KZ_RATES_DB, <<"custom">>]).
-define(PHONE_NUMBERS, [<<"+12223334444">>]).
-define(ACCOUNT_NAMES, [<<"account_for_rates">>]).

-spec correct() -> any().
correct() ->
    ?FORALL(Cmds
           ,commands(?MODULE)
           ,?TRAPEXIT(
               begin
                   timer:sleep(1000),
                   try run_commands(?MODULE, Cmds) of
                       {History, Model, Result} ->
                           _ = seq_rates:cleanup(),
                           ?WHENFAIL(io:format("Final Model:~n~p~n~nFailing Cmds:~n~p~n"
                                              ,[pqc_kazoo_model:pp(Model), zip(Cmds, History)]
                                              )
                                    ,aggregate(command_names(Cmds), Result =:= 'ok')
                                    )
                   catch
                       ?STACKTRACE(_E, _R, ST)
                       io:format("exception running commands: ~s:~p~n", [_E, _R]),
                       [io:format("~p~n", [S]) || S <- ST],
                       _ = seq_rates:cleanup(),
                       'false'
                       end

               end
              )
           ).

-spec correct_parallel() -> any().
correct_parallel() ->
    ?FORALL(Cmds
           ,parallel_commands(?MODULE)
           ,?TRAPEXIT(
               begin
                   {Sequential, Parallel, Result} = run_parallel_commands(?MODULE, Cmds),
                   _ = seq_rates:cleanup(),

                   ?WHENFAIL(io:format("S: ~p~nP: ~p~n", [Sequential, Parallel])
                            ,aggregate(command_names(Cmds), Result =:= 'ok')
                            )
               end
              )
           ).

-spec init() -> 'ok'.
init() ->
    _ = kz_data_tracing:clear_all_traces(),
    _ = [kapps_controller:start_app(App) ||
            App <- ['crossbar', 'hotornot', 'tasks']
        ],
    _ = [crossbar_maintenance:start_module(Mod) ||
            Mod <- ['cb_tasks', 'cb_rates', 'cb_accounts']
        ],
    ?INFO("INIT FINISHED").

-spec initial_state() -> pqc_kazoo_model:model().
initial_state() ->
    init(),
    API = pqc_cb_api:authenticate(),
    ?INFO("state initialized to ~p", [API]),
    pqc_kazoo_model:new(API).

-spec command(any()) -> proper_types:type().
command(Model) ->
    API = pqc_kazoo_model:api(Model),

    AccountName = account_name(),
    AccountId = pqc_accounts:symbolic_account_id(Model, AccountName),

    RateDoc = seq_rates:rate_doc(ratedeck_id(), rate_cost()),

    oneof([{'call', ?MODULE, 'upload_rate', [API, RateDoc]}
          ,{'call', ?MODULE, 'delete_rate', [API, ratedeck_id()]}
          ,{'call', ?MODULE, 'get_rate', [API, RateDoc]}
          ,{'call', ?MODULE, 'rate_did', [API, ratedeck_id(), phone_number()]}
          ,pqc_accounts:command(Model, AccountName)
          ,{'call', ?MODULE, 'create_service_plan', [API, ratedeck_id()]}
          ,{'call', ?MODULE, 'assign_service_plan', [API, AccountId, ratedeck_id()]}
          ,{'call', ?MODULE, 'rate_account_did', [API, AccountId, phone_number()]}
          ]).

ratedeck_id() ->
    oneof(?RATEDECK_NAMES).

rate_cost() ->
    range(1, 10).

phone_number() ->
    elements(?PHONE_NUMBERS).

account_name() ->
    oneof(?ACCOUNT_NAMES).

-spec next_state(pqc_kazoo_model:model(), any(), any()) -> pqc_kazoo_model:model().
next_state(Model, APIResp, {'call', _, 'create_account', _Args}=Call) ->
    pqc_accounts:next_state(Model, APIResp, Call);
next_state(Model
          ,_APIResp
          ,{'call', _, 'upload_rate', [_API, RateDoc]}
          ) ->
    Ratedeck = kzd_rates:ratedeck_id(RateDoc, ?KZ_RATES_DB),
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:is_rate_missing/3, [Ratedeck, RateDoc]}
                           ,{fun pqc_kazoo_model:add_rate_to_ratedeck/3, [Ratedeck, RateDoc]}
                           ]);
next_state(Model
          ,_APIResp
          ,{'call', ?MODULE, 'get_rate', [_API, _RateDoc]}
          ) ->
    Model;
next_state(Model
          ,_APIResp
          ,{'call', _, 'delete_rate', [_API, RatedeckId]}
          ) ->
    RateDoc = seq_rates:rate_doc(RatedeckId, 0),
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:does_rate_exist/3, [RatedeckId, RateDoc]}
                           ,{fun pqc_kazoo_model:remove_rate_from_ratedeck/3, [RatedeckId, RateDoc]}
                           ]);
next_state(Model
          ,_APIResp
          ,{'call', _, 'rate_did', [_API, _RatedeckId, _PhoneNumber]}
          ) ->
    Model;
next_state(Model
          ,_APIResp
          ,{'call', ?MODULE, 'create_service_plan', [_API, RatedeckId]}
          ) ->
    ServicePlan = seq_rates:ratedeck_service_plan(RatedeckId),
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:does_ratedeck_exist/2, [RatedeckId]}
                           ,{fun pqc_kazoo_model:add_service_plan/2, [ServicePlan]}
                           ]
                          );
next_state(Model
          ,_APIResp
          ,{'call', ?MODULE, 'assign_service_plan', [_API, AccountId, RatedeckId]}
          ) ->
    PlanId = seq_rates:service_plan_id(RatedeckId),
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:does_account_exist/2, [AccountId]}
                           ,{fun pqc_kazoo_model:does_service_plan_exist/2, [PlanId]}
                           ,{fun pqc_kazoo_model:add_service_plan/3, [AccountId, seq_rates:ratedeck_service_plan(RatedeckId)]}
                           ]
                          );
next_state(Model
          ,_APIResp
          ,{'call', ?MODULE, 'rate_account_did', [_API, _AccountId, _DID]}
          ) ->
    Model.

-spec precondition(pqc_kazoo_model:model(), any()) -> boolean().
precondition(_Model, _Call) -> 'true'.

-spec postcondition(pqc_kazoo_model:model(), any(), any()) -> boolean().
postcondition(Model, Call, APIResult) ->
    case postcondition1(Model, Call, APIResult) of
        'true' -> 'true';
        'false' ->
            ?INFO("postcondition failed for ~p", [Call]),
            'false'
    end.

postcondition1(Model, {'call', _, 'create_account', _Args}=Call, APIResult) ->
    pqc_accounts:postcondition(Model, Call, APIResult);
postcondition1(_Model
              ,{'call', _, 'upload_rate', [_API, _RateDoc]}
              ,{'ok', _TaskId}
              ) ->
    'true';
postcondition1(Model
              ,{'call', ?MODULE, 'get_rate', [_API, RateDoc]}
              ,FetchResp
              ) ->
    RatedeckId = kzd_rates:ratedeck_id(RateDoc),
    case pqc_kazoo_model:is_rate_missing(Model, RatedeckId, RateDoc) of
        'true' ->
            404 =:= kz_json:get_integer_value(<<"error">>, kz_json:decode(FetchResp));
        'false' ->
            Data = kz_json:get_json_value(<<"data">>, kz_json:decode(FetchResp), kz_json:new()),
            kz_json:all(fun({K, V}) ->
                                F = kz_term:to_atom(K),
                                V =:= kzd_rates:F(Data)
                        end
                       ,RateDoc
                       )
    end;
postcondition1(Model
              ,{'call', _, 'delete_rate', [_API, RatedeckId]}
              ,APIResult
              ) ->
    RateDoc = seq_rates:rate_doc(RatedeckId, 0),
    case pqc_kazoo_model:does_rate_exist(Model, RatedeckId, RateDoc) of
        'true' ->
            Resp = kz_json:decode(APIResult),
            <<"success">> =:= kz_json:get_ne_binary_value(<<"status">>, Resp)
                andalso kz_json:is_true([<<"data">>, <<"_read_only">>, <<"deleted">>], Resp);
        'false' ->
            404 =:= kz_json:get_integer_value(<<"error">>, kz_json:decode(APIResult))
    end;
postcondition1(Model
              ,{'call', _, 'rate_did', [_API, RatedeckId, PhoneNumber]}
              ,APIResult
              ) ->
    matches_cost(Model, RatedeckId, PhoneNumber, APIResult);
postcondition1(Model
              ,{'call', ?MODULE, 'create_service_plan', [_API, RatedeckId]}
              ,APIResult
              ) ->
    case pqc_kazoo_model:does_ratedeck_exist(Model, RatedeckId) of
        'true' ->
            ?INFO("ratedeck ~s exists, creating service plan should succeed: ~p"
                 ,[RatedeckId, APIResult]
                 ),
            'ok' =:= APIResult;
        'false' ->
            ?INFO("ratedeck ~s does not exist, creating service plan should fail: ~p"
                 ,[RatedeckId, APIResult]
                 ),
            {'error', 'no_ratedeck'} =:= APIResult
    end;
postcondition1(_Model
              ,{'call', ?MODULE, 'assign_service_plan', [_API, 'undefined', _RatedeckId]}
              ,?FAILED_RESPONSE
              ) ->
    ?INFO("not assigning ratedeck ~s to undefined account", [_RatedeckId]),
    'true';
postcondition1(Model
              ,{'call', ?MODULE, 'assign_service_plan', [_API, _AccountId, RatedeckId]}
              ,APIResult
              ) ->
    PlanId = seq_rates:service_plan_id(RatedeckId),
    case pqc_kazoo_model:does_service_plan_exist(Model, PlanId) of
        'true' ->
            ?INFO("model has service plan ~s, is assigned to account ~s: ~s", [PlanId, _AccountId, APIResult]),
            'undefined' =/=
                kz_json:get_value([<<"data">>, <<"plan">>, <<"ratedeck">>, RatedeckId]
                                 ,kz_json:decode(APIResult)
                                 );
        'false' ->
            ?INFO("model does not have service plan ~s, API should not have it listed: ~s", [PlanId, APIResult]),
            'undefined' =:=
                kz_json:get_value([<<"data">>, <<"plan">>, <<"ratedeck">>, RatedeckId]
                                 ,kz_json:decode(APIResult)
                                 )
    end;
postcondition1(_Model
              ,{'call', ?MODULE, 'rate_account_did', [_API, 'undefined', _DID]}
              ,?FAILED_RESPONSE
              ) ->
    'true';
postcondition1(Model
              ,{'call', ?MODULE, 'rate_account_did', [_API, AccountId, DID]}
              ,APIResult
              ) ->
    matches_service_plan_cost(Model, AccountId, DID, APIResult).

matches_service_plan_cost(Model, AccountId, DID, APIResult) ->
    case pqc_kazoo_model:has_service_plan_rate_matching(Model, AccountId, DID) of
        {'true', Cost} when is_number(APIResult) ->
            ?INFO("model rates ~s against account ~s as ~p, got ~p in API"
                 ,[DID, AccountId, Cost, kz_currency:dollars_to_units(APIResult)]
                 ),
            Cost =:= kz_currency:dollars_to_units(APIResult);
        {'true', _Cost} ->
            ?INFO("model rates ~s against account ~s as ~p, but got ~p in API"
                 ,[DID, AccountId, _Cost, APIResult]
                 ),
            'false';
        'false' ->
            ?INFO("model has no rate for ~s against ~s, got ~p from API"
                 ,[DID, AccountId, APIResult]
                 ),
            'undefined' =:= APIResult
    end.

matches_cost(Model, RatedeckId, DID, APIResult) ->
    case pqc_kazoo_model:has_rate_matching(Model, RatedeckId, DID) of
        {'true', Cost} when is_number(APIResult) ->
            ?INFO("model rates ~s as ~p, got ~p in API"
                 ,[DID, Cost, kz_currency:dollars_to_units(APIResult)]
                 ),
            Cost =:= kz_currency:dollars_to_units(APIResult);
        {'true', _Cost} ->
            ?INFO("model rates ~s as ~p, but got ~p in API"
                 ,[DID, _Cost, APIResult]
                 ),
            'false';
        'false' ->
            ?INFO("model has no rate for ~s, got ~p from API"
                 ,[DID, APIResult]
                 ),
            'undefined' =:= APIResult
    end.
