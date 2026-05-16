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
-module(properly_util).

-export([run_seq/1
        ,seq_functions/1
        ]).

-include("properly.hrl").

-spec run_seq(atom()) -> 'ok'.
run_seq(Module) ->
    run_seq(Module, seq_exports(Module:module_info())).

run_seq(_Module, []) -> 'ok';
run_seq(Module, [{Fun, 0} | Funs]) ->
    Module:Fun(),
    run_seq(Module, Funs).

-type fun_arity() :: {atom(), 0}.
-type fun_arities() :: [fun_arity()].
-spec seq_functions(atom()) -> {fun_arities(), fun_arities()}.
seq_functions(Module) ->
    Info = Module:module_info(),
    Exports = seq_exports(Info),

    StandAlone = props:get_value(['attributes', 'properly', 'standalone'], Info, []),

    lists:partition(fun(FunArity) ->
                            not lists:member(FunArity, StandAlone)
                    end
                   ,Exports
                   ).

-spec seq_exports(kz_term:proplist()) -> [{atom(), arity()}].
seq_exports(Info) ->
    case [{Fun, 0} || {Fun, 0} <- props:get_value('exports', Info),
                      Fun >= 'seq_',
                      Fun < 'seq`'
         ]
    of
        [] -> [{'seq', 0}];
        Fs -> Fs
    end.
