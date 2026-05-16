%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% @author Navoda Ginige
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_websites).

-export([seq/0
        ,seq_websites/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).

-spec seq() -> 'ok'.
seq() ->
    Fs = [fun seq_websites/0],
    run_funcs(Fs).

run_funcs([]) -> 'ok';
run_funcs([F|Fs]) ->
    _ = F(),
    cleanup(),
    run_funcs(Fs).

-spec seq_websites() -> 'ok'.
seq_websites() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_websites']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_websites:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryResp)),

    CreateWebsiteResp = pqc_cb_websites:create(API, AccountId, new_website_doc()),
    lager:info("created website : ~s", [CreateWebsiteResp]),
    CreatedWebsite = kz_json:get_json_value([<<"data">>], kz_json:decode(CreateWebsiteResp)),
    WebsiteId = kz_doc:id(CreatedWebsite),

    WebsiteObj = kzd_websites:set_name(CreatedWebsite, kz_binary:rand_hex(8)),
    UpdateWebsiteResp = pqc_cb_websites:update(API, AccountId, WebsiteObj),
    lager:info("updated website : ~s", [UpdateWebsiteResp]),
    'true' = kz_json:are_equal(WebsiteObj, kz_json:get_json_value([<<"data">>], kz_json:decode(UpdateWebsiteResp))),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchedWebsite = kz_json:merge(CreatedWebsite, Patch),

    PatchResp = pqc_cb_websites:patch(API, AccountId, WebsiteId, PatchedWebsite),
    lager:info("patched to ~s", [PatchResp]),
    'true' = kz_json:are_equal(PatchedWebsite, kz_json:get_json_value([<<"data">>], kz_json:decode(PatchResp))),

    SummaryResp = pqc_cb_websites:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [WebsiteSummary] = kz_json:get_list_value([<<"data">>], kz_json:decode(SummaryResp)),
    WebsiteId = kz_doc:id(WebsiteSummary),

    {'ok', Logo} = file:read_file(filename:join([code:priv_dir('properly'), "logo.png"])),

    UploadResp = pqc_cb_websites:update_binary(API, AccountId, WebsiteId, Logo),
    lager:info("upload resp: ~s", [UploadResp]),
    UploadedWebsiteWebsite = kz_json:get_json_value([<<"data">>], kz_json:decode(UploadResp)),
    WebsiteId = kz_doc:id(UploadedWebsiteWebsite),

    FetchedLogo = pqc_cb_websites:fetch(API, AccountId, WebsiteId, <<"image/png">>),
    lager:info("fetched binary again: ~p", [FetchedLogo]),
    Logo = FetchedLogo,

    DeleteResp = pqc_cb_websites:delete(API, AccountId, WebsiteId),
    lager:info("delete resp: ~s", [DeleteResp]),

    UserId = create_user(API, AccountId),

    OpenInBrowser = 'true',
    CreateWebsiteResp1 = pqc_cb_websites:create(API, AccountId, new_user_website_doc([UserId], 'true', OpenInBrowser)),
    lager:info("created website for specific user with account_wide=true: ~s", [CreateWebsiteResp1]),
    CreatedWebsite1 = kz_json:get_json_value([<<"data">>], kz_json:decode(CreateWebsiteResp1)),
    WebsiteId1 = kz_doc:id(CreatedWebsite1),

    SummaryResp1 = pqc_cb_websites:user_summary(API, AccountId, UserId),
    lager:info("summary resp for user: ~s", [SummaryResp1]),
    [WebsiteSummary1] = kz_json:get_list_value([<<"data">>], kz_json:decode(SummaryResp1)),
    WebsiteId1 = kz_doc:id(WebsiteSummary1),
    OpenInBrowser = kzd_websites:open_in_browser(WebsiteSummary1),

    DeleteResp1 = pqc_cb_websites:delete(API, AccountId, WebsiteId1),
    lager:info("delete resp: ~s", [DeleteResp1]),

    EmptySummaryAgain = pqc_cb_websites:summary(API, AccountId),
    lager:info("empty summary again: ~s", [EmptySummaryAgain]),
    [] = kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryAgain)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED website SEQ").

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

-spec create_account(pqc_cb_api:state(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_account(API, AccountName) ->
    AccountResp = properly_accountant:create_account(API, AccountName),
    lager:info("created account: ~s", [AccountResp]),

    kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)).

-spec new_website_doc() -> kzd_websites:doc().
new_website_doc() ->
    Set = [{fun kzd_websites:set_name/2, kz_binary:rand_hex(6)}
          ,{fun kzd_websites:set_web_url/2, kz_binary:rand_hex(10)}
          ],
    kz_doc:public_fields(kz_json:exec_first(Set, kzd_websites:new())).

-spec new_user_website_doc(list(), boolean(), boolean()) -> kzd_websites:doc().
new_user_website_doc(UserIds, AccountWide, OpenInBrowser) ->
    Set = [{fun kzd_websites:set_name/2, kz_binary:rand_hex(6)}
          ,{fun kzd_websites:set_web_url/2, kz_binary:rand_hex(10)}
          ,{fun kzd_websites:set_account_wide/2, AccountWide}
          ,{fun kzd_websites:set_users/2, UserIds}
          ,{fun kzd_websites:set_open_in_browser/2, OpenInBrowser}
          ],
    kz_doc:public_fields(kz_json:exec_first(Set, kzd_websites:new())).

create_user(API, AccountId) ->
    UserJObj = new_user(),
    CreateUserResp = pqc_cb_users:create(API, AccountId, UserJObj),
    lager:info("created user ~p", [CreateUserResp]),
    kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>]
                               ,kz_json:decode(CreateUserResp)
                               ).

-spec new_user() -> kzd_users:doc().
new_user() ->
    new_user(kz_json:new()).

-spec new_user(kzd_users:doc()) -> kzd_users:doc().
new_user(UserDoc) ->
    DefaultUser = kz_json_schema:add_defaults(kzd_users:new(), kzd_users:schema()),
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_users:set_first_name/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_users:set_last_name/2, kz_binary:rand_hex(4)}
                         ]
                        ,kz_json:merge(UserDoc, DefaultUser)
                        )
     ).
