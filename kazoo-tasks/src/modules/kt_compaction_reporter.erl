%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023-, 2600Hz
%%% @doc
%%% Collect and save/store compaction job's information for jobs started via sup commands,
%%% CSV JOBS app, or auto compaction trigger.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(kt_compaction_reporter).
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([start_tracking_job/3
        ,start_tracking_job/4
        ,stop_tracking_job/1
        ,set_job_dbs/2
        ,current_db/2
        ,skipped_db/2
        ,finished_db/3
        ,add_found_shards/2
        ,finished_shard/2
        ]).
%% "Mirrors" for SUP commands
-export([status/0, history/0, history/2, job_info/1]).

%% gen_server's callbacks
-export([init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_info/2
        ,code_change/3
        ,terminate/2
        ]).

-define(SERVER, ?MODULE).
-define(COMPACTION_VIEW, <<"compaction_jobs/crossbar_listing">>).

-type job_id() :: kz_term:ne_binary().
-type compaction_stats() :: #{%% Databases
                              'id' => kz_term:ne_binary() %% Job id.
                             ,'found_dbs' => pos_integer() %% Number of dbs found to be compacted
                             ,'compacted_dbs' => non_neg_integer() %% Number of dbs compacted so far
                             ,'queued_dbs' => non_neg_integer() %% remaining dbs to be compacted
                             ,'skipped_dbs' => non_neg_integer() %% dbs skipped because not data_size nor disk-data's ratio thresholds are met.
                             ,'current_db' => kz_term:api_ne_binary()
                             ,'processed_dbs' => kz_term:ne_binaries() %% `Encoded' DBs already processed, avoids processing duplicated events like skipped, finished, etc.
                              %% Shards
                             ,'found_shards' => non_neg_integer() %% Number of shards found so far
                             ,'compacted_shards' => non_neg_integer() %% Number of shards compacted so far
                              %% Storage
                             ,'disk_start' => non_neg_integer() %% disk_size sum of all dbs in bytes before compaction (for history command)
                             ,'disk_end' => non_neg_integer() %% disk_size sum of all dbs in bytes after compaction (for history command)
                             ,'data_start' => non_neg_integer() %% data_size sum of all dbs in bytes before compaction (for history command)
                             ,'data_end' => non_neg_integer() %% data_size sum of all dbs in bytes after compaction (for history command)
                             ,'recovered_disk' => non_neg_integer() %% bytes recovered so far (for status command)
                              %% Worker
                             ,'pid' => pid() %% worker's pid
                             ,'node' => node() %% node where the worker is running
                             ,'started' => kz_time:gregorian_seconds() %% datetime (in seconds) when the compaction started
                             ,'finished' => 'undefined' | kz_time:gregorian_seconds() %% datetime (in seconds) when the compaction ended
                              %% Misc
                             ,'compactor_monitor' => reference() %% Reference to monitor of process running the compaction process. Stop tracking if it sends a 'DOWN' message.
                             ,'last_update' => 'undefined' | kz_time:gregorian_seconds() %% datetime (in seconds) when the last update was received
                             }.
-type job_stats() :: 'undefined' | compaction_stats().
-type jobs() :: #{job_id() => compaction_stats()}.
-type monitors() :: #{reference() => job_id()}.
-type state() :: #{'jobs' => jobs()
                  ,'monitors' => monitors()
                  }.


%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec start_link() -> kz_types:startlink_ret().
start_link() ->
    gen_server:start_link({'local', ?MODULE}, ?MODULE, [], []).

%%------------------------------------------------------------------------------
%% @doc Start tracking a compaction job
%% @end
%%------------------------------------------------------------------------------
-spec start_tracking_job(pid(), node(), job_id()) -> 'ok'.
start_tracking_job(Pid, Node, JobId) ->
    start_tracking_job(Pid, Node, JobId, []).

%%------------------------------------------------------------------------------
%% @doc Start tracking a compaction job
%% @end
%%------------------------------------------------------------------------------
-spec start_tracking_job(pid(), node(), job_id(), [kt_compactor:db_and_sizes()]) -> 'ok'.
start_tracking_job(Pid, Node, JobId, DbsAndSizes) ->
    gen_server:cast(?SERVER, {'new_job', Pid, Node, JobId, DbsAndSizes}).

%%------------------------------------------------------------------------------
%% @doc Stop tracking compaction job, save current state on db.
%% @end
%%------------------------------------------------------------------------------
-spec stop_tracking_job(job_id()) -> 'ok'.
stop_tracking_job(JobId) ->
    gen_server:cast(?SERVER, {'stop_job', JobId}).

%%------------------------------------------------------------------------------
%% @doc Some jobs like `compact_all' and `compact_node' doesn't know the list of dbs to
%% be compacted at the beginning of the job, so we wait for that job to report the dbs
%% once it has the list of dbs to be compacted prior to start compacting them.
%% @end
%%------------------------------------------------------------------------------
-spec set_job_dbs(job_id(), kt_compactor:dbs_and_sizes()) -> 'ok'.
set_job_dbs(JobId, DbsAndSizes) ->
    gen_server:cast(?SERVER, {'set_job_dbs', JobId, DbsAndSizes}).

%%------------------------------------------------------------------------------
%% @doc Set current db being compacted for the given job id.
%% @end
%%------------------------------------------------------------------------------
-spec current_db(job_id(), kz_term:ne_binary()) -> 'ok'.
current_db(JobId, Db) ->
    gen_server:cast(?SERVER, {'current_db', JobId, normalize_db(Db)}).

%%------------------------------------------------------------------------------
%% @doc Notifies when a database has been skipped by the compactor worker. This happens
%% when not data_size nor disk-data's ratio thresholds are met.
%% @end
%%------------------------------------------------------------------------------
-spec skipped_db(job_id(), kz_term:ne_binary()) -> 'ok'.
skipped_db(JobId, Db) when is_binary(Db) ->
    gen_server:cast(?SERVER, {'skipped_db', JobId, normalize_db(Db)}).

%%------------------------------------------------------------------------------
%% @doc Set db already compacted for the given job id.
%% @end
%%------------------------------------------------------------------------------
-spec finished_db(job_id(), kz_term:ne_binary(), kz_csv:row()) -> 'ok'.
finished_db(JobId, Db, Row) ->
    gen_server:cast(?SERVER, {'finished_db', JobId, normalize_db(Db), Row}).

%%------------------------------------------------------------------------------
%% @doc Increases `found_shards' value by adding `ShardsCount' to it for the given job id.
%% @end
%%------------------------------------------------------------------------------
-spec add_found_shards(job_id(), non_neg_integer()) -> 'ok'.
add_found_shards(JobId, ShardsCount) when is_number(ShardsCount) ->
    gen_server:cast(?SERVER, {'add_found_shards', JobId, ShardsCount}).

%%------------------------------------------------------------------------------
%% @doc Increases the counter of `compacted_shards' for the given job id.
%% @end
%%------------------------------------------------------------------------------
-spec finished_shard(job_id(), kz_term:ne_binary()) -> 'ok'.
finished_shard(JobId, Shard) ->
    gen_server:cast(?SERVER, {'finished_shard', JobId, Shard}).

%%------------------------------------------------------------------------------
%% @doc Return the status for every compaction job currently running.
%% @end
%%------------------------------------------------------------------------------
-spec status() -> [kz_term:proplist()].
status() ->
    %% Result is a list of proplists or an empty list.
    gen_server:call(?SERVER, 'status').

%%------------------------------------------------------------------------------
%% @doc Returns history for the current Year and Month.
%% @end
%%------------------------------------------------------------------------------
-spec history() -> {'ok', kz_json:json_terms()} | {'error', atom()}.
history() ->
    {Year, Month, _} = erlang:date(),
    history(Year, Month).

%%------------------------------------------------------------------------------
%% @doc Return compaction history for the given year and month (YYYY, MM).
%% @end
%%------------------------------------------------------------------------------
-spec history(kz_time:year(), kz_time:month()) -> {'ok', kz_json:json_terms()} |
          {'error', atom()}.
history(Year, Month) when is_integer(Year)
                          andalso is_integer(Month) ->
    {'ok', AccountId} = kapps_util:get_master_account_id(),
    Opts = [{'year', Year}, {'month', Month}, 'include_docs'],
    kazoo_modb:get_results(AccountId, ?COMPACTION_VIEW, Opts).

%%------------------------------------------------------------------------------
%% @doc Return the information for the given job id
%% @end
%%------------------------------------------------------------------------------
-spec job_info(kz_term:ne_binary()) -> kz_term:proplist() | atom().
job_info(<<JobId/binary>>) ->
    {'ok', AccountId} = kapps_util:get_master_account_id(),
    case kazoo_modb:open_doc(AccountId, JobId) of
        {'ok', JObj} ->
            Int = fun(Key) -> kz_json:get_integer_value(Key, JObj) end,
            Str = fun(Key) -> kz_json:get_string_value(Key, JObj) end,
            DiskStart = Int([<<"storage">>, <<"disk">>, <<"start">>]),
            DiskEnd = Int([<<"storage">>, <<"disk">>, <<"end">>]),
            Start = Int([<<"worker">>, <<"started">>]),
            End = Int([<<"worker">>, <<"finished">>]),
            [{<<"id">>, kz_doc:id(JObj)}
            ,{<<"found_dbs">>, Str([<<"databases">>, <<"found">>])}
            ,{<<"compacted_dbs">>, Str([<<"databases">>, <<"compacted">>])}
            ,{<<"skipped_dbs">>, Str([<<"databases">>, <<"skipped">>])}
            ,{<<"found_shards">>, Str([<<"shards">>, <<"found">>])}
            ,{<<"compacted_shards">>, Str([<<"shards">>, <<"compacted">>])}
            ,{<<"disk_start">>, kz_term:to_binary(DiskStart)}
            ,{<<"disk_end">>, kz_term:to_binary(DiskEnd)}
            ,{<<"data_start">>, Str([<<"storage">>, <<"data">>, <<"start">>])}
            ,{<<"data_end">>, Str([<<"storage">>, <<"data">>, <<"end">>])}
            ,{<<"recovered_disk">>, kz_term:pretty_print_bytes(DiskStart - DiskEnd)}
            ,{<<"node">>, Str([<<"worker">>, <<"node">>])}
            ,{<<"pid">>, Str([<<"worker">>, <<"pid">>])}
            ,{<<"started">>, kz_term:to_list(kz_time:pretty_print_datetime(Start))}
            ,{<<"finished">>, kz_term:to_list(kz_time:pretty_print_datetime(End))}
            ,{<<"exec_time">>
             ,kz_term:to_list(kz_time:pretty_print_elapsed_s(End - Start))
             }
            ];
        {'error', Reason} ->
            Reason
    end.

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the server.
%% @end
%%------------------------------------------------------------------------------
-spec init([]) -> {'ok', state()}.
init([]) ->
    lager:info("started ~s", [?MODULE]),
    {'ok', #{'jobs' => #{}, 'monitors' => #{}}}.

%%------------------------------------------------------------------------------
%% @doc Handling call messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_call(any(), kz_term:pid_ref(), state()) -> kz_types:handle_call_ret_state(state()).
handle_call('status', _From, #{'jobs' := Jobs} = State) ->
    Ret = maps:fold(fun stats_to_status_fold/3, [], Jobs),
    {'reply', Ret, State};

handle_call(_Request, _From, State) ->
    lager:debug("unhandled call ~p from ~p", [_Request, _From]),
    {'reply', {'error', 'not_implemented'}, State}.

%%------------------------------------------------------------------------------
%% @doc Handling cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_cast({'new_job', pid(), node(), job_id(), kt_compactor:dbs_and_sizes()}, state()) -> kz_types:handle_cast_ret_state(state());
                 ({'stop_job', job_id()}, state()) -> kz_types:handle_cast_ret_state(state());
                 ({'set_job_dbs', job_id(), kt_compactor:dbs_and_sizes()}, state()) -> kz_types:handle_cast_ret_state(state());
                 ({'current_db' | 'skipped_db', job_id(), kz_term:ne_binary()}, state()) -> kz_types:handle_cast_ret_state(state());
                 ({'finished_db', job_id(), kz_term:ne_binary(), kz_csv:row()}, state()) -> kz_types:handle_cast_ret_state(state());
                 ({'add_found_shards', job_id(), non_neg_integer()}, state()) -> kz_types:handle_cast_ret_state(state());
                 ({'finished_shard', job_id(), kz_term:ne_binary()}, state()) -> kz_types:handle_cast_ret_state(state()).
handle_cast({'new_job', Pid, Node, JobId, DbsAndSizes}, State) ->
    {'noreply', do_new_job(State, Pid, Node, JobId, DbsAndSizes)};

handle_cast({'stop_job', JobId}, State) ->
    {'noreply', do_stop_job(State, JobId)};

handle_cast({'set_job_dbs', JobId, DbsAndSizes}, State) ->
    {'noreply', do_set_job_dbs(State, JobId, DbsAndSizes)};

handle_cast({'current_db', JobId, Db}, State) ->
    {'noreply', do_current_db(State, JobId, Db)};

handle_cast({'skipped_db', JobId, Db}, State) ->
    {'noreply', do_skipped_db(State, JobId, Db)};

handle_cast({'finished_db', JobId, Db, FRow}, State) ->
    {'noreply', do_finished_db(State, JobId, Db, FRow)};

handle_cast({'add_found_shards', JobId, ShardsCount}, State) ->
    {'noreply', do_add_found_shards(State, JobId, ShardsCount)};

handle_cast({'finished_shard', JobId, Shard}, State) ->
    {'noreply', do_finished_shard(State, JobId, Shard)};

handle_cast(_Msg, State) ->
    lager:debug("unhandled cast ~p", [_Msg]),
    {'noreply', State}.

%%------------------------------------------------------------------------------
%% @doc Handling all "out of band" (non call/cast) messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_info(any(), state()) -> kz_types:handle_info_ret_state(state()).
handle_info({'DOWN', MRef, 'process', Pid, Reason}, State) ->
    JobId = maps:get(MRef, State, 'undefined'),
    lager:debug("process ~p died with reason: ~p, when state was: ~p",
                [Pid, Reason, maps:get(JobId, State, 'undefined')]),
    stop_tracking_job(JobId),
    {'noreply', State};
handle_info(_Info, State) ->
    lager:debug("unhandled message ~p", [_Info]),
    {'noreply', State}.

%%------------------------------------------------------------------------------
%% @doc This function is called by a `gen_server' when it is about to
%% terminate. It should be the opposite of `Module:init/1' and do any
%% necessary cleaning up. When it returns, the `gen_server' terminates
%% with Reason. The return value is ignored.
%% @end
%%------------------------------------------------------------------------------
-spec terminate(any(), state()) -> 'ok'.
terminate(_Reason, _State) ->
    lager:debug("~s terminating with reason: ~p~n when state was: ~p"
               ,[?SERVER, _Reason, _State]
               ).

%%------------------------------------------------------------------------------
%% @doc Convert process state when code is changed.
%% @end
%%------------------------------------------------------------------------------
-spec code_change(any(), state(), any()) -> {'ok', state()}.
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec do_new_job(state(), pid(), node(), job_id(), kt_compactor:dbs_and_sizes()) -> state().
do_new_job(#{'monitors' := Monitors} = State, Pid, Node, JobId, DbsAndSizes) ->
    MRef = monitor('process', Pid),
    lager:info("start collecting data for compaction job ~p with monitor ~p", [JobId, MRef]),
    TotalDbs = length(DbsAndSizes),
    Stats = #{'id' => JobId
             ,'found_dbs' => TotalDbs
             ,'compacted_dbs' => 0
             ,'queued_dbs' => TotalDbs
             ,'skipped_dbs' => 0
             ,'current_db' => 'undefined'
             ,'processed_dbs' => []
             ,'found_shards' => 0
             ,'compacted_shards' => 0
             ,'disk_start' => 0
             ,'disk_end' => 0
             ,'data_start' => 0
             ,'data_end' => 0
             ,'recovered_disk' => 0
             ,'pid' => Pid
             ,'node' => Node
             ,'started' => kz_time:now_s()
             ,'finished' => 'undefined'
             ,'compactor_monitor' => MRef
             },
    update_job_stats(State#{'monitors' => Monitors#{MRef => JobId}}, JobId, Stats).

-spec do_stop_job(state(), job_id()) -> state().
do_stop_job(#{'jobs' := Jobs} = State, JobId) ->
    do_stop_job(State, JobId, maps:take(JobId, Jobs)).

-spec do_stop_job(state(), job_id(), 'error' | {compaction_stats(), jobs()}) -> state().
do_stop_job(State, JobId, 'error') ->
    lager:debug("invalid job_id (~p) provided, skipping request to handle stop_job", [JobId]),
    State;
do_stop_job(#{'monitors' := Monitors} = State, JobId, {#{'started' := Started, 'compactor_monitor' := MRef} = Stats, Jobs1}) ->
    'true' = demonitor(MRef, ['flush']),
    Finished = kz_time:now_s(),
    Elapsed = Finished - Started,
    lager:debug("~s finished, took ~s", [JobId, kz_time:pretty_print_elapsed_s(Elapsed)]),
    'ok' = save_compaction_stats(Stats#{'finished' => Finished}),
    %% Remove job and monitor information for the current (finished) job.
    State#{'jobs' => Jobs1, 'monitors' => maps:remove(MRef, Monitors)}.

-spec do_set_job_dbs(state(), job_id(), kt_compactor:dbs_and_sizes()) -> state().
do_set_job_dbs(#{'jobs' := Jobs} = State, JobId, DbsAndSizes) ->
    do_set_job_dbs(State, JobId, DbsAndSizes, job_stats(JobId, Jobs)).

-spec do_set_job_dbs(state(), job_id(), kt_compactor:dbs_and_sizes(), job_stats()) -> state().
do_set_job_dbs(State, JobId, _DbsAndSizes, 'undefined') ->
    lager:debug("invalid job_id (~p) provided, skipping request to handle set_job_dbs", [JobId]),
    State;
do_set_job_dbs(State, JobId, DbsAndSizes, Stats) ->
    TotalDbs = length(DbsAndSizes),
    update_job_stats(State, JobId, Stats#{'found_dbs' => TotalDbs
                                         ,'queued_dbs' => TotalDbs
                                         }).

-spec do_current_db(state(), job_id(), kz_term:ne_binary()) -> state().
do_current_db(#{'jobs' := Jobs} = State, JobId, Db) ->
    do_current_db(State, JobId, Db, job_stats(JobId, Jobs)).

-spec do_current_db(state(), job_id(), kz_term:ne_binary(), job_stats()) -> state().
do_current_db(State, JobId, _Db, 'undefined') ->
    lager:debug("invalid job_id (~p) provided, skipping request to handle current_db", [JobId]),
    State;
do_current_db(State, JobId, Db, Stats) ->
    update_job_stats(State, JobId, Stats#{'current_db' => Db}).

-spec do_skipped_db(state(), job_id(), kz_term:ne_binary()) -> state().
do_skipped_db(#{'jobs' := Jobs} = State, JobId, Db) ->
    Stats = job_stats(JobId,  Jobs),
    case Stats =/= 'undefined'
        %% Happens when the db was already "processed" on another BigCouch node but not on this one.
        andalso not lists:member(Db, maps:get('processed_dbs', Stats))
    of
        'false' ->
            lager:debug("invalid job_id (~p) provided or db already processed, skipping request to handle skipped_db", [JobId]),
            State;
        'true' ->
            lager:debug("~p db does not need compaction, skipped", [Db]),
            update_job_stats(State
                            ,JobId
                            ,increment_counter('skipped_dbs', Stats#{'current_db' => 'undefined'})
                            )
    end.

-spec do_finished_db(state(), job_id(), kz_term:ne_binary(), kz_csv:row()) -> state().
do_finished_db(#{'jobs' := Jobs} = State, JobId, Db, FRow) ->
    Stats = job_stats(JobId, Jobs),
    case Stats =/= 'undefined'
        %% Happens when the db was already "processed" on another BigCouch node but not on this one.
        andalso not lists:member(Db, maps:get('processed_dbs', Stats))
    of
        'false' ->
            lager:debug("invalid job_id (~p) provided or db already processed, skipping request to handle finished_db", [JobId]),
            State;
        'true' ->
            #{'recovered_disk' := CurrentRec
             ,'disk_start' := DiskStart
             ,'disk_end' := DiskEnd
             ,'data_start' := DataStart
             ,'data_end' := DataEnd
             ,'found_dbs' := Found
             ,'skipped_dbs' := Skipped
             ,'queued_dbs' := Queued
             ,'processed_dbs' := ProcessedDBs
             } = Stats,
            [_, _, OldDisk, OldData, NewDisk, NewData] = FRow,
            Recovered = (OldDisk-NewDisk),
            NewQueued = Queued - 1,
            lager:debug("recovered ~p bytes after compacting ~p db", [Recovered, Db]),
            update_job_stats(State, JobId, Stats#{'recovered_disk' => CurrentRec + Recovered
                                                 ,'disk_start' => DiskStart + OldDisk
                                                 ,'disk_end' => DiskEnd + NewDisk
                                                 ,'data_start' => DataStart + OldData
                                                 ,'data_end' => DataEnd + NewData
                                                 ,'compacted_dbs' => Found - NewQueued - Skipped
                                                 ,'queued_dbs' => NewQueued
                                                 ,'current_db' => 'undefined'
                                                 ,'processed_dbs' => [Db | ProcessedDBs]
                                                 })
    end.

-spec do_add_found_shards(state(), job_id(), non_neg_integer()) -> state().
do_add_found_shards(#{'jobs' := Jobs} = State, JobId, ShardsCount) ->
    do_add_found_shards(State, JobId, ShardsCount, job_stats(JobId, Jobs)).

-spec do_add_found_shards(state(), job_id(), non_neg_integer(), job_stats()) -> state().
do_add_found_shards(State, JobId, _ShardsCount, 'undefined') ->
    lager:debug("invalid job_id (~p) provided, skipping request to handle add_found_shards", [JobId]),
    State;
do_add_found_shards(State, JobId, ShardsCount, Stats) ->
    lager:debug("adding ~p to the number of found shards", [ShardsCount]),
    update_job_stats(State, JobId, increment_counter('found_shards', Stats, ShardsCount)).

do_finished_shard(#{'jobs' := Jobs} = State, JobId, Shard) ->
    do_finished_shard(State, JobId, Shard, job_stats(JobId, Jobs)).

do_finished_shard(State, JobId, _Shard, 'undefined') ->
    lager:debug("invalid job_id (~p) provided, skipping request to handle finished_shard", [JobId]),
    State;
do_finished_shard(State, JobId, _Shard, Stats) ->
    update_job_stats(State, JobId, increment_counter('compacted_shards', Stats)).

-spec job_stats(job_id(), jobs()) -> job_stats().
job_stats(JobId, Jobs) ->
    maps:get(JobId, Jobs, 'undefined').

-spec increment_counter(atom(), map()) -> map().
increment_counter(Key, Map) ->
    increment_counter(Key, Map, 1).

-spec increment_counter(atom(), map(), pos_integer()) -> map().
increment_counter(Key, Map, Increment) ->
    maps:update_with(Key, fun(V) -> V+Increment end, Map).

%%------------------------------------------------------------------------------
%% @doc Update Stats for given Job (JobId) within state.
%% @end
%%------------------------------------------------------------------------------
-spec update_job_stats(state(), job_id(), compaction_stats()) -> state().
update_job_stats(#{'jobs' := Jobs} = State, JobId, Stats) ->
    State#{'jobs' => Jobs#{JobId => Stats#{'last_update' => kz_time:now_s()}}}.

%%------------------------------------------------------------------------------
%% @doc Converts current state into a list of proplists including only some `Keys'.
%% @end
%%------------------------------------------------------------------------------
-spec stats_to_status_fold(kz_term:ne_binary(), compaction_stats(), [kz_term:proplist()]) ->
          [kz_term:proplist()].
stats_to_status_fold(_JobId, Stats = #{'found_dbs' := FoundDBs}, Acc) when is_binary(_JobId) ->
    Keys = ['id', 'found_dbs', 'compacted_dbs', 'queued_dbs', 'skipped_dbs', 'current_db',
            'found_shards', 'compacted_shards', 'recovered_disk', 'pid', 'node', 'started',
            'last_update'],
    StatsProp = [{kz_term:to_binary(Key), kz_term:to_binary(maps:get(Key, Stats))} || Key <- Keys],
    case FoundDBs of
        0 ->
            %% If compaction is running and `found_dbs=0' means it let this module know a new
            %% compaction job is running but it is missing to report the dbs to be compacted.
            %% Which means it is still loading dbs (sorting).
            MsgProp = [{<<"NOTE">>, <<"Still listing/sorting databases.">>}],
            [StatsProp ++ MsgProp | Acc];
        _ ->
            [StatsProp | Acc]
    end.

%%------------------------------------------------------------------------------
%% @doc Save compaction job stats on db.
%% @end
%%------------------------------------------------------------------------------
-spec save_compaction_stats(compaction_stats()) -> 'ok'.
save_compaction_stats(#{'id' := Id
                       ,'found_dbs' := FoundDBs
                       ,'compacted_dbs' := CompactedDBs
                       ,'queued_dbs' := QueuedDBs
                       ,'skipped_dbs' := SkippedDBs
                       ,'found_shards' := FoundShards
                       ,'compacted_shards' := CompactedShards
                       ,'disk_start' := DiskStart
                       ,'disk_end' := DiskEnd
                       ,'data_start' := DataStart
                       ,'data_end' := DataEnd
                       ,'pid' := Pid
                       ,'node' := Node
                       ,'started' := Started
                       ,'finished' := Finished
                       } = Stats) ->
    Map = #{<<"_id">> => Id
           ,<<"databases">> => #{<<"found">> => FoundDBs
                                ,<<"compacted">> => CompactedDBs
                                ,<<"queued">> => QueuedDBs
                                ,<<"skipped">> => SkippedDBs
                                }
           ,<<"shards">> => #{<<"found">> => FoundShards
                             ,<<"compacted">> => CompactedShards
                             }
           ,<<"storage">> => #{<<"disk">> =>
                                   #{<<"start">> => DiskStart
                                    ,<<"end">> => DiskEnd
                                    }
                              ,<<"data">> =>
                                   #{<<"start">> => DataStart
                                    ,<<"end">> => DataEnd
                                    }
                              }
           ,<<"worker">> => #{<<"pid">> => kz_term:to_binary(Pid)
                             ,<<"node">> => kz_term:to_binary(Node)
                             ,<<"started">> => Started
                             ,<<"finished">> => Finished
                             }
           ,<<"pvt_type">> => <<"compaction_job">>
           ,<<"pvt_created">> => kz_time:now_s()
           },
    lager:debug("saving stats after compaction job completion: ~p", [Stats]),
    {'ok', AccountId} = kapps_util:get_master_account_id(),
    {'ok', Doc} = kazoo_modb:save_doc(AccountId, kz_json:from_map(Map)),
    lager:info("created doc after compaction job completion: ~p", [Doc]),
    'ok'.

-spec normalize_db(kz_term:ne_binary()) -> kz_term:ne_binary().
normalize_db(Db) ->
    kz_http_util:urldecode(Db).
