%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_storage).

%% Manual testing
-export([seq/0
        ,seq_base/0
        ,seq_blacklisted_url/0
        ,seq_global/0
        ,seq_help_14308/0
        ,seq_help_14316/0
        ,seq_missing_ref/0
        ,seq_skip_validation/0

        ,cleanup/0
        ,storage_doc/1
        ]).

-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-properly({'standalone', [seq_help_14308/0
                         ,seq_help_14316/0
                         ,seq_skip_validation/0 % requires plan override flags
                         ,seq_global/0 % sets global storage, which gets reset in cleanup_system/0
                         ]}).

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-define(UUID, <<"2426cb457dc530acc881977ccbc9a7a7">>).

-define(BASE64_ENCODED, 'true').
-define(SEND_MULTIPART, 'true').

init_system() ->
    TestId = kz_binary:rand_hex(5),
    kz_log:put_callid(TestId),

    _ = kz_data_tracing:clear_all_traces(),
    _ = [kapps_controller:start_app(App) ||
            App <- ['crossbar', 'media_mgr']
        ],
    _ = [crossbar_maintenance:start_module(Mod) ||
            Mod <- ['cb_storage', 'cb_vmboxes']
        ],

    lager:info("INIT FINISHED").

-spec seq() -> 'ok'.
seq() ->
    Tests = [fun seq_base/0
            ,fun seq_skip_validation/0
            ,fun seq_global/0
            ,fun seq_missing_ref/0
            ,fun seq_blacklisted_url/0
            ,fun seq_help_14316/0
            ,fun seq_help_14308/0
            ],
    lists:foreach(fun run/1, Tests).

run(TestFun) ->
    TestFun().

-spec seq_help_14308() -> 'ok'.
seq_help_14308() ->
    lager:info("VANILLA URL"),
    API = init_api(),

    AccountId = create_account(API, ?ACCOUNT_NAME),

    UUID = kz_binary:rand_hex(16),
    Base = pqc_httpd:base_url(API),
    URL = <<Base/binary, ?MODULE_STRING>>,

    HandlerSettings = kz_json:from_list([{<<"handler">>, <<"http">>}
                                        ,{<<"name">>, <<"recording_server">>}
                                        ,{<<"settings">>
                                         ,kz_json:from_list([{<<"url">>, URL}
                                                            ,{<<"verb">>, <<"post">>}
                                                            ,{<<"base64_encode_data">>, 'false'}
                                                            ,{<<"field_list">>, []}
                                                            ])
                                         }
                                        ]),
    Attachments = kz_json:from_list([{UUID, HandlerSettings}]),

    Plan = kz_json:set_value([<<"modb">>, <<"types">>, <<"mailbox_message">>, <<"attachments">>, <<"handler">>], UUID, kz_json:new()),

    StorageDoc = kz_json:from_list([{<<"attachments">>, Attachments}
                                   ,{<<"plan">>, Plan}
                                   ]),

    kzs_plan:allow_validation_overrides(),
    CreatedResp = pqc_cb_storage:create(API, AccountId, StorageDoc, 'false'),
    lager:info("created resp: ~s", [CreatedResp]),

    _ = help_14308_vm(API, AccountId),

    cleanup(API, [AccountId]),
    lager:info("FINISHED VANILLA URL").

-spec seq_help_14316() -> 'ok'.
seq_help_14316() ->
    lager:info("CALL RECORDING TEST"),
    API = init_api(),

    AccountId = create_account(API, ?ACCOUNT_NAME),

    UUID = kz_binary:rand_hex(16),
    Hostname = kz_term:to_binary(kz_network_utils:get_hostname()),
    URL = <<"http://", Hostname/binary, "/index.fu?key=abc123&env=ext&reseller_id=42&reseller_prefix=prefix&account_prefix=pdp&recording=">>,

    HandlerSettings = kz_json:from_list([{<<"handler">>, <<"http">>}
                                        ,{<<"name">>, <<"recording_server">>}
                                        ,{<<"settings">>
                                         ,kz_json:from_list([{<<"url">>, URL}
                                                            ,{<<"verb">>, <<"post">>}
                                                            ,{<<"base64_encode_data">>, 'false'}
                                                            ])
                                         }
                                        ]),
    Attachments = kz_json:from_list([{UUID, HandlerSettings}]),

    Plan = kz_json:set_value([<<"modb">>, <<"types">>, <<"call_recording">>, <<"attachments">>, <<"handler">>], UUID, kz_json:new()),

    StorageDoc = kz_json:from_list([{<<"attachments">>, Attachments}
                                   ,{<<"plan">>, Plan}
                                   ]),

    kzs_plan:allow_validation_overrides(),
    CreatedResp = pqc_cb_storage:create(API, AccountId, StorageDoc, 'false'),
    lager:info("created resp: ~s", [CreatedResp]),

    %% The data cache isn't populated right away, give it a second
    timer:sleep(1000),

    StoreURL = kapps_call_recording:should_store_recording(AccountId, 'undefined'),
    {'true', 'local'} = StoreURL,
    lager:info("call recordings configured to store locally"),

    'true' = has_expected_plan(AccountId, <<"call_recording">>, URL),

    UpdateStorage = kz_json:set_value([<<"plan">>, <<"modb">>, <<"types">>, <<"mailbox_message">>, <<"attachments">>, <<"handler">>], UUID, StorageDoc),

    UpdatedResp = pqc_cb_storage:update(API, AccountId, UpdateStorage, 'false'),
    lager:info("updated resp: ~s", [UpdatedResp]),

    %% The data cache isn't populated right away, give it a second
    timer:sleep(1000),

    'true' = has_expected_plan(AccountId, <<"mailbox_message">>, URL),

    %% just checking if we see the reload in kzs_plan
    lager:info("hotload kzs_plan: ~p : ~p"
              ,[whereis('kazoo_bindings'), kazoo_maintenance:hotload('kzs_plan')]
              ),
    %% give it time to reload
    timer:sleep(1000),

    'true' = has_expected_plan(AccountId, <<"mailbox_message">>, URL),

    cleanup(API, [AccountId]),

    timer:sleep(1000),

    has_expected_plan(AccountId, <<"call_recording">>, 'undefined'),
    has_expected_plan(AccountId, <<"mailbox_message">>, 'undefined'),

    lager:info("FINISHED HELP 14316").

has_expected_plan(AccountId, DocType, 'undefined') ->
    DBPlan = kzs_plan:get_dataplan(kzs_util:format_account_mod_id(AccountId), DocType),
    lager:info("~s plan: ~p", [DocType, DBPlan]),
    'false' = maps:is_key('att_handler', DBPlan),
    'true';
has_expected_plan(AccountId, DocType, <<URL/binary>>) ->
    DBPlan = kzs_plan:get_dataplan(kzs_util:format_account_mod_id(AccountId), DocType),
    lager:info("~s plan: ~p", [DocType, DBPlan]),
    {'kz_att_http', HandlerMap} = maps:get('att_handler', DBPlan),
    'false' = maps:get('base64_encode_data', HandlerMap),
    URL = maps:get('url', HandlerMap),
    <<"post">> = maps:get('verb', HandlerMap),
    lager:info("call recordings configured to store to configured URL"),
    'true'.

-spec seq_blacklisted_url() -> 'ok'.
seq_blacklisted_url() ->
    lager:info("BLACKLIST TEST"),

    API = init_api(),

    AccountId = create_account(API, ?ACCOUNT_NAME),

    StorageDoc = storage_doc(kz_binary:rand_hex(16), <<"https://ignore:me@0.0.0.0">>),
    {'error', ShouldFailToCreate} = pqc_cb_storage:create(API, AccountId, StorageDoc),
    lager:info("should fail: ~s", [ShouldFailToCreate]),

    cleanup(API, [AccountId]),
    lager:info("FINISHED BLACKLIST").

-spec seq_skip_validation() -> 'ok'.
seq_skip_validation() ->
    lager:info("SKIP TEST"),

    API = init_api(),

    AccountId = create_account(API, ?ACCOUNT_NAME),

    StorageDoc = storage_doc(kz_binary:rand_hex(16)),
    {'error', ShouldFailToCreate} = pqc_cb_storage:create(API, AccountId, StorageDoc, 'false'),
    lager:info("should fail: ~s", [ShouldFailToCreate]),

    check_if_allowed(kz_json:decode(ShouldFailToCreate), 'false'),

    kzs_plan:allow_validation_overrides(),
    lager:info("allowing validation overrides"),
    timer:sleep(100),

    ShouldSucceedToCreate = pqc_cb_storage:create(API, AccountId, StorageDoc, 'false'),
    lager:info("should succeed: ~s", [ShouldSucceedToCreate]),

    check_if_allowed(kz_json:decode(ShouldSucceedToCreate), 'true'),

    lager:info("created without validation successfully"),

    kzs_plan:disallow_validation_overrides(),
    lager:info("dis-allowing validation overrides"),

    {'error', ShouldAgainFailToCreate} = pqc_cb_storage:create(API, AccountId, StorageDoc, 'false'),
    lager:info("should fail again: ~s", [ShouldAgainFailToCreate]),
    check_if_allowed(kz_json:decode(ShouldAgainFailToCreate), 'false'),

    cleanup(API, [AccountId]),
    lager:info("FINISHED SKIP TEST").

create_account(API, AccountName) ->
    AccountJSON = properly_accountant:create_account(API, AccountName),
    lager:info("created account: ~s", [AccountJSON]),

    AccountResp = kz_json:decode(AccountJSON),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, AccountResp),
    kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], AccountResp).

check_if_allowed(RespJObj, ShouldAllow) ->
    Errored = 'undefined' =:= kz_json:get_json_value([<<"data">>, <<"validate_settings">>], RespJObj),
    lager:info("request errored: ~p", [Errored]),
    ShouldAllow = Errored.

-spec seq_base() -> 'ok'.
seq_base() ->
    lager:info("BASE TEST"),
    API = init_api(),

    AccountId = create_account(API, ?ACCOUNT_NAME),

    Base = pqc_httpd:base_url(kz_log:get_callid()),
    URL = <<Base/binary, (?ACCOUNT_NAME)/binary>>,

    StorageDoc = storage_doc(kz_binary:rand_hex(16), URL),
    CreatedStorage = pqc_cb_storage:create(API, AccountId, StorageDoc),
    lager:info("created storage: ~p", [CreatedStorage]),

    Test = pqc_httpd:get_req(API, [?ACCOUNT_NAME, AccountId]),
    lager:info("test created ~p", [Test]),

    _ = test_vm_message(API, AccountId, ?ACCOUNT_NAME),

    cleanup(API, [AccountId]),
    lager:info("FINISHED").

init_api() ->
    _ = init_system(),
    #{request_id := LogId} = API = pqc_cb_api:authenticate(),
    {'ok', HTTPD} = pqc_httpd:start_link(LogId),
    API#{httpd => HTTPD}.

-spec seq_global() -> 'ok'.
seq_global() ->
    lager:info("GLOBAL TEST"),

    API = init_api(),

    AccountId = create_account(API, ?ACCOUNT_NAME),

    Base = pqc_httpd:base_url(kz_log:get_callid()),
    URL = <<Base/binary, (?ACCOUNT_NAME)/binary>>,
    StorageDoc = storage_doc(kz_binary:rand_hex(16), URL),

    CreatedStorage = pqc_cb_storage:create(API, 'undefined', StorageDoc),
    lager:info("created storage: ~p", [CreatedStorage]),

    Test = pqc_httpd:get_req(API, [<<?MODULE_STRING>>, <<"system_data">>]),
    lager:info("test created ~p", [Test]),

    _ = test_vm_message(API, AccountId, ?ACCOUNT_NAME),
    cleanup(API, [AccountId]),
    lager:info("FINISHED GLOBAL").

help_14308_vm(API, AccountId) ->
    CreateBox = pqc_cb_vmboxes:create_box(API, AccountId, <<"1010">>),
    lager:info("create VM box: ~p", [CreateBox]),
    BoxId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(CreateBox)),

    {'ok', MP3} = file:read_file(filename:join([code:priv_dir('properly'), "mp3.mp3"])),
    CreateVM = create_voicemail(API, AccountId, BoxId, MP3),
    lager:info("create VM: ~p", [CreateVM]),

    CreatedVM = kz_json:decode(CreateVM),
    MediaId = kz_json:get_ne_binary_value([<<"data">>, <<"media_id">>], CreatedVM),

    {_Headers, RequestBody} = pqc_httpd:wait_for_req(API, [<<?MODULE_STRING>>]),
    lager:info("get VM: ~p", [RequestBody]),

    'true' = handle_multipart_store(MediaId, MP3, RequestBody),
    lager:info("got mp3 data on our web server!"),

    MetadataResp = pqc_cb_vmboxes:fetch_message_metadata(API, AccountId, BoxId, MediaId),
    lager:info("message ~s meta: ~s", [MediaId, MetadataResp]),
    MediaId = kz_json:get_ne_binary_value([<<"data">>, <<"media_id">>], kz_json:decode(MetadataResp)),

    MessageBin = pqc_cb_vmboxes:fetch_message_binary(API, AccountId, BoxId, MediaId),
    lager:info("message bin =:= MP3: ~p", [MessageBin =:= MP3]),
    MessageBin = MP3,

    %% Tests that the media file can be retrieved from storage and proxied via KAZOO
    URL = kvm_message:media_url(AccountId, MediaId),
    lager:info("fetched URL: ~s", [URL]),
    {'ok', 200, _RespHeaders, FetchBin} = kz_http:get(URL),
    lager:info("resp headers: ~p", [_RespHeaders]),
    lager:info("fetched: ~p", [FetchBin]),

    %% media_mgr adds ShoutCAST related data
    MP3Size = byte_size(MP3),
    <<FetchedMP3:MP3Size/binary, _/binary>> = FetchBin,
    lager:info("fetched bin =:= MP3: ~p", [FetchedMP3 =:= MP3]),
    FetchedMP3 = MP3.

test_vm_message(API, AccountId, AccountName) ->
    CreateBox = pqc_cb_vmboxes:create_box(API, AccountId, <<"1010">>),
    lager:info("create VM box: ~p", [CreateBox]),
    CreateBoxResp = kz_json:decode(CreateBox),
    BoxId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], CreateBoxResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, CreateBoxResp),

    {'ok', MP3} = file:read_file(filename:join([code:priv_dir('properly'), "mp3.mp3"])),
    CreateVM = create_voicemail(API, AccountId, BoxId, MP3),
    lager:info("create VM message: ~p", [CreateVM]),

    CreatedVM = kz_json:decode(CreateVM),
    MediaId = kz_json:get_ne_binary_value([<<"data">>, <<"media_id">>], CreatedVM),

    {_Headers, <<RequestBody/binary>>} = pqc_httpd:wait_for_req(API, [AccountName, AccountId, MediaId]),
    lager:info("get VM message storage: ~p", [RequestBody]),

    'true' = handle_multipart_store(MediaId, MP3, RequestBody),
    lager:info("got mp3 data on our web server!"),

    %% pqc_httpd:update_req([<<?MODULE_STRING>>, AccountId, MediaId, AttachmentName], MP3),
    %% lager:info("updating media to non-encoded MP3"),

    MetadataResp = pqc_cb_vmboxes:fetch_message_metadata(API, AccountId, BoxId, MediaId),
    lager:info("message ~s meta: ~s", [MediaId, MetadataResp]),
    MediaId = kz_json:get_ne_binary_value([<<"data">>, <<"media_id">>], kz_json:decode(MetadataResp)),

    MessageBin = pqc_cb_vmboxes:fetch_message_binary(API, AccountId, BoxId, MediaId),
    lager:info("message bin =:= MP3: ~p", [MessageBin =:= MP3]),
    MessageBin = MP3.

-spec create_voicemail(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), binary()) ->
          pqc_cb_api:response().
create_voicemail(API, AccountId, BoxId, MP3) ->
    MessageJObj = default_message(),
    pqc_cb_vmboxes:new_message(API, AccountId, BoxId, MessageJObj, MP3).

default_message() ->
    kz_json:from_list([{<<"folder">>, <<"new">>}
                      ,{<<"caller_id_name">>, <<?MODULE_STRING>>}
                      ,{<<"caller_id_number">>, <<?MODULE_STRING>>}
                      ]).

handle_multipart_store(MediaId, MP3, RequestBody) ->
    handle_multipart_contents(MediaId, MP3, binary:split(RequestBody, <<"\r\n">>, ['global'])).

handle_multipart_contents(_MediaId, _MP3, []) -> 'true';
handle_multipart_contents(MediaId, MP3, [<<>> | Parts]) ->
    handle_multipart_contents(MediaId, MP3, Parts);
handle_multipart_contents(MediaId, MP3, [<<"content-type: application/json">>, <<>>, JSON | Parts]) ->
    lager:info("json body: ~s", [JSON]),
    JObj = kz_json:decode(JSON),
    MediaId = kz_json:get_ne_binary_value([<<"metadata">>, <<"media_id">>], JObj),
    lager:info("got expected media id ~s", [MediaId]),

    kz_json:all(fun({MessageKey, MessageValue}) ->
                        MessageValue =:= kz_json:get_value([<<"metadata">>, MessageKey], JObj)
                end
               ,default_message()
               ),

    handle_multipart_contents(MediaId, MP3, Parts);
handle_multipart_contents(MediaId, MP3, [<<"content-type: audio/mp3">>, <<>>, Base64MP3 | Parts]) ->
    case handle_mp3_contents(MP3, Base64MP3, ?BASE64_ENCODED) of
        'true' ->
            handle_multipart_contents(MediaId, MP3, Parts);
        'false' -> 'false'
    end;
handle_multipart_contents(MediaId, MP3, [<<"content-type: audio/mpeg">>, <<>>, Base64MP3 | Parts]) ->
    case handle_mp3_contents(MP3, Base64MP3, ?BASE64_ENCODED) of
        'true' ->
            handle_multipart_contents(MediaId, MP3, Parts);
        'false' -> 'false'
    end;
handle_multipart_contents(MediaId, MP3, [_Part | Parts]) ->
    ?DEBUG("skipping part ~s", [_Part]),
    handle_multipart_contents(MediaId, MP3, Parts).

handle_mp3_contents(MP3, Base64MP3, 'true') ->
    lager:info("checking base64-encoded data"),
    case base64:decode(Base64MP3) of
        MP3 ->
            lager:info("got expected mp3 data"),
            'true';
        _Data ->
            ?ERROR("failed to decode to mp3: ~w", [Base64MP3]),
            'false'
    end.

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = properly_maintenance:cleanup_module_accounts(?MODULE),
    cleanup_system().

cleanup(API, AccountIds) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, AccountIds),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() ->
    kzs_plan:disallow_validation_overrides(),
    kzs_plan:reset_system_dataplan().

-spec storage_doc(kz_term:ne_binary()) -> kzd_storage:doc().
storage_doc(UUID) ->
    storage_doc(UUID, 'undefined').

storage_doc(UUID, URL) ->
    kz_json:from_list([{<<"attachments">>, storage_attachments(UUID, URL)}
                      ,{<<"plan">>, storage_plan(UUID)}
                      ]).

storage_attachments(UUID, URL) ->
    kz_json:from_list([{UUID, http_handler(URL)}]).

http_handler(URL) ->
    kz_json:from_list([{<<"handler">>, <<"http">>}
                      ,{<<"name">>, <<?MODULE_STRING>>}
                      ,{<<"settings">>, http_handler_settings(URL)}
                      ]).

http_handler_settings('undefined') ->
    Base = pqc_httpd:base_url(kz_log:get_callid()),
    URL = <<Base/binary, ?MODULE_STRING>>,
    http_handler_settings(URL);
http_handler_settings(<<URL/binary>>) ->
    kz_json:from_list([{<<"url">>, URL}
                      ,{<<"verb">>, <<"post">>}
                      ,{<<"send_multipart">>, ?SEND_MULTIPART}
                      ,{<<"base64_encode_data">>, ?BASE64_ENCODED}
                      ,{<<"field_list">>, [kz_json:from_list([{<<"arg">>, <<"account_id">>}])
                                          ,kz_json:from_list([{<<"arg">>, <<"id">>}])
                                          ,kz_json:from_list([{<<"group">>
                                                              ,[kz_json:from_list([{<<"arg">>, <<"attachment">>}])
                                                               ,kz_json:from_list([{<<"const">>, <<"?from="?MODULE_STRING>>}])
                                                               ]
                                                              }
                                                             ])
                                          ]
                       }
                      ]).

storage_plan(UUID) ->
    storage_plan(UUID, 'undefined').

storage_plan(AttUUID, ConnUUID) ->
    kz_json:from_list([{<<"modb">>, modb_plan(AttUUID, ConnUUID)}]).

modb_plan(AttUUID, ConnUUID) ->
    kz_json:from_list([{<<"types">>, modb_types(AttUUID, ConnUUID)}]).

modb_types(AttUUID, ConnUUID) ->
    kz_json:from_list([{<<"mailbox_message">>, mailbox_handler(AttUUID, ConnUUID)}]).

mailbox_handler(AttUUID, ConnUUID) ->
    Handler = kz_json:from_list([{<<"handler">>, AttUUID}]),
    kz_json:from_list([{<<"attachments">>, Handler}
                      ,{<<"connection">>, ConnUUID}
                      ]).

storage_doc_missing_conn(AttUUID, ConnUUID) ->
    kz_json:from_list([{<<"attachments">>, storage_attachments(AttUUID, 'undefined')}
                      ,{<<"plan">>, storage_plan(AttUUID, ConnUUID)}
                      ]).

-spec seq_missing_ref() -> 'ok'.
seq_missing_ref() ->
    lager:info("MISSING REF TEST"),

    API = init_api(),

    AccountId = create_account(API, ?ACCOUNT_NAME),

    MissingConnDoc = storage_doc_missing_conn(kz_binary:rand_hex(16), kz_binary:rand_hex(16)),
    {'error', ErrMsg} = pqc_cb_storage:create(API, AccountId, MissingConnDoc),
    lager:info("failed to create storage: ~s", [ErrMsg]),
    cleanup(API, [AccountId]).
