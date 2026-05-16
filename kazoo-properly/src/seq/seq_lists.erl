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
-module(seq_lists).

-export([seq/0
        ,seq_lists/0
        ,seq_lists_user_level/0
        ,seq_lists_account_level/0
        ,seq_lists_primary_unique/0
        ,seq_lists_view_results/0
        ,cleanup/0
        ,new_list/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-spec seq() -> 'ok'.
seq() ->
    _ = [seq_lists()
        ,seq_lists_user_level()
        ,seq_lists_account_level()
        ,seq_lists_primary_unique()
        ,seq_lists_view_results()
        ],
    'ok'.

-spec seq_lists() -> 'ok'.
seq_lists() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_lists']),
    AccountId = create_account(API, hd(?ACCOUNT_NAMES)),

    EmptySummaryResp = pqc_cb_lists:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    ListJObj = new_list(),
    CreateResp = pqc_cb_lists:create(API, AccountId, ListJObj),
    lager:info("created list ~s", [CreateResp]),
    CreatedList = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    ListId = kz_doc:id(CreatedList),

    UserId = create_user(API, AccountId),
    ListOwnerIdJObj = new_list(),
    CreateRespOwnerId = pqc_cb_lists:create(API, AccountId, UserId, ListOwnerIdJObj),
    lager:info("created list ~s with owner_id", [CreateRespOwnerId]),
    CreatedListOwnerId = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateRespOwnerId)),
    ListIdOwnerId = kz_doc:id(CreatedListOwnerId),

    Summary = pqc_cb_lists:summary(API, AccountId),
    lager:info("summary: ~s", [Summary]),
    [Data] = kz_json:get_list_value(<<"data">>, kz_json:decode(Summary)),
    ListId = kz_doc:id(Data),

    Fetch = pqc_cb_lists:fetch(API, AccountId, ListId),
    lager:info("fetch: ~s", [Fetch]),
    FetchedData = kz_json:get_json_value(<<"data">>, kz_json:decode(Fetch)),
    ListId = kz_doc:id(FetchedData),

    Tag = <<"properly">>,
    ListWithTagJObj = new_list_with_tags([Tag]),
    CreateRespTag = pqc_cb_lists:create(API, AccountId, ListWithTagJObj),
    lager:info("created list with tag ~s", [CreateRespTag]),
    CreatedListTag = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateRespTag)),
    ListIdTag = kz_doc:id(CreatedListTag),

    SummaryByTag = pqc_cb_lists:summary_by_tag(API, AccountId, Tag),
    lager:info("summary by tag ~s resp: ~s", [Tag, SummaryByTag]),
    [DataPerTag] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryByTag)),
    ListIdTag = kz_doc:id(DataPerTag),

    SummaryByUser = pqc_cb_lists:summary(API, AccountId, UserId),
    lager:info("summary by user: ~s", [SummaryByUser]),
    _DataPerUser = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryByUser)),

    FetchByUser = pqc_cb_lists:fetch(API, AccountId, UserId, ListIdOwnerId),
    lager:info("fetch by user: ~s", [FetchByUser]),
    FetchedDataByUser = kz_json:get_json_value(<<"data">>, kz_json:decode(FetchByUser)),
    ListIdOwnerId = kz_doc:id(FetchedDataByUser),

    Patch = kz_json:from_list([{<<"favorite">>, 'true'}]),

    PatchByUser = pqc_cb_lists:patch(API, AccountId, UserId, ListIdOwnerId, Patch),
    lager:info("patched by user: ~s", [PatchByUser]),
    PatchedData = kz_json:get_json_value(<<"data">>, kz_json:decode(PatchByUser)),
    ListIdOwnerId = kz_doc:id(PatchedData),

    {'error', PatchByWrongUser} = pqc_cb_lists:patch(API, AccountId, UserId, ListId, Patch),
    lager:info("patch by wrong user: ~s", [PatchByWrongUser]),
    400 = kz_json:get_integer_value(<<"error">>, kz_json:decode(PatchByWrongUser)),

    DeleteTagResp = pqc_cb_lists:delete(API, AccountId, ListIdTag),
    lager:info("delete tag resp: ~s", [DeleteTagResp]),

    {'error', DeleteByWrongUser} = pqc_cb_lists:delete(API, AccountId, UserId, ListId),
    lager:info("delete by wrong user: ~s", [DeleteByWrongUser]),
    400 = kz_json:get_integer_value(<<"error">>, kz_json:decode(DeleteByWrongUser)),

    DeleteResp = pqc_cb_lists:delete(API, AccountId, ListId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_lists:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    DeleteUserResp = pqc_cb_lists:delete(API, AccountId, UserId, ListIdOwnerId),
    lager:info("delete by user resp: ~s", [DeleteUserResp]),

    EmptyUserAgain = pqc_cb_lists:summary(API, AccountId, UserId),
    lager:info("empty user summary resp: ~s", [EmptyUserAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyUserAgain)),

    cleanup(API, AccountId),
    lager:info("FINISHED LIST SEQ").

-spec seq_lists_user_level() -> 'ok'.
seq_lists_user_level() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_lists']),
    AccountName = hd(?ACCOUNT_NAMES),
    AccountId = create_account(API, AccountName),

    UserId = create_user(API, AccountId),
    Username = kz_binary:rand_hex(4),
    Password = kz_binary:rand_hex(4),
    AuthUserId = create_user(API, AccountId, Username, Password),
    AuthAPI = pqc_cb_api:authenticate(AccountName, Username, Password),

    {'error', EmptySummaryRespWithAuth} = pqc_cb_lists:summary(AuthAPI, AccountId, UserId),
    lager:info("empty summary resp for wrong user: ~s", [EmptySummaryRespWithAuth]),
    403 = kz_json:get_integer_value(<<"error">>, kz_json:decode(EmptySummaryRespWithAuth)),

    EmptySummaryResp = pqc_cb_lists:summary(AuthAPI, AccountId, AuthUserId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    Tag = <<"properly">>,
    ListWithTagJObj = new_list_with_tags([Tag]),

    {'error', CreateRespTagWithAuth} = pqc_cb_lists:create(AuthAPI, AccountId, UserId, ListWithTagJObj),
    lager:info("try to create list with tag for wrong user ~s", [CreateRespTagWithAuth]),
    403 = kz_json:get_integer_value(<<"error">>, kz_json:decode(CreateRespTagWithAuth)),

    CreateRespTag = pqc_cb_lists:create(AuthAPI, AccountId, AuthUserId, ListWithTagJObj),
    lager:info("created list with tag ~s", [CreateRespTag]),
    CreatedListTag = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateRespTag)),
    ListId = kz_doc:id(CreatedListTag),

    SummaryByTag = pqc_cb_lists:summary_by_tag(AuthAPI, AccountId, AuthUserId, Tag),
    lager:info("summary by tag ~s resp: ~s", [Tag, SummaryByTag]),
    [DataPerTag] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryByTag)),
    ListId = kz_doc:id(DataPerTag),

    Patch = kz_json:from_list([{<<"favorite">>, 'true'}]),

    {'error', PatchByWrongUser} = pqc_cb_lists:patch(AuthAPI, AccountId, UserId, ListId, Patch),
    lager:info("patch by wrong user: ~s", [PatchByWrongUser]),
    403 = kz_json:get_integer_value(<<"error">>, kz_json:decode(PatchByWrongUser)),

    PatchByUser = pqc_cb_lists:patch(AuthAPI, AccountId, AuthUserId, ListId, Patch),
    lager:info("patched by user: ~s", [PatchByUser]),
    PatchedData = kz_json:get_json_value(<<"data">>, kz_json:decode(PatchByUser)),
    ListId = kz_doc:id(PatchedData),

    {'error', DeleteByWrongUser} = pqc_cb_lists:delete(AuthAPI, AccountId, UserId, ListId),
    lager:info("delete by wrong user: ~s", [DeleteByWrongUser]),
    403 = kz_json:get_integer_value(<<"error">>, kz_json:decode(DeleteByWrongUser)),

    DeleteResp = pqc_cb_lists:delete(AuthAPI, AccountId, AuthUserId, ListId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_lists:summary(AuthAPI, AccountId, AuthUserId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API, AccountId),
    lager:info("FINISHED USER LEVEL LIST SEQ").

-spec seq_lists_account_level() -> 'ok'.
seq_lists_account_level() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_lists']),
    AccountName = hd(?ACCOUNT_NAMES),
    AccountId = create_account(API, AccountName),

    Username = kz_binary:rand_hex(4),
    Password = kz_binary:rand_hex(4),
    _AuthUserId = create_user(API, AccountId, Username, Password),
    AuthAPI = pqc_cb_api:authenticate(AccountName, Username, Password),

    EmptySummaryResp = pqc_cb_lists:summary(AuthAPI, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    ListJObj = new_list(),

    {'error', CreateRespUser} = pqc_cb_lists:create(AuthAPI, AccountId, ListJObj),
    lager:info("try to create list with user  ~s", [CreateRespUser]),
    403 = kz_json:get_integer_value(<<"error">>, kz_json:decode(CreateRespUser)),

    CreateResp = pqc_cb_lists:create(API, AccountId, ListJObj),
    lager:info("created list  ~s", [CreateResp]),
    CreatedList = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    ListId = kz_doc:id(CreatedList),

    Summary = pqc_cb_lists:summary(AuthAPI, AccountId),
    lager:info("summary resp: ~s", [Summary]),
    [Data] = kz_json:get_list_value(<<"data">>, kz_json:decode(Summary)),
    ListId = kz_doc:id(Data),

    Patch = kz_json:from_list([{<<"favorite">>, 'true'}]),

    {'error', PatchRespUser} = pqc_cb_lists:patch(AuthAPI, AccountId, ListId, Patch),
    lager:info("patch with user: ~s", [PatchRespUser]),
    403 = kz_json:get_integer_value(<<"error">>, kz_json:decode(PatchRespUser)),

    PatchResp = pqc_cb_lists:patch(API, AccountId, ListId, Patch),
    lager:info("patched resp: ~s", [PatchResp]),
    PatchedData = kz_json:get_json_value(<<"data">>, kz_json:decode(PatchResp)),
    ListId = kz_doc:id(PatchedData),

    {'error', DeleteRespUser} = pqc_cb_lists:delete(AuthAPI, AccountId, ListId),
    lager:info("delete with user: ~s", [DeleteRespUser]),
    403 = kz_json:get_integer_value(<<"error">>, kz_json:decode(DeleteRespUser)),

    DeleteResp = pqc_cb_lists:delete(API, AccountId, ListId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_lists:summary(AuthAPI, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API, AccountId),
    lager:info("FINISHED ACCOUNT LEVEL LIST SEQ").

-spec seq_lists_primary_unique() -> 'ok'.
seq_lists_primary_unique() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_lists']),
    AccountId = create_account(API, hd(?ACCOUNT_NAMES)),

    Contacts = create_duplicate_primary_contact(),
    ListJObj = new_list(Contacts),
    {'error', CreateFailedResp} = pqc_cb_lists:create(API, AccountId, ListJObj),
    lager:info("creating list resp ~s", [CreateFailedResp]),
    400 = kz_json:get_integer_value(<<"error">>, kz_json:decode(CreateFailedResp)),

    NewListJObj = new_list(),
    CreateResp = pqc_cb_lists:create(API, AccountId, NewListJObj),
    lager:info("created list  ~s", [CreateResp]),
    CreatedList = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    ListId = kz_doc:id(CreatedList),

    Patch = kz_json:from_list([{<<"contacts">>, Contacts}]),
    {'error', PatchResp} = pqc_cb_lists:patch(API, AccountId, ListId, Patch),
    lager:info("patch resp: ~s", [PatchResp]),
    400 = kz_json:get_integer_value(<<"error">>, kz_json:decode(PatchResp)),

    UpdateJObj = kzd_contacts:set_contacts(CreatedList, Contacts),
    {'error', UpdateResp} = pqc_cb_lists:update(API, AccountId, UpdateJObj),
    lager:info("update resp: ~s", [UpdateResp]),
    400 = kz_json:get_integer_value(<<"error">>, kz_json:decode(UpdateResp)),

    cleanup(API, AccountId),
    lager:info("FINISHED LIST SEQ").

-spec seq_lists_view_results() -> 'ok'.
seq_lists_view_results() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_lists']),
    AccountId = create_account(API, hd(?ACCOUNT_NAMES)),

    EmptySummaryResp = pqc_cb_lists:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    ListJObj = new_list(sample_contact()),
    CreateResp = pqc_cb_lists:create(API, AccountId, ListJObj),
    lager:info("created list ~s", [CreateResp]),
    CreatedList = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    _ListId = kz_doc:id(CreatedList),

    SummaryResp = pqc_cb_lists:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [Data] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),

    ActualResult = kzd_contacts:contacts(Data),
    ExpectedResult = sample_result(),
    ExpectedResult = ActualResult,

    cleanup(API, AccountId),
    lager:info("FINISHED LIST SEQ").

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = properly_maintenance:cleanup_module_accounts(?MODULE),
    cleanup_system().

cleanup(API, AccountId) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, [AccountId]),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.

-spec create_account(pqc_cb_api:state(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_account(API, AccountName) ->
    AccountResp = properly_accountant:create_account(API, AccountName),
    lager:info("created account: ~s", [AccountResp]),
    kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)).

-spec new_list() -> kzd_contacts:doc().
new_list() ->
    new_list(create_contact()).

-spec new_list(kz_term:api_ne_objects()) -> kzd_contacts:doc().
new_list(Contacts) ->
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_contacts:set_first_name/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_contacts:set_contacts/2, Contacts}
                         ]
                        ,kzd_contacts:new()
                        )
     ).

-spec new_list_with_tags(kz_term:ne_binaries()) -> kzd_contacts:doc().
new_list_with_tags(Tags) ->
    new_list_with_tags(Tags, create_contact()).

-spec new_list_with_tags(kz_term:ne_binaries(), kz_term:api_ne_objects()) -> kzd_contacts:doc().
new_list_with_tags(Tags, Contacts) ->
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_contacts:set_first_name/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_contacts:set_contacts/2, Contacts}
                         ,{fun kzd_contacts:set_tags/2, Tags}
                         ]
                        ,kzd_contacts:new()
                        )
     ).

-spec create_contact() -> kz_term:api_ne_objects().
create_contact() ->
    Voice = kz_json:from_list([{<<"type">>, <<"voice">>}
                              ,{<<"contact">>, kz_binary:rand_hex(8)}
                              ,{<<"primary">>, 'true'}
                              ]),
    Email = kz_json:from_list([{<<"type">>, <<"email">>}
                              ,{<<"contact">>, kz_binary:rand_hex(8)}
                              ,{<<"primary">>, 'true'}
                              ]),
    Sms = kz_json:from_list([{<<"type">>, <<"sms">>}
                            ,{<<"contact">>, kz_binary:rand_hex(8)}
                            ,{<<"primary">>, 'true'}
                            ]),
    [Voice, Email, Sms].

-spec create_duplicate_primary_contact() -> kz_term:api_ne_objects().
create_duplicate_primary_contact() ->
    Voice = kz_json:from_list([{<<"type">>, <<"voice">>}
                              ,{<<"contact">>, kz_binary:rand_hex(8)}
                              ,{<<"primary">>, 'true'}
                              ]),
    Email1 = kz_json:from_list([{<<"type">>, <<"email">>}
                               ,{<<"contact">>, kz_binary:rand_hex(8)}
                               ,{<<"primary">>, 'true'}
                               ]),
    Email2 = kz_json:from_list([{<<"type">>, <<"email">>}
                               ,{<<"contact">>, kz_binary:rand_hex(8)}
                               ,{<<"primary">>, 'true'}
                               ]),
    Sms = kz_json:from_list([{<<"type">>, <<"sms">>}
                            ,{<<"contact">>, kz_binary:rand_hex(8)}
                            ,{<<"primary">>, 'true'}
                            ]),
    [Voice, Email1, Email2, Sms].

-spec sample_contact() -> kz_term:api_ne_objects().
sample_contact() ->
    Voice1 = kz_json:from_list([{<<"type">>, <<"voice">>}
                               ,{<<"contact">>, <<"4156546297">>}
                               ,{<<"primary">>, 'false'}
                               ,{<<"device_type">>, <<"mobile">>}
                               ]),
    Voice2 = kz_json:from_list([{<<"type">>, <<"voice">>}
                               ,{<<"contact">>, <<"4158867903">>}
                               ,{<<"primary">>, 'true'}
                               ,{<<"device_type">>, <<"work">>}
                               ]),
    Email1 = kz_json:from_list([{<<"type">>, <<"email">>}
                               ,{<<"contact">>, <<"bitbashing@gmail.com">>}
                               ,{<<"primary">>, 'false'}
                               ,{<<"email_type">>, <<"home">>}
                               ]),
    Email2 = kz_json:from_list([{<<"type">>, <<"email">>}
                               ,{<<"contact">>, <<"karl@2600hz.com">>}
                               ,{<<"primary">>, 'false'}
                               ,{<<"email_type">>, <<"work">>}
                               ]),
    Email3 = kz_json:from_list([{<<"type">>, <<"email">>}
                               ,{<<"contact">>, <<"karl.anderson@ooma.com">>}
                               ,{<<"primary">>, 'true'}
                               ,{<<"email_type">>, <<"work">>}
                               ]),
    [Voice1, Voice2, Email1, Email2, Email3].

-spec sample_result() -> kz_term:api_ne_objects().
sample_result() ->
    Voice = kz_json:from_list([{<<"voice">>, <<"4158867903">>}]),
    Email = kz_json:from_list([{<<"email">>, <<"karl.anderson@ooma.com">>}]),
    [Voice, Email].

-spec create_user(pqc_cb_api:state(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_user(API, AccountId) ->
    create_user(API, AccountId, kz_binary:rand_hex(4), kz_binary:rand_hex(4)).

-spec create_user(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          kz_term:ne_binary().
create_user(API, AccountId, Username, Password) ->
    User = new_user(Username, Password),
    Resp = pqc_cb_users:create(API, AccountId, User),
    lager:info("created user: ~s", [Resp]),
    <<_/binary>> = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(Resp)).

-spec new_user(kz_term:ne_binary(), kz_term:ne_binary()) -> kzd_users:doc().
new_user(Username, Password) ->
    new_user(Username, Password, kz_json:new()).

-spec new_user(kz_term:ne_binary(), kz_term:ne_binary(), kzd_users:doc()) -> kzd_users:doc().
new_user(Username, Password, UserDoc) ->
    DefaultUser = kz_json_schema:add_defaults(kzd_users:new(), kzd_users:schema()),
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_users:set_first_name/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_users:set_last_name/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_users:set_username/2, Username}
                         ,{fun kzd_users:set_password/2, Password}
                         ]
                        ,kz_json:merge(UserDoc, DefaultUser)
                        )
     ).
