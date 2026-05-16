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
-module(properly_maintenance).

-export([run_modules/0
        ,run_module/1
        ,run_seq_modules/0
        ,run_seq_module/1
        ,modules/0
        ,cleanup_module_accounts/1
        ]).

-include("properly.hrl").

-elvis([{elvis_style, no_debug_call, disable}]).

-spec run_modules() -> 'no_return'.
run_modules() ->
    {'ok', _} = kapps_controller:start_app('properly'),
    _ = [run_module(M) || M <- modules()],
    'no_return'.

-spec run_module(atom() | kz_term:ne_binary()) -> 'no_return'.
run_module(Module) when is_atom(Module) ->
    Module = kz_module:ensure_loaded(Module),
    _ = quickcheck_exports(Module),
    'no_return';
run_module(ModuleBin) ->
    run_module(kz_term:to_atom(ModuleBin)).

-spec quickcheck_exports(module()) -> 'ok'.
quickcheck_exports(Module) ->
    _ = [quickcheck_export(Module, Function)
         || Function <- ['correct', 'correct_parallel'],
            kz_module:is_exported(Module, Function, 0)
        ],
    'ok'.

-spec quickcheck_export(module(), atom()) -> 'true'.
quickcheck_export(Module, Function) ->
    io:format("quick-checking ~s:~s/0~n", [Module, Function]),
    'true' = proper:quickcheck(Module:Function()).

-spec run_seq_modules() -> non_neg_integer().
run_seq_modules() ->
    {'ok', _} = kapps_controller:start_app('properly'),
    API = pqc_cb_api:init_api(['crossbar'], ['cb_system_configs']),
    _ = pqc_cb_api:patch_token_costs(API, 0),

    Modules = modules(),
    StartTime = kz_time:start_time(),
    Results = lists:foldl(fun run_seq_module_fold/2, [], Modules),
    ?SUP_LOG_DEBUG(":: finished running ~p modules in ~s~n"
                  ,[length(Modules), kz_time:pretty_print_elapsed_s(StartTime)]
                  ),
    lists:foldl(fun handle_results/2, 0, Results).

handle_results({Module, {'ok', SeqTests}}, HaltCode) ->
    case seq_fails(SeqTests) of
        0 -> HaltCode;
        N ->
            ?SUP_LOG_DEBUG("module ~s had no parallel failures and ~p sequential failures"
                          ,[Module, N]
                          ),
            HaltCode + N
    end;
handle_results({Module, {{'parallel_failures', PFail}, SeqTests}}, HaltCode) ->
    case seq_fails(SeqTests) of
        0 ->
            ?SUP_LOG_DEBUG("module ~s had ~p parallel failures and no sequential failures"
                          ,[Module, PFail]
                          ),
            HaltCode + PFail;
        N ->
            ?SUP_LOG_DEBUG("module ~s had ~p parallel failures and ~p sequential failures"
                          ,[Module, PFail, N]
                          ),
            HaltCode + PFail + N
    end.

seq_fails(SeqTests) ->
    lists:sum([1 || S <- SeqTests, S =/= 'ok']).

run_seq_module_fold(Module, Acc) ->
    [{Module, run_seq_module(kz_term:to_atom(Module, 'true'))} | Acc].

-spec run_seq_module(atom() | kz_term:ne_binary()) -> {'ok' | {'parallel_failures', pos_integer()}
                                                      ,['ok']
                                                      }.
run_seq_module(Module) when is_binary(Module) ->
    run_seq_module(kz_term:to_atom(Module));
run_seq_module(Module) ->
    {Parallel, StandAlone} = properly_util:seq_functions(Module),
    ?SUP_LOG_DEBUG(":: Running ~s ~p tests in parallel, ~p standalone"
                  ,[Module, length(Parallel), length(StandAlone)]
                  ),
    'ok' = httpc:set_options([{'max_sessions', length(Parallel) * 2 + length(StandAlone) + 1}]),

    StartTime = kz_time:start_time(),
    PidRefs = lists:map(fun(F) -> kz_process:spawn_monitor(fun run_seq_fun/2, [Module, F]) end
                       ,Parallel
                       ),
    ParallelResults = wait_for_pidrefs(PidRefs),
    ParallelTime = kz_time:start_time(),
    ?SUP_LOG_DEBUG(" ~s parallel took ~pms", [Module, kz_time:elapsed_ms(StartTime, ParallelTime)]),

    StandAloneResults = lists:map(fun(F) -> catch run_seq_fun(Module, F) end, StandAlone),
    StandAloneTime = kz_time:start_time(),
    ?SUP_LOG_DEBUG(" ~s stand alone took ~pms", [Module, kz_time:elapsed_ms(ParallelTime, StandAloneTime)]),

    ?SUP_LOG_DEBUG("~s tests ran in ~s", [Module, kz_time:pretty_print_elapsed_s(StartTime)]),
    {ParallelResults, StandAloneResults}.

wait_for_pidrefs(PidRefs) ->
    wait_for_pidrefs(PidRefs, 0).

wait_for_pidrefs([], 0) -> 'ok';
wait_for_pidrefs([], N) ->
    flush_mb(),
    {'parallel_failures', N};
wait_for_pidrefs([{Pid, Ref} | PidRefs], Failures) ->
    receive
        {'DOWN', Ref, 'process', Pid, 'normal'} ->
            wait_for_pidrefs(PidRefs, Failures);
        {'DOWN', Ref, 'process', Pid, Reason} ->
            handle_error_reason(PidRefs, Failures, Pid, Reason)
    after 30 * ?MILLISECONDS_IN_SECOND ->
            ?SUP_LOG_INFO("timed out waiting for parallel process ~p(~p) to finish", [Pid, Ref]),
            wait_for_pidrefs(PidRefs, Failures+1)
    end.

flush_mb() ->
    receive
        Msg ->
            ?SUP_LOG_INFO("unhandled message: ~p", [Msg]),
            flush_mb()
    after 0 -> 'ok'
    end.

%% sometimes couch barfs and we get the bubbled up 503 error
handle_error_reason(PidRefs, Failures, Pid
                   ,{'function_clause',
                     [{'kz_json','decode'
                      ,[{'error',<<ErrorJSON/binary>>}]
                      ,_Location
                      }
                     | _Stack
                     ]}=_Reason
                   ) ->
    handle_503_error_response(PidRefs, Failures, Pid, ErrorJSON);
%% sometimes the view lookup for unique realm/name fails with 503
%% but we get back the 400 validation error
handle_error_reason(PidRefs, Failures, Pid
                   ,{{'badmatch', {'error', <<ErrorJSON/binary>>}}
                    ,[{_M,_F,_Arity,_Location}
                     | _Stack
                     ]
                    }=_Reason
                   ) ->
    ErrorResp = kz_json:decode(ErrorJSON),

    UniquenessFail = (kz_json:is_defined([<<"data">>, <<"realm">>, <<"unique">>, <<"message">>], ErrorResp)
                      orelse kz_json:is_defined([<<"data">>, <<"name">>, <<"unique">>, <<"message">>], ErrorResp)
                     ),

    case kz_json:get_integer_value(<<"error">>, ErrorResp) =:= 400
        andalso UniquenessFail
    of
        'true' ->
            ?SUP_LOG_INFO("test in ~p failed with 400 non-unique realm/name, not counting as a failure", [Pid]),
            wait_for_pidrefs(PidRefs, Failures);
        'false' ->
            ?SUP_LOG_INFO("test in ~p exited with ~p", [Pid, _Reason]),
            wait_for_pidrefs(PidRefs, Failures+1)
    end;
handle_error_reason(PidRefs, Failures, Pid
                   ,{{'nocatch',
                      {'invalid_json'
                      ,{'error','function_clause'}
                      ,{'error', ErrorJSON}
                      }
                     }
                    ,_ST
                    }) ->
    handle_503_error_response(PidRefs, Failures, Pid, ErrorJSON);
handle_error_reason(PidRefs, Failures, Pid
                   ,{'error','socket_closed_remotely'}
                   ) ->
    ?SUP_LOG_INFO("test in ~p exited because crossbar broke, not counting as failure"
                 ,[Pid]
                 ),
    wait_for_pidrefs(PidRefs, Failures);
handle_error_reason(PidRefs, Failures, Pid, _Reason) ->
    ?SUP_LOG_INFO("test in ~p exited with ~p", [Pid, _Reason]),
    wait_for_pidrefs(PidRefs, Failures+1).

handle_503_error_response(PidRefs, Failures, Pid, ErrorJSON) ->
    ErrorResp = kz_json:decode(ErrorJSON),
    case kz_json:get_integer_value(<<"error">>, ErrorResp) of
        503 ->
            ?SUP_LOG_INFO("test in ~p failed with a 503, not counting as a failure"
                         ,[Pid]
                         ),
            wait_for_pidrefs(PidRefs, Failures);
        400 ->
            case lists:any(fun(UE) ->
                                   kz_json:is_defined([<<"data">>, UE, <<"unique">>], ErrorResp)
                           end
                          ,[<<"sip.username">>, <<"realm">>, <<"name">>]
                          )
            of
                'true' ->
                    ?SUP_LOG_INFO("test in ~p failed with uniqueness error, not counting as a failure"
                                 ,[Pid]
                                 ),
                    wait_for_pidrefs(PidRefs, Failures);
                'false' ->
                    count_error(PidRefs, Failures, Pid, ErrorJSON)
            end;
        _Error ->
            count_error(PidRefs, Failures, Pid, ErrorJSON)
    end.

count_error(PidRefs, Failures, Pid, ErrorJSON) ->
    ?SUP_LOG_INFO("test in ~p exited with error JSON ~s", [Pid, ErrorJSON]),
    wait_for_pidrefs(PidRefs, Failures+1).

run_seq_fun(Module, {Function, 0}) ->
    ?SUP_LOG_DEBUG("::   running ~s:~s/0 in ~p", [Module, Function, self()]),
    StartTime = kz_time:start_time(),
    Module:Function(),
    timer:sleep(100),
    ?SUP_LOG_DEBUG("::   finished ~s:~s/0 in ~p: ~pms", [Module, Function, self(), kz_time:elapsed_ms(StartTime)]).

local_functions(Module) ->
    Info = Module:module_info(),
    local_exports(Info).

local_exports(Info) ->
    [{Fun, 0} || {Fun, 0} <- props:get_value('exports', Info),
                 Fun >= 'local_',
                 Fun < 'local`'
    ].

-spec cleanup_module_accounts(kz_term:text()) -> 'ok'.
cleanup_module_accounts(M) ->
    Module = kz_term:to_atom(M, 'true'),
    {Ps, Ss} = properly_util:seq_functions(Module),
    Ls = local_functions(Module),
    AccountNames = [list_to_binary([kz_term:to_binary(M), "_", kz_term:to_binary(F)])
                    || {F, _A} <- Ps++Ss++Ls
                   ],
    ?SUP_LOG_DEBUG("cleaning up ~s accounts: ~p", [M, AccountNames]),
    seq_accounts:cleanup_accounts(AccountNames).

-spec modules() -> [module()].
modules() ->
    Ms = case application:get_key('properly', 'modules') of
             {'ok', Modules} ->
                 [Module || Module <- Modules,
                            'pqc_cb_skels' =/= Module,
                            kz_module:is_exported(Module, 'seq', 0)
                 ];
             'undefined' ->
                 'ok' = application:load('properly'),
                 modules()
         end,
    kz_term:shuffle_list(Ms).
