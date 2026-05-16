%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2024-, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_cdrs).

%% Manual testing
-export([seq/0
        ,seq_straight/0
        ,seq_paginated/0
        ,seq_paginated_owner/0
        ,seq_task/0
         %%,seq_big_dataset/0

        ,seed_cdrs/1
        ,seed_cdrs/2
        ,cleanup/0
        ]).

-include_lib("proper/include/proper.hrl").
-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").


-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-define(CDRS_PER_MONTH, 4).

-spec seq() -> 'ok'.
seq() ->
    _ = pqc_cb_system_configs:patch_default_config(pqc_cb_api:authenticate()
                                                  ,<<"crossbar.cdrs">>
                                                  ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"should_filter_empty_strings">>, 'true'}])}])
                                                  ),
    lists:foreach(fun(F) -> F() end
                 ,[fun seq_straight/0
                  ,fun seq_paginated/0
                  ,fun seq_paginated_owner/0
                  ,fun seq_task/0
                  ,fun seq_big_dataset/0
                  ]
                 ).

-spec seq_straight() -> 'ok'.
seq_straight() ->
    API = pqc_cb_api:init_api(['crossbar']
                             ,['cb_cdrs']
                             ),

    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_cdrs:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    EmptyCSVResp = pqc_cb_cdrs:summary(API, AccountId, <<"text/csv">>),
    lager:info("empty CSV resp: ~s", [EmptyCSVResp]),

    CDRs = seed_cdrs(AccountId),
    lager:info("seeded ~p CDRs", [length(CDRs)]),

    SummaryResp = pqc_cb_cdrs:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    RespCDRs = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    'true' = cdrs_exist(CDRs, RespCDRs),

    CSVResp = pqc_cb_cdrs:summary(API, AccountId, <<"text/csv">>),
    lager:info("csv resp: ~s", [CSVResp]),

    InteractionsResp = pqc_cb_cdrs:interactions(API, AccountId),
    lager:info("interactions resp: ~s", [InteractionsResp]),

    lists:foreach(fun(CDR) -> seq_cdr(API, AccountId, CDR) end, CDRs),

    cleanup(API, [AccountId]),
    lager:info("FINISHED STRAIGHT SEQ").

-spec seq_paginated() -> 'ok'.
seq_paginated() ->
    API = pqc_cb_api:init_api(['crossbar']
                             ,['cb_cdrs']
                             ),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_cdrs:paginated_summary(API, AccountId),
    lager:info("empty summary resp: ~p", [EmptySummaryResp]),
    [] = EmptySummaryResp,

    CDRs = seed_cdrs(AccountId),
    timer:sleep(150), % let couch breathe

    SummaryResp = pqc_cb_cdrs:paginated_summary(API, AccountId),
    lager:info("summary resp: ~p", [SummaryResp]),

    'true' = cdrs_exist(CDRs, SummaryResp),

    InteractionsResp = pqc_cb_cdrs:paginated_interactions(API, AccountId),
    InteractionIds = lists:sort([kzd_cdrs:interaction_id(I) || I <- InteractionsResp]),

    CDRInteractionIDs = lists:usort([kzd_cdrs:interaction_id(CDR) || CDR <- CDRs]),
    case CDRInteractionIDs =:= InteractionIds of
        'true' -> 'ok';
        'false' ->
            lager:info("failed to fetch expected interaction IDs from API"),
            lager:info("missing from response: ~p", [CDRInteractionIDs -- InteractionIds]),
            throw({'error', 'interaction_ids', 'not_found'})
    end,

    cleanup(API, [AccountId]),
    lager:info("FINISHED PAGINATED SEQ").

-spec seq_paginated_owner() -> 'ok'.
seq_paginated_owner() ->
    API = pqc_cb_api:init_api(['crossbar']
                             ,['cb_cdrs']
                             ),
    AccountId = create_account(API, ?ACCOUNT_NAME),
    OwnerId = create_owner(AccountId),

    EmptySummaryResp = pqc_cb_cdrs:paginated_summary(API, AccountId),
    lager:info("empty summary resp: ~p", [EmptySummaryResp]),
    [] = EmptySummaryResp,

    CDRs = seed_cdrs(AccountId, OwnerId),

    SummaryResp = pqc_cb_cdrs:paginated_summary(API, AccountId, OwnerId),
    lager:info("summary resp: ~p", [SummaryResp]),

    'true' = cdrs_exist(CDRs, SummaryResp),

    InteractionsResp = pqc_cb_cdrs:paginated_interactions(API, AccountId, OwnerId),
    InteractionIds = lists:sort([kzd_cdrs:interaction_id(I) || I <- InteractionsResp]),

    CDRInteractionIDs = lists:usort([kzd_cdrs:interaction_id(CDR) || CDR <- CDRs]),
    case CDRInteractionIDs =:= InteractionIds of
        'true' -> 'ok';
        'false' ->
            lager:info("failed to fetch expected interaction IDs from API"),
            lager:info("missing from response: ~p", [CDRInteractionIDs -- InteractionIds]),
            throw({'error', 'interaction_ids', 'not_found'})
    end,

    cleanup(API, [AccountId]),
    lager:info("FINISHED PAGINATED SEQ").

-spec seq_big_dataset() -> 'ok'.
seq_big_dataset() ->
    lager:info("creating large dataset and not paginating results"),
    API = pqc_cb_api:init_api(['crossbar'], ['cb_cdrs']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    {Year, Month, Day} = erlang:date(),

    CDRCount = 2700,

    GenerateCDRsStart = kz_time:start_time(),
    CDRs = lists:foldl(fun(_, Acc) ->
                               InteractionId = interaction_id(Year, Month, Day),
                               [create_cdr(AccountId, 'undefined', Year, Month, InteractionId) | Acc]
                       end
                      ,[]
                      ,lists:seq(1, CDRCount)
                      ),

    AccountMODb = kzs_util:format_account_id(AccountId, Year, Month),
    {'ok', Saved} = kazoo_modb:save_docs(AccountMODb, CDRs, [{'publish_change_notice', 'false'}]),

    lager:info("saved ~p generated CDRs in ~pms"
              ,[length(CDRs), kz_time:elapsed_ms(GenerateCDRsStart)]
              ),

    Fails = [S || S <- Saved, not kz_json:is_true(<<"ok">>, S)],
    ([] =:= Fails)
        orelse lager:warning("failed to save ~p", [Fails]),
    [] = Fails,
    CDRCount = length(Saved),

    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"crossbar">>
                                                  ,kz_json:from_list([{<<"default">>
                                                                      ,kz_json:from_list([{<<"request_memory_limit">>, 'null'}])
                                                                      }])
                                                  ),
    ChunkedJSON = pqc_cb_cdrs:unpaginated_summary(API, AccountId),
    ChunkedJObj = kz_json:decode(ChunkedJSON),
    ChunkedCount = length(kz_json:get_list_value(<<"data">>, ChunkedJObj)),
    lager:info("unpaginated and unbound memory resp returned ~p CDRs (expect ~p)", [ChunkedCount, CDRCount]),
    CDRCount = ChunkedCount,

    UnChunkedJSON = pqc_cb_cdrs:unpaginated_summary(API, AccountId, 'false'),
    UnChunkedJObj = kz_json:decode(UnChunkedJSON),
    UnChunkedCount = length(kz_json:get_list_value(<<"data">>, UnChunkedJObj)),
    lager:info("unpaginated/unchunked and unbound memory resp returned ~p CDRs", [UnChunkedCount]),
    CDRCount = UnChunkedCount,

    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"crossbar">>
                                                  ,kz_json:from_list([{<<"default">>
                                                                      ,kz_json:from_list([{<<"request_memory_limit">>, 8 * ?BYTES_M}])
                                                                      }])
                                                  ), % cap at 8Mb

    ChunkedUnpaginatedJSON = pqc_cb_cdrs:unpaginated_summary(API, AccountId),
    ChunkedUnpaginatedJObj = kz_json:decode(ChunkedUnpaginatedJSON),
    ChunkedUnpaginatedCount = length(kz_json:get_list_value(<<"data">>, ChunkedUnpaginatedJObj)),
    lager:info("chunked/unpaginated and unbound memory resp returned ~p CDRs", [ChunkedUnpaginatedCount]),
    CDRCount = ChunkedUnpaginatedCount,

    {'error', UnChunkedErrorJSON} = pqc_cb_cdrs:unpaginated_summary(API, AccountId, 'false'),
    lager:info("unchunked/unpaginated and bound memory resp: ~s", [UnChunkedErrorJSON]),
    UnChunkedErrorJObj = kz_json:decode(UnChunkedErrorJSON),
    416 = kz_json:get_integer_value(<<"error">>, UnChunkedErrorJObj),
    <<"range not satisfiable">> = kz_json:get_ne_binary_value(<<"message">>, UnChunkedErrorJObj),

    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"crossbar">>
                                                  ,kz_json:from_list([{<<"default">>
                                                                      ,kz_json:from_list([{<<"request_memory_limit">>, 'null'}])
                                                                      }])
                                                  ),
    PaginatedSummary = pqc_cb_cdrs:paginated_summary(API, AccountId, 'undefined', CDRCount div 10),
    PaginatedLength = length(PaginatedSummary),
    lager:info("paginated: ~p", [PaginatedLength]),
    CDRCount = PaginatedLength,

    cleanup(API, [AccountId]),
    lager:info("FINISHED BIG DATASET SEQ").

-spec seq_task() -> 'ok'.
seq_task() ->
    API = pqc_cb_api:init_api(['crossbar', 'tasks']
                             ,['cb_cdrs']
                             ),

    AccountId = create_account(API, ?ACCOUNT_NAME),
    _CDRs = seed_cdrs(AccountId),

    CreateResp = pqc_cb_tasks:create_account(API, AccountId, "category=billing&action=dump"),
    lager:info("created task ~s", [CreateResp]),
    TaskId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>]
                                        ,kz_json:decode(CreateResp)
                                        ),
    _ExecResp = pqc_cb_tasks:execute(API, AccountId, TaskId),
    lager:info("exec task ~s: ~s", [TaskId, _ExecResp]),

    _DelResp = wait_for_task(API, AccountId, TaskId),
    lager:info("finished task ~s: ~s", [TaskId, _DelResp]),

    cleanup(API, [AccountId]),
    lager:info("FINISHED TASK SEQ").

seq_cdr(API, AccountId, CDR) ->
    CDRId = kz_doc:id(CDR),
    InteractionId = kzd_cdrs:interaction_id(CDR),

    FetchResp = pqc_cb_cdrs:fetch(API, AccountId, CDRId),
    FetchedJObj = kz_json:get_json_value(<<"data">>, kz_json:decode(FetchResp)),
    'true' = cdr_exists(CDR, [FetchedJObj]),

    %% KZOO-45: Ensure empty strings have been stripped
    'undefined' = kz_json:get_ne_binary_value(<<"media_server">>, FetchedJObj),

    %% Should be able to convert CDR ID to interaction_id
    LegsResp = pqc_cb_cdrs:legs(API, AccountId, CDRId),
    'true' = cdr_exists(CDR, kz_json:get_list_value(<<"data">>, kz_json:decode(LegsResp))),

    InteractionResp = pqc_cb_cdrs:legs(API, AccountId, InteractionId),
    'true' = cdr_exists(CDR, kz_json:get_list_value(<<"data">>, kz_json:decode(InteractionResp))).

cdr_exists(CDR, RespCDRs) ->
    lists:any(fun(RespCDR) -> kz_doc:id(RespCDR) =:= kz_doc:id(CDR) end, RespCDRs).

-spec cdrs_exist(kz_json:objects(), kz_json:objects()) -> boolean().
cdrs_exist([], []) -> 'true';
cdrs_exist([], APIs) ->
    IDs = [kz_doc:id(CDR) || CDR <- APIs],
    lager:info("  failed to find API results in CDRs: ~s", [kz_binary:join(IDs, <<", ">>)]),
    'false';
cdrs_exist(CDRs, []) ->
    IDs = [kz_doc:id(CDR) || CDR <- CDRs],
    lager:info("  failed to find CDR(s) in API response: ~s", [kz_binary:join(IDs, <<", ">>)]),
    'false';
cdrs_exist([_|_]=CDRs, [API|APIs]) ->
    cdrs_exist([CDR || CDR <- CDRs, kz_doc:id(CDR) =/= kz_doc:id(API)]
              ,APIs
              ).

create_account(API, AccountName) ->
    AccountResp = properly_accountant:create_account(API, AccountName),
    lager:info("created account: ~s", [AccountResp]),

    kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)).

create_owner(AccountId) ->
    AccountDb = kzs_util:format_account_db(AccountId),

    OwnerId = kz_binary:rand_hex(16),
    Owner = kz_json:set_value(<<"_id">>, OwnerId, kzd_users:new()),
    {'ok', _Saved}= kz_datamgr:save_doc(AccountDb, Owner),
    lager:info("saved owner to ~s: ~p", [AccountDb, _Saved]),
    OwnerId.

-spec cleanup() -> 'ok'.
cleanup() ->
    cleanup(pqc_cb_api:authenticate()).

-spec cleanup(pqc_cb_api:state()) -> 'ok'.
cleanup(API) ->
    properly_maintenance:cleanup_module_accounts(?MODULE),
    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"crossbar">>
                                                  ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"request_memory_limit">>, 'null'}])}])
                                                  ),
    cleanup_system().

cleanup(API, AccountIds) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, AccountIds),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.

-spec seed_cdrs(kz_term:ne_binary()) -> kz_json:objects().
seed_cdrs(AccountId) ->
    seed_cdrs(AccountId, 'undefined').

-spec seed_cdrs(kz_term:ne_binary(), kz_term:api_ne_binary()) -> kz_json:objects().
seed_cdrs(AccountId, OwnerId) ->
    {Year, Month, _} = erlang:date(),

    kazoo_modb:create(kzs_util:format_account_id(AccountId, Year, Month)),
    {PrevY, PrevM} = kazoo_modb_util:prev_year_month(Year, Month),
    kazoo_modb:create(kzs_util:format_account_id(AccountId, PrevY, PrevM)),

    seed_cdrs(AccountId, OwnerId, Year, Month).

-spec seed_cdrs(kz_term:ne_binary(), kz_term:api_ne_binary(), kz_time:year(), kz_time:month()) -> kz_json:objects().
seed_cdrs(AccountId, OwnerId, Year, Month) ->
    AccountMODb = kzs_util:format_account_id(AccountId, Year, Month),
    _ = kazoo_modb:create(AccountMODb),

    CDRs = seed_interaction(AccountId, OwnerId, Year, Month),
    MoreCDRs = seed_interaction(AccountId, OwnerId, Year, Month),
    EvenMoreCDRs = seed_interaction(AccountId, OwnerId, Year, Month),
    {PrevY, PrevM} = kazoo_modb_util:prev_year_month(Year, Month),
    PrevCDRs = seed_interaction(AccountId, OwnerId, PrevY, PrevM),
    CDRs ++ MoreCDRs ++ EvenMoreCDRs ++ PrevCDRs.

seed_interaction(AccountId, OwnerId, Year, Month) ->
    {{_, _, Day}, _} = calendar:universal_time(),
    {Y, M, D} = kz_date:normalize({Year, Month, Day}),

    InteractionId = interaction_id(Y, M, D),

    lists:foldl(fun(_Seq, Acc) ->
                        {'ok', CDR} = seed_cdr(AccountId, OwnerId, Y, M, InteractionId),
                        [CDR | Acc]
                end
               ,[]
               ,lists:seq(1, ?CDRS_PER_MONTH)
               ).

interaction_id(Year, Month, Day) ->
    InteractionTime = interaction_time(Year, Month, Day),
    InteractionKey = kz_binary:rand_hex(4),
    list_to_binary([integer_to_binary(InteractionTime), "-", InteractionKey]).

seed_cdr(AccountId, OwnerId, Year, Month, InteractionId) ->
    [ITime, InteractionKey] = binary:split(InteractionId, <<"-">>),
    InteractionTime = kz_term:to_integer(ITime),

    CDR = create_cdr(AccountId, OwnerId, Year, Month
                    ,InteractionId, InteractionTime, InteractionKey
                    ),

    AccountMODb = kzs_util:format_account_id(AccountId, InteractionTime),
    kazoo_modb:save_doc(AccountMODb, CDR, ['allow_old_modb_creation']).

create_cdr(AccountId, OwnerId, Year, Month, InteractionId) ->
    [ITime, InteractionKey] = binary:split(InteractionId, <<"-">>),
    InteractionTime = kz_term:to_integer(ITime),
    create_cdr(AccountId, OwnerId, Year, Month, InteractionId, InteractionTime, InteractionKey).

create_cdr(AccountId, OwnerId, Year, Month, InteractionId, InteractionTime, InteractionKey) ->
    CallId = kz_binary:rand_hex(6),

    CDRId = kzd_cdrs:create_doc_id(CallId, Year, Month),

    AccountMODb = kzs_util:format_account_id(AccountId, InteractionTime),

    JObj = kz_json:from_list([{<<"_id">>, CDRId}
                             ,{<<"call_id">>, CallId}

                             ,{<<"interaction_id">>, InteractionId}
                             ,{<<"interaction_key">>, InteractionKey}
                             ,{<<"interaction_time">>, InteractionTime}

                             ,{<<"custom_channel_vars">>, kz_json:from_list([{<<"owner_id">>, OwnerId}])}

                             ,{<<"call_direction">>, <<"inbound">>}

                             ,{<<"request">>, <<"2600@hertz.com">>}
                             ,{<<"to">>, <<"capt@crunch.com">>}
                             ,{<<"from">>, <<"cereal@killer.com">>}

                             ,{<<"ringing_seconds">>, 3}
                             ,{<<"billing_seconds">>, 6}
                             ,{<<"duration_seconds">>, 9}
                             ,{<<"timestamp">>, InteractionTime}
                             ]),

    Props = [{'type', <<"cdr">>}
            ,{'account_id', AccountId}
            ,{'now', InteractionTime}
            ],
    kz_doc:update_pvt_parameters(JObj, AccountMODb, Props).

interaction_time(Year, Month, Day) ->
    {Today, _} = calendar:universal_time(),
    interaction_time(Year, Month, Day, Today).

interaction_time(Year, Month, Day, {Year, Month, Day}) ->
    calendar:datetime_to_gregorian_seconds({{Year, Month, Day}, {0, 0, 0}});
interaction_time(Year, Month, Day, _Today) ->
    calendar:datetime_to_gregorian_seconds({{Year, Month, Day}, {23, 59, 59}}).

wait_for_task(API, AccountId, TaskId) ->
    Start = kz_time:start_time(),
    wait_for_task(API, AccountId, TaskId, Start).

-spec wait_for_task(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_time:start_time()) ->
          pqc_cb_api:response() | {'error', 'timeout'}.
wait_for_task(API, AccountId, TaskId, Start) ->
    wait_for_task(API, AccountId, TaskId, Start, kz_time:elapsed_s(Start)).

wait_for_task(_API, _AccountId, _TaskId, _Start, ElapsedS) when ElapsedS > 30 ->
    lager:warning("waiting for task ~s in account ~s timed out"),
    {'error', 'timeout'};
wait_for_task(API, AccountId, TaskId, Start, _ElapsedS) ->
    GetResp = pqc_cb_tasks:fetch(API, AccountId, TaskId),
    GetJObj = kz_json:decode(GetResp),

    case kz_json:get_value([<<"metadata">>, <<"status">>]
                          ,GetJObj
                          )
    of
        <<"success">> ->
            %% fetch csv
            lager:info("task fininshed: ~s", [GetResp]),
            get_csvs(API, AccountId, TaskId, kz_json:get_list_value([<<"metadata">>, <<"csvs">>], GetJObj, [])),
            pqc_cb_tasks:delete(API, AccountId, TaskId);
        <<"failure">> ->
            lager:warning("task failed: ~s", [GetResp]),
            pqc_cb_tasks:delete(API, AccountId, TaskId);
        <<"internal_error">> ->
            lager:warning("task failed with internal error: ~s", [GetResp]),
            pqc_cb_tasks:delete(API, AccountId, TaskId);
        _Status ->
            lager:info("wrong status(~s) for task in ~s", [_Status, GetResp]),
            timer:sleep(1000),
            wait_for_task(API, AccountId, TaskId, Start)
    end.

get_csvs(_API, _AccountId, _TaskId, []) -> 'ok';
get_csvs(API, AccountId, TaskId, [CSV|CSVs]) ->
    _ = get_csv(API, AccountId, TaskId, CSV),
    get_csvs(API, AccountId, TaskId, CSVs).

get_csv(API, AccountId, TaskId, CSV) ->
    FetchResp = pqc_cb_tasks:fetch_csv(API, AccountId, TaskId, CSV),
    lager:info("fetched ~s(~s): ~s", [TaskId, CSV, FetchResp]).
