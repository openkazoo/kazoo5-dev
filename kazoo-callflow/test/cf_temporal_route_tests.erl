%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_temporal_route_tests).

-include_lib("kazoo_stdlib/include/kz_types.hrl"). %% ?SECONDS_IN_DAY
-include("module/cf_temporal_route.hrl").
-include_lib("eunit/include/eunit.hrl").

maybe_build_rule_test_() ->
    TZ = <<"UTC">>,
    NowDT = {Today, _} = kz_time:adjust_utc_datetime(calendar:universal_time(), TZ),
    LSec = calendar:datetime_to_gregorian_seconds(NowDT),

    TodayGS = kz_time:to_gregorian_seconds({Today, {0, 0, 0}}, TZ),
    TodayBin = kz_date:to_iso8601(Today),
    YesterdayGS = TodayGS - ?SECONDS_IN_DAY,
    YesterdayBin = kz_date:to_iso8601(YesterdayGS),
    TomorrowGS = TodayGS + ?SECONDS_IN_DAY,
    TomorrowBin = kz_date:to_iso8601(TomorrowGS),

    RunTest = fun(Id, RulesDoc) ->
                      cf_temporal_route:maybe_build_rule([], LSec, <<"unknown">>, TZ, NowDT, [], Id, RulesDoc)
              end,

    Inputs = [{"Just StartDate, in the past: rule built", kz_binary:rand_hex(4), rules_doc(YesterdayGS)}
             ,{"Just StartDate, in the future: rule skipped", 'undefined', rules_doc(TomorrowGS)}
             ,{"StartDate in the past, EndDate in the past: rule skipped", 'undefined', rules_doc(YesterdayGS, YesterdayGS+1)}
             ,{"StartDate in the past, EndDate in the future: rule built", kz_binary:rand_hex(4), rules_doc(YesterdayGS, TomorrowGS)}
             ,{"StartDate in the future, EndDate in the future: rule skipped", 'undefined', rules_doc(TomorrowGS, TomorrowGS+1)}
             ,{"Just StartDate, in the past and excluded today: rule skipped", 'undefined', rules_doc(YesterdayGS, 'undefined', [TodayBin])}
             ,{"Just StartDate, in the past and excluded yesterday and tomorrow: rule built"
              ,kz_binary:rand_hex(4)
              ,rules_doc(YesterdayGS, 'undefined', [YesterdayBin, TomorrowBin])
              }
             ,{"StartDate in the past, EndDate in the future and excluded today: rule skipped"
              ,'undefined'
              ,rules_doc(YesterdayGS, TomorrowGS, [TodayBin])
              }
             ,{"StartDate in the past, EndDate in the future and excluded yesterday and tomorrow: rule built"
              ,kz_binary:rand_hex(4)
              ,rules_doc(YesterdayGS, TomorrowGS, [YesterdayBin, TomorrowBin])
              }
             ],
    [{Label, try_rules_doc(RunTest, RuleId, RulesDoc)}
     || {Label, RuleId, RulesDoc} <- Inputs
    ].

try_rules_doc(RunTest, 'undefined', RulesDoc) ->
    ?_assertEqual([], RunTest(kz_binary:rand_hex(4), RulesDoc));
try_rules_doc(RunTest, RuleId, RulesDoc) ->
    [BuildRule|_] = RunTest(RuleId, RulesDoc),
    ?_assertEqual(RuleId, rule_id(BuildRule)).

-spec rules_doc(kz_time:gregorian_seconds()) -> kzd_temporal_rules:doc().
rules_doc(StartDate) ->
    rules_doc(StartDate, 'undefined').

-spec rules_doc(kz_time:gregorian_seconds(), kz_time:gregorian_seconds()) -> kzd_temporal_rules:doc().
rules_doc(StartDate, EndDate) ->
    rules_doc(StartDate, EndDate, 'undefined').

-spec rules_doc(kz_time:gregorian_seconds(), kz_time:gregorian_seconds(), kz_term:api_ne_binaries()) -> kzd_temporal_rules:doc().
rules_doc(StartDate, EndDate, Exclude) ->
    Setters = [{fun kzd_temporal_rules:set_start_date/2, StartDate}
              ,{fun kzd_temporal_rules:set_end_date/2, EndDate}
              ,{fun kzd_temporal_rules:set_exclude/2, Exclude}
              ],
    kz_doc:setters(kzd_temporal_rules:new(), Setters).

-spec rule_id(rule()) -> kz_term:ne_binary().
rule_id(#rule{id = Id}) -> Id.
