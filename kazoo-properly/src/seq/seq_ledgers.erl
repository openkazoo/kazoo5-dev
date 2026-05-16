%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023-, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_ledgers).

%% Manual test functions
-export([seq/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-properly({standalone, [seq/0]}).

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec initial_state() -> pqc_kazoo_model:model().
initial_state() ->
    _ = init_system(),
    API = pqc_cb_api:authenticate(),
    pqc_kazoo_model:new(API).

init_system() ->
    TestId = kz_binary:rand_hex(5),
    kz_log:put_callid(TestId),

    _ = kz_data_tracing:clear_all_traces(),
    _ = [kapps_controller:start_app(App) ||
            App <- ['crossbar']
        ],
    _ = [crossbar_maintenance:start_module(Mod) ||
            Mod <- ['cb_ledgers', 'cb_system_configs']
        ],
    lager:info("INIT FINISHED").

-spec seq() -> 'ok'.
seq() ->
    Model = initial_state(),
    API = pqc_kazoo_model:api(Model),

    ConfigResp = pqc_cb_system_configs:get_default_config(API, <<"crossbar">>),
    lager:info("config resp: ~s", [ConfigResp]),
    PriorChunkSize = kz_json:get_integer_value([<<"default">>, <<"load_view_chunk_size">>]
                                              ,kz_json:decode(ConfigResp)
                                              ,1
                                              ),

    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"crossbar">>
                                                  ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"load_view_chunk_size">>, 1}])}])
                                                  ),

    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    lager:info("created account: ~s", [AccountResp]),

    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    EmptySourceFetchCSV = pqc_cb_ledgers:fetch_by_source(API, AccountId, <<?MODULE_STRING>>, <<"text/csv">>),
    lager:info("empty source fetch CSV: ~s", [EmptySourceFetchCSV]),

    Ledger2 = ledger_doc(<<"baseball">>),
    CreditResp2 = pqc_cb_ledgers:credit(API, AccountId, Ledger2),
    lager:info("credit: ~s", [CreditResp2]),

    %% make sure ledgers have diff pvt_created
    timer:sleep(?MILLISECONDS_IN_SECOND),

    %% put the non-custom ledger later, since sorting is descending
    Ledger = ledger_doc(),
    CreditResp = pqc_cb_ledgers:credit(API, AccountId, Ledger),
    lager:info("credit: ~s", [CreditResp]),

    %% make sure view includes next second in startkey will be 1s later
    timer:sleep(?MILLISECONDS_IN_SECOND),

    SourceFetch = pqc_cb_ledgers:fetch_by_source(API, AccountId, <<?MODULE_STRING>>),
    lager:info("source fetch: ~s", [SourceFetch]),
    Data = kz_json:get_value(<<"data">>, kz_json:decode(SourceFetch)),
    _ = ledgers_exist(Data, [Ledger, Ledger2]),

    SourceFetchCSV = pqc_cb_ledgers:fetch_by_source(API, AccountId, <<?MODULE_STRING>>, <<"text/csv">>),
    lager:info("source fetch CSV: '~s'", [SourceFetchCSV]),
    'true' = ledgers_exist_in_csv(SourceFetchCSV, [Ledger, Ledger2]),

    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"crossbar">>
                                                  ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"load_view_chunk_size">>, PriorChunkSize}])}])
                                                  ),

    cleanup(API, [AccountId]),
    lager:info("FINISHED").

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = seq_accounts:cleanup_accounts(?ACCOUNT_NAMES),
    cleanup_system().

cleanup(API, Accounts) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, Accounts),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.

ledgers_exist(_Data, []) -> 'true';
ledgers_exist(Data, [Ledger | Ledgers]) ->
    lists:any(fun(Datum) -> ledger_matches(Datum, Ledger) end, Data)
        andalso ledgers_exist(Data, Ledgers).

ledger_matches(Datum, Ledger) ->
    kzd_ledgers:source_id(Datum) =:= kzd_ledgers:source_id(Ledger)
        andalso kzd_ledgers:unit_amount(Datum) =:= kzd_ledgers:unit_amount(Ledger).

ledgers_exist_in_csv(CSV, Ledgers) ->
    {Header, Rows} = kz_csv:take_row(CSV),
    MetaPos = header_has_column_name(Header, <<"metadata_bonus">>),
    SourceIdPos = header_has_column_name(Header, <<"Source ID">>),
    is_integer(MetaPos)
        andalso is_integer(SourceIdPos)
        andalso ledgers_in_rows({MetaPos, SourceIdPos}, Rows, Ledgers).

header_has_column_name(Headers, ColumnName) ->
    header_has_column_name(Headers, ColumnName, 1).

header_has_column_name([], _ColumnName, _N) ->
    lager:info("failed to find column '~s'", [_ColumnName]),
    'undefined';
header_has_column_name([ColumnName | _Headers], ColumnName, N) ->
    lager:debug("found column '~s' at ~p", [ColumnName, N]),
    N;
header_has_column_name([_Header | Headers], ColumnName, N) ->
    header_has_column_name(Headers, ColumnName, N+1).

ledgers_in_rows(Pos, Rows, Ledgers) ->
    ledgers_in_row(Pos, kz_csv:take_row(Rows), Ledgers).

ledgers_in_row({_MetaPos, _SourceIdPos}, 'eof', []) -> 'true';
ledgers_in_row({_MetaPos, _SourceIdPos}, 'eof', _Ledgers) ->
    lager:info("failed to find ledgers in CSV: ~p", [_Ledgers]),
    'false';
ledgers_in_row({MetaPos, SourceIdPos}, {Row, Rows}, Ledgers) ->
    %% remove ledger matching Row
    RowSourceId = lists:nth(SourceIdPos, Row),
    RowMetaValue = try lists:nth(MetaPos, Row) catch _:_ -> <<>> end,

    Ls = [Ledger
          || Ledger <- Ledgers,
             kzd_ledgers:source_id(Ledger) =/= RowSourceId,
             metadata_bonus(Ledger) =/= RowMetaValue
         ],

    ledgers_in_row({MetaPos, SourceIdPos}, kz_csv:take_row(Rows), Ls).

metadata_bonus(Ledger) ->
    Metadata = kzd_ledgers:metadata(Ledger, kz_json:new()),
    kz_json:get_value(<<"bonus">>, Metadata, <<>>).

-spec ledger_doc() -> kzd_ledgers:doc().
ledger_doc() ->
    lists:foldl(fun({F, V}, D) -> F(D, V) end
               ,kzd_ledgers:new()
               ,[{fun kzd_ledgers:set_source_service/2, <<?MODULE_STRING>>}
                ,{fun kzd_ledgers:set_source_id/2, kz_binary:rand_hex(4)}
                ,{fun kzd_ledgers:set_usage_quantity/2, 1}
                ,{fun kzd_ledgers:set_usage_unit/2, <<"Hz">>}
                ,{fun kzd_ledgers:set_usage_type/2, <<"cycle">>}
                ,{fun(J, V) -> kz_json:set_value(<<"amount">>, V, J) end, 2.6}
                ]
               ).

-spec ledger_doc(kz_term:ne_binary()) -> kzd_ledgers:doc().
ledger_doc(Value) ->
    kz_json:set_value([<<"metadata">>, <<"bonus">>], Value, ledger_doc()).
