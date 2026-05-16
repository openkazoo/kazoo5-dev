%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2025, 2600Hz
%%% @doc Functions shared between crossbar modules
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_modules_util).

-export([pass_hashes/2
        ,get_devices_owned_by/2
        ,cavs_from_context/1
        ,ccvs_from_context/1

        ,attachment_name/2
        ,parse_media_type/1

        ,bucket_name/1
        ,token_cost/1, token_cost/2, token_cost/3
        ,tokens_remaining/1
        ,consume_tokens/2, consume_tokens/3
        ,consume_tokens_until/2, consume_tokens_until/3

        ,bind/2

        ,take_sync_field/1

        ,remove_plaintext_password/1

        ,validate_number_ownership/2
        ,apply_assignment_updates/2
        ,log_assignment_updates/1

        ,normalize_media_upload/5

        ,get_request_action/1
        ,normalize_alphanum_name/1

        ,maybe_convert_numbers_to_list/1
        ]).

-export([phonebook_port_in/1
        ,phonebook_comment/2
        ,phonebook_lnp_lookup/1

        ,should_send_to_phonebook/1
        ]).

-include("crossbar.hrl").
-include_lib("kazoo_stdlib/include/kazoo_json.hrl").

-type binding() :: {kz_term:ne_binary(), atom()}.
-type bindings() :: [binding(),...].
-spec bind(atom(), bindings()) -> 'ok'.
bind(Module, Bindings) ->
    _ = [crossbar_bindings:bind(Binding, Module, Function)
         || {Binding, Function} <- Bindings
        ],
    'ok'.

-spec pass_hashes(kz_term:ne_binary(), kz_term:ne_binary()) -> {kz_term:ne_binary(), kz_term:ne_binary()}.
pass_hashes(Username, Password) ->
    kzd_module_utils:pass_hashes(Username, Password).


-spec get_devices_owned_by(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_json:objects().
get_devices_owned_by(OwnerID, DB) ->
    case kz_datamgr:get_results(DB
                               ,<<"attributes/owned">>
                               ,[{'key', [OwnerID, <<"device">>]}
                                ,'include_docs'
                                ])
    of
        {'ok', JObjs} ->
            lager:debug("found ~b devices owned by ~s", [length(JObjs), OwnerID]),
            [kz_json:get_value(<<"doc">>, JObj) || JObj <- JObjs];
        {'error', _R} ->
            lager:debug("unable to fetch devices: ~p", [_R]),
            []
    end.

-spec cavs_from_context(cb_context:context()) -> kz_term:proplist().
cavs_from_context(Context) ->
    cvs_from_context(Context, <<"custom_application_vars">>).

-spec ccvs_from_context(cb_context:context()) -> kz_term:proplist().
ccvs_from_context(Context) ->
    cvs_from_context(Context, <<"custom_conference_vars">>).

-spec cvs_from_context(cb_context:context(), kz_term:ne_binary()) -> kz_term:proplist().
cvs_from_context(Context, CustomVars) ->
    ReqData = cb_context:req_data(Context),
    QueryString = cb_context:query_string(Context),
    cvs_from_request(ReqData, QueryString, CustomVars).

-spec cvs_from_request(kz_json:object(), kz_json:object(), kz_term:ne_binary()) -> kz_term:proplist().
cvs_from_request(ReqData, QueryString, CustomVars) ->
    CVs = kz_json:get_json_value(CustomVars, ReqData, kz_json:new()),
    kapps_call_util:filter_ccvs(kz_json:merge(CVs, QueryString)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec phonebook_port_in(cb_context:context()) -> knm_phonebook:response().
phonebook_port_in(Context) ->
    knm_phonebook:maybe_create_port_in(cb_context:doc(Context), phonebook_options(Context)).

-spec phonebook_comment(cb_context:context(), kz_json:objects()) -> knm_phonebook:response().
phonebook_comment(Context, Comments) ->
    knm_phonebook:maybe_add_comment(cb_context:doc(Context), Comments, phonebook_options(Context)).

-spec phonebook_lnp_lookup(cb_context:context()) -> knm_phonebook:response().
phonebook_lnp_lookup(Context) ->
    knm_phonebook:lnp_lookup(cb_context:doc(Context), phonebook_options(Context)).

-spec should_send_to_phonebook(cb_context:context()) -> boolean().
should_send_to_phonebook(Context) ->
    knm_phonebook:should_send_to_phonebook(phonebook_options(Context)).

phonebook_options(Context) ->
    [{'auth_token', cb_context:auth_token(Context)}
    ,{'port_authority_id', cb_context:fetch(Context, 'port_authority_id')}
    ,{'master_account_id', cb_context:master_account_id(Context)}
    ,{'user_agent', cb_context:req_header(Context, <<"User-Agent">>)}
    ].

%%------------------------------------------------------------------------------
%% @doc Generate an attachment name if one is not provided and ensure
%% it has an extension (for the associated content type)
%% @end
%%------------------------------------------------------------------------------
-spec attachment_name(binary(), kz_term:text()) -> kz_term:ne_binary().
attachment_name(Filename, CT) ->
    Generators = [fun(A) ->
                          case kz_term:is_empty(A) of
                              'true' -> kz_term:to_hex_binary(crypto:strong_rand_bytes(16));
                              'false' -> A
                          end
                  end
                 ,fun(A) ->
                          case kz_term:is_empty(filename:extension(A)) of
                              'false' -> A;
                              'true' ->
                                  <<A/binary, ".", (kz_mime:to_extension(CT))/binary>>
                          end
                  end
                 ],
    lists:foldl(fun(F, A) -> F(A) end, Filename, Generators).

-spec parse_media_type(kz_term:ne_binary()) -> media_values() |
          {'error', 'badarg'}.
parse_media_type(MediaType) ->
    try cow_http_hd:parse_accept(MediaType)
    catch
        _E:_R ->
            lager:debug("failed to parse ~p: ~s: ~p", [MediaType, _E, _R]),
            {'error', 'badarg'}
    end.

-spec bucket_name(cb_context:context()) -> kz_term:ne_binary().
bucket_name(Context) ->
    bucket_name(cb_context:client_ip(Context), cb_context:account_id(Context)).

-spec bucket_name(kz_term:api_ne_binary(), kz_term:api_ne_binary()) -> kz_term:ne_binary().
bucket_name('undefined', 'undefined') ->
    <<"no_ip/no_account">>;
bucket_name(IP, 'undefined') ->
    <<IP/binary, "/no_account">>;
bucket_name('undefined', AccountId) ->
    <<"no_ip/", AccountId/binary>>;
bucket_name(IP, AccountId) ->
    <<IP/binary, "/", AccountId/binary>>.

-spec tokens_remaining(cb_context:context()) -> non_neg_integer().
tokens_remaining(Context) ->
    lists:sum([kz_buckets:tokens_remaining(<<"crossbar">>, BucketName)
               || BucketName <- cb_context:token_bucket_names(Context)
              ]).

-spec consume_tokens(cb_context:context(), non_neg_integer()) ->
          {boolean(), cb_context:context()}.
consume_tokens(Context, Cost) ->
    consume_tokens(Context, Cost, bucket_name(Context)).

-spec consume_tokens(cb_context:context(), non_neg_integer(), kz_term:ne_binary()) ->
          {boolean(), cb_context:context()}.
consume_tokens(Context, Cost, <<BucketName/binary>>) ->
    consume_tokens(Context, BucketName, Cost, fun kz_buckets:consume_tokens/3).

-spec consume_tokens_until(cb_context:context(), non_neg_integer()) ->
          {boolean(), cb_context:context()}.
consume_tokens_until(Context, Cost) ->
    consume_tokens_until(Context, Cost, bucket_name(Context)).

-spec consume_tokens_until(cb_context:context(), non_neg_integer(), kz_term:ne_binary()) ->
          {boolean(), cb_context:context()}.
consume_tokens_until(Context, Cost, BucketName) ->
    consume_tokens(Context, BucketName, Cost, fun kz_buckets:consume_tokens_until/3).

-type consume_fun() :: fun((kz_term:ne_binary(), kz_term:ne_binary(), non_neg_integer()) -> boolean()).
-spec consume_tokens(cb_context:context(), kz_term:ne_binary(), non_neg_integer(), consume_fun()) ->
          {boolean(), cb_context:context()}.
consume_tokens(Context, BucketName, Cost, ConsumeFun) ->
    Setters = [{fun cb_context:add_consumed_token_buckets/2, Cost}
              ,{fun cb_context:add_token_bucket_name/2, BucketName}
              ],
    {ConsumeFun(?APP_NAME, BucketName, Cost)
    ,cb_context:setters(Context, Setters)
    }.

-spec token_cost(cb_context:context()) -> non_neg_integer().
token_cost(Context) ->
    token_cost(Context, 1).

-spec token_cost(cb_context:context(), non_neg_integer() | kz_json:path()) -> non_neg_integer().
token_cost(Context, <<Suffix/binary>>) ->
    token_cost(Context, 1, [Suffix]);
token_cost(Context, [_|_]=Suffix) ->
    token_cost(Context, 1, Suffix);
token_cost(Context, Default) ->
    token_cost(Context, Default, []).

-spec token_cost(cb_context:context(), non_neg_integer(), kz_json:path()) -> non_neg_integer().
token_cost(Context, Default, Suffix) when is_integer(Default), Default >= 0 ->
    Costs = kapps_config:get(?CONFIG_CAT, <<"token_costs">>, 1),
    find_token_cost(Costs
                   ,Default
                   ,Suffix
                   ,cb_context:req_nouns(Context)
                   ,cb_context:req_verb(Context)
                   ,cb_context:account_id(Context)
                   ).

-spec find_token_cost(kz_json:object() | non_neg_integer()
                     ,Default
                     ,kz_json:path()
                     ,req_nouns()
                     ,http_method()
                     ,kz_term:api_ne_binary()
                     ) ->
          integer() | Default.
find_token_cost(0, _Default, _Suffix, _Nouns, _ReqVerb, _AccountId) ->
    lager:info("no token costs configured"),
    0;
find_token_cost(N, Default, _Suffix, _Nouns, _ReqVerb, _AccountId)
  when is_integer(N), is_integer(Default) ->
    Cost = max(N, Default),
    lager:info("token cost of ~p configured", [Cost]),
    Cost;
find_token_cost(JObj, Default, Suffix, [{Endpoint, _} | _], ReqVerb, 'undefined') ->
    Keys = [[Endpoint, ReqVerb | Suffix]
           ,[Endpoint | Suffix]
           ],
    get_token_cost(JObj, Default, Keys);
find_token_cost(JObj, Default, Suffix, [{Endpoint, _}|_], ReqVerb, AccountId) ->
    Keys = [[AccountId, Endpoint, ReqVerb | Suffix]
           ,[AccountId, Endpoint | Suffix]
           ,[AccountId | Suffix]
           ,[Endpoint, ReqVerb | Suffix]
           ,[Endpoint | Suffix]
           ],
    get_token_cost(JObj, Default, Keys).

-spec get_token_cost(kz_json:object(), Default, kz_json:paths()) ->
          integer() | Default.
get_token_cost(JObj, Default, Keys) ->
    case kz_json:get_first_defined(Keys, JObj) of
        'undefined' -> Default;
        V -> kz_term:to_integer(V)
    end.

-spec take_sync_field(cb_context:context()) -> cb_context:context().
take_sync_field(Context) ->
    Doc = cb_context:doc(Context),
    ShouldSync = kz_json:is_true(<<"sync">>, Doc, 'false'),
    CleansedDoc = kz_json:delete_key(<<"sync">>, Doc),
    cb_context:setters(Context, [{fun cb_context:store/3, 'sync', ShouldSync}
                                ,{fun cb_context:set_doc/2, CleansedDoc}
                                ]).

-spec remove_plaintext_password(cb_context:context()) -> cb_context:context().
remove_plaintext_password(Context) ->
    Doc = kz_json:delete_keys([<<"password">>
                              ,<<"confirm_password">>
                              ]
                             ,cb_context:doc(Context)
                             ),
    cb_context:set_doc(Context, Doc).

-spec validate_number_ownership(kz_term:ne_binaries(), cb_context:context()) ->
          cb_context:context().
validate_number_ownership(Numbers, Context) ->
    AccountId =  cb_context:auth_account_id(Context),
    case kz_term:is_empty(AccountId)
        orelse knm_numbers:validate_ownership(AccountId, Numbers)
    of
        'true' -> Context;
        {'false', Unauthorized} ->
            Prefix = <<"unauthorized to use ">>,
            NumbersStr = kz_binary:join(Unauthorized, <<", ">>),
            Message = <<Prefix/binary, NumbersStr/binary>>,
            cb_context:add_system_error(403, 'forbidden', Message, Context)
    end.

-type assignment_to_apply() :: {kz_term:ne_binary(), kz_term:api_ne_binary()}.
-type assignments_to_apply() :: [assignment_to_apply()].
-type port_req_assignment() :: {kz_term:ne_binary(), kz_term:api_ne_binary(), kz_json:object()}.
-type port_req_assignments() :: [port_req_assignment()].
-type assignment_update() :: {kz_term:ne_binary(), knm_numbers:return()} |
                             {kz_term:ne_binary(), {'ok', kz_json:object()}} |
                             {kz_term:ne_binary(), {'error', any()}}.
-type assignment_updates() :: [assignment_update()].

-spec apply_assignment_updates(assignments_to_apply(), cb_context:context()) ->
          assignment_updates().
apply_assignment_updates(Updates, Context) ->
    Breaked = kz_term:break_list(lists:ukeysort(1, Updates), 100),
    PidRefs = [kz_process:spawn_monitor(fun do_apply_assignment_updates/3
                                       ,[self(), List, Context]
                                       )
               || List <- Breaked
              ],
    wait_for_pid_refs(PidRefs).

-spec do_apply_assignment_updates(pid(), assignments_to_apply(), cb_context:context()) -> 'ok'.
do_apply_assignment_updates(Collector, Updates, Context) ->
    AccountId = cb_context:account_id(Context),
    %% first try numbers,
    %% if any number not_found try ports
    MaybePorts = maybe_assign_to_app(Collector, Updates, AccountId),
    _ = maybe_assign_to_port_number(Collector, Updates, AccountId, MaybePorts),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec wait_for_pid_refs(kz_term:pid_refs()) -> assignment_updates().
wait_for_pid_refs([]) ->
    [];
wait_for_pid_refs([_|_]=PidRefs) ->
    wait_for_pid_refs(PidRefs, [], 0).

-spec wait_for_pid_refs(kz_term:pid_refs(), assignment_updates(), non_neg_integer()) -> assignment_updates().
wait_for_pid_refs([], Results, Total) ->
    lager:info("processed ~p workers",[Total]),
    Results;
wait_for_pid_refs(PidRefs, Results, Total) ->
    receive
        {'results', Result1} ->
            wait_for_pid_refs(PidRefs, Results ++ Result1, Total);
        {'DOWN', Ref, 'process', Pid, Reason} ->
            handle_down_pid_ref(Pid, Ref, PidRefs, Results, Total, Reason)
    end.

handle_down_pid_ref(Pid, Ref, PidRefs, Results, Total, Reason) ->
    case lists:keytake(Pid, 1, PidRefs) of
        'false' ->
            wait_for_pid_refs(PidRefs, Results, Total);
        {'value', {Pid, Ref}, NewPidRefs} ->
            maybe_log_down_reason(Pid, Reason),
            wait_for_pid_refs(NewPidRefs, Results, Total+1)
    end.

maybe_log_down_reason(_Pid, 'normal') -> 'ok';
maybe_log_down_reason(Pid, Reason) -> lager:info("worker pid ~p died: ~p", [Pid, Reason]).

-spec maybe_assign_to_port_number(pid(), assignments_to_apply(), kz_term:ne_binary(), kz_term:ne_binaries()) -> 'ok'.
maybe_assign_to_port_number(Collector, Updates, AccountId, ToCheck) ->
    case get_portin_numbers(AccountId, Updates, ToCheck) of
        {'ok', {PortUpdates, NotFounds}} ->
            assign_to_port_number(Collector, PortUpdates, NotFounds);
        {'error', Reason} ->
            [{N, {'error', Reason}} || N <- ToCheck]
    end.

-spec get_portin_numbers(kz_term:ne_binary(), assignments_to_apply(), kz_term:ne_binaries()) ->
          {'ok', {port_req_assignments(), assignment_updates()}} | {'error', any()}.
get_portin_numbers(AccountId, Up, ToCheck) ->
    Updates = maps:from_list(Up),
    case knm_port_request:get_portin_numbers(AccountId, ToCheck) of
        {'ok', JObjs} ->
            PortUpdates = maps:from_list(
                            [{Number, {Number, App, JObj}}
                             || JObj <- JObjs,
                                {Number, _} <- kz_json:to_proplist(kzd_port_requests:numbers(JObj, kz_json:new())),
                                App <- [maps:get(Number, Updates, 'no_assign')],
                                App =/= 'no_assign'
                            ]
                           ),
            {'ok', {maps:values(PortUpdates), [{N, {'error', 'not_found'}} || N <- ToCheck -- maps:keys(PortUpdates)]}};
        {'error', _}=Error ->
            Error
    end.

-spec assign_to_port_number(pid(), port_req_assignments(), assignment_updates()) -> 'ok'.
assign_to_port_number(Collector, PRUpdates, NotFounds) ->
    {'ok', Success, Failed} = knm_port_request:assign_to_app_bulk(PRUpdates),
    Result = [{'ok', Ok} || Ok <- Success] ++ [{'error', F} || F <- Failed] ++ NotFounds,
    Collector ! {'results', Result},
    'ok'.

-spec maybe_assign_to_app(pid(), assignments_to_apply(), kz_term:ne_binary()) -> kz_term:ne_binaries().
maybe_assign_to_app(Collector, NumUpdates, AccountId) ->
    Options = [{'auth_by', AccountId}
              ,{'batch_run', 'true'}
              ,{'dry_run', 'false'}
              ],
    Groups = maps:groups_from_list(fun({_DID, Assign}) -> Assign end
                                  ,fun({DID, _Assign}) -> DID end
                                  ,NumUpdates
                                  ),
    {ToReport, NotFounds} = maps:fold(fun(Assign, Nums, {Result, NotFoundAcc}) ->
                                              Collection = knm_ops:assign_to_app(Nums, Assign, Options),
                                              Good = format_assignment_succeeded(knm_pipe:succeeded(Collection)),
                                              {Bad, NotfoundInner} = format_assignment_failure(knm_pipe:failed(Collection)),
                                              {Result ++ Good ++ Bad,  NotFoundAcc ++ NotfoundInner}
                                      end, {[], []}, Groups),
    Collector ! {'results', ToReport},
    NotFounds.

-spec format_assignment_succeeded(knm_phone_number:pn_records()) -> assignment_updates().
format_assignment_succeeded(PhoneNumbers) ->
    [{knm_phone_number:number(PN), {'ok', PN}}
     || PN <- PhoneNumbers
    ].

-spec format_assignment_failure(knm_errors:failed()) -> {assignment_updates(), kz_term:ne_binaries()}.
format_assignment_failure(Failed) ->
    maps:fold(fun format_assignment_failure_fold/3, {[], []}, Failed).

-spec format_assignment_failure_fold(kz_term:ne_binary(), knm_errors:reason(), {assignment_updates(), kz_term:ne_binaries()}) ->
          {assignment_updates(), kz_term:ne_binaries()}.
format_assignment_failure_fold(Number, 'not_found', {Failed, NotFound}) ->
    {Failed, [Number | NotFound]};
format_assignment_failure_fold(Number, Reason, {Failed, NotFound}) ->
    {[{Number, {'error', Reason}} | Failed], NotFound}.

-spec log_assignment_updates(assignment_updates()) -> 'ok'.
log_assignment_updates(Updates) when length(Updates) > 50 ->
    lager:debug("made a giant request and expect logs in a tight loop? figure it out yourself then!");
log_assignment_updates(Updates) ->
    lists:foreach(fun log_assignment_update/1, Updates).

-spec log_assignment_update(assignment_update()) -> 'ok'.
log_assignment_update({DID, {'ok', _}}) ->
    lager:debug("successfully updated ~s", [DID]);
log_assignment_update({DID, {'error', E}}) ->
    lager:debug("failed to update ~s: ~p", [DID, E]).

-spec normalize_media_upload(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object(), kz_media_util:normalization_options()) ->
          {cb_context:context(), kz_json:object()}.
normalize_media_upload(Context, FromExt, ToExt, FileJObj, NormalizeOptions) ->
    NormalizedResult = kz_media_util:normalize_media(FromExt
                                                    ,ToExt
                                                    ,kz_json:get_binary_value(<<"contents">>, FileJObj)
                                                    ,NormalizeOptions
                                                    ),
    handle_normalized_upload(Context, FileJObj, ToExt, NormalizedResult).

-spec handle_normalized_upload(cb_context:context(), kz_json:object(), kz_term:ne_binary(), kz_media_util:normalized_media()) ->
          {cb_context:context(), kz_json:object()}.
handle_normalized_upload(Context, FileJObj, ToExt, {'ok', Contents}) ->
    lager:debug("successfully normalized to ~s", [ToExt]),
    {Major, Minor, _} = cow_mimetypes:all(<<"foo.", (ToExt)/binary>>),

    NewFileJObj = kz_json:set_values([{[<<"headers">>, <<"content_type">>], <<Major/binary, "/", Minor/binary>>}
                                     ,{[<<"headers">>, <<"content_length">>], iolist_size(Contents)}
                                     ,{<<"contents">>, Contents}
                                     ]
                                    ,FileJObj
                                    ),

    UpdatedContext = cb_context:setters(Context
                                       ,[{fun cb_context:set_req_files/2, [{<<"original_media">>, FileJObj}
                                                                          ,{<<"normalized_media">>, NewFileJObj}
                                                                          ]
                                         }
                                        ,{fun cb_context:set_doc/2, kz_json:delete_key(<<"normalization_error">>, cb_context:doc(Context))}
                                        ]
                                       ),
    {UpdatedContext, NewFileJObj};
handle_normalized_upload(Context, FileJObj, ToExt, {'error', _R}) ->
    lager:warning("failed to convert to ~s: ~p", [ToExt, _R]),
    Reason = <<"failed to communicate with conversion utility">>,
    UpdatedDoc = kz_json:set_value(<<"normalization_error">>, Reason, cb_context:doc(Context)),
    UpdatedContext = cb_context:set_doc(Context, UpdatedDoc),
    {UpdatedContext, FileJObj}.

%% Before, we used cb_context:req_value/2 which searched "data" then the envelope
%% but we want "action" on the envelope to be respected for these PUTs against
%% /channels or /conferences, so we reverse the order here (just in case people are
%% only putting "action" in "data"
-spec get_request_action(cb_context:context()) -> kz_term:api_ne_binary().
get_request_action(Context) ->
    kz_json:find(<<"action">>, [cb_context:req_json(Context)
                               ,cb_context:req_data(Context)
                               ]
                ).

-spec normalize_alphanum_name(kz_term:api_binary() | cb_context:context()) -> cb_context:context() | kz_term:api_binary().
normalize_alphanum_name('undefined') ->
    'undefined';
normalize_alphanum_name(Name) when is_binary(Name) ->
    re:replace(kz_term:to_lower_binary(Name), <<"[^a-z0-9]">>, <<>>, ['global', {'return', 'binary'}]);
normalize_alphanum_name(Context) ->
    Doc = cb_context:doc(Context),
    Name = kz_json:get_ne_binary_value(<<"name">>, Doc),
    cb_context:set_doc(Context, kz_json:set_value(<<"pvt_alphanum_name">>, normalize_alphanum_name(Name), Doc)).

-spec maybe_convert_numbers_to_list(cb_context:context()) -> cb_context:context().
maybe_convert_numbers_to_list(Context) ->
    case maybe_requesting_csv(Context) of
        'true' ->
            Numbers = kz_json:get_json_value(<<"numbers">>, cb_context:resp_data(Context)),
            NewRespData = kz_json:foldl(fun convert_numbers_to_list/3, [], Numbers),
            cb_context:set_resp_data(Context, NewRespData);
        'false' -> Context
    end.

-spec maybe_requesting_csv(cb_context:context()) -> boolean().
maybe_requesting_csv(Context) ->
    case cb_context:req_header(Context, <<"accept">>) of
        <<"text/csv">> -> 'true';
        _ -> <<"csv">> =:= cb_context:req_param(Context, <<"accept">>)
    end.

-spec convert_numbers_to_list(kz_term:ne_binary(), kz_json:object(), kz_json:object()) -> kz_json:objects().
convert_numbers_to_list(Key, Value, JObj) ->
    [kz_json:from_list([{<<"number">>, Key} | kz_json:recursive_to_proplist(Value)])
    | JObj
    ].
