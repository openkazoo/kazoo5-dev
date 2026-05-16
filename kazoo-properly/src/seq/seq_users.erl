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
-module(seq_users).

-export([seq/0
        ,seq_crud/0
        ,seq_dup_keys/0
        ,seq_kcal_41/0
        ,seq_kcro_150/0
        ,seq_kzoo_309/0
        ,seq_kzoo_75/0
        ,seq_paginate/0
        ,seq_kcro_216/0
        ,cleanup/0
        ,new_user/0, new_user/1
        ]).

-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kazoo_json.hrl"). %% ?EMPTY_JSON_OBJECT

-properly({'standalone', [seq_kcro_150/0
                         ,seq_kcro_216/0
                         ]}).

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).

-type user_objects_proplist() :: kz_term:proplist_kv(kz_term:ne_binary()
                                                    ,kz_term:ne_binary()
                                                    ).
-type kcro_150_init_state() :: {pqc_cb_api:state() %% API
                               ,kz_term:ne_binary() %% AccountId
                               ,kz_term:ne_binary() %% UserId
                               ,user_objects_proplist() %% User Objects
                               }.
-type object_types() :: kz_term:ne_binary() | kz_term:ne_binaries().

-spec seq() -> 'ok'.
seq() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun seq_crud/0
                  ,fun seq_dup_keys/0
                  ,fun seq_kcal_41/0
                  ,fun seq_kcro_150/0
                  ,fun seq_kzoo_309/0
                  ,fun seq_kzoo_75/0
                  ,fun seq_paginate/0
                  ,fun seq_kcro_216/0
                  ]
                 ).

-spec seq_crud() -> 'ok'.
seq_crud() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_users']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    'ok' = create_simple_user(API, AccountId),
    wrong_format_check(API, AccountId),

    cleanup(API, [AccountId]),
    lager:info("FINISHED USERS SEQ").

-spec seq_kzoo_75() -> 'ok'.
seq_kzoo_75() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_users']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    'ok' = create_user_with_ftp_recordings(API, AccountId),
    cleanup(API, [AccountId]),
    lager:info("FINISHED KZOO-75").

%% @doc Test that API gives an error response when including duplicate
%% keys in request
-spec seq_dup_keys() -> 'ok'.
seq_dup_keys() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_users']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_users:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    UserProps = kz_json:to_proplist(new_user()),
    UserJObj = kz_json:from_list([{<<"first_name">>, <<?MODULE_STRING>>} | UserProps]),

    {'error', CreateResp} = pqc_cb_users:create(API, AccountId, UserJObj),
    lager:info("error creating user ~s", [CreateResp]),
    ErrorJObj = kz_json:decode(CreateResp),

    <<"error">> = kz_json:get_ne_binary_value(<<"status">>, ErrorJObj),
    <<"body">> = kz_json:get_ne_binary_value([<<"data">>, <<"json">>, <<"invalid">>, <<"target">>], ErrorJObj),
    400 = kz_json:get_integer_value(<<"error">>, ErrorJObj),

    cleanup(API, [AccountId]),
    lager:info("FINISHED DUP KEYS").

-spec seq_paginate() -> 'ok'.
seq_paginate() ->
    %% setup
    API = pqc_cb_api:init_api(['crossbar'], ['cb_users']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptyUserSummary = pqc_cb_users:summary(API, AccountId),
    lager:info("empty summary: ~s", [EmptyUserSummary]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyUserSummary)),

    %% initialization
    UserCount = 10,
    UserIds = [create_user(API, AccountId, ?ACCOUNT_NAME, Count) || Count <- lists:seq(1, UserCount)],

    %% create 2 devices for every user
    DeviceCount = 2,
    DeviceIds = [create_device(API, AccountId, UserId, Count)
                 || {UserId, _} <- UserIds,
                    Count <- lists:seq(1, DeviceCount)
                ],

    %% create a callflow for each user
    %% disabled cause why is it here?
    %% _CallflowIds = [create_callflow(API, AccountId, UID, Count) || {UID, Count} <- UserIds],

    %% testing
    UserSummaryResp = pqc_cb_users:paginated_summary(API, AccountId, 100),
    lager:info("user summary ~s", [UserSummaryResp]),
    UserSummary = kz_json:decode(UserSummaryResp),

    %% fetch the whole listing of users
    UserCount = kz_json:get_integer_value(<<"page_size">>, UserSummary),
    UserListing = kz_json:get_list_value(<<"data">>, UserSummary),
    'true' = lists:all(fun(User) -> props:is_defined(kz_doc:id(User), UserIds) end, UserListing),

    %% fetch users 2 by 2
    fetch_users_by_page(API, AccountId, UserIds, 2, 'undefined'),

    %% check that each user's devices get paginated properly
    _ = [check_devices_summary(pqc_cb_users:devices(API, AccountId, UserId), DeviceCount, just_user_devices(UserId, DeviceIds))
         || {UserId, _} <- UserIds
        ],

    %% fetch the whole listing of devices
    check_devices_summary(pqc_cb_devices:summary(API, AccountId), DeviceCount * UserCount, DeviceIds),

    %% check that a user's devices are paginated properly 1 by 1
    _ = [fetch_devices_by_page(API, AccountId, UserId, just_user_devices(UserId, DeviceIds), 1, 'undefined')
         || {UserId, _} <- UserIds
        ],

    %% cleanup
    cleanup(API, [AccountId]),
    lager:info("FINISHED PAGINATE").

%% test password expiration
-spec seq_kcro_216() -> 'ok'.
seq_kcro_216() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_users', 'cb_user_auth', 'cb_system_configs']),
    pqc_cb_api:patch_token_costs(API, 0),
    set_password_expiry(API, 'null'),

    AccountId = create_account(API, ?ACCOUNT_NAME),

    Username = kz_binary:rand_hex(6),
    Password = kz_binary:rand_hex(6),

    CreatedUser = create_new_user(API, AccountId, [{<<"username">>, Username}
                                                  ,{<<"password">>, Password}
                                                  ]),
    UserId = kz_doc:id(CreatedUser),

    %% with no sys config expiry, password is valid
    FetchResp = pqc_cb_users:fetch(API, AccountId, UserId),
    lager:info("fetched user before password expiry set: ~s", [FetchResp]),
    FetchJObj = kz_json:decode(FetchResp),
    'false' = kz_json:is_true([<<"metadata">>, <<"is_password_expired">>], FetchJObj),
    'false' = kz_json:is_true([<<"data">>, <<"require_password_update">>], FetchJObj, 'false'),

    %% user_auth attempt is valid
    AuthResp = pqc_cb_user_auth:by_account_id(API, AccountId, Username, Password),
    lager:info("auth resp: ~s", [AuthResp]),
    'true' = kz_json:is_defined(<<"auth_token">>, kz_json:decode(AuthResp)),

    %% with sys config expiry set, password is expired (since no pvt_password_timestamp)
    set_password_expiry(API, ?SECONDS_IN_HOUR),
    FetchResp2 = pqc_cb_users:fetch(API, AccountId, UserId),
    lager:info("fetched user after password expiry set: ~s", [FetchResp2]),
    FetchJObj2 = kz_json:decode(FetchResp2),
    'true' = kz_json:is_true([<<"metadata">>, <<"is_password_expired">>], FetchJObj2),
    %% force password update key is set
    'true' = kz_json:is_true([<<"data">>, <<"require_password_update">>], FetchJObj2),

    %% user_auth should fail
    AuthResp2 = pqc_cb_user_auth:by_account_id(API, AccountId, Username, Password),
    lager:info("auth resp should fail: ~p", [AuthResp2]),

    %% update password on user
    NewPassword = kz_binary:rand_hex(6),
    PatchedResp = pqc_cb_users:patch(API, AccountId, UserId, kz_json:from_list([{<<"password">>, NewPassword}])),
    lager:info("patched new password in: ~s", [PatchedResp]),
    %% password should be valid on resp
    'false' = kz_json:is_true([<<"metadata">>, <<"is_password_expired">>], kz_json:decode(PatchedResp)),

    %% password is valid, user_auth should succeed with new password
    AuthResp3 = pqc_cb_user_auth:by_account_id(API, AccountId, Username, NewPassword),
    lager:info("auth resp with new password: ~s", [AuthResp3]),
    'true' = kz_json:is_defined(<<"auth_token">>, kz_json:decode(AuthResp3)),

    cleanup(API, [AccountId]),

    lager:info("FINISHED KCRO-216").

%% KCRO-150 {
-spec seq_kcro_150() -> 'ok'.
seq_kcro_150() ->
    %% initialize
    API = pqc_cb_api:init_api(['crossbar'], ['cb_users'
                                            ,'cb_phone_numbers'
                                            ,'cb_callflows'
                                            ,'cb_vmboxes'
                                            ,'cb_devices'
                                            ,'cb_conferences'
                                            ,'cb_faxboxes'
                                            ,'cb_media'
                                            ]),

    %% testing
    TestCases = [fun only_delete_user_not_payload/1
                ,fun only_delete_user_empty_object_types/1
                ,fun delete_user_and_numbers/1
                ,fun delete_user_and_callflow/1
                ,fun delete_user_and_some_objects/1
                ,fun delete_user_and_all_its_objects/1
                ,fun delete_user_and_duplicated_objects/1
                ],
    lists:foreach(fun(TestCase) ->
                          State = {_API, AccountId, _, _} = seq_kcro_150_init_state(API),
                          TestCase(State),
                          cleanup(API, [AccountId]) %% Remove account and "everything" associated to it.
                  end
                 ,TestCases
                 ),

    %% cleanup
    lager:info("FINISHED KCRO 150").

-spec seq_kcal_41() -> 'ok'.
seq_kcal_41() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_users']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    CreateUser = pqc_cb_users:create(API, AccountId, new_user()),
    lager:info("created user: ~s", [CreateUser]),
    CreateResp = kz_json:decode(CreateUser),
    _UserId = kz_doc:id(kz_json:get_json_value(<<"metadata">>, CreateResp)),
    User = kz_json:get_json_value(<<"data">>, CreateResp),

    CfwdUser1 = call_forwarded_user_1(User),
    CfwdUser2 = call_forwarded_user_2(User),
    CfwdUser3 = call_forwarded_user_3(User),
    LegacyUser = legacy_call_forward(User),

    SummaryResults = pqc_cb_users:summary(API, AccountId),
    lager:info("summary listing of users no cfwd: ~s", [SummaryResults]),

    SummaryFeatures = kz_json:get_list_value([<<"data">>, 1, <<"features">>]
                                            ,kz_json:decode(SummaryResults)
                                            ),
    'false' = lists:member(<<"call_forward">>, SummaryFeatures),

    find_call_forward_feature(API, AccountId, CfwdUser1, 'false'),
    remove_call_forward(API, AccountId, CfwdUser1),
    find_call_forward_feature(API, AccountId, CfwdUser2, 'true'),
    remove_call_forward(API, AccountId, CfwdUser2),
    find_call_forward_feature(API, AccountId, CfwdUser3, 'true'),
    remove_call_forward(API, AccountId, CfwdUser3),
    find_call_forward_feature(API, AccountId, LegacyUser, 'true'),
    remove_call_forward(API, AccountId, LegacyUser),

    cleanup(API, [AccountId]),
    lager:info("FINISHED KCAL-41").

remove_call_forward(API, AccountId, User) ->
    RemoveCfwdResp = pqc_cb_users:update(API, AccountId, kz_json:set_value(<<"call_forward">>, 'null', User)),
    lager:info("removed cfwd user: ~s", [RemoveCfwdResp]),

    NextSummaryResults = pqc_cb_users:summary(API, AccountId),
    lager:info("next summary listing of users no cfwd: ~s", [NextSummaryResults]),

    NextSummaryFeatures = kz_json:get_list_value([<<"data">>, 1, <<"features">>]
                                                ,kz_json:decode(NextSummaryResults)
                                                ),
    'false' = lists:member(<<"call_forward">>, NextSummaryFeatures).

find_call_forward_feature(API, AccountId, UpdateUser, ShouldExist) ->
    UpdateResp = pqc_cb_users:update(API, AccountId, UpdateUser),
    lager:info("updated user: ~s", [UpdateResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(UpdateResp)),

    SummaryResultsCfwd = pqc_cb_users:summary(API, AccountId),
    lager:info("summary listing of users with cfwd: ~s", [SummaryResultsCfwd]),

    SummaryCfwdFeatures = kz_json:get_list_value([<<"data">>, 1, <<"features">>]
                                                ,kz_json:decode(SummaryResultsCfwd)
                                                ),
    ShouldExist = lists:member(<<"call_forward">>, SummaryCfwdFeatures).

%% Only user object should be deleted {
-spec only_delete_user_not_payload(kcro_150_init_state()) -> 'ok'.
only_delete_user_not_payload({_API, _AccountId, _UserId, _UserObjs}=InitState) ->
    lager:debug("running ~p:~p/~p test case", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    %% generate_command_for_manually_testing_kcro_150_implementation(InitState),
    run_delete_user_action(InitState, [], kz_json:new()).

-spec only_delete_user_empty_object_types(kcro_150_init_state()) -> 'ok'.
only_delete_user_empty_object_types({_API, _AccountId, _UserId, _UserObjs}=InitState) ->
    lager:debug("running ~p:~p/~p test case", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    ObjTypes = [],
    ReqBody = kz_json:from_list([{<<"object_types">>, ObjTypes}]),
    run_delete_user_action(InitState, ObjTypes, ReqBody).
%% }

%% User deleted and Callflows should remain undeleted, but without reconcilable numbers assigned to it.
-spec delete_user_and_numbers(kcro_150_init_state()) -> 'ok'.
delete_user_and_numbers({_API, _AccountId, _UserId, _UserObjs}=InitState) ->
    lager:debug("running ~p:~p/~p test case", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    run_delete_user_action(InitState, [<<"phone_numbers">>]),
    verify_callflow_numbers_were_updated(InitState).

%% If the request is to only delete the user and the numbers in use by the callflows owned by the
%% user, the numbers should be deleted, but also, the callflows loosing the numbers should be
%% updated (its numbers' list) to reflect these changes.
-spec verify_callflow_numbers_were_updated(kcro_150_init_state()) -> 'ok'.
verify_callflow_numbers_were_updated({API, AccountId, _UserId, UserObjs}) ->
    CallflowId = props:get_ne_binary_value(<<"callflow">>, UserObjs),
    Number = props:get_ne_binary_value(<<"phone_numbers">>, UserObjs),
    FetchResp = fetch_user_object(API, AccountId, <<"callflow">>, CallflowId),
    Callflow = kz_json:get_json_value(<<"data">>, kz_json:decode(FetchResp)),
    'false' = lists:member(Number, kzd_callflows:numbers(Callflow)),
    'ok'.

%% User and callflows removed, but numbers should not be deleted.
-spec delete_user_and_callflow(kcro_150_init_state()) -> 'ok'.
delete_user_and_callflow({_API, _AccountId, _UserId, _UserObjs}=InitState) ->
    lager:debug("running ~p:~p/~p test case", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    run_delete_user_action(InitState, [<<"callflow">>]).

%% Only objects listed within `object_types' array should be deleted.
-spec delete_user_and_some_objects(kcro_150_init_state()) -> 'ok'.
delete_user_and_some_objects({_API, _AccountId, _UserId, _UserObjs}=InitState) ->
    lager:debug("running ~p:~p/~p test case", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    run_delete_user_action(InitState
                          ,[<<"callflow">>, <<"phone_numbers">>, <<"vmbox">>, <<"conference">>]
                          ).

%% User along all of its owned objects should be deleted.
-spec delete_user_and_all_its_objects(kcro_150_init_state()) -> 'ok'.
delete_user_and_all_its_objects({_API, _AccountId, _UserId, _UserObjs}=InitState) ->
    lager:debug("running ~p:~p/~p test case", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    run_delete_user_action(InitState, <<"all">>).

%% When duplicated objects are provided, the delete should still succeed and not try to delete the
%% same object twice, or the number of times it was listed.
-spec delete_user_and_duplicated_objects(kcro_150_init_state()) -> 'ok'.
delete_user_and_duplicated_objects({_API, _AccountId, _UserId, _UserObjs}=InitState) ->
    lager:debug("running ~p:~p/~p test case", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    run_delete_user_action(InitState, [<<"media">>, <<"vmbox">>, <<"media">>, <<"media">>]).

-spec run_delete_user_action(kcro_150_init_state(), object_types()) -> 'ok'.
run_delete_user_action({_API, _AccountId, _UserId, _UserObjs}=InitState, ObjTypes) ->
    ReqBody = kz_json:from_list([{<<"object_types">>, ObjTypes}]),
    run_delete_user_action(InitState, ObjTypes, ReqBody).

%% Runs `DELETE /user/{USER_ID}' action. Then, based on the list of object_types sent on the request,
%% creates a list of objects (see props:split/2 call) that should have been deleted and another list
%% with the objects that should have NOT been deleted and verify the results match the expected
%% behavior using these 2 lists.
-spec run_delete_user_action(kcro_150_init_state(), object_types(), kz_json:object()) -> 'ok'.
run_delete_user_action({API, AccountId, UserId, _UserObjs}=InitState, ObjTypes, ?EMPTY_JSON_OBJECT) ->
    verify_delete_user(InitState, ObjTypes, pqc_cb_users:delete(API, AccountId, UserId));
run_delete_user_action({API, AccountId, UserId, _UserObjs}=InitState, ObjTypes, ReqBody) ->
    verify_delete_user(InitState, ObjTypes, pqc_cb_users:delete(API, AccountId, UserId, ReqBody)).

-spec verify_delete_user(kcro_150_init_state(), object_types(), pqc_cb_api:response()) -> 'ok'.
verify_delete_user({API, AccountId, UserId, UserObjs}, ObjTypes, DeleteResp) ->
    lager:debug("delete user response: ~p", [DeleteResp]),
    'true' = check_success(DeleteResp),
    {Deleted, NotDeleted} = props:partition(split_user_objects_filter(ObjTypes), UserObjs),
    Deleted1 = [{<<"user">>, UserId} | Deleted], %% User is implicitly deleted.
    'true' = verify_user_objects(API, AccountId, Deleted1, NotDeleted),
    'ok'.
%% }

%% Make sure users may contain an emergency address. If addresses.emergency key is set in the
%% request, all the required emergency address' fields should be present.
-spec seq_kzoo_309() -> 'ok'.
seq_kzoo_309() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_users']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    AddrFields = [{Field, kz_binary:rand_hex(4)}
                  || Field <- [<<"country">>
                              ,<<"locality">>
                              ,<<"name">>
                              ,<<"postal_code">>
                              ,<<"region">>
                              ,<<"street">>
                              ]
                 ] ++ [{<<"house_number">>, kz_term:rand_integer(1, 10)}],

    seq_kzoo_309_new_user_addresses(API, AccountId, AddrFields),
    seq_kzoo_309_old_user_addresses(API, AccountId, AddrFields),

    cleanup(API, [AccountId]),
    lager:info("FINISHED KZOO_309 SEQ").

-spec seq_kzoo_309_new_user_addresses(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:proplist()) -> 'ok'.
seq_kzoo_309_new_user_addresses(API, AccountId, AddrFields) ->
    lager:info("running tests for NEW user addresses schema"),
    %% When addresses.emergency is set and all the required fields are present, the request must succeed.
    Addresses = kz_json:from_list_recursive([{<<"emergency">>, AddrFields}]),
    UserJObj = kzd_users:set_addresses(new_user(), Addresses),
    CreateResp = pqc_cb_users:create(API, AccountId, UserJObj),
    lager:info("created user ~s", [CreateResp]),
    CreatedUser = get_decoded_data(CreateResp),
    'true' = addrs_are_equal(kzd_users:addresses(CreatedUser), Addresses),

    %% When any of the required emergency address' fields is missing, the request should fail.
    [{FirstKey, _} | AddrFields2] = AddrFields,
    EmerAddr2 = kz_json:from_list_recursive([{<<"emergency">>, AddrFields2}]),
    UserJObj2 = kzd_users:set_addresses(new_user(), EmerAddr2),
    _Failed = {'error', ErrorRespEnc} = pqc_cb_users:create(API, AccountId, UserJObj2),
    lager:info("expected failure response: ~p", [_Failed]),
    %% TODO: Check why cb_users is encoding the dots when a required field is part of an object.
    %% Look at next line for an example.
    ExpErr = kz_json:from_list_recursive([{<<"addresses%2Eemergency%2E", FirstKey/binary>>
                                          ,[{<<"required">>
                                            ,[{<<"value">>, FirstKey}
                                             ,{<<"message">>, <<"Field is required but missing">>}
                                             ]
                                            }
                                           ]
                                          }
                                         ]),
    'true' = kz_json:are_equal(get_decoded_data(ErrorRespEnc), ExpErr),
    'ok'.

-spec seq_kzoo_309_old_user_addresses(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:proplist()) -> 'ok'.
seq_kzoo_309_old_user_addresses(API, AccountId, AddrFields) ->
    lager:info("running tests for OLD user addresses schema"),
    OldSchema = [kz_json:from_list([{<<"address">>, <<"old address schema">>}])],
    NewSchema = kz_json:from_list([{<<"vcard">>, OldSchema}]),

    %% Old schema is not allowed anymore when creating users.
    User0 = kz_json:set_value(<<"addresses">>, OldSchema, new_user()),
    _ExpFail0 = {'error', CreateResp0} = pqc_cb_users:create(API, AccountId, User0),
    lager:info("expected failure: ~p", [_ExpFail0]),
    Expected0 = kz_json:from_list_recursive([{<<"addresses">>
                                             ,[{<<"type">>
                                               ,[{<<"value">>, kz_json:to_proplist(OldSchema)}
                                                ,{<<"target">>, <<"object">>}
                                                ,{<<"message">>, <<"Value did not match type(s): object">>}
                                                ]
                                               }
                                              ]
                                             }
                                            ]),
    'true' = kz_json:are_equal(get_decoded_data(CreateResp0), Expected0),

    %% Create user without addresses.
    CreatedUser1 = pqc_cb_users:create(API, AccountId, new_user()),
    UserId = kz_doc:id(get_decoded_data(CreatedUser1)),
    {'ok', UserDoc} = kzd_users:fetch(AccountId, UserId),
    'true' = addrs_are_equal('undefined', {'ok', UserDoc}),
    %% Then, add (old schema) addresses directly to user's DB document.
    'true' = addrs_are_equal(OldSchema
                            ,kz_datamgr:save_doc(AccountId, kz_json:set_value(<<"addresses">>, OldSchema, UserDoc))
                            ),
    %% Get user via HTTP API, addresses should have been automatically migrated for the response only,
    %% not updated within DB.
    'true' = addrs_are_equal(NewSchema, pqc_cb_users:fetch(API, AccountId, UserId)),
    'true' = addrs_are_equal(OldSchema, kzd_users:fetch(AccountId, UserId)),
    %% PATCH user, addresses should also be updated in DB as well, as part of the PATCH action, because
    %% user addresses is migrated as part of the validation process within cb_users.
    PatchJObj0 = kz_json:from_list([{<<"first_name">>, <<"name">>}]),
    'true' = addrs_are_equal(NewSchema, pqc_cb_users:patch(API, AccountId, UserId, PatchJObj0)),
    {'ok', UserDoc1} = kzd_users:fetch(AccountId, UserId),
    'true' = addrs_are_equal(NewSchema, {'ok', UserDoc1}),

    EmerAddress = kz_json:from_list_recursive([{<<"emergency">>, AddrFields}]),

    %% Set user's addresses back to old schema.
    'true' = addrs_are_equal(OldSchema
                            ,kz_datamgr:save_doc(AccountId, kz_json:set_value(<<"addresses">>, OldSchema, UserDoc1))
                            ),
    %% PATCH emergency address to user with old schema addresses field. Old schema should be
    %% migrated along the process.
    PatchJObj1 = kz_json:from_list([{<<"addresses">>, EmerAddress}]),
    Expected1 = kz_json:merge(EmerAddress, NewSchema), %% kz_json:from_list([{<<"emergency">>, EmerAddres}, {<<"vcard">>, OldSchema}])
    Patch = pqc_cb_users:patch(API, AccountId, UserId, PatchJObj1),
    'true' = addrs_are_equal(Expected1, Patch),
    'true' = addrs_are_equal(Expected1, kzd_users:fetch(AccountId, UserId)),
    'ok'.

-spec addrs_are_equal(kz_term:api_object()
                     | kz_json:objects() %% User's old addresses schema.
                     ,kz_json:object()
                     | kz_term:ne_binary()
                     | {'ok', kz_term:ne_binary()} %% pqc_cb_{MODULE} responses.
                     | {'ok', kz_json:object() | kz_json:objects()} | kz_datamgr:data_error() %% kz_datamgr:save_doc/3 responses.
                     ) -> boolean().
addrs_are_equal(AddressJObj, {'ok', UserJObj}) -> %% kzd_users:[fetch, save_doc]/2 reply.
    %% Cannot use kzd_users:addresses/1 function here, because it expects the addresses' value to be
    %% an object, so when the old schema is being used as the value for this field, the function
    %% will return 'undefined'.
    addrs_are_equal(AddressJObj, kz_json:get_value(<<"addresses">>, UserJObj));
addrs_are_equal(AddressJObj, <<Bin/binary>>) -> %% Successful HTTP API reply.
    addrs_are_equal(AddressJObj, kz_json:get_value(<<"addresses">>, get_decoded_data(Bin)));
addrs_are_equal([OldSchema], [UserAddresses]) -> %% User's old addresses' schema.
    addrs_are_equal(OldSchema, UserAddresses);
addrs_are_equal(AddressesJObj0, AddressesJObj1) ->
    %% Cannot rely on getting 'addresses' object's value here, because sometimes,
    %% AddressesJObj1 is the addresses object itself.
    kz_json:are_equal(AddressesJObj0, AddressesJObj1).

-spec get_decoded_data(kz_term:ne_binary()) -> kz_json:object().
get_decoded_data(APIRespBin) ->
    kz_json:get_json_value(<<"data">>, kz_json:decode(APIRespBin)).

just_user_devices(UserId, DeviceIds) ->
    [{DeviceId, UserId} || {DeviceId, UID} <- DeviceIds, UserId =:= UID].

check_devices_summary(<<DeviceSummaryResp/binary>>, DeviceCount, DeviceIds) ->
    lager:info("device summary: ~s", [DeviceSummaryResp]),
    DeviceSummary = kz_json:decode(DeviceSummaryResp),

    DeviceCount = kz_json:get_integer_value(<<"page_size">>, DeviceSummary),
    DeviceListing = kz_json:get_list_value(<<"data">>, DeviceSummary),

    'true' = lists:all(fun(Device) -> props:is_defined(kz_doc:id(Device), DeviceIds) end, DeviceListing).

fetch_users_by_page(API, AccountId, [_|_]=UserIds, PageSize, StartKey) ->
    SummaryResp = pqc_cb_users:paginated_summary(API, AccountId, PageSize, StartKey),
    lager:info("summary for start key ~p: ~s", [StartKey, SummaryResp]),
    Summary = kz_json:decode(SummaryResp),

    PageSize = kz_json:get_integer_value(<<"page_size">>, Summary),

    %% case kz_json:get_ne_binary_value(<<"start_key">>, Summary) of
    %%     StartKey -> 'ok';
    %%     _SK when StartKey =:= 'undefined' -> 'ok'
    %% end,

    NextStartKey = kz_json:get_ne_binary_value(<<"next_start_key">>, Summary),
    UserSummary = kz_json:get_list_value(<<"data">>, Summary),

    case lists:foldl(fun filter_user/2, UserIds, UserSummary) of
        [] when NextStartKey =:= 'undefined' ->
            lager:info("all users found");
        NewUserIds when NextStartKey =/= 'undefined' ->
            lager:info("fetching next page"),
            fetch_users_by_page(API, AccountId, NewUserIds, PageSize, NextStartKey)
    end.

filter_user(UserJObj, UserIds) ->
    props:delete(kz_doc:id(UserJObj), UserIds).

fetch_devices_by_page(API, AccountId, UserId, [_|_]=DeviceIds, PageSize, StartKey) ->
    SummaryResp = pqc_cb_users:paginated_devices(API, AccountId, UserId, PageSize, StartKey),
    lager:info("summary for start key ~p: ~s", [StartKey, SummaryResp]),
    Summary = kz_json:decode(SummaryResp),

    PageSize = kz_json:get_integer_value(<<"page_size">>, Summary),

    %% case kz_json:get_ne_binary_value(<<"start_key">>, Summary) of
    %%     StartKey -> 'ok';
    %%     _SK when StartKey =:= 'undefined' -> 'ok'
    %% end,

    NextStartKey = kz_json:get_ne_binary_value(<<"next_start_key">>, Summary),
    DeviceSummary = kz_json:get_list_value(<<"data">>, Summary),

    case lists:foldl(fun filter_user/2, DeviceIds, DeviceSummary) of
        [] when NextStartKey =:= 'undefined' ->
            lager:info("all devices found");
        NewDeviceIds when NextStartKey =/= 'undefined' ->
            lager:info("fetching next page of devices"),
            fetch_devices_by_page(API, AccountId, UserId, NewDeviceIds, PageSize, NextStartKey);
        _IDs ->
            lager:warning("device IDs left for next_start_key ~p: ~p", [NextStartKey, _IDs]),
            throw({'error', 'too_many_devices'})
    end.

create_user(API, AccountId, AccountName, Count) ->
    UserJObj = new_user(kz_json:from_list([{<<"count">>, Count}
                                          ,{<<"first_name">>, kz_term:to_binary(Count)}
                                          ,{<<"last_name">>, AccountName}
                                          ])),
    CreateResp = pqc_cb_users:create(API, AccountId, UserJObj),
    maybe_log_create_entity_resp('user', CreateResp),
    CreatedUser = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    {kz_doc:id(CreatedUser), Count}.

create_device(API, AccountId, OwnerId, Count) ->
    DeviceJObj = seq_devices:new_device(kz_json:from_list([{<<"count">>, Count}
                                                          ,{<<"owner_id">>, OwnerId}
                                                          ])),
    CreateResp = pqc_cb_devices:create(API, AccountId, DeviceJObj),
    maybe_log_create_entity_resp('device', CreateResp),
    CreatedDevice = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    {kz_doc:id(CreatedDevice), OwnerId}.

%% create_callflow(API, AccountId, UserId, Number) when is_integer(Number) ->
%%     create_callflow(API, AccountId, UserId, [kz_term:to_binary(Number)]);
create_callflow(API, AccountId, UserId, [<<_Number/binary>>|_] = Numbers) ->
    Flow = kz_json:from_list([{<<"module">>, <<"user">>}
                             ,{<<"data">>, kz_json:from_list([{<<"id">>, UserId}])}
                             ]),
    Callflow = kz_doc:public_fields(
                 kz_doc:setters(kzd_callflows:new()
                               ,[{fun kzd_callflows:set_numbers/2, Numbers}
                                ,{fun kzd_callflows:set_name/2, UserId}
                                ,{fun kzd_callflows:set_flow/2, Flow}
                                ,{fun kzd_callflows:set_owner_id/2, UserId}
                                ]
                               )
                ),

    CreateResp = pqc_cb_callflows:create(API, AccountId, Callflow),
    maybe_log_create_entity_resp('callflow', CreateResp),
    CreatedCallflow = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    {kz_doc:id(CreatedCallflow), Numbers}.

-spec create_vmbox(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          kz_term:ne_binary().
create_vmbox(API, AccountId, Name, MailBox, OwnerId) ->
    CreateResp = pqc_cb_vmboxes:create_box(API, AccountId, kz_json:from_list([{<<"name">>, Name}
                                                                             ,{<<"mailbox">>, MailBox}
                                                                             ,{<<"owner_id">>, OwnerId}
                                                                             ])),
    maybe_log_create_entity_resp('vmbox', CreateResp),
    kz_doc:id(kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp))).

-spec add_number(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
add_number(API, AccountId, Number) ->
    CreateResp = pqc_cb_phone_numbers:add_number(API, AccountId, Number),
    maybe_log_create_entity_resp('number', CreateResp),
    kz_doc:id(kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp))).

-spec create_conference(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_conference(API, AccountId, OwnerId) ->
    create_conference(API, AccountId, OwnerId, kz_binary:rand_hex(4)).

-spec create_conference(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_conference(API, AccountId, OwnerId, Name) ->
    CreateResp = pqc_cb_conferences:create(API, AccountId, kz_json:from_list([{<<"name">>, Name}
                                                                             ,{<<"owner_id">>, OwnerId}
                                                                             ])),
    maybe_log_create_entity_resp('conference', CreateResp),
    kz_doc:id(kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp))).

-spec create_faxbox(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_faxbox(API, AccountId, OwnerId) ->
    create_faxbox(API, AccountId, OwnerId, kz_binary:rand_hex(4)).

-spec create_faxbox(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_faxbox(API, AccountId, OwnerId, Name) ->
    CreateResp = pqc_cb_faxboxes:create(API, AccountId, kz_json:from_list([{<<"name">>, Name}
                                                                          ,{<<"owner_id">>, OwnerId}
                                                                          ])),
    maybe_log_create_entity_resp('faxbox', CreateResp),
    kz_doc:id(kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp))).

-spec create_media(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          kz_term:ne_binary().
create_media(API, AccountId, Name, MediaSource, OwnerId) ->
    CreateResp = pqc_cb_media:create(API, AccountId, kz_json:from_list([{<<"name">>, Name}
                                                                       ,{<<"media_source">>, MediaSource}
                                                                       ,{<<"owner_id">>, OwnerId}
                                                                       ])),
    maybe_log_create_entity_resp('media', CreateResp),
    kz_doc:id(kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp))).

create_user_with_ftp_recordings(API, AccountId) ->
    Hostname = kz_term:to_binary(kz_network_utils:get_hostname()),
    UserJObj = kz_json:set_values([{[<<"call_recording">>, <<"inbound">>, <<"offnet">>, <<"url">>]
                                   ,<<"ftp://user:password@", Hostname/binary>>
                                   }
                                  ,{[<<"call_recording">>, <<"outbound">>, <<"onnet">>, <<"url">>]
                                   ,<<"ftps://user:password@", Hostname/binary>>
                                   }
                                  ]
                                 ,new_user()
                                 ),
    <<CreateResp/binary>> = pqc_cb_users:create(API, AccountId, UserJObj),
    lager:info("created user ~s", [CreateResp]),

    CreatedUser = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    <<_UserId/binary>> = kz_doc:id(CreatedUser),
    'true' = user_docs_match(kzd_users:set_password(UserJObj, 'null'), CreatedUser),

    lager:info("created successfully").

%% unconditional is enabled but common is not enabled => disabled
call_forwarded_user_1(User) ->
    CallForward = kz_doc:setters(kz_json:new()
                                ,[{fun kzd_call_forward:set_number/2, kz_binary:rand_hex(3)}
                                 ,{fun kzd_call_forward:set_enabled/2, 'true'}
                                 ]
                                ),
    Unconditional = kz_doc:setters(kzd_call_forward_types:set_unconditional(kz_json:new(), CallForward)
                                  ,[{fun kzd_call_forward:set_number/2, kz_binary:rand_hex(3)}
                                   ,{fun kzd_call_forward:set_enabled/2, 'false'}
                                   ]
                                  ),
    kzd_users:set_call_forward(User, Unconditional).

%% unconditional is enabled and common is enabled => enabled
call_forwarded_user_2(User) ->
    CallForward = kz_doc:setters(kz_json:new()
                                ,[{fun kzd_call_forward:set_number/2, kz_binary:rand_hex(3)}
                                 ,{fun kzd_call_forward:set_enabled/2, 'true'}
                                 ]
                                ),
    Unconditional = kz_doc:setters(kzd_call_forward_types:set_unconditional(kz_json:new(), CallForward)
                                  ,[{fun kzd_call_forward:set_number/2, kz_binary:rand_hex(3)}
                                   ,{fun kzd_call_forward:set_enabled/2, 'true'}
                                   ]
                                  ),
    kzd_users:set_call_forward(User, Unconditional).

%% unconditional is not enabled but common is enabled => enabled
call_forwarded_user_3(User) ->
    CallForward = kz_doc:setters(kz_json:new()
                                ,[{fun kzd_call_forward:set_number/2, kz_binary:rand_hex(3)}
                                 ,{fun kzd_call_forward:set_enabled/2, 'false'}
                                 ]
                                ),
    Unconditional = kz_doc:setters(kzd_call_forward_types:set_unconditional(kz_json:new(), CallForward)
                                  ,[{fun kzd_call_forward:set_number/2, kz_binary:rand_hex(3)}
                                   ,{fun kzd_call_forward:set_enabled/2, 'true'}
                                   ]
                                  ),
    kzd_users:set_call_forward(User, Unconditional).

%% legacy is settings on root "call_forward" object
legacy_call_forward(User) ->
    CallForward = kz_doc:setters(kz_json:new()
                                ,[{fun kzd_call_forward:set_number/2, kz_binary:rand_hex(3)}
                                 ,{fun kzd_call_forward:set_enabled/2, 'true'}
                                 ]
                                ),
    kzd_users:set_call_forward(User, CallForward).

create_simple_user(API, AccountId) ->
    EmptySummaryResp = pqc_cb_users:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    CreatedUser = create_new_user(API, AccountId),
    UserId = kz_doc:id(CreatedUser),

    UserWithEmail = kzd_users:set_email(CreatedUser, <<(kz_binary:rand_hex(4))/binary, "@2600hz.com">>),
    UpdateResp = pqc_cb_users:update(API, AccountId, UserWithEmail),
    lager:info("updated to ~s", [UpdateResp]),
    'true' = user_docs_match(UserWithEmail, kz_json:get_json_value(<<"data">>, kz_json:decode(UpdateResp))),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchedUser = kz_json:merge(UserWithEmail, Patch),

    PatchResp = pqc_cb_users:patch(API, AccountId, UserId, Patch),
    lager:info("patched to ~s", [PatchResp]),
    'true' = user_docs_match(PatchedUser, kz_json:get_json_value(<<"data">>, kz_json:decode(PatchResp))),

    SummaryResp = pqc_cb_users:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryUser] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    UserId = kz_doc:id(SummaryUser),

    DeleteResp = pqc_cb_users:delete(API, AccountId, UserId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_users:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),
    lager:info("FINISHED SIMPLE USER").

create_new_user(API, AccountId) ->
    create_new_user(API, AccountId, []).

create_new_user(API, AccountId, UserProps) ->
    UserJObj = new_user(kz_json:from_list(UserProps)),
    CreateResp = pqc_cb_users:create(API, AccountId, UserJObj),
    lager:info("created user ~s", [CreateResp]),
    kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)).

wrong_format_check(API, AccountId) ->
    ShortEmail = kzd_users:set_email(new_user(), <<"e">>),
    {'error', ShortEmailError} = pqc_cb_users:create(API, AccountId, ShortEmail),
    lager:info("validation failed creating empty email: ~s", [ShortEmailError]),

    WrongFormat = kzd_users:set_email(new_user(), kz_binary:rand_hex(4)),
    {'error', WrongFormatError} = pqc_cb_users:create(API, AccountId, WrongFormat),
    lager:info("validation failed creating user: ~s", [WrongFormatError]),

    RespEmail = kz_json:get_ne_binary_value([<<"data">>, <<"email">>, <<"wrong_format">>, <<"value">>]
                                           ,kz_json:decode(WrongFormatError)
                                           ),
    'true' = kzd_users:email(WrongFormat) =:= RespEmail,

    lager:info("FINISHED WRONG FORMAT CHECK").

user_docs_match(Model, RespJObj) ->
    kz_json:all(fun({ModelPath, ModelValue}) ->
                        user_setting_matches(ModelPath, ModelValue, RespJObj)
                end
               ,kz_json:flatten(kz_json:delete_key(<<"_read_only">>, Model))
               ).

user_setting_matches(ModelPath, ModelValue, RespJObj) ->
    case kz_json:get_value(ModelPath, RespJObj) of
        ModelValue -> 'true';
        _V ->
            lager:info("key ~s is ~p instead of ~p"
                      ,[kz_binary:join(ModelPath), _V, ModelValue]
                      ),
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
    cleanup_system(API).

cleanup_system() ->
    API = pqc_cb_api:authenticate(),
    cleanup_system(API).

cleanup_system(API) ->
    set_password_expiry(API, 'null'),
    pqc_cb_api:patch_token_costs(API, 0).

-spec create_account(pqc_cb_api:state(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_account(API, AccountName) ->
    AccountJSON = properly_accountant:create_account(API, AccountName),
    lager:info("created account: ~s", [AccountJSON]),
    AccountResp = kz_json:decode(AccountJSON),

    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, AccountResp),

    AccountData = kz_json:get_json_value(<<"metadata">>, AccountResp),
    'true' = kz_json:is_true(<<"enabled">>, AccountData),

    kz_json:get_ne_binary_value(<<"id">>, AccountData).

-spec new_user() -> kzd_users:doc().
new_user() ->
    new_user(kz_json:new()).

-spec new_user(kzd_users:doc()) -> kzd_users:doc().
new_user(UserDoc) ->
    NewUser = kz_json:exec_first([{fun kzd_users:set_first_name/2
                                  ,kzd_users:first_name(UserDoc, kz_binary:rand_hex(4))
                                  }
                                 ,{fun kzd_users:set_last_name/2
                                  ,kzd_users:last_name(UserDoc, kz_binary:rand_hex(4))
                                  }
                                 ,{fun kzd_users:set_username/2
                                  ,kzd_users:username(UserDoc, kz_binary:rand_hex(6))
                                  }
                                 ,{fun kzd_users:set_password/2
                                  ,kzd_users:password(UserDoc, kz_binary:rand_hex(6))
                                  }
                                 ]
                                ,kzd_users:new()
                                ),
    DefaultUser = kz_json_schema:add_defaults(NewUser, kzd_users:schema()),
    kz_doc:public_fields(kz_json:merge(UserDoc, DefaultUser)).

-spec maybe_log_create_entity_resp(atom(), pqc_cb_api:response()) -> 'ok'.
maybe_log_create_entity_resp(DocType, {'error', _}=CreateResp) ->
    lager:info("error in create ~s resp: ~p", [DocType, CreateResp]);
maybe_log_create_entity_resp(_DocType, <<_Ignore/binary>>) ->
    lager:info("created ~s: ~s", [_DocType, _Ignore]).

%% KCRO-150 (some) helpers {
-spec seq_kcro_150_init_state(pqc_cb_api:state()) -> kcro_150_init_state().
seq_kcro_150_init_state(API) ->
    AccountId = create_account(API, ?ACCOUNT_NAME),
    {UserId, _} = create_user(API, AccountId, ?ACCOUNT_NAME, 1),
    Number = <<"4151919191">>,
    CFNumber = add_number(API, AccountId, Number),
    %% Create callflow and set numbers=create_numbers + extension (4 digits) number, just to make
    %% sure it works when there are extension numbers assigned to the same callflow.
    {CallflowId, _} = create_callflow(API, AccountId, UserId, [<<"1001">>, CFNumber]),
    {DeviceId, _} = create_device(API, AccountId, UserId, 1),
    {API
    ,AccountId
    ,UserId
    ,[{<<"phone_numbers">>, Number}
     ,{<<"callflow">>, CallflowId}
     ,{<<"device">>, DeviceId}
     ,{<<"vmbox">>, create_vmbox(API, AccountId, <<"KCRO-150">>, <<"KCRO-150">>, UserId)}
     ,{<<"conference">>, create_conference(API, AccountId, UserId)}
     ,{<<"faxbox">>, create_faxbox(API, AccountId, UserId)}
     ,{<<"media">>, create_media(API, AccountId, <<"KCRO-150">>, <<"recording">>, UserId)}
     ]
    }.

-spec fetch_user_object(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
fetch_user_object(API, AccountId, ObjType, ObjId) ->
    URL = pqc_cb_crud:entity_url(API, AccountId, api_from_obj_type(ObjType), ObjId),
    lager:debug("GET-ing ~s", [URL]),
    pqc_cb_crud:fetch(API, URL, [pqc_cb_expect:code(200), pqc_cb_expect:code(404)]).

-spec api_from_obj_type(kz_term:ne_binary()) -> kz_term:ne_binary().
api_from_obj_type(<<"user">>) -> <<"users">>;
api_from_obj_type(<<"phone_numbers">>) -> <<"phone_numbers">>;
api_from_obj_type(<<"callflow">>) -> <<"callflows">>;
api_from_obj_type(<<"device">>) -> <<"devices">>;
api_from_obj_type(<<"vmbox">>) -> <<"vmboxes">>;
api_from_obj_type(<<"conference">>) -> <<"conferences">>;
api_from_obj_type(<<"faxbox">>) -> <<"faxboxes">>;
api_from_obj_type(<<"media">>) -> <<"media">>.

-spec verify_user_objects(pqc_cb_api:state(), kz_term:ne_binary(), user_objects_proplist(), user_objects_proplist()) ->
          boolean().
verify_user_objects(API, AccountId, Deleted, NonDeleted) ->
    verify_user_objects_do_not_exist(API, AccountId, Deleted)
        andalso verify_user_objects_do_exist(API, AccountId, NonDeleted).

-spec verify_user_objects_do_exist(pqc_cb_api:state(), kz_term:ne_binary(), user_objects_proplist()) ->
          boolean().
verify_user_objects_do_exist(_API, _AccountId, []) ->
    'true'; %% Not objects to verify its existence, so they exist, right (?)
verify_user_objects_do_exist(API, AccountId, [_|_]=ObjsProp) ->
    lager:debug("verifying these objects were NOT deleted: ~p", [ObjsProp]),
    lists:all(fun({ObjType, ObjId}) ->
                      check_success(fetch_user_object(API, AccountId, ObjType, ObjId))
              end
             ,ObjsProp
             ).

-spec verify_user_objects_do_not_exist(pqc_cb_api:state(), kz_term:ne_binary(), user_objects_proplist()) ->
          boolean().
verify_user_objects_do_not_exist(API, AccountId, [_|_]=ObjsProp) ->
    lager:debug("verifying these objects were deleted: ~p", [ObjsProp]),
    %% Conferences API always return 200 OK for every `GET /v2/accounts/{ACCOUNT_ID}/conferences/{CONF_ID}'
    %% requests, even if the conference-id does not exist, in which case it will return an "ad-hoc"
    %% conference object.
    lists:all(fun({<<"conference">>, ConfId}) ->
                      check_not_found(kz_datamgr:open_doc(kzs_util:to_database(AccountId), ConfId));
                 ({ObjType, ObjId}) ->
                      check_not_found(fetch_user_object(API, AccountId, ObjType, ObjId))
              end
             ,ObjsProp
             ).

-spec check_success(kz_term:ne_binary()) -> boolean().
check_success(APIRespBin) ->
    JObj = kz_json:decode(APIRespBin),
    Received = kz_json:get_ne_binary_value(<<"status">>, JObj),
    maybe_log_expected_vs_received(<<"success">>, Received, JObj).

-spec check_not_found({'error', 'not_found'} | kz_term:ne_binary()) -> boolean().
check_not_found({'error', 'not_found'}) ->
    'true';
check_not_found(<<APIRespBin/binary>>) ->
    JObj = kz_json:decode(APIRespBin),
    Received = {kz_json:get_ne_binary_value(<<"status">>, JObj)
               ,kz_json:get_ne_binary_value(<<"error">>, JObj)
               },
    maybe_log_expected_vs_received({<<"error">>, <<"404">>}, Received, JObj).

-spec maybe_log_expected_vs_received({kz_term:ne_binary(), kz_term:ne_binary()} | kz_term:ne_binary()
                                    ,{kz_term:ne_binary(), kz_term:ne_binary()} | kz_term:ne_binary()
                                    ,kz_json:object()
                                    ) -> boolean().
maybe_log_expected_vs_received(Expected, Expected, _JObj) ->
    'true';
maybe_log_expected_vs_received(Expected, Received, JObj) ->
    lager:warning("expected=~p, received=~p from: ~p", [Expected, Received, JObj]),
    'false'.

-spec split_user_objects_filter(object_types()) -> props:filter_fun().
split_user_objects_filter(<<"all">>) ->
    %% Everything should have been deleted.
    fun(_) -> 'true' end;
split_user_objects_filter([]) ->
    %% Only the user should have been deleted.
    fun(_) -> 'false' end;
split_user_objects_filter([_|_]=ObjTypes) ->
    %% Only user + requested object_types should have been deleted.
    fun({K, _V}) -> lists:member(K, ObjTypes) end.

set_password_expiry(API, Value) ->
    CBConfigReset = pqc_cb_system_configs:patch_default_config(API
                                                              ,<<"crossbar">>
                                                              ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"password_expiry_s">>, Value}])}])
                                                              ),
    lager:info("set crossbar config for password expiry to ~p: ~s", [Value, CBConfigReset]),

    Config = kz_json:get_json_value([<<"data">>, <<"default">>], kz_json:decode(CBConfigReset)),
    Value = kz_json:get_value(<<"password_expiry_s">>, Config, 'null').
