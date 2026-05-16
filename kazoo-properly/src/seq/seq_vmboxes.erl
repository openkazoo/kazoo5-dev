%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2018-2024, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_vmboxes).

-export([seq/0
        ,seq_kcal_45/0
        ,seq_kcro_24/0
        ,seq_kzoo_52/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-spec seq() -> 'ok'.
seq() ->
    Fs = [fun seq_kcal_45/0
         ,fun seq_kcro_24/0
         ,fun seq_kzoo_52/0
         ],
    lists:foreach(fun run/1, Fs).

run(F) -> F().

-spec seq_kcro_24() -> 'ok'.
seq_kcro_24() ->
    API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account: ~s", [AccountResp]),

    AccountId = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    BoxName = kz_binary:rand_hex(4),
    CreateResp = pqc_cb_vmboxes:create_box(API, AccountId, BoxName),
    lager:info("created box resp: ~s", [CreateResp]),

    CreatedBox = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    BoxId = kz_doc:id(CreatedBox),

    %% create messages
    {{Year, Month, Day}, _} = calendar:universal_time(),
    CurrentMonth = {{Year, Month, Day}
                   ,CurrentMsgs = [{<<"0-new">>, <<"new">>}     %% oldest
                                  ,{<<"1-saved">>, <<"saved">>}
                                  ,{<<"2-new">>, <<"new">>}
                                  ,{<<"3-saved">>, <<"saved">>}
                                  ,{<<"4-saved">>, <<"saved">>}
                                  ,{<<"5-new">>, <<"new">>}
                                  ,{<<"6-saved">>, <<"saved">>}
                                  ,{<<"7-new">>, <<"new">>}
                                  ,{<<"8-saved">>, <<"saved">>} %% newest
                                  ]
                   },
    create_messages(API, AccountId, BoxId, CurrentMonth),

    {PrevYear, PrevMonth, PrevDay} = kz_date:normalize({Year, Month-1, Day}),

    LastMonth = {{PrevYear, PrevMonth, PrevDay}
                ,OlderMsgs = [{<<"10-new">>, <<"new">>}
                             ,{<<"11-saved">>, <<"saved">>}
                             ,{<<"12-new">>, <<"new">>}
                             ,{<<"13-saved">>, <<"saved">>}
                             ]
                },
    create_messages(API, AccountId, BoxId, LastMonth),

    ExpectedCDRs = lists:reverse(CurrentMsgs) ++ lists:reverse(OlderMsgs),
    ExpectedCDRIds = [CDRId || {CDRId, _} <- ExpectedCDRs],
    NewCDRIds = [CDRId || {CDRId, <<"new">>} <- ExpectedCDRs],

    lager:info("expected CDR IDs: ~p", [ExpectedCDRIds]),

    %% The main principle to reproduce the issue seems to be to "tune"
    %% page_size in such a way that it would be less than db size but
    %% there are requested items in the rest of the db that satisfy
    %% the filter. These items will be missed in the response.

    %% For example, the current MODB contains 4 new(n) items and 5
    %% saved(s) messages - "n s n s s n s n s", the order does matter.

    %% If we request new messages with "page_size=5" and filter for
    %% non-saved messages, we will get only 2 "new" messages from this db,
    %% as the code takes the next db because the page_size is reached,
    %% independent on the fact that next_start_key is available and
    %% the filtered out result less that page_size.
    %% ------------------------------------------------------------------------
    ListedResp = pqc_cb_vmboxes:list_messages(API, AccountId, BoxId
                                             ,[{<<"page_size">>, 5}
                                              ,{<<"filter_not_folder">>, <<"saved">>}
                                              ]),
    lager:info("listed messages ~s", [ListedResp]),
    ListedJObj = kz_json:decode(ListedResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, ListedJObj),
    5 = kz_json:get_integer_value(<<"page_size">>, ListedJObj),

    lager:info("expecting ~p", [NewCDRIds]),
    Listing = kz_json:get_list_value(<<"data">>, ListedJObj),
    UpdatedCDRIds = remove_expected_messages(NewCDRIds, Listing),

    NextStartKey = kz_json:get_ne_binary_value(<<"next_start_key">>, ListedJObj),

    SecondPageResp = pqc_cb_vmboxes:list_messages(API, AccountId, BoxId
                                                 ,[{<<"page_size">>, 5}
                                                  ,{<<"filter_not_folder">>, <<"saved">>}
                                                  ,{<<"start_key">>, NextStartKey}
                                                  ]
                                                 ),
    lager:info("second page: ~s", [SecondPageResp]),
    SecondPage = kz_json:decode(SecondPageResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, SecondPage),
    1 = kz_json:get_integer_value(<<"page_size">>, SecondPage),

    lager:info("expecting second page ~p", [UpdatedCDRIds]),
    SecondListing = kz_json:get_list_value(<<"data">>, SecondPage),
    [] = remove_expected_messages(UpdatedCDRIds, SecondListing),

    AllNewOnePageResp = pqc_cb_vmboxes:list_messages(API, AccountId, BoxId
                                                    ,[{<<"filter_not_folder">>, <<"saved">>}]
                                                    ),
    lager:info("all new messages ~s", [AllNewOnePageResp]),
    AllNewJObj = kz_json:decode(AllNewOnePageResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, AllNewJObj),
    'true' = length(NewCDRIds) =:= kz_json:get_integer_value(<<"page_size">>, AllNewJObj),
    AllNewListing = kz_json:get_list_value(<<"data">>, AllNewJObj),
    [] = remove_expected_messages(NewCDRIds, AllNewListing),

    AllMessagesResp = pqc_cb_vmboxes:list_messages(API, AccountId, BoxId),
    lager:info("all messages ~s", [AllMessagesResp]),
    AllJObj = kz_json:decode(AllMessagesResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, AllJObj),

    'true' = length(ExpectedCDRIds) =:= kz_json:get_integer_value(<<"page_size">>, AllJObj),
    AllListing = kz_json:get_list_value(<<"data">>, AllJObj),
    [] = remove_expected_messages(ExpectedCDRIds, AllListing),

    %% no pagination enabled
    NoPagingResp = pqc_cb_vmboxes:list_messages(API, AccountId, BoxId, [{<<"paginate">>, 'false'}]),
    lager:info("no paging messages ~s", [NoPagingResp]),
    NoPagingJObj = kz_json:decode(NoPagingResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, NoPagingJObj),

    NoPagingListing = kz_json:get_list_value(<<"data">>, NoPagingJObj),
    'true' = length(ExpectedCDRIds) =:= length(NoPagingListing),
    [] = remove_expected_messages(ExpectedCDRIds, NoPagingListing),

    %% no pagination enabled but with filter
    NoPagingFilterResp = pqc_cb_vmboxes:list_messages(API, AccountId, BoxId, [{<<"paginate">>, 'false'}
                                                                             ,{<<"filter_not_folder">>, <<"saved">>}
                                                                             ]),
    lager:info("no paging but filtered messages ~s", [NoPagingFilterResp]),
    NoPagingFilterJObj = kz_json:decode(NoPagingFilterResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, NoPagingFilterJObj),

    NoPagingFilterListing = kz_json:get_list_value(<<"data">>, NoPagingFilterJObj),
    'true' = length(NewCDRIds) =:= length(NoPagingFilterListing),
    [] = remove_expected_messages(NewCDRIds, NoPagingFilterListing),


    DeleteResp = pqc_cb_vmboxes:delete_box(API, AccountId, BoxId),
    lager:info("delete resp: ~s", [DeleteResp]),
    Delete = kz_json:decode(DeleteResp),
    Metadata = kz_json:get_json_value(<<"metadata">>, Delete),
    DeletedBox = kz_json:get_json_value(<<"data">>, Delete),
    BoxId = kz_doc:id(DeletedBox),
    BoxName = kzd_vmboxes:name(DeletedBox),

    'true' = kz_json:is_true([<<"deleted">>], Metadata),

    cleanup(API, [AccountId]),
    lager:info("FINISHED KCRO-24").

remove_expected_messages(CDRIds, []) -> CDRIds;
remove_expected_messages([CDRId | CDRIds], [Message | Messages]) ->
    CDRId = kz_json:get_ne_binary_value(<<"call_id">>, Message),
    remove_expected_messages(CDRIds, Messages).

-spec seq_kzoo_52() -> 'ok'.
seq_kzoo_52() ->
    API = initial_state(),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account: ~s", [AccountResp]),

    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    BoxName = kz_binary:rand_hex(4),
    CreateResp = pqc_cb_vmboxes:create_box(API, AccountId, BoxName),
    lager:info("created box resp: ~s", [CreateResp]),
    CreatedBox = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    BoxId = kz_doc:id(CreatedBox),
    BoxName = kzd_vmboxes:name(CreatedBox),

    DeleteResp = pqc_cb_vmboxes:delete_box(API, AccountId, BoxId),
    lager:info("delete resp: ~s", [DeleteResp]),
    Delete = kz_json:decode(DeleteResp),
    DeletedBox = kz_json:get_json_value(<<"data">>, Delete),
    Metadata = kz_json:get_json_value(<<"metadata">>, Delete),

    BoxId = kz_doc:id(DeletedBox),
    BoxName = kzd_vmboxes:name(DeletedBox),
    'true' = kz_json:is_true([<<"deleted">>], Metadata),

    cleanup(API, [AccountId]),
    lager:info("FINISHED KZOO-52").

-spec seq_kcal_45() -> 'ok'.
seq_kcal_45() ->
    API = initial_state(),

    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    lager:info("created account: ~s", [AccountResp]),

    AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

    BoxNumber = kz_binary:rand_hex(4),
    Alias = kz_binary:rand_hex(4),
    <<CreateResp/binary>> = pqc_cb_vmboxes:create_box(API, AccountId, new_box(BoxNumber, [Alias])),
    lager:info("created box resp: ~s", [CreateResp]),

    %% shouldn't make two VM boxes of same number
    {'error', SameBoxNumberError} = pqc_cb_vmboxes:create_box(API, AccountId, new_box(BoxNumber)),
    lager:info("didn't create matching box name ~s: ~s", [BoxNumber, SameBoxNumberError]),
    'true' = kz_json:is_defined([<<"data">>, <<"mailbox">>, <<"unique">>, <<"message">>]
                               ,kz_json:decode(SameBoxNumberError)
                               ),

    %% Aliases shouldn't be usable as box number
    {'error', AliasAsBoxNumberError} = pqc_cb_vmboxes:create_box(API, AccountId, new_box(Alias)),
    lager:info("didn't create matching box with existing alias ~s: ~s", [Alias, AliasAsBoxNumberError]),
    'true' = kz_json:is_defined([<<"data">>, <<"mailbox">>, <<"unique">>, <<"message">>]
                               ,kz_json:decode(AliasAsBoxNumberError)
                               ),

    %% boxes can't share aliases
    OtherBoxNumber = kz_binary:rand_hex(4),
    {'error', SharedAliasNameError} = pqc_cb_vmboxes:create_box(API, AccountId, new_box(OtherBoxNumber, [Alias])),
    lager:info("didn't create other box ~s with existing alias ~s: ~s"
              ,[OtherBoxNumber, Alias, SharedAliasNameError]
              ),
    'true' = kz_json:is_defined([<<"data">>, <<"mailbox">>, <<"unique">>, <<"message">>]
                               ,kz_json:decode(SharedAliasNameError)
                               ),

    %% can't use other box number as alias
    {'error', BoxNumberAsAliasError} = pqc_cb_vmboxes:create_box(API, AccountId, new_box(OtherBoxNumber, [BoxNumber])),
    lager:info("didn't create other box ~s with existing box name ~s as alias: ~s"
              ,[OtherBoxNumber, BoxNumber, BoxNumberAsAliasError]
              ),
    'true' = kz_json:is_defined([<<"data">>, <<"mailbox">>, <<"unique">>, <<"message">>]
                               ,kz_json:decode(BoxNumberAsAliasError)
                               ),

    cleanup(API, [AccountId]),
    lager:info("FINISHED KCAL-45").

-spec initial_state() -> pqc_cb_api:state().
initial_state() ->
    _ = init_system(),
    pqc_cb_api:authenticate().

init_system() ->
    TestId = kz_binary:rand_hex(5),
    kz_log:put_callid(TestId),

    _ = kz_data_tracing:clear_all_traces(),
    _ = [kapps_controller:start_app(App) ||
            App <- ['crossbar']
        ],
    _ = [crossbar_maintenance:start_module(Mod) ||
            Mod <- ['cb_vmboxes']
        ],
    lager:info("INIT FINISHED").

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = properly_maintenance:cleanup_module_accounts(?MODULE),
    cleanup_system().

cleanup(API, AccountIds) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, AccountIds),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.

create_messages(API, AccountId, BoxId, {{Year, Month, Day}, Folders}) ->
    MODB = kzs_util:format_account_id(AccountId, Year, Month),
    'true' = kazoo_modb:create(MODB),

    {'ok', MP3} = file:read_file(filename:join([code:priv_dir('properly'), "mp3.mp3"])),

    StartTime = calendar:datetime_to_gregorian_seconds({{Year, Month, Day}, {0, 0, 0}}),

    {_StartTime, Messages} = lists:foldl(fun create_voicemail/2
                                        ,{StartTime, []}
                                        ,Folders
                                        ),
    create_new_messages(API, AccountId, BoxId, MP3, Messages).

-spec create_new_messages(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), binary(), kz_json:objects()) -> 'ok'.
create_new_messages(_API, _AccountId, _BoxId, _MP3, []) -> 'ok';
create_new_messages(API, AccountId, BoxId, MP3, [Message | Messages]) ->
    _R = pqc_cb_vmboxes:new_message(API, AccountId, BoxId, Message, MP3),
    lager:debug("created ~s: ~s", [kz_json:get_value(<<"call_id">>, Message), _R]),
    create_new_messages(API, AccountId, BoxId, MP3, Messages).

create_voicemail(Folder, {Timestamp, Messages}) ->
    Message = create_message(Folder, Timestamp),
    {Timestamp + ?SECONDS_IN_MINUTE, [Message | Messages]}.

create_message({CallId, Folder}, Timestamp) ->
    kz_json:from_list([{<<"call_id">>, CallId}
                      ,{<<"timestamp">>, Timestamp}
                      ,{<<"folder">>, Folder}
                      ,{<<"metadata">>
                       ,kz_json:from_list([{<<"call_id">>, CallId}
                                          ,{<<"caller_id_name">>, <<?MODULE_STRING>>}
                                          ,{<<"caller_id_number">>, <<?MODULE_STRING>>}
                                          ,{<<"length">>, 0}
                                          ,{<<"folder">>, Folder}
                                          ,{<<"timestamp">>, Timestamp}
                                          ])
                       }
                      ]).

new_box(BoxNumber) ->
    new_box(BoxNumber, []).

new_box(BoxNumber, Aliases) ->
    kz_json:set_values([{<<"name">>, kz_binary:rand_hex(4)}
                       ,{<<"mailbox">>, BoxNumber}
                       ,{<<"aliases">>, Aliases}
                       ]
                      ,kzd_vmboxes:new()
                      ).
