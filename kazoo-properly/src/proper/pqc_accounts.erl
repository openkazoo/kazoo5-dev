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
-module(pqc_accounts).

-export([command/2
        ,symbolic_account_id/2

        ,next_state/3
        ,postcondition/3
        ]).

-export([cleanup_accounts/1, cleanup_accounts/2]).

-include("properly.hrl").

-export_type([account_id/0]).

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).
-define(SUPP_16_COUNT, 5).

-type account_id() :: {'call', 'pqc_kazoo_model', 'account_id_by_name', [pqc_cb_api:state() | proper_types:type()]} |
                      kz_term:ne_binary().

-define(API_MODULE, 'pqc_cb_accounts').

-spec command(pqc_kazoo_model:model(), kz_term:ne_binary() | proper_types:type()) ->
          {'call', ?API_MODULE, 'create_account', [pqc_cb_api:state() | proper_types:term()]}.
command(Model, Name) ->
    {'call', ?API_MODULE, 'create_account', [pqc_kazoo_model:api(Model), Name]}.

-spec symbolic_account_id(pqc_kazoo_model:model(), kz_term:ne_binary() | proper_types:type()) ->
          account_id().
symbolic_account_id(Model, Name) ->
    {'call', 'pqc_kazoo_model', 'account_id_by_name', [Model, Name]}.

-spec next_state(pqc_kazoo_model:model(), any(), any()) -> pqc_kazoo_model:model().
next_state(Model
          ,APIResp
          ,{'call', ?API_MODULE, 'create_account', [_API, Name]}
          ) ->
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:is_account_missing/2, [Name]}
                           ,{fun pqc_kazoo_model:add_account/3, [Name, APIResp]}
                           ]).

-spec postcondition(pqc_kazoo_model:model(), any(), any()) -> boolean().
postcondition(Model
             ,{'call', _, 'create_account', [_API, Name]}
             ,APIResult
             ) ->
    case pqc_kazoo_model:account_id_by_name(Model, Name) of
        'undefined' ->
            ?INFO("no account by the name of ~s, should be an account id in ~s"
                 ,[Name, APIResult]
                 ),
            'undefined' =/= pqc_cb_response:account_id(APIResult);
        _AccountId ->
            ?INFO("account ~s (~s) found, API should be an error: ~s"
                 ,[Name, _AccountId, APIResult]
                 ),
            500 =:= pqc_cb_response:error_code(APIResult)
    end.

-spec cleanup_accounts(kz_term:ne_binaries()) -> 'ok'.
cleanup_accounts(AccountNames) ->
    cleanup_accounts(pqc_cb_api:authenticate(), AccountNames).

-spec cleanup_accounts(pqc_cb_api:state(), kz_term:ne_binaries()) -> 'ok'.
cleanup_accounts(API, AccountNames) ->
    lager:info("cleaning up accounts ~p", [AccountNames]),
    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"tasks">>
                                                  ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"soft_delete_pause_ms">>, 100}])}])
                                                  ),
    _ = [cleanup_account(API, AccountName) || AccountName <- AccountNames],
    kt_cleanup:cleanup_soft_deletes(?KZ_ACCOUNTS_DB).

-spec cleanup_account(pqc_cb_api:state(), kz_term:ne_binary()) -> 'ok'.
cleanup_account(API, AccountName) ->
    _Attempt = try pqc_cb_search:search_account_by_name(API, AccountName) of
                   ?FAILED_RESPONSE ->
                       lager:info("failed to search for account by name ~s~n", [AccountName]);
                   APIResp ->
                       Data = pqc_cb_response:data(APIResp),
                       case kz_json:get_ne_binary_value([1, <<"id">>], Data) of
                           'undefined' -> check_accounts_db(AccountName);
                           AccountId -> pqc_cb_accounts:delete(API, AccountId)
                       end
               catch
                   'throw':{'error', 'socket_closed_remotely'} ->
                       ?ERROR("broke the SUT cleaning up account ~s (~p)~n", [AccountName, API])
               end,
    timer:sleep(1000).% was needed to stop overwhelming the socket, at least locally

check_accounts_db(Name) ->
    AccountName = kzd_accounts:normalize_name(Name),
    ViewOptions = [{'key', AccountName}],
    case kz_datamgr:get_results(?KZ_ACCOUNTS_DB, <<"accounts/listing_by_name">>, ViewOptions) of
        {'ok', []} -> 'ok';
        {'error', _E} -> ?ERROR("failed to list by name: ~p", [_E]);
        {'ok', JObjs} ->
            ?INFO("deleting from ~s: ~p~n", [?KZ_ACCOUNTS_DB, JObjs]),
            kz_datamgr:del_docs(?KZ_ACCOUNTS_DB, JObjs)
    end.
