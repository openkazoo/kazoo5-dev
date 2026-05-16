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
-module(seq_accounts).

-export([cleanup/0, cleanup_accounts/1, cleanup_accounts/2
        ,check_accounts_db/1

         %% kapps_maintenance:check_release callback
        ,seq/0
        ,seq_enable_and_delete_topup/0
        ,seq_enable_and_disable_account_using_patch/0
        ,seq_44832/0
        ,seq_kzoo_54/0
        ,seq_kzoo_61/0
        ,seq_supp_16/0
        ,seq_kcro_92/0
        ,seq_kzoo_222/0
        ,seq_api_key/0
        ,seq_kcro_176/0
        ,seq_kzoo_376/0
        ,seq_move/0

        ,pick_tz/0
        ,create_account_tree/2
        ,sub_account_names/1
        ]).

-include("properly.hrl").
-include_lib("qdate_localtime/include/tz_database.hrl").

-properly({'standalone', [seq_supp_16/0
                         ,seq_kzoo_222/0
                         ,seq_move/0
                         ]}).

-export_type([account_id/0]).

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-define(SUPP_16_COUNT, 5).
-define(KZOO_222_COUNT, 2).

-type account_id() :: {'call', 'pqc_kazoo_model', 'account_id_by_name', [pqc_cb_api:state() | proper_types:type()]} |
                      kz_term:ne_binary().

-spec cleanup_accounts(kz_term:ne_binaries()) -> 'ok'.
cleanup_accounts(AccountNames) ->
    cleanup_accounts(pqc_cb_api:authenticate(), AccountNames).

-spec cleanup_accounts(pqc_cb_api:state(), kz_term:ne_binaries() | kz_term:atoms()) -> 'ok'.
cleanup_accounts(API, AccountNames) ->
    lager:info("cleaning up accounts ~p", [AccountNames]),
    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"tasks">>
                                                  ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"soft_delete_pause_ms">>, 100}])}])
                                                  ),
    _ = [cleanup_account(API, AccountName) || AccountName <- AccountNames],
    kt_cleanup:cleanup_soft_deletes(?KZ_ACCOUNTS_DB).

-spec cleanup_account(pqc_cb_api:state(), kz_term:ne_binary() | atom()) -> 'ok'.
cleanup_account(API, <<"seq_", _/binary>>=AccountName) ->
    cleanup_by_name(API, AccountName);
cleanup_account(API, <<AccountId:32/binary>>) ->
    lager:info("trying to delete account by id ~s", [AccountId]),
    case pqc_cb_accounts:delete(API, AccountId) of
        {'error', ErrorResp} ->
            lager:info("error deleting ~s: ~s", [AccountId, ErrorResp]);
        DeleteResp ->
            lager:info("delete resp: ~s", [DeleteResp])
    end,
    _ = check_accounts_db(AccountId),
    timer:sleep(150);
cleanup_account(API, <<AccountName/binary>>) ->
    cleanup_by_name(API, AccountName);
cleanup_account(API, AccountName) ->
    cleanup_account(API, kz_term:to_binary(AccountName)).

cleanup_by_name(API, AccountName) ->
    _Attempt = try pqc_cb_search:search_account_by_name(API, AccountName) of
                   ?FAILED_RESPONSE ->
                       lager:info("failed to search for account by name ~s~n", [AccountName]),
                       check_accounts_db(AccountName);
                   APIResp ->
                       Data = pqc_cb_response:data(APIResp),
                       lager:info("found account '~s' to cleanup: ~p", [AccountName, Data]),
                       _ = case kz_json:get_ne_binary_value([1, <<"id">>], Data) of
                               'undefined' -> 'ok';
                               AccountId -> pqc_cb_accounts:delete(API, AccountId)
                           end,
                       timer:sleep(50),
                       check_accounts_db(AccountName)
               catch
                   'throw':{'error', 'socket_closed_remotely'} ->
                       ?ERROR("broke the SUT cleaning up account ~s (~p)~n", [AccountName, API])
               end,
    timer:sleep(150). % was needed to stop overwhelming the socket, at least locally

-spec check_accounts_db(kz_term:ne_binary()) -> any().
check_accounts_db(<<Id:32/binary>>) ->
    case kz_datamgr:open_cache_doc(?KZ_ACCOUNTS_DB, Id) of
        {'ok', JObj} -> kz_datamgr:del_doc(?KZ_ACCOUNTS_DB, JObj);
        {'error', 'not_found'} -> 'ok'
    end;
check_accounts_db(Name) ->
    AccountName = kzd_accounts:normalize_name(Name),
    ViewOptions = [{'key', AccountName}],
    case kz_datamgr:get_results(?KZ_ACCOUNTS_DB, <<"accounts/listing_by_name">>, ViewOptions) of
        {'ok', []} -> 'ok';
        {'error', _E} -> ?ERROR("failed to list by name: ~p", [_E]);
        {'ok', JObjs} ->
            lager:info("deleting from ~s: ~p~n", [?KZ_ACCOUNTS_DB, JObjs]),
            kz_datamgr:del_docs(?KZ_ACCOUNTS_DB, JObjs)
    end.

-spec seq() -> 'ok'.
seq() ->
    lists:foreach(fun exec_seq/1
                 ,[fun seq_enable_and_delete_topup/0
                  ,fun seq_enable_and_disable_account_using_patch/0
                  ,fun seq_44832/0
                  ,fun seq_kzoo_54/0
                  ,fun seq_kzoo_61/0
                  ,fun seq_supp_16/0
                  ,fun seq_kcro_92/0
                  ,fun seq_kzoo_222/0
                  ,fun seq_api_key/0
                  ,fun seq_kcro_176/0
                  ,fun seq_kzoo_376/0
                  ,fun seq_move/0
                  ]).

exec_seq(F) -> F().

-spec seq_44832() -> 'ok'.
seq_44832() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account ~s", [AccountResp]),

    AccountJObj = kz_json:get_value(<<"data">>, kz_json:decode(AccountResp)),
    AccountId = kz_json:get_binary_value(<<"id">>, AccountJObj),

    RequestData = kz_json:set_value(<<"enabled">>, 'false', AccountJObj),

    lists:foreach(fun(N) ->
                          %% This will crash if we get back the 409 error, which is not expected
                          lager:info("updating ~s for the ~p time", [AccountId, N]),
                          <<_Update/binary>> = pqc_cb_accounts:update(API, AccountId, RequestData),
                          lager:info("update for ~s on the ~p time results in revision ~s"
                                    ,[AccountId, N, kz_json:get_value(<<"revision">>, kz_json:decode(_Update))]
                                    ),
                          timer:sleep(60)
                  end
                 ,lists:seq(1, 4)
                 ),

    _ = cleanup(API, [AccountId]),
    lager:info("finished double-POST check").

-spec seq_kzoo_54() -> 'ok'.
seq_kzoo_54() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),

    RealmSuffix = kz_term:to_binary(kz_network_utils:get_hostname()),
    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"crossbar.accounts">>
                                                  ,kz_json:from_list([{<<"default">>
                                                                      ,kz_json:from_list([{<<"account_realm_suffix">>, RealmSuffix}])
                                                                      }])
                                                  ),

    AccountName = ?ACCOUNT_NAME,
    AccountReq = kz_json:from_list([{<<"name">>, AccountName}
                                   ,{<<"realm">>, AccountName}
                                   ]
                                  ),

    CustomAccountResp = properly_accountant:create_account(API, AccountReq),
    lager:info("created custom account ~s", [CustomAccountResp]),

    RespJObj = kz_json:decode(CustomAccountResp),
    CustomAccountJObj = kz_json:get_value(<<"data">>, RespJObj),
    CustomAccountId = kz_doc:id(kz_json:get_json_value(<<"metadata">>, RespJObj)),
    AccountName = kzd_accounts:name(CustomAccountJObj),
    AccountName = kzd_accounts:realm(CustomAccountJObj),

    CustomDeleteResp = pqc_cb_accounts:delete(API, CustomAccountId),
    lager:info("deleted custom account ~s", [CustomDeleteResp]),
    CustomAccountId = kz_doc:id(kz_json:get_value(<<"data">>, kz_json:decode(CustomDeleteResp))),

    DefaultCreateResp = properly_accountant:create_account(API, AccountName),
    lager:info("created default account ~s", [DefaultCreateResp]),

    DefaultAccountJObj = kz_json:get_value(<<"data">>, kz_json:decode(DefaultCreateResp)),
    DefaultAccountId = kz_doc:id(DefaultAccountJObj),
    AccountName = kzd_accounts:name(DefaultAccountJObj),
    lager:info("realm ~s is suffixed by ~s", [kzd_accounts:realm(DefaultAccountJObj), RealmSuffix]),
    {_, _} = binary:match(kzd_accounts:realm(DefaultAccountJObj), RealmSuffix),

    DefaultDeleteResp = pqc_cb_accounts:delete(API, DefaultAccountId),
    DefaultAccountId = kz_doc:id(kz_json:get_value(<<"data">>, kz_json:decode(DefaultDeleteResp))),

    _ = cleanup(API, [DefaultAccountId]),
    lager:info("finished name/realm checks").

-spec seq_enable_and_delete_topup() -> 'ok'.
seq_enable_and_delete_topup() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account: ~s", [AccountResp]),

    AccountJObj = kz_json:get_value(<<"data">>, kz_json:decode(AccountResp)),
    AccountId = kz_json:get_binary_value(<<"id">>, AccountJObj),
    TopupConfig = kz_json:from_list([{<<"threshold">>,10},{<<"amount">>,50}]),
    RequestData = kz_json:set_value(<<"topup">>, TopupConfig, AccountJObj),
    RequestEnvelope = pqc_cb_api:create_envelope(RequestData),

    Resp = topup_request(API, AccountId, RequestEnvelope),
    lager:info("enable topup resp: ~s", [Resp]),

    RespJObj = pqc_cb_response:data(Resp),
    'true' = kz_json:are_equal(TopupConfig, kz_json:get_ne_value(<<"topup">>, RespJObj)),
    RequestData1 = kz_json:delete_key(<<"topup">>, RespJObj),
    RequestEnvelope1 = pqc_cb_api:create_envelope(RequestData1),

    Resp1 = topup_request(API, AccountId, RequestEnvelope1),
    lager:info("disable topup resp: ~s", [Resp1]),

    'undefined' = kz_json:get_ne_value(<<"topup">>, kz_json:decode(Resp1)),

    _ = cleanup(API, [AccountId]),
    lager:info("FINISHED ENABLE_AND_DISABLE_TOPUP TEST").

-spec seq_enable_and_disable_account_using_patch() -> 'ok'.
seq_enable_and_disable_account_using_patch() ->
    lager:info("STARTING ENABLE_AND_DISABLE_ACCOUNT_USING_PATCH TEST"),
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account: ~s", [AccountResp]),

    AccountId = kz_json:get_binary_value(<<"id">>, pqc_cb_response:data(AccountResp)),

    Fetched = pqc_cb_response:data(pqc_cb_accounts:fetch(API, AccountId)),
    'true' = kz_json:is_true(<<"enabled">>, Fetched, 'true'),

    lager:info("disabling account"),
    ReqJObj = kz_json:from_list([{<<"enabled">>, 'false'}]),
    Disabled = pqc_cb_response:metadata(pqc_cb_accounts:patch(API, AccountId, ReqJObj)),
    'false' = kz_json:is_true(<<"enabled">>, Disabled, 'true'),

    lager:info("patching something else"),
    ReqJObj2 = kz_json:from_list([{<<"entitlements">>, 'null'}]),
    StillDisabled = pqc_cb_response:metadata(pqc_cb_accounts:patch(API, AccountId, ReqJObj2)),
    'false' = kz_json:is_true(<<"enabled">>, StillDisabled, 'true'),

    lager:info("enabling account"),
    ReqJObj1 = kz_json:from_list([{<<"enabled">>, 'true'}]),
    Enabled = pqc_cb_response:metadata(pqc_cb_accounts:patch(API, AccountId, ReqJObj1)),
    'true' = kz_json:is_true(<<"enabled">>, Enabled, 'true'),

    _ = cleanup(API, [AccountId]),
    lager:info("FINISHED ENABLE_AND_DISABLE_ACCOUNT_USING_PATCH TEST").

-spec seq_kzoo_61() -> 'ok'.
seq_kzoo_61() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),

    AccountReq = kz_json:from_list([{<<"name">>, ?ACCOUNT_NAME}
                                   ,{<<"realm">>, ?ACCOUNT_NAME}
                                   ]
                                  ),
    AccountResp = properly_accountant:create_account(API, AccountReq),
    lager:info("created account ~s", [AccountResp]),
    RespData = kz_json:decode(AccountResp),
    AccountId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], RespData),

    {'ok', AccountSchema} = kz_json_schema:load(<<"accounts">>),
    Required = [[<<"data">>, R]
                || R <- kz_json:get_list_value(<<"required">>, AccountSchema, [])
               ],

    Fields = [[<<"metadata">>, <<"billing_mode">>]
             ,{[<<"metadata">>, <<"created">>], fun erlang:is_integer/1}
             ,{[<<"metadata">>, <<"enabled">>], 'true'}
             ,{[<<"metadata">>, <<"is_reseller">>], fun kz_term:is_boolean/1}
             ,{[<<"data">>, <<"realm">>], ?ACCOUNT_NAME}
             ,{[<<"metadata">>, <<"reseller_id">>], pqc_cb_api:auth_account_id(API)}
             ,{[<<"metadata">>, <<"superduper_admin">>], 'false'}
             ,{[<<"metadata">>, <<"wnm_allow_additions">>], fun kz_term:is_boolean/1}
             | Required
             ],
    'true' = lists:all(fun(Field) -> response_has_field(Field, RespData) end
                      ,Fields
                      ),

    _ = cleanup(API, [AccountId]),
    lager:info("FINISHED EXPECTED FIELDS").

%% @doc Test that bad timezones are rejected
-spec seq_kcro_92() -> 'ok'.
seq_kcro_92() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account ~s", [AccountResp]),

    AccountJObj = kz_json:get_value(<<"data">>, kz_json:decode(AccountResp)),
    AccountId = kz_json:get_binary_value(<<"id">>, AccountJObj),

    PatchJObj = kzd_accounts:set_timezone(kz_json:new(), <<"Mars/Tséyi'">>),
    {'error', ErrorResp} = pqc_cb_accounts:patch(API, AccountId, PatchJObj),
    lager:info("invalid tz: ~s", [ErrorResp]),

    TZ = pick_tz(),
    TZJObj = kzd_accounts:set_timezone(kz_json:new(), TZ),
    PatchResp = pqc_cb_accounts:patch(API, AccountId, TZJObj),
    lager:info("valid tz: ~s", [PatchResp]),

    AccountDoc = kz_json:get_json_value(<<"data">>, kz_json:decode(PatchResp)),
    TZ = kzd_accounts:timezone(AccountDoc),

    _ = cleanup(API, [AccountId]),
    lager:info("FINISHED TIMEZONE").

-spec pick_tz() -> kz_term:ne_binary().
pick_tz() ->
    pick_tz_nth(?tz_database).

%% @doc tested a variety of ways to choose a random element
%% - using hd(kz_term:shuffle_list(TZDB)): upwards of 6ms
%% - using rand:uniform() > 0.5 to pop elements off the TZDB: dozen microseconds but hard to get out of Africa TZs
%% - using lists:nth as below: under 20 microseconds, better distribution
pick_tz_nth(TZDatabase) ->
    Rand = rand:uniform(length(TZDatabase)),
    {TZStr,_,_,_,_,_,_,_,_} = lists:nth(Rand, TZDatabase),
    kz_term:to_binary(TZStr).

%% @doc Tests account API's parents vs tree path
-spec seq_supp_16() -> 'ok'.
seq_supp_16() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),

    AccountIds = create_account_tree(API, ?SUPP_16_COUNT),
    lager:info("created accounts: ~p", [AccountIds]),

    _ = verify_account_trees(API, AccountIds),

    _ = cleanup(API, [Id || {_Name, Id} <- lists:reverse(AccountIds)]),
    lager:info("FINISHED TREE").

verify_account_trees(#{account_id:=MasterAccountId}=API, AccountIds) ->
    %% account ids is built in reverse order, so descendant to ancestor, leaf to root
    verify_account_trees(API, AccountIds, tl(AccountIds ++ [{0, MasterAccountId}])).

verify_account_trees(API, AccountIds, Acc0) ->
    _ = lists:foldl(fun(AccountId, Acc) -> tree_and_parents(API, AccountId, Acc) end
                   ,Acc0
                   ,AccountIds
                   ),
    lager:info("account trees verified").

tree_and_parents(API, {Name, AccountId}, AccountIds) ->
    TreeResp = pqc_cb_accounts:tree(API, AccountId),
    lager:info("~s tree resp: ~s", [Name, TreeResp]),
    TreeListing = kz_json:get_list_value(<<"data">>, kz_json:decode(TreeResp)),
    validate_ancestors(AccountIds, TreeListing),
    lager:info("all ancestors in tree response"),

    ParentsResp = pqc_cb_accounts:parents(API, AccountId),
    lager:info("~s parents resp: ~s", [Name, ParentsResp]),
    ParentsListing = kz_json:get_list_value(<<"data">>, kz_json:decode(ParentsResp)),
    validate_ancestors(AccountIds, ParentsListing),
    lager:info("all ancestors in parents response"),

    tl(AccountIds). % pop off descendant so just ancestors are considered

%% Listing = [{'id':'{ID}','name':'{NAME}'},...] from root to leaf
%% AccountIds = [{Name, AccountId},...], from leaf to root
validate_ancestors(AccountIds, Listing) ->
    TopFirst = lists:reverse(AccountIds),
    validate_ancestors1(TopFirst, Listing).

validate_ancestors1([], []) -> 'ok';
validate_ancestors1([{_Name, AccountId} | AccountIds]
                   ,[AccountSummary | Listing]
                   ) ->
    AccountId = kz_doc:id(AccountSummary),
    validate_ancestors1(AccountIds, Listing).

-spec create_account_tree(pqc_cb_api:state(), pos_integer()) ->
          [{[char()], kz_term:ne_binary()}].
create_account_tree(API, Count) ->
    lists:foldl(fun(C, Acc) -> create_account_tree(API, C, Acc) end
               ,[]
               ,sub_account_names(Count)
               ).

create_account_tree(#{account_id:=ParentAccountId}=API, Name, []) ->
    AccountId = create_sub_account(API, Name, ParentAccountId),
    [{Name, AccountId}];
create_account_tree(API, Name, [{_, ParentAccountId}|_]=Acc) ->
    AccountId = create_sub_account(API, Name, ParentAccountId),
    [{Name, AccountId} | Acc].

create_sub_account(API, Name, ParentAccountId) ->
    AccountReq = kz_json:from_list([{<<"name">>, Name}
                                   ,{<<"realm">>, Name}
                                   ]
                                  ),
    AccountResp = properly_accountant:create_account(API, AccountReq, ParentAccountId),

    lager:info("created child account ~s of ~s: ~s", [Name, ParentAccountId, AccountResp]),
    Resp = kz_json:decode(AccountResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, Resp),
    kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], Resp).

response_has_field({Field, Predicate}, AccountJObj) when is_function(Predicate, 1) ->
    response_had_field(Field, Predicate(kz_json:get_value(Field, AccountJObj)));
response_has_field({Field, Value}, AccountJObj) ->
    response_had_field({Field, Value}, Value =:= kz_json:get_value(Field, AccountJObj));
response_has_field(Field, AccountJObj) ->
    response_had_field(Field, kz_json:is_defined(Field, AccountJObj)).

response_had_field(_Field, 'true') -> 'true';
response_had_field(Field, 'false') ->
    lager:info("response did not have field: ~p", [Field]),
    'false'.

-spec sub_account_names(pos_integer()) -> kz_term:ne_binaries().
sub_account_names(Count) ->
    lists:reverse([<<?MODULE_STRING, Char>> || Char <- lists:seq($a, $a+Count-1)]).

-spec seq_kzoo_222() -> 'ok'.
seq_kzoo_222() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),

    AccountIds = create_account_tree(API, ?KZOO_222_COUNT),
    lager:info("created accounts child->parent: ~p", [AccountIds]),

    verify_no_child_to_parent_access(API, AccountIds),

    lists:foreach(fun({_Name, AccountId}) ->
                          FetchResp = pqc_cb_accounts:fetch(API, AccountId),
                          lager:info("account ~s fetched: ~s", [AccountId, FetchResp]),
                          <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(FetchResp)),

                          DeleteResp = pqc_cb_accounts:delete(API, AccountId),
                          lager:info("account ~s deleted: ~s", [AccountId, DeleteResp]),
                          <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(DeleteResp))
                  end
                 ,AccountIds % delete from descendant to ancestor
                 ),

    _ = cleanup(API, []),
    lager:info("FINISHED TREE").

verify_no_child_to_parent_access(#{account_id:=MasterAccountId}=API, AccountIds) ->
    %% account ids is built in reverse order, so descendant to ancestor, leaf to root
    verify_no_child_to_parent_access(API, AccountIds, tl(AccountIds ++ [{0, MasterAccountId}])).

verify_no_child_to_parent_access(API, AccountIds, Acc0) ->
    _ = lists:foldl(fun(AccountId, Acc) -> child_to_parent_access(API, AccountId, Acc) end
                   ,Acc0
                   ,AccountIds
                   ),
    lager:info("no child access to parents").

child_to_parent_access(API, {_Name, ChildAccountId}, AncestorAccountIds) ->
    ChildAPI = auth_account_by_api_key(API, ChildAccountId),
    lager:info("checking child account ~s", [ChildAccountId]),
    'true' = lists:all(fun({_, ParentId}) -> no_child_access_to_parent(ChildAPI, ParentId) end
                      ,AncestorAccountIds
                      ),
    tl(AncestorAccountIds).

no_child_access_to_parent(ChildAPI, ParentId) ->
    case pqc_cb_accounts:fetch(ChildAPI, ParentId) of
        {'error', _} -> no_child_create_new_parent_account(ChildAPI, ParentId);
        Resp ->
            lager:info("child accessed parent ~s: ~s", [ParentId, Resp]),
            'false'
    end.

%% as part of KZOO-376, ensure a child can't create a "new" descendant
%% with the Parent's ID
no_child_create_new_parent_account(#{base_url := BaseURL}=ChildAPI, ParentId) ->
    AccountData = kz_json:set_values([{<<"id">>, ParentId}
                                     ,{<<"name">>, kz_binary:rand_hex(6)}
                                     ]
                                    ,kzd_accounts:new()
                                    ),
    URL = string:join([BaseURL, "accounts"], "/"),
    ErrorResp = pqc_cb_crud:create(ChildAPI
                                  ,URL
                                  ,pqc_cb_api:create_envelope(AccountData)
                                  ,[pqc_cb_expect:code(401)]
                                  ),
    lager:info("expected error creating sub-account: ~s", [ErrorResp]),
    401 =:= kz_json:get_integer_value(<<"error">>, kz_json:decode(ErrorResp)).

auth_account_by_api_key(API, ChildAccountId) ->
    APIKeyResp = pqc_cb_accounts:api_key(API, ChildAccountId),
    APIKey = kz_json:get_ne_binary_value([<<"data">>, <<"api_key">>], kz_json:decode(APIKeyResp)),

    ChildAuthResp = pqc_cb_api_auth:authenticate(API, APIKey),
    ChildAuthToken = kz_json:get_ne_binary_value(<<"auth_token">>, kz_json:decode(ChildAuthResp)),
    API#{auth_token => ChildAuthToken}.

%% test authing by API key, changing API key, then authing with old
%% and new keys
-spec seq_api_key() -> 'ok'.
seq_api_key() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account ~s", [AccountResp]),

    AccountJObj = kz_json:get_value(<<"data">>, kz_json:decode(AccountResp)),
    AccountId = kz_json:get_binary_value(<<"id">>, AccountJObj),

    APIKeyResp = pqc_cb_accounts:api_key(API, AccountId),
    OldAPIKey = kz_json:get_ne_binary_value([<<"data">>, <<"api_key">>], kz_json:decode(APIKeyResp)),

    OldAuthResp = pqc_cb_api_auth:authenticate(API, OldAPIKey),
    lager:info("old auth resp: ~s", [OldAuthResp]),
    OldAuthToken = kz_json:get_ne_binary_value(<<"auth_token">>, kz_json:decode(OldAuthResp)),

    OldAccountResp = pqc_cb_accounts:fetch(API#{auth_token => OldAuthToken}, AccountId),
    lager:info("old account resp: ~s", [OldAccountResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(OldAccountResp)),

    ResetResp = pqc_cb_accounts:reset_api_key(API, AccountId),
    lager:info("reset resp: ~s", [ResetResp]),
    NewAPIKey = kz_json:get_ne_binary_value([<<"data">>, <<"api_key">>], kz_json:decode(ResetResp)),
    'true' = (OldAPIKey =/= NewAPIKey),

    NewAuthResp = pqc_cb_api_auth:authenticate(API, NewAPIKey),
    lager:info("new auth resp: ~s", [NewAuthResp]),
    NewAuthToken = kz_json:get_ne_binary_value(<<"auth_token">>, kz_json:decode(OldAuthResp)),

    NewAccountResp = pqc_cb_accounts:fetch(API#{auth_token => NewAuthToken}, AccountId),
    lager:info("new account resp: ~s", [NewAccountResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(NewAccountResp)),

    {'error', ErrorResp} = pqc_cb_api_auth:authenticate(API, OldAPIKey),
    lager:info("expected error for old api key: ~s", [ErrorResp]),

    _ = cleanup(API, [AccountId]),
    lager:info("FINISHED API_KEY").

-spec seq_kcro_176() -> 'ok'.
seq_kcro_176() ->
    API = pqc_cb_api:init_api(['crossbar']
                             ,['cb_accounts'
                              ,'cb_clicktocall'
                              ]
                             ),

    AccountResp = properly_accountant:create_account(API, ?ACCOUNT_NAME),
    lager:info("created account ~s", [AccountResp]),
    AccountId = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    kcro_176_valid_token_api_auth(API, AccountId),
    kcro_176_basic_auth(API, AccountId),
    kcro_176_bad_auth_token_c2call(API, AccountId),
    kcro_176_no_auth_token_c2call(API, AccountId),

    _ = cleanup(API, [AccountId]),
    lager:info("FINISHED KCRO 176").

kcro_176_valid_token_api_auth(API, AccountId) ->
    #{account_id := MasterAccountId} = API,

    APIKeyResp = pqc_cb_accounts:api_key(API, AccountId),
    AccountAPIKey = kz_json:get_ne_binary_value([<<"data">>, <<"api_key">>], kz_json:decode(APIKeyResp)),
    AccountAuthResp = pqc_cb_api_auth:authenticate(API, AccountAPIKey),
    lager:info("account auth resp: ~s", [AccountAuthResp]),
    AccountAuthToken = kz_json:get_ne_binary_value(<<"auth_token">>, kz_json:decode(AccountAuthResp)),

    lager:info("testing access with valid auth token a parent account returns 403 forbidden"),
    {'error', ForbiddenErrResp} = pqc_cb_accounts:fetch(API#{auth_token => AccountAuthToken}, MasterAccountId),
    lager:info("expected error accessing parent account with valid auth token: ~s", [ForbiddenErrResp]),
    403 = kz_json:get_integer_value(<<"error">>, kz_json:decode(ForbiddenErrResp)),

    lager:info("testing if acces with valid auth tokens a non existing account id, was 404, now should be 401 unauthorized"),
    {'error', NonExistsId} = pqc_cb_accounts:fetch(API#{auth_token => AccountAuthToken}, kz_binary:rand_hex(16)),
    lager:info("expected error accessing non existing account i with valid auth tokend: ~s", [NonExistsId]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(NonExistsId)),

    lager:info("testing if access with valid auth token a bogus account id, was 404, now should be 401 unauthorized"),
    {'error', BadId} = pqc_cb_accounts:fetch(API#{auth_token => AccountAuthToken}, <<"lol">>),
    lager:info("expected error accessing a bogus account id with valid auth token: ~s", [BadId]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(BadId)).

kcro_176_basic_auth(API, AccountId) ->
    {_UserId, Username, Password} = seq_auth_attempts:create_user(API, AccountId),

    BasicUser = iolist_to_binary([AccountId, $:, kz_binary:md5([Username, $:, Password])]),
    Authorization = base64:encode(BasicUser),

    lager:info("testing access valid account id with basic auth is successfull"),
    ValidId = pqc_cb_accounts:fetch(API#{basic_auth => Authorization}, AccountId),
    lager:info("expected sucess access valid account id with basic auth: ~s", [ValidId]),
    AccountId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(ValidId)),

    lager:info("testing if access a non existing account id with basic auth is 401 unauthorized"),
    {'error', NonExistsId} = pqc_cb_accounts:fetch(API#{basic_auth => Authorization}, kz_binary:rand_hex(16)),
    lager:info("expected error basic auth accessing non existing account id: ~s", [NonExistsId]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(NonExistsId)),

    lager:info("testing if access a bogus account id with basic auth is 401 unauthorized"),
    {'error', BadId} = pqc_cb_accounts:fetch(API#{basic_auth => Authorization}, <<"lol">>),
    lager:info("expected error basic auth accessing a bogus account id: ~s", [BadId]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(BadId)).

kcro_176_bad_auth_token_c2call(API, AccountId) ->
    lager:info("if accessing non-existing account's c2c and bad auth token"),
    {'error', NonExistsId} = pqc_cb_clicktocall:connect(API#{auth_token => <<"lol">>}
                                                       ,kz_binary:rand_hex(16)
                                                       ,kz_binary:rand_hex(16)
                                                       ),
    lager:info("expected error accessing bogus account's c2c with bad auth token: ~s", [NonExistsId]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(NonExistsId)),

    lager:info("if accessing bogus account's c2c and bad auth token"),
    {'error', UnauthedC2CErrResp} = pqc_cb_clicktocall:connect(API#{auth_token => <<"lol">>}
                                                              ,<<"haha">>
                                                              ,kz_binary:rand_hex(16)
                                                              ),
    lager:info("expected error accessing bogus account's c2c with bad auth token: ~s", [UnauthedC2CErrResp]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(UnauthedC2CErrResp)),

    lager:info("if accessing a known account, with bad auth token, 401 unauthorized"),
    {'error', UnauthedErrResp} = pqc_cb_accounts:fetch(API#{auth_token => <<"lol">>}, AccountId),
    lager:info("expected error accessing account ~s with bad auth token: ~s", [AccountId, UnauthedErrResp]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(UnauthedErrResp)),

    lager:info("if accessing a bogus account id with bad auth token, 401 as well"),
    {'error', UnauthedBogusErrResp} = pqc_cb_accounts:fetch(API#{auth_token => <<"lol">>}, kz_binary:rand_hex(16)),
    lager:info("expected error accessing bogus account with bad auth token: ~s", [UnauthedBogusErrResp]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(UnauthedBogusErrResp)).

kcro_176_no_auth_token_c2call(API, AccountId) ->
    lager:info("if accessing non-existing account's c2c and no auth token"),
    {'error', UnauthedC2CErrResp} = pqc_cb_clicktocall:connect(API#{auth_token => 'undefined'}
                                                              ,kz_binary:rand_hex(16)
                                                              ,kz_binary:rand_hex(16)
                                                              ),
    lager:info("expected error accessing non-existing account's c2c with no auth token: ~s", [UnauthedC2CErrResp]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(UnauthedC2CErrResp)),

    lager:info("if accessing bogus account's c2c and no auth token"),
    {'error', BadId} = pqc_cb_clicktocall:connect(API#{auth_token => 'undefined'}
                                                 ,<<"haha">>
                                                 ,kz_binary:rand_hex(16)
                                                 ),
    lager:info("expected error accessing bogus account's c2c with no auth token: ~s", [BadId]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(BadId)),

    lager:info("if accessing a known account, with no auth token, 401 unauthorized"),
    {'error', UnauthedErrResp} = pqc_cb_accounts:fetch(API#{auth_token => 'undefined'}, AccountId),
    lager:info("expected error accessing account ~s with no auth token: ~s", [AccountId, UnauthedErrResp]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(UnauthedErrResp)),

    lager:info("if accessing a bogus account id with no auth token, 401 as well"),
    {'error', UnauthedBogusErrResp} = pqc_cb_accounts:fetch(API#{auth_token => 'undefined'}, kz_binary:rand_hex(16)),
    lager:info("expected error accessing bogus account with no auth token: ~s", [UnauthedBogusErrResp]),
    401 = kz_json:get_integer_value(<<"error">>, kz_json:decode(UnauthedBogusErrResp)).

%% @doc test Account move
-spec seq_move() -> 'ok'.
seq_move() ->
    #{account_id := MasterAccountId}=API = pqc_cb_api:init_api(['crossbar']
                                                              ,['cb_accounts']
                                                              ),

    [ResellerA, ResellerB, Child] = sub_account_names(3),

    ResellerAResp = properly_accountant:create_account(API, ResellerA),
    lager:info("created A's account ~s", [ResellerAResp]),
    ResellerAAccountId = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(ResellerAResp)),

    ResellerBResp = properly_accountant:create_account(API, ResellerB),
    lager:info("created B's account ~s", [ResellerBResp]),
    ResellerBAccountId = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(ResellerBResp)),

    ChildResp = properly_accountant:create_account(API, Child, ResellerAAccountId),
    lager:info("created child's account under A: ~s", [ChildResp]),
    ChildAccountId = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(ChildResp)),

    ChildTreeResp = pqc_cb_accounts:tree(API, ChildAccountId),
    lager:info("child ~s tree: ~s", [ChildAccountId, ChildTreeResp]),
    [Master, ParentA] = kz_json:get_list_value(<<"data">>, kz_json:decode(ChildTreeResp)),
    MasterAccountId = kz_doc:id(Master),
    ResellerAAccountId = kz_doc:id(ParentA),

    lager:info("moving child ~s from ~s to ~s", [ChildAccountId, ResellerAAccountId, ResellerBAccountId]),
    MoveResp = pqc_cb_accounts:move(API, ChildAccountId, ResellerBAccountId),
    lager:info("move resp: ~s", [MoveResp]),
    MoveJObj = kz_json:decode(MoveResp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, MoveJObj),
    ChildAccountId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], MoveJObj),

    MovedChildTreeResp = pqc_cb_accounts:tree(API, ChildAccountId),
    lager:info("moved child ~s tree: ~s", [ChildAccountId, MovedChildTreeResp]),
    [Master, ParentB] = kz_json:get_list_value(<<"data">>, kz_json:decode(MovedChildTreeResp)),
    MasterAccountId = kz_doc:id(Master),
    ResellerBAccountId = kz_doc:id(ParentB),

    lager:info("finished with MOVE"),
    cleanup(API, [ChildAccountId, ResellerAAccountId, ResellerBAccountId]).

-spec topup_request(pqc_cb_api:state(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
topup_request(API, AccountId, RequestEnvelope) ->
    timer:sleep(100),
    pqc_cb_crud:update(API
                      ,pqc_cb_accounts:account_url(API, AccountId)
                      ,RequestEnvelope
                      ).

%% 1. PUT to /v2/accounts (so it uses the auth account id as the
%% "parent") using a master account auth token
%% 2. Request data includes "id":"{MASTER_ACCOUNT_ID}"
%% 3. When Crossbar tries to create the account doc from the request data (with no _rev), a conflict occurs (since the account doc exists with a _rev), and Crossbar "rolls back" the "new" account by deleting the database (thus deleting the master account)
%% 4. Profit?
-spec seq_kzoo_376() -> 'ok'.
seq_kzoo_376() ->
    #{account_id := MasterAccountId
     ,base_url := BaseURL
     } = API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),

    AccountData = kz_json:set_values([{<<"id">>, MasterAccountId}
                                     ,{<<"name">>, kz_binary:rand_hex(6)}
                                     ]
                                    ,kzd_accounts:new()
                                    ),
    URL = string:join([BaseURL, "accounts"], "/"),
    ErrorResp = pqc_cb_crud:create(API
                                  ,URL
                                  ,pqc_cb_api:create_envelope(AccountData)
                                  ,[pqc_cb_expect:code(401)]
                                  ),
    lager:info("expected error creating sub-account: ~s", [ErrorResp]),

    FetchResp = pqc_cb_accounts:fetch(API, MasterAccountId),
    lager:info("can still fetch master account ~s: ~s", [MasterAccountId, FetchResp]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(FetchResp)),

    _ = cleanup(API, []),
    lager:info("FINISHED KZOO 376").

-spec cleanup() -> 'ok'.
cleanup() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),
    cleanup(API).

-spec cleanup(pqc_cb_api:state()) -> 'ok'.
cleanup(API) ->
    Supp16Accounts = sub_account_names(?SUPP_16_COUNT),
    cleanup(API, account_names() ++ Supp16Accounts).

cleanup(API, AccountNames) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),

    _ = cleanup_accounts(API, AccountNames),
    _ = pqc_cb_api:cleanup(API),
    'ok'.

-spec account_names() -> kz_term:ne_binaries().
account_names() ->
    [list_to_binary([?MODULE_STRING "_", kz_term:to_binary(Fun)])
     || {Fun, 0} <- ?MODULE:module_info('exports'),
        Fun >= 'seq_'
    ].
