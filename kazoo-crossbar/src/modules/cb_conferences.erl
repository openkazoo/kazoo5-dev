%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Conferences module
%%% Handle client requests for conference documents
%%%
%%% URI schema:
%%% /v2/accounts/{AccountId}/conferences
%%% /v2/accounts/{AccountId}/conferences/{ConferenceID}
%%% /v2/accounts/{AccountId}/conferences/{ConferenceID}/participants
%%% /v2/accounts/{AccountId}/conferences/{ConferenceID}/participants/{ParticipantId}
%%% /v2/accounts/{AccountId}/conferences/{ConferenceID}/email_invite
%%%
%%%
%%% @author Karl Anderson
%%% @author James Aimonetti
%%% @author Roman Galeev
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_conferences).

-export([init/0
        ,allowed_methods/0, allowed_methods/1, allowed_methods/2, allowed_methods/3
        ,resource_exists/0, resource_exists/1, resource_exists/2, resource_exists/3
        ,validate/1, validate/2, validate/3, validate/4
        ,validate_resource/2
        ,post/2
        ,put/1, put/2, put/3, put/4
        ,patch/2
        ,delete/2
        ]).

-ifdef(TEST).
-export([build_valid_endpoints/3]).
-endif.

-include("crossbar.hrl").
-include_lib("nklib/include/nklib.hrl").

-define(CB_LIST_BY_NUMBER, <<"conference/listing_by_number">>).

-define(EMAIL_INVITE, <<"email_invite">>).
-define(PARTICIPANTS, <<"participants">>).
-define(MUTE, <<"mute">>).
-define(UNMUTE, <<"unmute">>).
-define(DEAF, <<"deaf">>).
-define(UNDEAF, <<"undeaf">>).
-define(KICK, <<"kick">>).
-define(RELATE, <<"relate">>).
-define(PLAY, <<"play">>).

-define(PUT_ACTION, <<"action">>).

-define(MIN_DIGITS_FOR_DID, 5).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.conferences">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.conferences">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.conferences">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.validate_resource.conferences">>, ?MODULE, 'validate_resource'),
    _ = crossbar_bindings:bind(<<"*.execute.put.conferences">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.conferences">>, ?MODULE, 'post'),
    _ = crossbar_bindings:bind(<<"*.execute.patch.conferences">>, ?MODULE, 'patch'),
    _ = crossbar_bindings:bind(<<"*.execute.delete.conferences">>, ?MODULE, 'delete'),
    'ok'.

%%%=============================================================================
%%% REST API Callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() -> [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_ConferenceId) -> [?HTTP_GET, ?HTTP_PATCH, ?HTTP_DELETE, ?HTTP_POST, ?HTTP_PUT].

-spec allowed_methods(path_token(), path_token()) -> http_methods().
allowed_methods(_ConferenceId, ?PARTICIPANTS) -> [?HTTP_GET, ?HTTP_PUT];
allowed_methods(_ConferenceId, ?EMAIL_INVITE) -> [?HTTP_PUT].

-spec allowed_methods(path_token(), path_token(), path_token()) -> http_methods().
allowed_methods(_ConferenceId, ?PARTICIPANTS, _ParticipantId) -> [?HTTP_GET, ?HTTP_PUT].

-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_) -> 'true'.

-spec resource_exists(path_token(), path_token()) -> 'true'.
resource_exists(_, _) -> 'true'.

-spec resource_exists(path_token(), path_token(), path_token()) -> 'true'.
resource_exists(_, _, _) -> 'true'.

-spec validate_resource(cb_context:context(), path_token()) -> cb_context:context().
validate_resource(Context, ConferenceId) ->
    validate_resource_conference(cb_context:req_verb(Context), Context, ConferenceId).

-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_conferences(cb_context:req_verb(Context), Context).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ConferenceId) ->
    validate_conference(cb_context:req_verb(Context), Context, ConferenceId).

-spec validate(cb_context:context(), path_token(), path_token()) -> cb_context:context().
validate(Context, ConferenceId, ?PARTICIPANTS) ->
    validate_participants(cb_context:req_verb(Context), Context, ConferenceId);
validate(Context, ConferenceId, ?EMAIL_INVITE) ->
    validate_email_invite(cb_context:req_verb(Context), Context, ConferenceId).

-spec validate(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
validate(Context, ConferenceId, ?PARTICIPANTS, ParticipantId) ->
    validate_participant(cb_context:req_verb(Context), Context, ConferenceId, ParticipantId).

%%%=============================================================================
%%% Request object validators
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_conferences(http_method(), cb_context:context()) -> cb_context:context().
validate_conferences(?HTTP_GET, Context) ->
    Options = [{'doc_type', <<"conference">>}
              ,{'mapper', crossbar_view:get_value_fun()}
              ,{'no_batch', 'true'}
              ],
    Selector = [{'start', [{<<"doc_type">>, <<"conference">>}]}
               ,{'end', [{<<"doc_type">>, <<"conference">>}]}
               ],
    LoadedContext = crossbar_view:find(Context, <<"crossbar_listings/by_type_id">>, Selector, Options),
    case cb_context:resp_status(LoadedContext) of
        'success' ->
            maybe_add_running_conferences(LoadedContext);
        _ ->
            LoadedContext
    end;
validate_conferences(?HTTP_PUT, Context) ->
    create_conference(Context).

-spec validate_resource_conference(http_method(), cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
validate_resource_conference(?HTTP_GET, Context, ConferenceId) ->
    Context1 = maybe_load_conference(ConferenceId, Context),
    case cb_context:resp_status(Context1) of
        'success' ->
            Context2 = enrich_conference(Context1, ConferenceId),
            cb_context:store(Context2, 'conference_data', cb_context:get_metadata(Context2));
        _Else ->
            Context1
    end;
validate_resource_conference(_, Context, _ConferenceId) ->
    Context.

-spec validate_conference(http_method(), cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
validate_conference(?HTTP_GET, Context, ConferenceId) ->
    Context1 = maybe_load_conference(ConferenceId, Context),
    case cb_context:resp_status(Context1) of
        'success' ->
            enrich_conference(Context1, ConferenceId);
        _Else ->
            Context1
    end;
validate_conference(?HTTP_POST, Context, ConferenceId) ->
    update_conference(ConferenceId, Context);
validate_conference(?HTTP_PUT, Context, ConferenceId) ->
    maybe_load_conference(ConferenceId, Context);
validate_conference(?HTTP_PATCH, Context, ConferenceId) ->
    patch_conference(ConferenceId, Context);
validate_conference(?HTTP_DELETE, Context, ConferenceId) ->
    load_conference(ConferenceId, Context).

-spec validate_participants(http_method(), cb_context:context(), path_token()) ->
          cb_context:context().
validate_participants(?HTTP_GET, Context0, ConferenceId) ->
    Context1 = maybe_load_conference(ConferenceId, Context0),
    case cb_context:resp_status(Context1) of
        'success' -> enrich_participants(ConferenceId, Context1);
        _Else -> Context1
    end;
validate_participants(?HTTP_PUT, Context, ConferenceId) ->
    maybe_load_conference(ConferenceId, Context).

-spec validate_participant(http_method(), cb_context:context(), path_token(), path_token()) ->
          cb_context:context().
validate_participant(?HTTP_GET, Context0, ConferenceId, ParticipantId) ->
    Context1 = maybe_load_conference(ConferenceId, Context0),
    case cb_context:resp_status(Context1) of
        'success' -> enrich_participant(ParticipantId, ConferenceId, Context1);
        _Else -> Context1
    end;
validate_participant(?HTTP_PUT, Context, ConferenceId, _ParticipantId) ->
    maybe_load_conference(ConferenceId, Context).

-spec validate_email_invite(http_method(), cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
validate_email_invite(?HTTP_PUT, Context, ConferenceId) ->
    Schema = <<"conferences.email_invite">>,
    OnSuccess = fun(Acc) -> lager:warning("validation for ~s passed", [Schema]), Acc end, %% TODO: decrease log level to debug.
    case kzd_module_utils:validate_schema(Schema, {cb_context:req_data(Context), []}, OnSuccess) of
        {ReqData, []} ->
            {'ok', Conf} = kz_datamgr:open_cache_doc(cb_context:account_id(Context), ConferenceId),
            crossbar_doc:handle_datamgr_success(ReqData
                                               ,cb_context:store(Context, 'conference_doc', Conf)
                                               );
        {_ReqData, Errors} ->
            lager:info("validation errors on ~s: ~p", [Schema, Errors]),
            cb_context:add_doc_validation_errors(Context, Errors)
    end.

-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, _ConferenceId) ->
    crossbar_doc:save(Context).

-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_doc:save(Context).

-spec put(cb_context:context(), path_token()) -> cb_context:context().
put(Context, ConferenceId) ->
    handle_conference_action(Context, ConferenceId, cb_modules_util:get_request_action(Context)).

-spec put(cb_context:context(), path_token(), path_token()) -> cb_context:context().
put(Context, ConferenceId, ?PARTICIPANTS) ->
    Action = cb_context:req_value(Context, ?PUT_ACTION),
    handle_participants_action(Context, ConferenceId, Action);
put(Context, _ConferenceId, ?EMAIL_INVITE) ->
    kapps_notify_publisher:cast(build_email_invite_kapi_req(Context)
                               ,fun kapi_notifications:publish_email_invite/1
                               ),
    crossbar_util:response(<<"request accepted">>, Context).


-spec put(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
put(Context, ConferenceId, ?PARTICIPANTS, ParticipantId) ->
    Action = cb_context:req_value(Context, ?PUT_ACTION),
    participant_action(Context, ConferenceId, ParticipantId, Action).

participant_action(Context, ConferenceId, ParticipantId, ?PLAY) ->
    play(Context, ConferenceId, ParticipantId, cb_context:req_value(Context, <<"data">>));

participant_action(Context, ConferenceId, ParticipantId, Action) ->
    perform_participant_action(conference(ConferenceId), Action, kz_term:to_integer(ParticipantId)),
    crossbar_util:response_202(<<"ok">>, Context).

-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, _) ->
    crossbar_doc:save(Context).

-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _) ->
    crossbar_doc:delete(Context).

%%%=============================================================================
%%% Conference validation helpers
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec maybe_load_conference(path_token(), cb_context:context()) -> cb_context:context().
maybe_load_conference(ConferenceId, Context) ->
    maybe_build_conference(ConferenceId, load_conference(ConferenceId, Context)).

-spec maybe_build_conference(path_token(), cb_context:context()) -> cb_context:context().
maybe_build_conference(ConferenceId, Context) ->
    case cb_context:resp_status(Context) of
        'success' -> Context; % loaded an existing conference
        _ ->
            lager:info("building an ad-hoc conference for ~s", [ConferenceId]),
            build_conference(ConferenceId, Context)
    end.

-spec build_conference(path_token(), cb_context:context()) -> cb_context:context().
build_conference(ConferenceId, Context) ->
    Conference = kz_doc:set_id(kzd_conference:new(), ConferenceId),
    Merged = kz_json:merge(Conference, cb_context:req_data(Context)),
    crossbar_doc:handle_datamgr_success(Merged, Context).

-spec load_conference(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
load_conference(ConferenceId, Context) ->
    crossbar_doc:load(ConferenceId, Context, ?TYPE_CHECK_OPTION(kzd_conference:type())).

-spec create_conference(cb_context:context()) -> cb_context:context().
create_conference(Context) ->
    OnSuccess = fun(C) -> validate_numbers('undefined', C) end,
    cb_context:validate_request_data(<<"conferences">>, Context, OnSuccess).

-spec update_conference(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
update_conference(ConferenceId, Context) ->
    OnSuccess = fun(C) -> validate_numbers(ConferenceId, C) end,
    cb_context:validate_request_data(<<"conferences">>, Context, OnSuccess).

-spec patch_conference(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
patch_conference(ConferenceId, Context) ->
    crossbar_doc:patch_and_validate(ConferenceId, Context, fun update_conference/2).

-spec on_successful_validation(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
on_successful_validation('undefined', Context) ->
    cb_context:update_doc(Context, {fun kz_doc:set_type/2, <<"conference">>});
on_successful_validation(ConferenceId, Context) ->
    crossbar_doc:load_merge(ConferenceId, Context, ?TYPE_CHECK_OPTION(<<"conference">>)).

%%------------------------------------------------------------------------------
%% @doc Create a new conference document with the data provided, if it is valid
%% @end
%%------------------------------------------------------------------------------
-spec validate_numbers(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
validate_numbers(Id, Context) ->
    Doc = cb_context:doc(Context),
    DbDoc = cb_context:fetch(Context, 'db_doc', kz_json:new()),

    OldConf = kzd_conferences:conference_numbers(DbDoc, []),
    OldMember = kzd_conferences:member_numbers(DbDoc, []),
    OldModerator = kzd_conferences:moderator_numbers(DbDoc, []),
    OldKeys = OldConf ++ OldMember ++ OldModerator,

    NewConf = kzd_conferences:conference_numbers(Doc, []),
    NewMember = kzd_conferences:member_numbers(Doc, []),
    NewModerator = kzd_conferences:moderator_numbers(Doc, []),
    NewKeys = NewConf ++ NewMember ++ NewModerator,

    validate_numbers(Id, Context, NewKeys, lists:usort(OldKeys) =:= lists:usort(NewKeys)).

-spec validate_numbers(kz_term:api_binary(), cb_context:context(), kz_term:ne_binaries(), boolean()) ->
          cb_context:context().
validate_numbers(Id, Context, _, 'true') ->
    validate_unique_name(Id, Context);
validate_numbers(Id, Context, Keys, 'false') ->
    AccountId = cb_context:account_id(Context),
    case kz_datamgr:get_results(AccountId, ?CB_LIST_BY_NUMBER, [{'keys', Keys}]) of
        {'error', _R} ->
            cb_context:add_system_error('datastore_fault', Context);
        {'ok', []} ->
            validate_unique_name(Id, Context);
        {'ok', JObjs} when Id =:= 'undefined' ->
            invalid_numbers(Context, kz_datamgr:get_result_keys(JObjs));
        {'ok', JObjs} ->
            case [JObj || JObj <- JObjs, kz_doc:id(JObj) =/= Id] of
                [] ->
                    validate_unique_name(Id, Context);
                OtherJObjs ->
                    invalid_numbers(Context, kz_datamgr:get_result_keys(OtherJObjs))
            end
    end.

-spec invalid_numbers(cb_context:context(), kz_term:ne_binaries()) -> cb_context:context().
invalid_numbers(Context, Keys) ->
    Numbers = kz_binary:join(Keys),
    Error = kz_json:from_list([{<<"message">>, <<"Numbers already in use">>}
                              ,{<<"cause">>, Numbers}
                              ]),
    cb_context:add_validation_error([<<"numbers">>], <<"unique">>, Error, Context).

-spec validate_unique_name(kz_term:api_ne_binary(), cb_context:context()) -> cb_context:context().
validate_unique_name(Id, Context) ->
    Doc = cb_context:doc(Context),
    DbDoc = cb_context:fetch(Context, 'db_doc', kz_json:new()),
    validate_unique_name(Id, Context, kzd_conferences:name(DbDoc), kzd_conferences:name(Doc)).

-spec validate_unique_name(kz_term:api_ne_binary(), cb_context:context(), kz_term:api_ne_binary(), kz_term:ne_binary()) -> cb_context:context().
validate_unique_name(Id, Context, Name, Name) ->
    on_successful_validation(Id, Context);
validate_unique_name(Id, Context, _OldName, NewName) ->
    Options = [{'doc_type', <<"conference">>}
              ,{'no_batch', 'true'}
              ],
    Selector = [{'key', [{<<"doc_type">>, <<"conference">>}, {<<"name">>, NewName}]}],
    case kz_view:find(cb_context:db_name(Context), <<"crossbar_listings/by_type_name">>, Selector, Options) of
        {'ok', []} ->
            on_successful_validation(Id, Context);
        {'ok', _} when Id =:= 'undefined' ->
            invalid_unique_name(Context, NewName);
        {'ok', JObjs} ->
            case [JObj || JObj <- JObjs, kz_doc:id(JObj) =/= Id] of
                [] ->
                    on_successful_validation(Id, Context);
                _ ->
                    invalid_unique_name(Context, NewName)
            end;
        {'error', Reason} ->
            crossbar_doc:handle_datamgr_errors(Reason, <<"crossbar_listings/by_type_name">>, Context)
    end.

-spec invalid_unique_name(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
invalid_unique_name(Context, Name) ->
    Error = kz_json:from_list([{<<"message">>, <<"public conference needs a system-wide unique name">>}
                              ,{<<"cause">>, Name}
                              ]),
    cb_context:add_validation_error([<<"name">>], <<"unique">>, Error, Context).

%%%=============================================================================
%%% ?EMAIL_INVITE request helpers
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec build_email_invite_kapi_req(cb_context:context()) -> kz_term:proplist().
build_email_invite_kapi_req(Context) ->
    Types = [<<"Conference Call-In Number">>, <<"MainConference">>],
    {'ok', Callflows} = kz_datamgr:get_results(cb_context:db_name(Context)
                                              ,<<"crossbar_listings/by_type_name">>
                                              ,[{'keys', [[kzd_callflows:type(), T] || T <- Types]}
                                               ,{'result_key', <<"doc">>}
                                               ,'include_docs'
                                               ]
                                              ),
    Conf = cb_context:fetch(Context, 'conference_doc'),
    ReqData = cb_context:req_data(Context),
    [{<<"Conference-ID">>, kz_doc:id(Conf)}
    ,{<<"Conference-Numbers">>, kzd_conferences:conference_numbers(Conf)}
    ,{<<"Conference-Name">>, kzd_conferences:name(Conf)}
    ,{<<"Conference-Link">>, kz_json:get_binary_value(<<"conference_link">>, ReqData)}
    ,{<<"Conference-Call-In-Numbers">>, [kz_json:get_binary_value(<<"numbers">>, CF) || CF <- Callflows]}
    ,{<<"Conference-Participant-Pins">>, kzd_conferences:member_pins(Conf)}
    ,{<<"Invite-Message">>, kz_json:get_binary_value(<<"invite_message">>, ReqData)}
    ,{<<"Guests">>, kz_json:get_list_value(<<"guests">>, ReqData)}
    | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
    ].

%%%=============================================================================
%%% Conference Actions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle_conference_action(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary()) -> cb_context:context().
handle_conference_action(Context, ConferenceId, <<"lock">>) ->
    kapps_conference_command:lock(conference(ConferenceId)),
    crossbar_util:response_202(<<"ok">>, Context);
handle_conference_action(Context, ConferenceId, <<"unlock">>) ->
    kapps_conference_command:unlock(conference(ConferenceId)),
    crossbar_util:response_202(<<"ok">>, Context);
handle_conference_action(Context, ConferenceId, ?PLAY) ->
    play(Context, ConferenceId, cb_context:req_value(Context, <<"data">>));
handle_conference_action(Context, ConferenceId, <<"dial">>) ->
    dial(Context, ConferenceId, cb_context:req_value(Context, <<"data">>));
handle_conference_action(Context, ConferenceId, <<"record">>) ->
    record_conference(Context, ConferenceId, cb_context:req_value(Context, <<"data">>));
handle_conference_action(Context, ConferenceId, <<"vars">>) ->
    vars_conference(Context, ConferenceId);
handle_conference_action(Context, ConferenceId, Action) ->
    lager:warning("unhandled conference id ~p action: ~p", [ConferenceId, Action]),
    Error = kz_json:from_list([{<<"message">>, <<"Value not found in enumerated list of values">>}
                              ,{<<"target">>, [<<"lock">>, <<"unlock">>, ?PLAY, <<"dial">>, <<"record">>, <<"vars">>]}
                              ,{<<"value">>, Action}
                              ]),
    cb_context:add_validation_error(<<"action">>, <<"enum">>, Error, Context).

-spec vars_conference(cb_context:context(), kz_term:ne_binary()) ->
          cb_context:context().
vars_conference(Context, ConferenceId) ->
    CCVs = kz_json:from_list(cb_modules_util:ccvs_from_context(Context)),
    API = [{<<"Conference-ID">>, ConferenceId}
          ,{<<"Custom-Conference-Vars">>, CCVs}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    lager:info("API: ~p", [API]),
    _ = kz_amqp_worker:cast(API, fun(P) -> kapi_conference:publish_vars(ConferenceId, P) end),
    crossbar_util:response_202(<<"vars sent">>, Context).

-spec record_conference(cb_context:context(), kz_term:ne_binary(), kz_term:api_object()) ->
          cb_context:context().
record_conference(Context, _ConferenceId, 'undefined') ->
    data_required(Context, <<"record">>);
record_conference(Context, ConferenceId, RecordingData) ->
    toggle_recording(Context, ConferenceId, kz_json:get_ne_binary_value(<<"action">>, RecordingData)).

-spec toggle_recording(cb_context:context(), kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          cb_context:context().
toggle_recording(Context, ConferenceId, <<"start">>) ->
    lager:info("starting the recording of conference ~s", [ConferenceId]),
    kapps_conference_command:record(conference(ConferenceId)),
    crossbar_util:response_202(<<"starting recording">>, Context);
toggle_recording(Context, ConferenceId, <<"stop">>) ->
    lager:info("stopping the recording of conference ~s", [ConferenceId]),
    kapps_conference_command:recordstop(conference(ConferenceId)),
    crossbar_util:response_202(<<"stopping recording">>, Context);
toggle_recording(Context, _ConferenceId, 'undefined') ->
    cb_context:add_validation_error([<<"data">>, <<"action">>]
                                   ,<<"required">>
                                   ,kz_json:from_list([{<<"message">>, <<"recording requires an action">>}])
                                   ,Context
                                   );
toggle_recording(Context, _ConferenceId, Action) ->
    lager:debug("invalid action: ~p", [Action]),
    cb_context:add_validation_error([<<"data">>, <<"action">>]
                                   ,<<"enum">>
                                   ,kz_json:from_list(
                                      [{<<"message">>, <<"Value not found in enumerated list of values">>}
                                      ,{<<"target">>, [<<"start">>, <<"stop">>]}
                                      ,{<<"value">>, Action}
                                      ])
                                   ,Context
                                   ).

-spec play(cb_context:context(), path_token(), kz_term:api_object()) ->
          cb_context:context().
play(Context, _ConferenceId, 'undefined') ->
    data_required(Context, <<"play">>);
play(Context, ConferenceId, Data) ->
    play_media(Context, ConferenceId, kz_json:get_ne_binary_value(<<"media_id">>, Data)).

-spec play(cb_context:context(), path_token(), pos_integer(), kz_term:api_object()) ->
          cb_context:context().
play(Context, _ConferenceId, _ParticipantId, 'undefined') ->
    data_required(Context, <<"play">>);
play(Context, ConferenceId, ParticipantId, Data) ->
    play_media(Context, ConferenceId, ParticipantId, kz_json:get_ne_binary_value(<<"media_id">>, Data)).

-spec data_required(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
data_required(Context, Action) ->
    cb_context:add_validation_error(<<"data">>
                                   ,<<"required">>
                                   ,kz_json:from_list([{<<"message">>, <<"action '", Action/binary, "' requires a data object">>}])
                                   ,Context
                                   ).

-spec play_media(cb_context:context(), path_token(), kz_term:api_ne_binary()) ->
          cb_context:context().
play_media(Context, _ConferenceId, 'undefined') ->
    media_id_required(Context);
play_media(Context, ConferenceId, MediaId) ->
    case kz_media_util:media_path(MediaId, cb_context:account_id(Context)) of
        'undefined' ->
            media_id_invalid(Context, MediaId);
        Media ->
            lager:info("playing ~s to conference ~s", [Media, ConferenceId]),
            kapps_conference_command:play(Media, conference(ConferenceId)),
            crossbar_util:response_202(<<"ok">>, Context)
    end.

-spec play_media(cb_context:context(), path_token(), pos_integer(), kz_term:api_ne_binary()) ->
          cb_context:context().
play_media(Context, _ConferenceId, _ParticipantId, 'undefined') ->
    media_id_required(Context);
play_media(Context, ConferenceId, ParticipantId, MediaId) ->
    case kz_media_util:media_path(MediaId, cb_context:account_id(Context)) of
        'undefined' ->
            media_id_invalid(Context, MediaId);
        Media ->
            lager:info("playing ~s to conference ~s participant ~p", [Media, ConferenceId, ParticipantId]),
            kapps_conference_command:play(Media, ParticipantId, conference(ConferenceId)),
            crossbar_util:response_202(<<"ok">>, Context)
    end.

-spec media_id_invalid(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
media_id_invalid(Context, MediaId) ->
    crossbar_util:response_bad_identifier(MediaId, Context).

-spec media_id_required(cb_context:context()) -> cb_context:context().
media_id_required(Context) ->
    cb_context:add_validation_error([<<"data">>, <<"media_id">>]
                                   ,<<"required">>
                                   ,kz_json:from_list([{<<"message">>, <<"action 'play' requires a media ID or URL">>}])
                                   ,Context
                                   ).

-spec dial(cb_context:context(), path_token(), kz_term:api_object()) -> cb_context:context().
dial(Context, _ConferenceId, 'undefined') ->
    data_required(Context, <<"dial">>);
dial(Context, ConferenceId, Data) ->
    case build_valid_endpoints(cb_context:set_resp_status(Context, 'success'), ConferenceId, Data) of
        {Context1, []} -> error_no_endpoints(Context1);
        {Context1, Endpoints} ->
            case cb_context:has_errors(Context1) of
                'true' -> Context1;
                'false' ->
                    Resp = exec_dial_endpoints(Context1, ConferenceId, Data, Endpoints),
                    crossbar_util:response_202(<<"attempted dial">>, Resp, Context1)
            end
    end.

-spec build_valid_endpoints(cb_context:context(), kz_term:ne_binary(), kz_json:object()) ->
          {cb_context:context(), kz_json:objects()}.
build_valid_endpoints(Context, ConferenceId, Data) ->
    case kz_json_schema:validate(<<"conferences.dial">>, Data) of
        {'ok', ValidData} ->
            build_endpoints_to_dial(Context, ConferenceId, kz_json:get_list_value(<<"endpoints">>, ValidData));
        {'error', Errors} ->
            lager:info("dial data failed to validate"),
            {cb_context:failed(Context, Errors), []}
    end.

-spec exec_dial_endpoints(cb_context:context(), path_token(), kz_json:object(), kz_json:objects()) ->
          kz_json:object().
exec_dial_endpoints(Context, ConferenceId, Data, ToDial) ->
    Conference = cb_context:doc(Context),
    CAVs = kz_json:from_list(cb_modules_util:cavs_from_context(Context)),
    Timeout = kz_json:get_integer_value(<<"timeout">>, Data, ?BRIDGE_DEFAULT_SYSTEM_TIMEOUT_S),
    TargetCallId = kz_json:get_ne_binary_value(<<"target_call_id">>, Data),

    Command = [{<<"Account-ID">>, cb_context:account_id(Context)}
              ,{<<"Application-Name">>, <<"dial">>}
              ,{<<"Caller-ID-Name">>, kz_json:get_ne_binary_value(<<"caller_id_name">>, Data, kz_json:get_ne_binary_value(<<"name">>, Conference))}
              ,{<<"Caller-ID-Number">>, kz_json:get_ne_binary_value(<<"caller_id_number">>, Data)}
              ,{<<"Conference-ID">>, ConferenceId}
              ,{<<"Custom-Application-Vars">>, CAVs}
              ,{<<"Endpoints">>, ToDial}
              ,{<<"Msg-ID">>, cb_context:req_id(Context)}
              ,{<<"Outbound-Call-ID">>, kz_json:get_ne_binary_value(<<"outbound_call_id">>, Data)}
              ,{<<"Participant-Flags">>, kz_json:get_list_value(<<"participant_flags">>, Data)}
              ,{<<"Profile-Name">>, kz_json:find(<<"profile_name">>, [Data, Conference])}
              ,{<<"Target-Call-ID">>, TargetCallId}
              ,{<<"Timeout">>, Timeout}
              | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
              ],

    Zone = zone(ConferenceId, TargetCallId),
    case kz_amqp_worker:call(Command
                            ,fun(P) -> kapi_conference:publish_dial(Zone, P) end
                            ,fun dial_resp/1
                            ,(Timeout * ?MILLISECONDS_IN_SECOND) * length(ToDial)
                            )
    of
        {'ok', Resp} ->
            case kz_api:event_name(Resp) of
                <<"error">> ->
                    kz_json:from_list([{<<"status">>, <<"error">>}
                                      ,{<<"message">>, kz_json:get_ne_binary_value(<<"Error-Message">>, Resp, <<"unknown error">>)}
                                      ]);
                <<"command">> ->
                    kz_json:normalize(kz_api:remove_defaults(Resp))
            end;
        {'error', 'timeout'} ->
            kz_json:from_list([{<<"status">>, <<"error">>}
                              ,{<<"message">>, <<"timed out trying to dial endpoints">>}
                              ]);
        {'error', _E} ->
            lager:info("failed to hear back about the dial: ~p", [_E]),
            kz_json:from_list([{<<"status">>, <<"error">>}
                              ,{<<"message">>, <<"conference dial failed to find a media server">>}
                              ])
    end.

dial_resp(JObj) ->
    kapi_conference:dial_resp_v(JObj)
        orelse kapi_conference:conference_error_v(JObj).

-spec zone(kz_term:ne_binary(), kz_term:api_ne_binary()) -> kz_term:ne_binary().
zone(ConferenceId, 'undefined') ->
    discover_conference_zone(ConferenceId);
zone(ConferenceId, TargetCallId) ->
    Req = [{<<"Call-ID">>, TargetCallId}
          ,{<<"Fields">>, <<"all">>}
          ,{<<"Active-Only">>, 'true'}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],

    case kz_amqp_worker:call_collect(Req
                                    ,fun kapi_call:publish_query_channels_req/1
                                    ,{'ecallmgr', fun kapi_call:query_channels_resp_v/1}
                                    )
    of
        {'ok', [Resp|_]} ->
            NodeInfo = kz_nodes:node_to_json(kz_api:node(Resp)),
            Zone = kz_json:get_ne_binary_value(<<"zone">>, NodeInfo, kz_config:zone('binary')),
            lager:info("got back channel resp, using target ~s zone ~s", [TargetCallId, Zone]),
            Zone;
        _E ->
            lager:info("target ~s not found (~p), checking conference id ~s"
                      ,[TargetCallId, _E, ConferenceId]
                      ),
            discover_conference_zone(ConferenceId)
    end.

-spec discover_conference_zone(kz_term:ne_binary()) -> kz_term:ne_binary().
discover_conference_zone(ConferenceId) ->
    case kapps_conference_command:search(ConferenceId, ?APP_NAME, ?APP_VERSION) of
        {'error', _E} ->
            lager:debug("failed to search for ~s: ~p", [ConferenceId, _E]),
            kz_config:zone('binary');
        {'ok', SearchResp} ->
            Zone = kz_json:get_ne_binary_value(<<"Zone">>, SearchResp, kz_config:zone('binary')),
            lager:debug("found conference ~s in zone ~s", [ConferenceId, Zone]),
            Zone
    end.

-record(build_acc, {endpoints = [] :: kz_json:objects()
                   ,call :: kapps_call:call()
                   ,context :: cb_context:context()
                   ,element = 1 :: pos_integer()
                   }).
-type build_acc() :: #build_acc{}.

-define(BUILD_ACC(Es, Call, Context, El)
       ,#build_acc{endpoints=Es
                  ,call=Call
                  ,context=Context
                  ,element=El
                  }
       ).

-spec build_endpoints_to_dial(cb_context:context(), path_token(), kz_term:ne_binaries()) ->
          {cb_context:context(), kz_json:objects()}.
build_endpoints_to_dial(Context, ConferenceId, Endpoints) ->
    ?BUILD_ACC(ToDial, _Call, Context1, _Element) =
        lists:foldl(fun build_endpoint/2
                   ,?BUILD_ACC([], create_call(Context, ConferenceId), Context, 1)
                   ,Endpoints
                   ),
    {Context1, ToDial}.

-spec error_no_endpoints(cb_context:context()) -> cb_context:context().
error_no_endpoints(Context) ->
    cb_context:add_validation_error([<<"data">>, <<"endpoints">>]
                                   ,<<"minItems">>
                                   ,kz_json:from_list([{<<"message">>, <<"endpoints failed to resolve to route-able destinations">>}
                                                      ,{<<"target">>, 1}
                                                      ])
                                   ,Context
                                   ).

-spec create_call(cb_context:context(), kz_term:ne_binary()) -> kapps_call:call().
create_call(Context, ConferenceId) ->
    Routines =
        [{F, V}
         || {F, V} <- [{fun kapps_call:set_account_id/2, cb_context:account_id(Context)}
                      ,{fun kapps_call:set_resource_type/2, <<"audio">>}
                      ,{fun kapps_call:set_authorizing_id/2, ConferenceId}
                      ,{fun kapps_call:set_authorizing_type/2, <<"conference">>}
                      ],
            'undefined' =/= V
        ],
    kapps_call:exec(Routines, kapps_call:new()).

-spec build_endpoint(kz_term:ne_binary(), build_acc()) -> build_acc().
build_endpoint(<<"sip:", _/binary>>=URI, ?BUILD_ACC(_, _, _, _)=Acc) ->
    lager:info("building SIP endpoint ~s", [URI]),
    build_sip_endpoint(URI, Acc);
build_endpoint(<<_:32/binary>>=EndpointId, ?BUILD_ACC(Endpoints, Call, Context, Element)) ->
    Properties = kz_json:from_list([{<<"source">>, kz_term:to_binary(?MODULE)}
                                   ,{<<"endpoint_module_version">>, <<"v5">>}
                                   ]),
    case kz_endpoint:build(EndpointId, Properties, Call) of
        {'ok', Legs} -> ?BUILD_ACC(Endpoints ++ Legs, Call, Context, Element+1);
        {'error', _E} ->
            lager:info("failed to build endpoint ~s: ~p", [EndpointId, _E]),
            ?BUILD_ACC(Endpoints, Call, Context, Element+1)
    end;
build_endpoint(?NE_BINARY=Number, ?BUILD_ACC(Endpoints, Call, Context, Element)=Acc) ->
    case knm_converters:is_reconcilable(Number)
        orelse byte_size(Number) < ?MIN_DIGITS_FOR_DID
    of
        'true' -> build_number_endpoint(Number, Acc);
        'false' ->
            ?BUILD_ACC(Endpoints
                      ,Call
                      ,add_not_endpoint_error(Context, Element)
                      ,Element+1
                      )
    end;
build_endpoint(Device, ?BUILD_ACC(Endpoints, Call, Context, Element)) ->
    DeviceWithId = kz_json:insert_value(<<"id">>, kz_binary:rand_hex(16), Device),
    Properties = kz_json:from_list([{<<"source">>, kz_term:to_binary(?MODULE)}]),
    case kz_endpoint:build(DeviceWithId, Properties, Call) of
        {'ok', Legs} -> ?BUILD_ACC(Endpoints ++ Legs, Call, Context, Element+1);
        {'error', _E} ->
            lager:info("failed to build endpoint ~s: ~p", [kz_doc:id(Device), _E]),
            ?BUILD_ACC(Endpoints, Call, Context, Element+1)
    end.

-spec add_not_endpoint_error(cb_context:context(), pos_integer()) -> cb_context:context().
add_not_endpoint_error(Context, Element) when is_integer(Element) ->
    cb_context:add_validation_error([<<"data">>, <<"endpoints">>, Element]
                                   ,<<"enum">>
                                   ,kz_json:from_list([{<<"message">>, <<"Value not a number, device or user ID, or SIP endpoint">>}])
                                   ,Context
                                   ).

-spec build_number_endpoint(kz_term:ne_binary(), build_acc()) -> build_acc().
build_number_endpoint(Number, ?BUILD_ACC(Endpoints, Call, Context, Element)) ->
    AccountRealm = kapps_call:account_realm(Call),
    Endpoint = [{<<"Invite-Format">>, <<"loopback">>}
               ,{<<"Route">>,  Number}
               ,{<<"To-DID">>, Number}
               ,{<<"To-Realm">>, AccountRealm}
               ,{<<"Simplify-Loopback">>, 'true'}
               ,{<<"Custom-Channel-Vars">>
                ,kz_json:from_list([{<<"Account-ID">>, kapps_call:account_id(Call)}
                                   ,{<<"Authorizing-Type">>, <<"conference">>}
                                   ,{<<"Authorizing-ID">>, kapps_call:authorizing_id(Call)}
                                   ,{<<"Loopback-Request-URI">>, <<Number/binary, "@", AccountRealm/binary>>}
                                   ,{<<"Request-URI">>, <<Number/binary, "@", AccountRealm/binary>>}
                                   ,{<<"Require-Ignore-Early-Media">>, <<"true">>}
                                   ,{<<"Ignore-Early-Media">>, <<"true">>}
                                   ])

                }
               ],

    lager:info("adding number ~s endpoint", [Number]),
    ?BUILD_ACC([kz_json:from_list(Endpoint) | Endpoints], Call, Context, Element+1).

-spec build_sip_endpoint(kz_term:ne_binary(), build_acc()) -> build_acc().
build_sip_endpoint(URI, Acc) ->
    build_sip_endpoint(URI, sip_uri(URI), Acc).

-spec build_sip_endpoint(kz_term:ne_binary(), {binary(), binary()} | 'undefined', build_acc()) ->
          build_acc().
build_sip_endpoint(URI, undefined, ?BUILD_ACC(Endpoints, Call, Context, Element)) ->
    ?BUILD_ACC(Endpoints, Call, add_invalid_uri_error(Context, URI, Element), Element+1);
build_sip_endpoint(URI, {SipUsername, SipRealm}, ?BUILD_ACC(Endpoints, Call, Context, Element)) ->
    SIPSettings = kz_json:from_list([{<<"invite_format">>, <<"route">>}
                                    ,{<<"route">>, URI}
                                    ,{<<"realm">>, SipRealm}
                                    ,{<<"username">>, SipUsername}
                                    ]),
    Device = kz_json:from_list([{<<"sip">>, SIPSettings}]),
    Properties = kz_json:from_list([{<<"source">>, kz_term:to_binary(?MODULE)}]),
    case kz_endpoint:build(Device, Properties, Call) of
        {'ok', SIPEndpoints} ->
            ?BUILD_ACC(SIPEndpoints ++ Endpoints, Call, Context, Element+1);
        {'error', _E} ->
            lager:info("failed to build SIP URI: ~p", [_E]),
            ?BUILD_ACC(Endpoints, Call, add_not_found_error(Context, URI, Element), Element+1)
    end.

-spec sip_uri(kz_term:ne_binary()) -> {binary(), binary()} | 'undefined'.
sip_uri(URI) ->
    try nklib_parse_uri:uris(URI) of
        [#uri{user=User, domain=Realm}] -> {User, Realm};
        _Else -> 'undefined'
    catch
        _Ex:Err:_ST ->
            lager:error("invalid uri ~p => ~p / ~p", [URI, _Ex, Err]),
            kz_log:log_stacktrace(_ST),
            'undefined'
    end.

-spec add_not_found_error(cb_context:context(), kz_term:ne_binary(), pos_integer()) -> cb_context:context().
add_not_found_error(Context, Id, Index) when is_integer(Index) ->
    cb_context:add_validation_error([<<"data">>, <<"endpoints">>, Index]
                                   ,<<"not_found">>
                                   ,kz_json:from_list([{<<"message">>, <<"ID ", Id/binary, " not found">>}])
                                   ,Context
                                   ).

-spec add_invalid_uri_error(cb_context:context(), kz_term:ne_binary(), pos_integer()) -> cb_context:context().
add_invalid_uri_error(Context, Id, Index) when is_integer(Index) ->
    cb_context:add_validation_error([<<"data">>, <<"endpoints">>, Index]
                                   ,<<"not_found">>
                                   ,kz_json:from_list([{<<"message">>, <<"URI ", Id/binary, " is invalid">>}])
                                   ,Context
                                   ).

%%%=============================================================================
%%% Participant Actions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle_participants_action(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary()) -> cb_context:context().
handle_participants_action(Context, ConferenceId, Action=?MUTE) ->
    handle_participants_action(Context, ConferenceId, Action,
                               fun(P) -> kz_json:is_false(<<"Is-Moderator">>, P)
                                             andalso kz_json:is_true(<<"Speak">>, P)
                               end);
handle_participants_action(Context, ConferenceId, Action=?UNMUTE) ->
    handle_participants_action(Context, ConferenceId, Action,
                               fun(P) -> kz_json:is_false(<<"Is-Moderator">>, P)
                                             andalso kz_json:is_false(<<"Speak">>, P)
                               end);
handle_participants_action(Context, ConferenceId, Action=?DEAF) ->
    handle_participants_action(Context, ConferenceId, Action,
                               fun(P) -> kz_json:is_false(<<"Is-Moderator">>, P)
                                             andalso kz_json:is_true(<<"Hear">>, P)
                               end);
handle_participants_action(Context, ConferenceId, Action=?UNDEAF) ->
    handle_participants_action(Context, ConferenceId, Action,
                               fun(P) -> kz_json:is_false(<<"Is-Moderator">>, P)
                                             andalso kz_json:is_false(<<"Hear">>, P)
                               end);
handle_participants_action(Context, ConferenceId, Action=?KICK) ->
    handle_participants_action(Context, ConferenceId, Action, fun kz_term:always_true/1);
handle_participants_action(Context, ConferenceId, Action=?PLAY) ->
    handle_conference_action(Context, ConferenceId, Action);
handle_participants_action(Context, ConferenceId, ?RELATE) ->
    OnSuccess = fun(C) -> handle_participants_relate(C, ConferenceId) end,
    RelateData = cb_context:req_value(Context, <<"data">>, kz_json:new()),
    WithConference = kz_json:set_value(<<"conference_id">>, ConferenceId, RelateData),

    cb_context:validate_request_data(<<"metaflows.relate">>
                                    ,cb_context:set_req_data(Context, WithConference)
                                    ,OnSuccess
                                    );
handle_participants_action(Context, _ConferenceId, _Action) ->
    lager:error("unhandled conference id ~p participants action: ~p", [_ConferenceId, _Action]),
    cb_context:add_system_error('faulty_request', Context).

%% action applicable to conference participants selected by selector function
-type filter_fun() :: fun((kz_json:object()) -> boolean()).
-spec handle_participants_action(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary(), filter_fun()) ->
          cb_context:context().
handle_participants_action(Context, ConferenceId, Action, Selector) ->
    ConfData = request_conference_details(ConferenceId),
    Participants = extract_participants(ConfData),
    Conf = conference(ConferenceId),
    _ = [perform_participant_action(Conf, Action, kz_json:get_integer_value(<<"Participant-ID">>, P))
         || P <- Participants,
            filter_participant(P, Selector)
        ],
    cb_context:set_resp_status(Context, 'success').

-spec filter_participant(kz_json:object(), filter_fun()) -> boolean().
filter_participant(JObj, Fun) ->
    ConfVars = kz_json:get_json_value(<<"Conference-Channel-Vars">>, JObj, kz_json:new()),
    Fun(ConfVars).

-spec handle_participants_relate(cb_context:context(), path_token()) ->
          cb_context:context().
handle_participants_relate(Context, ConferenceId) ->
    ConfData = request_conference_details(ConferenceId),
    Participants = extract_participants(ConfData),

    ParticipantId = kz_term:to_integer(cb_context:req_value(Context, <<"participant_id">>)),
    OtherParticipantId = kz_term:to_integer(cb_context:req_value(Context, <<"other_participant">>)),

    case find_participants(Participants, ParticipantId, OtherParticipantId) of
        [] ->
            lists:foldl(fun participant_not_found/2
                       ,Context
                       ,[ParticipantId, OtherParticipantId]
                       );
        [ParticipantId] ->
            participant_not_found(OtherParticipantId, Context);
        [OtherParticipantId] ->
            participant_not_found(ParticipantId, Context);
        [_, _] ->
            relate(Context, ConferenceId, ParticipantId, OtherParticipantId)
    end.

-spec relate(cb_context:context(), path_token(), pos_integer(), pos_integer()) ->
          cb_context:context().
relate(Context, ConferenceId, ParticipantId, OtherParticipantId) ->
    Conference = conference(ConferenceId),
    Relationship = cb_context:req_value(Context, <<"relationship">>, <<"clear">>),

    kapps_conference_command:relate_participants(ParticipantId, OtherParticipantId, Relationship, Conference),
    lager:info("relating ~p to ~p with ~s in conference ~s"
              ,[ParticipantId, OtherParticipantId, Relationship, ConferenceId]
              ),
    crossbar_util:response_202(<<"relating participants">>, Context).

-spec find_participants(kz_json:objects(), pos_integer(), pos_integer()) ->
          [pos_integer()].
find_participants(Participants, ParticipantId, OtherParticipantId) ->
    [PID || P <- Participants,
            PID <- [kz_json:get_integer_value(<<"Participant-ID">>, P)],
            ParticipantId =:= PID
                orelse OtherParticipantId =:= PID
    ].

-spec participant_not_found(pos_integer(), cb_context:context()) -> cb_context:context().
participant_not_found(ParticipantId, Context) ->
    cb_context:add_system_error('bad_identifier'
                               ,kz_json:from_list([{<<"id">>, ParticipantId}])
                               ,Context
                               ).

-spec perform_participant_action(kapps_conference:conference(), kz_term:ne_binary(), non_neg_integer()) -> 'ok'.
perform_participant_action(Conference, ?MUTE, ParticipantId) ->
    kapps_conference_command:mute_participant(ParticipantId, Conference);
perform_participant_action(Conference, ?UNMUTE, ParticipantId) ->
    kapps_conference_command:unmute_participant(ParticipantId, Conference);
perform_participant_action(Conference, ?DEAF, ParticipantId) ->
    kapps_conference_command:deaf_participant(ParticipantId, Conference);
perform_participant_action(Conference, ?UNDEAF, ParticipantId) ->
    kapps_conference_command:undeaf_participant(ParticipantId, Conference);
perform_participant_action(Conference, ?KICK, ParticipantId) ->
    kapps_conference_command:kick(ParticipantId, Conference).

%% add real-time call-info to participants
-spec enrich_participant(path_token(), path_token(), cb_context:context()) -> cb_context:context().
enrich_participant(ParticipantId, ConferenceId, Context) ->
    Participants = extract_participants(
                     request_conference_details(ConferenceId)
                    ),
    [Normalized|_] = [kz_json:normalize_jobj(JObj)
                      || JObj <- Participants,
                         ParticipantId =:= kz_json:get_ne_binary_value(<<"Participant-ID">>, JObj)
                     ] ++ [kz_json:new()],
    cb_context:set_resp_data(Context, Normalized).

-spec enrich_participants(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
enrich_participants(ConferenceId, Context) ->
    Participants = extract_participants(
                     request_conference_details(ConferenceId)
                    ),
    Normalized = [kz_json:normalize_jobj(JObj) || JObj <- Participants],
    cb_context:set_resp_data(Context, Normalized).

-spec enrich_conference(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
enrich_conference(Context, ConferenceId) ->
    RealtimeData = conference_realtime_data(ConferenceId),
    cb_context:add_metadata_values(Context, kz_json:to_proplist(RealtimeData)).

-spec conference_realtime_data(kz_term:ne_binary()) -> kz_json:object().
conference_realtime_data(ConferenceId) ->
    ConferenceDetails = request_conference_details(ConferenceId),
    Participants = extract_participants(ConferenceDetails),
    {Moderators, Members} = partition_participants_count(Participants),
    C2 = kz_json:from_list(
           [{<<"members">>, Members}
           ,{<<"moderators">>, Moderators}
           ,{<<"duration">>, run_time(ConferenceDetails)}
           ,{<<"is_locked">>, kz_json:get_value(<<"Locked">>, ConferenceDetails, 'false')}
           ,{<<"participants">>, [kz_json:normalize_jobj(Participant) || Participant <- Participants]}
           ]),
    Routines = [{fun kz_json:delete_key/2, <<"Participants">>}
               ,fun kz_api:remove_defaults/1
               ,fun kz_json:normalize/1
               ],
    kz_json:merge(kz_json:exec(Routines, ConferenceDetails), C2).

-spec request_conference_details(path_token()) -> kz_json:object().
request_conference_details(ConferenceId) ->
    Req = [{<<"Conference-ID">>, ConferenceId}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    case kz_amqp_worker:call_collect(Req, fun kapi_conference:publish_search_req/1, {'ecallmgr', 'true'}) of
        {'error', _E} ->
            lager:debug("unable to lookup conference details: ~p", [_E]),
            kz_json:new();
        {'ok', JObjs} -> find_conference_details(JObjs);
        {'timeout', JObjs} ->
            lager:info("failed to hear from all expected nodes, using what was received"),
            find_conference_details(JObjs)
    end.

-spec find_conference_details(kz_json:objects()) -> kz_json:object().
find_conference_details(JObjs) ->
    ValidResponses = [JObj || JObj <- JObjs, kapi_conference:search_resp_v(JObj)],
    case find_most_recent_conference(ValidResponses) of
        'undefined' -> kz_json:new();
        Latest -> Latest
    end.

-spec find_most_recent_conference(kz_json:objects()) -> kz_term:api_object().
find_most_recent_conference(ValidResponses) ->
    case lists:sort(fun sort_by_runtime/2, ValidResponses) of
        [Latest|_] -> Latest;
        [] -> 'undefined'
    end.

-spec sort_by_runtime(kz_json:object(), kz_json:object()) -> boolean().
sort_by_runtime(A, B) -> run_time(A) > run_time(B).

%%%=============================================================================
%%% Utility functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec conference(kz_term:ne_binary()) -> kapps_conference:conference().
conference(ConferenceId) ->
    kapps_conference:set_id(ConferenceId, kapps_conference:new()).

-spec run_time(kz_json:object()) -> integer().
run_time(Conf) -> kz_json:get_value(<<"Run-Time">>, Conf, 0).

-spec extract_participants(kz_json:object()) -> kz_json:objects().
extract_participants(JObj) ->
    add_duration_to_participants(kz_json:get_value(<<"Participants">>, JObj, [])).

-spec calc_duration(kz_json:object()) -> integer().
calc_duration(Participant) ->
    Stamp = kz_time:now_s(),
    JoinTime = kz_json:get_value(<<"Join-Time">>, Participant),
    Stamp - JoinTime.

-spec add_duration_to_participants(kz_json:objects()) -> kz_json:objects().
add_duration_to_participants(Participants) ->
    [kz_json:set_value(<<"Duration">>, calc_duration(Participant), Participant)
     || Participant <- Participants
    ].

-spec partition_participants_count(kz_json:objects()) -> {integer(), integer()}.
partition_participants_count(Participants) ->
    partition_participants_count(Participants, fun(P) -> kz_json:is_true([<<"Conference-Channel-Vars">>, <<"Is-Moderator">>], P) end).

-spec partition_participants_count(kz_json:objects(), fun((kz_json:object()) -> boolean())) -> {integer(), integer()}.
partition_participants_count(Participants, Fun) ->
    {A, B} = partition_participants(Participants, Fun),
    {erlang:length(A), erlang:length(B)}.

-spec partition_participants(kz_json:objects(), fun()) -> {kz_json:objects(), kz_json:objects()}.
partition_participants(Participants, Fun) ->
    lists:partition(Fun, Participants).

-spec maybe_add_running_conferences(cb_context:context()) -> cb_context:context().
maybe_add_running_conferences(Context) ->
    case maybe_get_read_only_fields(Context) of
        'undefined' ->
            add_running_conferences(Context);
        [] ->
            Context;
        Fields ->
            FieldsFun = kz_view:build_fields_fun(Fields, 'undefined'),
            add_running_conferences(cb_context:store(Context, 'fields_fun', FieldsFun))
    end.

-spec add_running_conferences(cb_context:context()) -> cb_context:context().
add_running_conferences(Context) ->
    AccountId = cb_context:account_id(Context),
    Req = [{<<"Account-ID">>, AccountId}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    case kz_amqp_worker:call_collect(Req, fun kapi_conference:publish_search_req/1, {'ecallmgr', 'true'}) of
        {'error', _E} ->
            lager:debug("error searching conferences for account ~s: ~p", [AccountId, _E]),
            handle_search_resp(Context, [kz_json:new()]);
        {'ok', JObjs} ->
            handle_search_resp(Context, JObjs);
        {'timeout', JObjs} ->
            lager:info("failed to hear from all expected nodes, using what was received"),
            handle_search_resp(Context, JObjs)
    end.

-spec maybe_get_read_only_fields(cb_context:context()) -> kz_view:fields() | 'undefined'.
maybe_get_read_only_fields(Context) ->
    maybe_get_read_only_fields(Context, kz_term:is_true(cb_context:fetch(Context, 'has_fields'))).

-spec maybe_get_read_only_fields(cb_context:context(), boolean()) -> kz_view:fields() | 'undefined'.
maybe_get_read_only_fields(_, 'false') ->
    'undefined';
maybe_get_read_only_fields(Context, 'true') ->
    get_read_only_fields(cb_context:fetch(Context, 'fields', []), []).

-spec get_read_only_fields(kz_view:fields(), kz_view:fields()) -> kz_view:fields().
get_read_only_fields([<<"_read_only">>|Fields], Acc) ->
    get_read_only_fields(Fields, [<<"_read_only">> | Acc]);
get_read_only_fields([[<<"_read_only">>|_] = Field| Fields], Acc) ->
    get_read_only_fields(Fields, [Field | Acc]);

get_read_only_fields([{<<"_read_only">>, _} = Field | Fields], Acc) ->
    get_read_only_fields(Fields, [Field | Acc]);
get_read_only_fields([[{<<"_read_only">>, _}|_] = Field| Fields], Acc) ->
    get_read_only_fields(Fields, [Field | Acc]);

get_read_only_fields([], Acc) ->
    Acc;
get_read_only_fields([_|Fields], Acc) ->
    get_read_only_fields(Fields, Acc).

-spec handle_search_resp(cb_context:context(), kz_json:objects()) -> cb_context:context().
handle_search_resp(Context, JObjs) ->
    FieldsFun = cb_context:fetch(Context, 'fields_fun'),
    RunningConferences = lists:foldl(fun search_conferences_fold/2, kz_json:new(), JObjs),
    ReadOnly = kz_json:map(fun move_to_read_only/2, RunningConferences),
    Conferences = [add_realtime_fold(JObj, ReadOnly, FieldsFun)
                   || JObj <- cb_context:resp_data(Context)
                  ],
    cb_context:set_resp_data(Context, Conferences).

-spec search_conferences_fold(kz_json:object(), kz_json:object()) ->
          kz_json:object().
search_conferences_fold(JObj, Acc) ->
    V = kz_json:get_json_value(<<"Conferences">>, JObj, kz_json:new()),
    kz_json:merge_jobjs(V, Acc).

-spec move_to_read_only(kz_json:key(), kz_json:object()) ->
          {kz_json:key(), kz_json:object()}.
move_to_read_only(Id, Realtime) ->
    {Id, kz_json:from_list([{<<"_read_only">>, kz_json:normalize(Realtime)}])}.

-spec add_realtime_fold(kzd_conference:doc(), kz_json:object(), kz_view:fields_fun()) -> kz_json:object().
add_realtime_fold(Conference, ReadOnly, 'undefined') ->
    Realtime = kz_json:get_value(kz_doc:id(Conference), ReadOnly, empty_realtime_data()),
    kz_json:merge(Conference, Realtime);
add_realtime_fold(Conference, ReadOnly, FieldsFun) ->
    [Realtime] = kz_view:apply_fields_fun(FieldsFun, [kz_json:get_ne_json_value(kz_doc:id(Conference), ReadOnly, empty_realtime_data())]),
    kz_json:merge(Conference, Realtime).

-spec empty_realtime_data() -> kz_json:object().
empty_realtime_data() ->
    kz_json:from_list_recursive(
      [{<<"_read_only">>
       ,[{<<"members">>, 0}
        ,{<<"moderators">>, 0}
        ,{<<"duration">>, 0}
        ,{<<"is_locked">>, 'false'}
        ]
       }]).
