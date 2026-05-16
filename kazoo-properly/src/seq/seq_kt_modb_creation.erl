%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2013-2024, 2600Hz
%%% @doc Test creating MODBs ahead of time
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_kt_modb_creation).

-export([seq/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar']
                             ,['cb_accounts']
                             ),
    AccountId = create_account(API),

    {Year, Month, Day} = erlang:date(),
    CurrentMODB = kzs_util:format_account_id(AccountId, Year, Month),

    'true' = kz_datamgr:db_exists(CurrentMODB),

    %% ensure we trigger the task
    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"tasks.modb_creation">>
                                                  ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"creation_day">>, Day}])}])
                                                  ),
    %% create all MODBs in the first time unit
    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"tasks.modb_creation">>
                                                  ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"create_in_parallel">>, 1000}])}])
                                                  ),

    {NextYear, NextMonth, _} = kz_date:normalize({Year, Month+1, 1}),
    NextMODB = kzs_util:format_account_id(AccountId, NextYear, NextMonth),

    'false' = check_for_creation(NextMODB, 0),
    lager:info("modb ~s not created yet", [NextMODB]),

    %% trigger the task
    kt_modb_creation:handle_req(),

    lager:info("checking for '~s'", [NextMODB]),
    'true' = check_for_creation(NextMODB, 5 * ?MILLISECONDS_IN_SECOND),

    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    cleanup(API).

check_for_creation(NextMODB, WaitForMs) ->
    check_for_creation(NextMODB, WaitForMs, kz_time:start_time()).

check_for_creation(NextMODB, WaitForMs, StartTime) ->
    case kz_datamgr:db_exists(NextMODB) of
        'true' ->
            lager:info("found ~s is created", [NextMODB]),
            check_for_views(NextMODB);
        'false' ->
            ElapsedMs = kz_time:elapsed_ms(StartTime),
            case ElapsedMs > WaitForMs of
                'true' ->
                    lager:info("failed to find ~s in ~p(~p)", [NextMODB, WaitForMs, ElapsedMs]),
                    'false';
                'false' ->
                    timer:sleep(50),
                    check_for_creation(NextMODB, WaitForMs, StartTime)
            end
    end.

check_for_views(NextMODB) ->
    Views = kz_datamgr:view_definitions(NextMODB, 'modb'),
    check_for_views(NextMODB, Views, 5*?MILLISECONDS_IN_SECOND, kz_time:start_time()).

check_for_views(_NextMODB, [], _WaitForMs, StartTime) ->
    lager:info("found all views in ~p ms", [kz_time:elapsed_ms(StartTime)]),
    'true';
check_for_views(NextMODB, Views, WaitForMs, StartTime) ->
    FilterFun = fun({ViewId, _ViewDef}) ->
                        case kz_datamgr:open_doc(NextMODB, ViewId) of
                            {'ok', _} -> 'false';
                            _ -> 'true'
                        end
                end,
    case lists:filter(FilterFun, Views) of
        [] -> 'true';
        MissingViews ->
            ElapsedMs = kz_time:elapsed_ms(StartTime),
            case ElapsedMs < WaitForMs of
                'true' ->
                    timer:sleep(50),
                    check_for_views(NextMODB, MissingViews, WaitForMs, StartTime);
                'false' ->
                    lager:info("waited too long to find all views - missing ~p", [MissingViews]),
                    'false'
            end
    end.

create_account(API) ->
    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    ?INFO("created account: ~s", [AccountResp]),

    kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)).

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = seq_accounts:cleanup_accounts(?ACCOUNT_NAMES),
    cleanup_system().

cleanup(API) ->
    ?INFO("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, ?ACCOUNT_NAMES),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.
