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
-module(seq_recordings).

%%-export([command/2
%%        ,next_state/3
%%        ,postcondition/3
%%        ]).

-export([seq/0]).
-export([init_seq/0]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<"account_for_recordings">>]).
-define(MP3_FILE, filename:join([code:priv_dir('properly'), <<"mp3.mp3">>])).

-spec init_seq() -> any().
init_seq() ->
    _ = init(),
    Model = initial_state(),
    API = pqc_kazoo_model:api(Model),
    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    {API, kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp))}.

-spec seq() -> 'ok'.
seq() ->
    File = ?MP3_FILE,
    {'ok', Contents} = file:read_file(File),
    {API, AccountId} = init_seq(),

    try
        ?INFO("created account ~s", [AccountId]),

        {'ok', []} = pqc_cb_recordings:summary(API, AccountId),
        ?INFO("no recordings available yet", []),

        {'ok', RecordingDoc} = pqc_cb_recordings:create(API, AccountId),
        ?INFO("created recording ~p", [RecordingDoc]),

        {'ok', [RecordingSummary]} = pqc_cb_recordings:summary(API, AccountId),
        ?INFO("recording available: ~p", [RecordingSummary]),

        'true' = kz_doc:id(RecordingSummary) =:= kz_doc:id(RecordingDoc),
        ?INFO("recording is available"),

        {'ok', Recording} = pqc_cb_recordings:fetch(API, AccountId, kz_doc:id(RecordingSummary)),
        ?INFO("recording meta: ~p", [Recording]),

        {'ok', Contents} = pqc_cb_recordings:fetch_binary(API, AccountId, kz_doc:id(RecordingSummary)),
        ?INFO("fetched MP3"),

        {'ok', Contents} = pqc_cb_recordings:fetch_tunneled(API, AccountId, kz_doc:id(RecordingSummary)),
        ?INFO("fetched tunneled MP3"),

        {'ok', Deleted} = pqc_cb_recordings:delete(API, AccountId, kz_doc:id(RecordingSummary)),
        ?INFO("deleted recording: ~p", [Deleted]),

        {'ok', []} = pqc_cb_recordings:summary(API, AccountId),
        ?INFO("no recordings available again", []),

        io:format(?MODULE_STRING":seq/0 was successful~n")
    catch
        ?STACKTRACE(_E, _R, ST)
        ?INFO(?MODULE_STRING ":seq/0 failed ~s: ~p", [_E, _R]),
        _ = [?INFO("st: ~p", [S]) || S <- ST],
        io:format(?MODULE_STRING ":seq/0 failed: ~s: ~p", [_E, _R])
    after
        seq_accounts:cleanup_accounts(API, ?ACCOUNT_NAMES),
        pqc_cb_api:cleanup(API)
    end,
    ?INFO("seq finished running: ~p", [API]),
    io:format('user', "logs in /tmp/~s.log~n", [maps:get('request_id', API)]).

init() ->
    _ = kz_data_tracing:clear_all_traces(),
    _ = [kapps_controller:start_app(App) ||
            App <- ['crossbar']
        ],
    _ = [crossbar_maintenance:start_module(Mod) ||
            Mod <- ['cb_recordings', 'cb_accounts']
        ],
    ?INFO("INIT FINISHED").

-spec initial_state() -> pqc_kazoo_model:model().
initial_state() ->
    API = pqc_cb_api:authenticate(),
    ?INFO("state initialized to ~p", [API]),
    pqc_kazoo_model:new(API).
