%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% @author Manushi Perera
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_whitelabel).

-export([seq/0
        ,seq_whitelabel/0
        ,seq_email/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).

-spec seq() -> 'ok'.
seq() ->
    Fs = [fun seq_whitelabel/0
         ,fun seq_email/0
         ],
    run_funcs(Fs).

run_funcs([]) -> 'ok';
run_funcs([F|Fs]) ->
    _ = F(),
    cleanup(),
    run_funcs(Fs).

-spec seq_whitelabel() -> 'ok'.
seq_whitelabel() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_whitelabel']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    {'error', EmptySummaryResp}= pqc_cb_whitelabel:summary_whitelabel(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    404 = kz_json:get_integer_value(<<"error">>, kz_json:decode(EmptySummaryResp)),

    CreateWhitelabelResp = pqc_cb_whitelabel:create_whitelabel(API, AccountId, new_whitelabel_doc()),
    lager:info("created whitelabel : ~s", [CreateWhitelabelResp]),
    CreatedWhitelabel = kz_json:get_json_value([<<"data">>], kz_json:decode(CreateWhitelabelResp)),
    WhitelabelId = kz_doc:id(CreatedWhitelabel),

    WhitelabelJObj = kzd_whitelabel:set_company_name(CreatedWhitelabel, kz_binary:rand_hex(8)),
    UpdateWhitelabelResp = pqc_cb_whitelabel:update_whitelabel(API, AccountId, WhitelabelJObj),
    lager:info("updated whitelabel : ~s", [UpdateWhitelabelResp]),
    'true' = kz_json:are_equal(WhitelabelJObj, kz_json:get_json_value([<<"data">>], kz_json:decode(UpdateWhitelabelResp))),

    SummaryResp = pqc_cb_whitelabel:summary_whitelabel(API, AccountId),
    lager:info("whitelabel summary resp: ~s", [SummaryResp]),
    WhitelabelSummary = kz_json:get_json_value([<<"data">>], kz_json:decode(SummaryResp)),
    WhitelabelId = kz_doc:id(WhitelabelSummary),

    DeleteResp = pqc_cb_whitelabel:delete_whitelabel(API, AccountId),
    lager:info("delete resp: ~s", [DeleteResp]),

    {'error', EmptySummaryAgain} = pqc_cb_whitelabel:summary_whitelabel(API, AccountId),
    lager:info("empty summary again: ~s", [EmptySummaryAgain]),
    404 = kz_json:get_integer_value(<<"error">>, kz_json:decode(EmptySummaryAgain)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED whitelabel SEQ").

-spec seq_email() -> 'ok'.
seq_email() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_whitelabel']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    CreateWhitelabelResp = pqc_cb_whitelabel:create_whitelabel(API, AccountId, new_whitelabel_doc()),
    lager:info("created whitelabel : ~s", [CreateWhitelabelResp]),
    CreatedWhitelabel = kz_json:get_json_value([<<"data">>], kz_json:decode(CreateWhitelabelResp)),
    WhitelabelId = kz_doc:id(CreatedWhitelabel),
    lager:info("created whitelabel ID : ~s", [WhitelabelId]),

    EmptySummaryResp = pqc_cb_whitelabel:summary_email(API, AccountId),
    lager:info("empty summary: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryResp)),

    CreatedEmailResp = pqc_cb_whitelabel:create_email(API, AccountId, new_email_doc()),
    lager:info("created email : ~s", [CreatedEmailResp]),
    CreatedEmail = kz_json:get_json_value([<<"metadata">>], kz_json:decode(CreatedEmailResp)),
    EmailId = kz_doc:id(CreatedEmail),

    FetchEmailResp = pqc_cb_whitelabel:fetch_email(API, AccountId, EmailId),
    lager:info("fetch email: ~s", [FetchEmailResp]),
    FetchedEmailJObj = kz_json:get_json_value([<<"data">>], kz_json:decode(FetchEmailResp)),

    EmailJObj = kzd_emails:set_dkim_selector(FetchedEmailJObj, kz_binary:rand_hex(6)),
    UpdatedEmailResp = pqc_cb_whitelabel:update_email(API, AccountId, EmailId, EmailJObj),
    lager:info("updated email: ~s", [UpdatedEmailResp]),
    UpdatedEmailJObj = kz_json:get_json_value([<<"data">>], kz_json:decode(UpdatedEmailResp)),
    'true' = kz_json:are_equal(EmailJObj, UpdatedEmailJObj),

    VerificationCode = pqc_cb_whitelabel:fetch_verification_code(AccountId, EmailId),
    CodeJObj = kzd_email_claim:set_code(kz_json:new(), VerificationCode),
    VerifiedEmailResp = pqc_cb_whitelabel:verify_email(API, AccountId, EmailId, CodeJObj),
    lager:info("verified email: ~s", [VerifiedEmailResp]),
    VerifiedEmailMetadata = kz_json:get_json_value([<<"metadata">>], kz_json:decode(VerifiedEmailResp)),
    'true' = kz_json:get_boolean_value([<<"verified">>], VerifiedEmailMetadata),

    UpdateDKIMResp = pqc_cb_whitelabel:update_dkim(API, AccountId, EmailId, generate_pem_file()),
    lager:info("updated email with DKIM pem file : ~s", [UpdateDKIMResp]),
    'true' = kz_json:are_equal(UpdatedEmailJObj, kz_json:get_json_value([<<"data">>], kz_json:decode(UpdateDKIMResp))),

    SummaryEmailResp = pqc_cb_whitelabel:summary_email(API, AccountId),
    lager:info("email summary resp: ~s", [SummaryEmailResp]),
    [EmailSummary] = kz_json:get_list_value([<<"data">>], kz_json:decode(SummaryEmailResp)),
    'true' = kz_json:get_boolean_value([<<"verified">>], EmailSummary),

    DeleteEmailResp = pqc_cb_whitelabel:delete_email(API, AccountId, EmailId),
    lager:info("delete email resp: ~s", [DeleteEmailResp]),

    EmptySummaryAgainResp = pqc_cb_whitelabel:summary_email(API, AccountId),
    lager:info("empty email summary again: ~s", [EmptySummaryAgainResp]),
    [] = kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryAgainResp)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED EMATL SEQ").

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

-spec new_whitelabel_doc() -> kzd_whitelabel:doc().
new_whitelabel_doc() ->
    Set = [{fun kzd_whitelabel:set_company_name/2, kz_binary:rand_hex(6)}
          ,{fun kzd_whitelabel:set_domain/2, kz_binary:rand_hex(10)}
          ],
    kz_doc:public_fields(kz_json:exec_first(Set, kzd_whitelabel:new())).

-spec new_email_doc() -> kzd_emails:doc().
new_email_doc() ->
    Set = [{fun kzd_emails:set_email/2, <<(kz_binary:rand_hex(4))/binary, "@2600hz.com">>}
          ,{fun kzd_emails:set_dkim_selector/2, kz_binary:rand_hex(10)}
          ],
    kz_doc:public_fields(kz_json:exec_first(Set, kzd_emails:new())).

-spec generate_pem_file() -> kz_term:ne_binary().
generate_pem_file() ->
    FileName = filename:join([code:priv_dir('properly')
                             ,kz_term:to_list(kz_binary:rand_hex(10)) ++ ".pem"
                             ]),
    {'ok', _Result} = kz_os:cmd(["openssl genrsa -out ", FileName, " 1024"]),
    lager:info("openssl genrsa to ~s: ~s", [FileName, _Result]),
    {'ok', PemBin} = file:read_file(FileName),
    lager:info("PEM: ~s", [PemBin]),
    _ = file:delete(FileName),
    PemBin.
