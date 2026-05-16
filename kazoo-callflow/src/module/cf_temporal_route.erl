%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Controls and picks Callflows based rules.
%%%
%%% <h4>Data options:</h4>
%%% <dl>
%%%   <dt>`action'</dt>
%%%   <dd>One of: `menu', `enable', `disable', `reset'.</dd>
%%%
%%%   <dt>`rules'</dt>
%%%   <dd>List of the rules.</dd>
%%%
%%%   <dt>`interdigit_timeout'</dt>
%%%   <dd>How long to wait for the next DTMF, in milliseconds. Default is 2000.</dd>
%%% </dl>
%%%
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_temporal_route).

-behaviour(gen_cf_action).

-include("callflow.hrl").
-include("cf_temporal_route.hrl").

-export([handle/2]).

-ifdef(TEST).
-export([maybe_build_rule/8]).
-endif.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> any().
handle(Data, Call) ->
    #temporal{local_sec=LocalSeconds
             ,local_date=LocalDate
             } = Temporal
        = get_temporal_route(Data, Call),
    case action(Data) of
        <<"menu">> ->
            lager:info("temporal rules main menu"),
            _ = temporal_route_menu(Temporal, rule_ids(Data), Call),
            cf_exe:continue(Call);
        <<"enable">> ->
            lager:info("force temporal rules to enable"),
            _ = enable_temporal_rules(Temporal, rule_ids(Data), Call),
            cf_exe:continue(Call);
        <<"disable">> ->
            lager:info("force temporal rules to disable"),
            _ = disable_temporal_rules(Temporal, rule_ids(Data), Call),
            cf_exe:continue(Call);
        <<"reset">> ->
            lager:info("resume normal temporal rule operation"),
            _ = reset_temporal_rules(Temporal, rule_ids(Data), Call),
            cf_exe:continue(Call);
        _Action ->
            Rules = get_temporal_rules(Temporal, Call),
            case ktr_routes:process(LocalSeconds, LocalDate, Rules) of
                'undefined' ->
                    cf_exe:continue(Call);
                ChildId ->
                    cf_exe:continue(ChildId, Call)
            end
    end.


%%------------------------------------------------------------------------------
%% @doc Finds and returns a list of rule records that have do not occur in
%% the future as well as pertain to this temporal route mapping.
%% @end
%%------------------------------------------------------------------------------
-spec get_temporal_rules(temporal(), kapps_call:call()) -> rules().
get_temporal_rules(#temporal{local_sec=LocalSeconds
                            ,routes=Routes
                            ,timezone=TZ
                            }
                  ,Call
                  ) ->
    get_temporal_rules(Routes, LocalSeconds, kapps_call:account_db(Call), TZ, []).

-spec get_temporal_rules(routes(), kz_time:gregorian_seconds(), kz_term:ne_binary(), kz_term:ne_binary(), rules()) -> rules().
get_temporal_rules(Routes, LocalSeconds, AccountDb, <<TZ/binary>>, Rules) ->
    NowDatetime = kz_time:adjust_utc_datetime(calendar:universal_time(), TZ),
    get_temporal_rules(Routes, LocalSeconds, AccountDb, TZ, NowDatetime, Rules).

-spec get_temporal_rules(routes(), kz_time:gregorian_seconds(), kz_term:ne_binary(), kz_term:ne_binary(), kz_time:datetime(), rules()) -> rules().
get_temporal_rules([], _, _, _, _, Rules) -> lists:reverse(Rules);
get_temporal_rules([{RouteId, CallflowChildKey}|Routes], LocalSeconds, AccountDb, TZ, NowDatetime, Rules) ->
    case kz_datamgr:open_cache_doc(AccountDb, RouteId) of
        {'error', _R} ->
            lager:info("unable to find temporal rule ~s in ~s", [RouteId, AccountDb]),
            get_temporal_rules(Routes, LocalSeconds, AccountDb, TZ, NowDatetime, Rules);
        {'ok', TemporalRulesDoc} ->
            maybe_build_rule(Routes, LocalSeconds, AccountDb, TZ, NowDatetime, Rules, CallflowChildKey
                            ,TemporalRulesDoc
                            )
    end.

-spec maybe_build_rule(routes(), kz_time:gregorian_seconds(), kz_term:ne_binary(), kz_term:ne_binary(), kz_time:datetime(), rules(), kz_term:ne_binary(), kzd_temporal_rules:doc()) -> rules().
maybe_build_rule(Routes, LocalSeconds, AccountDb, TZ, NowDatetime, Rules, CallflowChildKey, TemporalRulesDoc) ->
    StartDate = kz_date:from_gregorian_seconds(kzd_temporal_rules:start_date(TemporalRulesDoc, LocalSeconds), TZ),
    EndDate = maybe_date_from_gregorian_seconds(kzd_temporal_rules:end_date(TemporalRulesDoc), TZ),
    RuleName = kzd_temporal_rules:name(TemporalRulesDoc, ?RULE_DEFAULT_NAME),

    case ktr_rule:should_build_rule(NowDatetime
                                   ,{StartDate, {0,0,0}}
                                   ,{EndDate, {23,59,59}}
                                   ,kzd_temporal_rules:exclude(TemporalRulesDoc, [])
                                   )
    of
        'false' ->
            lager:warning("rule ~s is either in the past, future, or excluded; discarding", [RuleName]),
            get_temporal_rules(Routes, LocalSeconds, AccountDb, TZ, NowDatetime, Rules);
        'true' ->
            lager:debug("building rule ~s (branch to ~s)", [RuleName, CallflowChildKey]),
            get_temporal_rules(Routes, LocalSeconds, AccountDb, TZ, NowDatetime
                              ,[ktr_rule:new(CallflowChildKey, TemporalRulesDoc, StartDate, EndDate) | Rules]
                              )
    end.

-spec maybe_date_from_gregorian_seconds(end_date(), kz_term:ne_binary()) -> end_date().
maybe_date_from_gregorian_seconds('undefined', _TZ) -> 'undefined';
maybe_date_from_gregorian_seconds(EndDate, TZ) -> kz_date:from_gregorian_seconds(EndDate, TZ).

%%------------------------------------------------------------------------------
%% @doc Loads the temporal record with data from the db.
%% @end
%%------------------------------------------------------------------------------
-spec maybe_load_rules(kz_json:object(), kapps_call:call(), routes()) -> routes().
maybe_load_rules(Data, _Call, Routes) ->
    RuleIDs = rule_ids(Data),
    lager:info("loaded ~p routes from rules", [length(RuleIDs)]),
    Routes ++ [{ID, ID} || ID <- RuleIDs].

-spec maybe_load_branch_keys(kz_json:object(), kapps_call:call(), routes()) -> routes().
maybe_load_branch_keys(_Data, Call, Routes) ->
    {'branch_keys', Rules} = cf_exe:get_branch_keys(Call),
    lager:info("loaded ~p routes from branch_keys", [length(Rules)]),
    Routes ++ [{X, X} || X <- Rules].

-spec maybe_load_rulesets(kz_json:object(), kapps_call:call(), routes()) -> routes().
maybe_load_rulesets(Data, Call, Routes) ->
    case rule_set_id(Data) of
        'undefined' ->
            lager:info("no rule_set id configured"),
            Routes;
        RuleSetId ->
            lager:info("loading rules from rule_set ~p", [RuleSetId]),
            Routes ++ [{X, <<"rule_set">>} || X <- get_rule_set(RuleSetId, Call)]
    end.

-spec maybe_expand_rulesets(kapps_call:call(), routes()) -> routes().
maybe_expand_rulesets(Call, Rules) ->
    try_load_rulesets(Call, lists:flatten(Rules), []).

-spec try_load_rulesets(kapps_call:call(), routes(), routes()) -> routes().
try_load_rulesets(_Call, [], Acc) ->
    lists:reverse(Acc);

try_load_rulesets(Call, [{_,<<"rule_set">>}=H|T], Acc) ->
    try_load_rulesets(Call, T, [H | Acc]);

try_load_rulesets(Call, [{Id, _}|T], Acc) ->
    NewRules = case get_rule_set(Id, Call) of
                   [] ->
                       [{Id, Id} | Acc];
                   SetVals ->
                       lager:info("loaded ~p rules from rule_set ~p", [length(SetVals), Id]),
                       [{X, Id} || X <- SetVals] ++ Acc
               end,
    try_load_rulesets(Call, T, NewRules).

-spec get_temporal_route(kz_json:object(), kapps_call:call()) -> temporal().
get_temporal_route(Data, Call) ->
    lager:info("loading temporal route..."),

    Rules = lists:foldl(fun(F, A) -> F(Data, Call, A) end
                       ,[]
                       ,[fun maybe_load_rules/3 % {RouteId, RouteId}
                        ,fun maybe_load_branch_keys/3 % {ChildKey, ChildKey}
                        ,fun maybe_load_rulesets/3 % {RouteId, "rule_set"}
                        ]),
    Expanded = maybe_expand_rulesets(Call, Rules),

    lager:info("routes are: ~p", [Expanded]),

    load_current_time(#temporal{routes = Expanded
                               ,timezone = cf_util:get_timezone(Data, Call)
                               ,interdigit_timeout = interdigit_timeout(Data)
                               }
                     ).

%%------------------------------------------------------------------------------
%% @doc Loads rules set from account db.
%% @end
%%------------------------------------------------------------------------------
-spec get_rule_set(route() | kz_term:ne_binary(), kapps_call:call()) -> kz_term:ne_binaries().
get_rule_set({Id, Id}, Call) ->
    get_rule_set(Id, Call);

get_rule_set(Id, Call) ->
    AccountId = kapps_call:account_id(Call),
    lager:info("loading temporal rule set ~s", [Id]),
    case kz_datamgr:open_cache_doc(AccountId, Id) of
        {'error', _E} ->
            lager:error("failed to load ~s in ~s", [Id, AccountId]),
            [];
        {'ok', TemporalRulesSet} ->
            kzd_temporal_rules_sets:temporal_rules(TemporalRulesSet, [])
    end.

%%------------------------------------------------------------------------------
%% @doc Present the caller with the option to enable, disable, or reset
%% the provided temporal rules.
%% @end
%%------------------------------------------------------------------------------
-spec temporal_route_menu(temporal(), rule_ids(), kapps_call:call()) -> cf_api_std_return().
temporal_route_menu(#temporal{keys=#keys{enable=Enable
                                        ,disable=Disable
                                        ,reset=Reset
                                        }
                             ,prompts=#prompts{main_menu=MainMenu}
                             ,interdigit_timeout=Interdigit
                             }=Temporal
                   ,Rules
                   ,Call
                   ) ->
    NoopId = kapps_call_command:prompt(MainMenu, Call),

    case kapps_call_command:collect_digits(1
                                          ,kapps_call_command:default_collect_timeout()
                                          ,Interdigit
                                          ,NoopId
                                          ,Call
                                          )
    of
        {'ok', Enable} ->
            enable_temporal_rules(Temporal, Rules, Call);
        {'ok', Disable} ->
            disable_temporal_rules(Temporal, Rules, Call);
        {'ok', Reset} ->
            reset_temporal_rules(Temporal, Rules, Call);
        {'error', _} ->
            {'ok', kz_json:new()};
        {'ok', _} ->
            temporal_route_menu(Temporal, Rules, Call)
    end.

%%------------------------------------------------------------------------------
%% @doc Retrieve and update the enabled key on the temporal rule document.
%% Also plays messages to the caller based on the results of that
%% operation.
%% @end
%%------------------------------------------------------------------------------
-spec disable_temporal_rules(temporal(), rule_ids(), kapps_call:call()) -> cf_api_std_return().
disable_temporal_rules(#temporal{prompts=#prompts{marked_disabled=Disabled}}, [], Call) ->
    kapps_call_command:b_prompt(Disabled, Call);
disable_temporal_rules(Temporal, [RuleId|T]=Rules, Call) ->
    try
        AccountDb = kapps_call:account_db(Call),
        {'ok', JObj} = kz_datamgr:open_doc(AccountDb, RuleId),
        case kz_datamgr:save_doc(AccountDb, kzd_temporal_rules:set_enabled(JObj, 'false')) of
            {'ok', _} ->
                lager:info("set temporal rule ~s to disabled", [RuleId]),
                disable_temporal_rules(Temporal, T, Call);
            {'error', 'conflict'} ->
                lager:info("conflict during disable of temporal rule ~s, trying again", [RuleId]),
                disable_temporal_rules(Temporal, Rules, Call);
            {'error', R1} ->
                lager:info("unable to update temporal rule ~s, ~p", [RuleId, R1]),
                disable_temporal_rules(Temporal, T, Call)
        end
    catch
        _:R2 ->
            lager:info("unable to update temporal rules ~p", [R2]),
            disable_temporal_rules(Temporal, T, Call)
    end.

%%------------------------------------------------------------------------------
%% @doc Retrieve and update the enabled key on the temporal rule document.
%% Also plays messages to the caller based on the results of that
%% operation.
%% @end
%%------------------------------------------------------------------------------
-spec reset_temporal_rules(temporal(), rule_ids(), kapps_call:call()) -> cf_api_std_return().
reset_temporal_rules(#temporal{prompts=#prompts{marker_reset=Reset}}, [], Call) ->
    kapps_call_command:b_prompt(Reset, Call);
reset_temporal_rules(Temporal, [RuleId|T]=Rules, Call) ->
    try
        AccountDb = kapps_call:account_db(Call),
        {'ok', JObj} = kz_datamgr:open_doc(AccountDb, RuleId),
        case kz_datamgr:save_doc(AccountDb, kzd_temporal_rules:delete_enabled(JObj)) of
            {'ok', _} ->
                lager:info("reset temporal rule ~s", [RuleId]),
                reset_temporal_rules(Temporal, T, Call);
            {'error', 'conflict'} ->
                lager:info("conflict during reset of temporal rule ~s, trying again", [RuleId]),
                reset_temporal_rules(Temporal, Rules, Call);
            {'error', R1} ->
                lager:info("unable to reset temporal rule ~s, ~p", [RuleId, R1]),
                reset_temporal_rules(Temporal, T, Call)
        end
    catch
        _:R2 ->
            lager:info("unable to reset temporal rule ~s ~p", [RuleId, R2]),
            reset_temporal_rules(Temporal, T, Call)
    end.

%%------------------------------------------------------------------------------
%% @doc Retrieve and update the enabled key on the temporal rule document.
%% Also plays messages to the caller based on the results of that
%% operation.
%% @end
%%------------------------------------------------------------------------------
-spec enable_temporal_rules(temporal(), rule_ids(), kapps_call:call()) -> cf_api_std_return().
enable_temporal_rules(#temporal{prompts=#prompts{marked_enabled=Enabled}}, [], Call) ->
    kapps_call_command:b_prompt(Enabled, Call);
enable_temporal_rules(Temporal, [RuleId|T]=Rules, Call) ->
    try
        AccountDb = kapps_call:account_db(Call),
        {'ok', RuleDoc} = kz_datamgr:open_doc(AccountDb, RuleId),
        case kz_datamgr:save_doc(AccountDb, kzd_temporal_rules:set_enabled(RuleDoc, 'true')) of
            {'ok', _} ->
                lager:info("set temporal rule ~s to enabled active", [RuleId]),
                enable_temporal_rules(Temporal, T, Call);
            {'error', 'conflict'} ->
                lager:info("conflict during enable of temporal rule ~s, trying again", [RuleId]),
                enable_temporal_rules(Temporal, Rules, Call);
            {'error', R1} ->
                lager:info("unable to enable temporal rule ~s, ~p", [RuleId, R1]),
                enable_temporal_rules(Temporal, T, Call)
        end
    catch
        _:R2 ->
            lager:info("unable to enable temporal rule ~s ~p", [RuleId, R2]),
            enable_temporal_rules(Temporal, T, Call)
    end.

%%------------------------------------------------------------------------------
%% @doc determines the appropriate Gregorian seconds to be used as the
%% current date/time for this temporal route selection
%% @end
%%------------------------------------------------------------------------------
-spec load_current_time(temporal()) -> temporal().
load_current_time(#temporal{timezone=Timezone}=Temporal)->
    {LocalDate, LocalTime} = kz_time:adjust_utc_datetime(calendar:universal_time(), Timezone),
    lager:info("local time for ~s is {~w,~w}", [Timezone, LocalDate, LocalTime]),
    Temporal#temporal{local_sec=calendar:datetime_to_gregorian_seconds({LocalDate, LocalTime})
                     ,local_date=LocalDate
                     ,local_time=LocalTime
                     }.

-spec interdigit_timeout(kz_json:object()) -> integer().
interdigit_timeout(Data) ->
    kz_json:get_integer_value(<<"interdigit_timeout">>
                             ,Data
                             ,kapps_call_command:default_interdigit_timeout()
                             ).

-type rule_ids() :: kz_term:ne_binaries().
-spec rule_ids(kz_json:object()) -> rule_ids().
rule_ids(Data) ->
    kz_json:get_list_value(<<"rules">>, Data, []).

-spec action(kz_json:object()) -> kz_term:api_ne_binary().
action(Data) ->
    kz_json:get_ne_binary_value(<<"action">>, Data).

-spec rule_set_id(kz_json:object()) -> kz_term:api_ne_binary().
rule_set_id(Data) ->
    kz_json:get_ne_binary_value(<<"rule_set">>, Data).
