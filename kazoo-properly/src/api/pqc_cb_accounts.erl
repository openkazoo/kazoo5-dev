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
-module(pqc_cb_accounts).

-export([create/2, create/3
        ,update/3
        ,delete/2
        ,patch/3
        ,fetch/2

        ,tree/2, parents/2
        ,api_key/2, reset_api_key/2
        ,allow_number_additions/1
        ,move/3
        ,promote/2
        ]).

-export([account_url/1, account_url/2
        ,external_caller_id_number/0, external_caller_id_name/0
        ,internal_caller_id_number/0, internal_caller_id_name/0
        ,emergency_caller_id_number/0, emergency_caller_id_name/0
        ]).

-include("properly.hrl").

-spec external_caller_id_number() -> kz_term:ne_binary().
external_caller_id_number() -> <<"10002224444">>.

-spec external_caller_id_name() -> kz_term:ne_binary().
external_caller_id_name() -> <<"cid-external">>.

-spec internal_caller_id_number() -> kz_term:ne_binary().
internal_caller_id_number() -> <<"4444">>.

-spec internal_caller_id_name() -> kz_term:ne_binary().
internal_caller_id_name() -> <<"cid-internal">>.

-spec emergency_caller_id_number() -> kz_term:ne_binary().
emergency_caller_id_number() -> external_caller_id_number().

-spec emergency_caller_id_name() -> kz_term:ne_binary().
emergency_caller_id_name() -> <<"cid-emergency">>.

-spec create(pqc_cb_api:state(), kz_json:object() | kz_term:ne_binary()) -> pqc_cb_api:response().
create(API, NewAccount) ->
    create(API, NewAccount, pqc_cb_api:auth_account_id(API)).

-spec create(pqc_cb_api:state(), kz_json:object() | kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
create(API, <<NewAccountName/binary>>, <<AuthAccountId/binary>>) ->
    ExternalCID = kz_json:from_list([{<<"number">>, external_caller_id_number()}
                                    ,{<<"name">>, external_caller_id_name()}
                                    ]),
    InternalCID = kz_json:from_list([{<<"number">>, internal_caller_id_number()}
                                    ,{<<"name">>, internal_caller_id_name()}
                                    ]),
    EmergencyCID = kz_json:from_list([{<<"number">>, emergency_caller_id_number()}
                                     ,{<<"name">>, emergency_caller_id_name()}
                                     ]),
    CallerIdSettings = kz_json:from_list([{<<"external">>, ExternalCID}
                                         ,{<<"internal">>, InternalCID}
                                         ,{<<"emergency">>, EmergencyCID}
                                         ]),
    RequestData = kz_json:from_list([{<<"name">>, NewAccountName}
                                    ,{<<"caller_id">>, CallerIdSettings}
                                    ,{<<"realm">>, realm()}
                                    ]),
    create(API, RequestData, AuthAccountId);
create(API, NewAccountName, AuthAccountId) when is_atom(NewAccountName) ->
    create(API, kz_term:to_binary(NewAccountName), AuthAccountId);
create(API, RequestData, <<AuthAccountId/binary>>) ->
    RequestEnvelope = pqc_cb_api:create_envelope(RequestData),

    pqc_cb_crud:create(API, account_url(AuthAccountId), RequestEnvelope, [pqc_cb_expect:codes([201, 500])]).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
update(API, AccountId, ReqData) ->
    RequestEnvelope = pqc_cb_api:create_envelope(ReqData),

    pqc_cb_crud:update(API , account_url(API, AccountId), RequestEnvelope).

-spec allow_number_additions(kz_term:ne_binary()) -> 'ok'.
allow_number_additions(<<AccountId/binary>>) ->
    {'ok', _Account} = kzd_accounts:update(AccountId
                                          ,[{kzd_accounts:path_allow_number_additions(), 'true'}]
                                          ),
    ?INFO("updated ~s (~s) to allow number additions", [AccountId, kz_doc:revision(_Account)]).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId) ->
    pqc_cb_crud:fetch(API, account_url(API, AccountId)).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
patch(API, AccountId, ReqJObj) ->
    RequestEnvelope = pqc_cb_api:create_envelope(ReqJObj),

    pqc_cb_crud:patch(API, account_url(API, AccountId), RequestEnvelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId) ->
    pqc_cb_crud:delete(API, account_url(API, AccountId)).

-spec tree(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
tree(API, AccountId) ->
    pqc_cb_crud:fetch(API, string:join([account_url(API, AccountId), "tree"], "/")).

-spec parents(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
parents(API, AccountId) ->
    pqc_cb_crud:fetch(API, string:join([account_url(API, AccountId), "parents"], "/")).

-spec api_key(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
api_key(API, AccountId) ->
    pqc_cb_crud:fetch(API, string:join([account_url(API, AccountId), "api_key"], "/")).

-spec reset_api_key(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
reset_api_key(API, AccountId) ->
    pqc_cb_crud:create(API, string:join([account_url(API, AccountId), "api_key"], "/")).

-spec move(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary() | kz_json:object()) -> pqc_cb_api:response().
move(API, AccountId, <<ToAccountId/binary>>) ->
    move(API, AccountId, kz_json:from_list([{<<"to">>, ToAccountId}]));
move(API, AccountId, ReqData) ->
    RequestEnvelope = pqc_cb_api:create_envelope(ReqData),

    pqc_cb_crud:update(API, string:join([account_url(API, AccountId), "move"], "/"), RequestEnvelope).

-spec promote(pqc_cb_api:state(), kz_term:ne_binary()) -> any().
promote(API, AccountId) ->
    Envelope = pqc_cb_api:create_envelope(kz_json:new()),

    pqc_cb_crud:create(API, string:join([account_url(API, AccountId), "reseller"], "/"), Envelope).

-spec account_url(seq_accounts:account_id() | pqc_cb_api:state()) -> string().
account_url(#{base_url:=APIBase
             ,account_id:=AccountId
             }
           ) ->
    account_url(APIBase, AccountId);
account_url(#{account_id:=AccountId}=API) ->
    account_url(API, AccountId);
account_url(<<AccountId/binary>>) ->
    account_url(pqc_cb_api:v2_base_url(), AccountId).

-spec account_url(string() | seq_accounts:account_id() | pqc_cb_api:state(), kz_term:ne_binary()) ->
          string().
account_url(#{base_url := APIBase}, AccountId) ->
    account_url(APIBase, AccountId);
account_url(#{}, AccountId) ->
    account_url(pqc_cb_api:v2_base_url(), AccountId);
account_url(APIBase, <<AccountId/binary>>) ->
    string:join([APIBase, "accounts", kz_term:to_list(AccountId)], "/").

realm() ->
    iolist_to_binary([kz_binary:rand_hex(4)
                     ,[$. | kz_network_utils:get_hostname()]
                     ]).
