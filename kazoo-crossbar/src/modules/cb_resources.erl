%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2026, 2600Hz
%%% @doc Handle client requests for resource documents
%%% @author Karl Anderson
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_resources).

-export([init/0
        ,authorize/1, authorize/2, authorize/3
        ,allowed_methods/0, allowed_methods/1, allowed_methods/2
        ,resource_exists/0, resource_exists/1, resource_exists/2
        ,validate/1, validate/2, validate/3
        ,put/1, put/2
        ,post/2
        ,patch/2
        ,delete/2
        ]).

-include("crossbar.hrl").

-define(CB_LIST, <<"resources/crossbar_listing">>).
-define(JOBS_LIST, <<"resources/jobs_listing">>).
-define(COLLECTION, <<"collection">>).
-define(JOBS, <<"jobs">>).

-define(KEY_SUCCESS, <<"success">>).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _Pid = maybe_start_jobs_listener(),
    lager:debug("started jobs listener: ~p", [_Pid]),
    Binder = fun ({Binding, F}) -> crossbar_bindings:bind(Binding, ?MODULE, F) end,
    lists:foreach(Binder, [{<<"*.allowed_methods.resources">>, 'allowed_methods'}
                          ,{<<"*.resource_exists.resources">>, 'resource_exists'}
                          ,{<<"*.validate.resources">>, 'validate'}
                          ,{<<"*.execute.put.resources">>, 'put'}
                          ,{<<"*.execute.post.resources">>, 'post'}
                          ,{<<"*.execute.patch.resources">>, 'patch'}
                          ,{<<"*.execute.delete.resources">>, 'delete'}
                          ,{<<"*.authorize.resources">>, 'authorize'}
                          ]).

-spec maybe_start_jobs_listener() -> pid().
maybe_start_jobs_listener() ->
    case jobs_listener_pid() of
        'undefined' ->
            {'ok', Pid} = crossbar_module_sup:start_child('crossbar_jobs_listener'),
            Pid;
        Pid -> Pid
    end.

-spec jobs_listener_pid() -> kz_term:api_pid().
jobs_listener_pid() ->
    whereis('crossbar_jobs_listener').

-spec authorize(cb_context:context()) -> boolean() | {'stop', cb_context:context()}.
authorize(Context) ->
    authorize_nouns(Context, cb_context:req_nouns(Context)).

-spec authorize(cb_context:context(), path_token()) -> boolean() | {'stop', cb_context:context()}.
authorize(Context, _) ->
    authorize_nouns(Context, cb_context:req_nouns(Context)).

-spec authorize(cb_context:context(), path_token(), path_token()) -> boolean() | {'stop', cb_context:context()}.
authorize(Context, _, _) ->
    authorize_nouns(Context, cb_context:req_nouns(Context)).

-spec authorize_nouns(cb_context:context(), req_nouns()) -> boolean() | {'stop', cb_context:context()}.
authorize_nouns(Context, [{<<"global_resources">>, _}|_]) ->
    maybe_authorize_admin(Context);
authorize_nouns(Context, [{<<"resources">>, _} | _]) ->
    case cb_context:account_id(Context) of
        'undefined' -> maybe_authorize_admin(Context);
        _AccountId -> 'true'
    end;
authorize_nouns(_Context, _Nouns) ->
    'false'.

-spec maybe_authorize_admin(cb_context:context()) ->
          'true' |
          {'stop', cb_context:context()}.
maybe_authorize_admin(Context) ->
    case cb_context:is_superduper_admin(Context) of
        'true' ->
            lager:debug("authz the request for global resources"),
            'true';
        'false' -> {'stop', Context}
    end.

%%------------------------------------------------------------------------------
%% @doc This function determines the verbs that are appropriate for the
%% given Nouns. For example `/accounts/' can only accept `GET' and `PUT'.
%%
%% Failure here returns `405 Method Not Allowed'.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(?COLLECTION) ->
    [?HTTP_PUT, ?HTTP_POST];
allowed_methods(?JOBS) ->
    [?HTTP_GET, ?HTTP_PUT];
allowed_methods(_ResourceId) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_PATCH, ?HTTP_DELETE].

-spec allowed_methods(path_token(), path_token()) -> http_methods().
allowed_methods(?JOBS, _JobId) ->
    [?HTTP_GET].

%%------------------------------------------------------------------------------
%% @doc This function determines if the provided list of Nouns are valid.
%% Failure here returns `404 Not Found'.
%% @end
%%------------------------------------------------------------------------------

-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_) -> 'true'.

-spec resource_exists(path_token(), path_token()) -> 'true'.
resource_exists(?JOBS, _ID) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc This function determines if the parameters and content are correct
%% for this request
%%
%% Failure here returns 400.
%% @end
%%------------------------------------------------------------------------------

-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    case is_global_resource_request(Context) of
        'true' ->
            validate_resources(cb_context:set_db_name(Context, ?KZ_OFFNET_DB)
                              ,cb_context:req_verb(Context)
                              );
        'false' ->
            validate_resources(Context, cb_context:req_verb(Context))
    end.

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ?COLLECTION) ->
    case is_global_resource_request(Context) of
        'true' ->
            validate_collection(cb_context:set_db_name(Context, ?KZ_OFFNET_DB));
        'false' ->
            validate_collection(Context)
    end;
validate(Context, ?JOBS) ->
    validate_jobs(maybe_set_account_to_master(Context), cb_context:req_verb(Context));
validate(Context, Id) ->
    case is_global_resource_request(Context) of
        'true' ->
            validate_resource(cb_context:set_db_name(Context, ?KZ_OFFNET_DB)
                             ,Id
                             ,cb_context:req_verb(Context)
                             );
        'false' ->
            validate_resource(Context, Id, cb_context:req_verb(Context))
    end.

-spec validate(cb_context:context(), path_token(), path_token()) -> cb_context:context().
validate(Context, ?JOBS, JobId) ->
    read_job(maybe_set_account_to_master(Context), JobId).

-spec maybe_set_account_to_master(cb_context:context()) -> cb_context:context().
maybe_set_account_to_master(Context) ->
    case cb_context:account_id(Context) of
        'undefined' -> set_account_to_master(Context);
        _AccountId -> Context
    end.

-spec set_account_to_master(cb_context:context()) -> cb_context:context().
set_account_to_master(Context) ->
    {'ok', AccountId} = kapps_util:get_master_account_id(),
    cb_context:set_account_id(Context, AccountId).

-spec validate_resources(cb_context:context(), http_method()) -> cb_context:context().
validate_resources(Context, ?HTTP_GET) ->
    summary(Context);
validate_resources(Context, ?HTTP_PUT) ->
    create(Context).

-spec validate_resource(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_resource(Context, Id, ?HTTP_GET) ->
    read(Id, Context);
validate_resource(Context, Id, ?HTTP_POST) ->
    update(Id, Context);
validate_resource(Context, Id, ?HTTP_PATCH) ->
    validate_patch(read(Id, Context), Id);
validate_resource(Context, Id, ?HTTP_DELETE) ->
    read(Id, Context).

validate_patch(Context, ResourceId) ->
    crossbar_doc:patch_and_validate(ResourceId, Context, fun update/2).

validate_collection(Context) ->
    lists:foldl(fun validate_collection_fold/2
               ,cb_context:setters(Context
                                  ,[{fun cb_context:set_doc/2, kz_json:new()}
                                   ,{fun cb_context:set_resp_data/2, kz_json:new()}
                                   ,{fun cb_context:set_resp_status/2, 'success'}
                                   ]
                                  )
               ,cb_context:req_data(Context)
               ).

-type collection_fold_acc() :: cb_context:context().
-spec validate_collection_fold(kz_json:object(), collection_fold_acc()) -> collection_fold_acc().
validate_collection_fold(Resource, C) ->
    Id = kz_doc:id(Resource, kz_datamgr:get_uuid()),
    case validate_collection_resource(kz_doc:set_id(Resource, Id)
                                     ,C
                                     ,cb_context:req_verb(C)
                                     )
    of
        {'ok', C1} ->
            lager:debug("~s loaded successfully", [Id]),
            cb_context:set_resp_data(C
                                    ,kz_json:set_value([?KEY_SUCCESS, Id], cb_context:doc(C1), cb_context:resp_data(C))
                                    );
        {'error', 'not_found'} ->
            RespData = cb_context:resp_data(C),
            lager:debug("~s not found", [Id]),
            cb_context:set_resp_data(C, kz_json:set_value([<<"errors">>, Id], <<"resource does not exist">>, RespData));
        {'error', Errors} ->
            RespData = cb_context:resp_data(C),
            lager:debug("~s failed validation: ~p", [Id, Errors]),
            lager:debug("adding to ~p", [RespData]),
            cb_context:set_resp_data(C, kz_json:set_value([<<"errors">>, Id], Errors, RespData))
    end.

-spec validate_collection_resource(kz_json:object(), cb_context:context(), http_method()) ->
          {'ok', cb_context:context()} |
          {'error', 'not_found' | kz_json:object()}.
validate_collection_resource(Resource, Context, ?HTTP_POST) ->
    C1 = crossbar_doc:load(kz_doc:id(Resource), Context, ?TYPE_CHECK_OPTION(<<"resource">>)),
    case cb_context:resp_status(C1) of
        'success' -> validate_collection_resource_patch(Resource, C1);
        _Status -> {'error', 'not_found'}
    end;
validate_collection_resource(Resource, Context, ?HTTP_PUT) ->
    Context1 = create(cb_context:set_req_data(Context, Resource)),
    case cb_context:resp_status(Context1) of
        'success' -> {'ok', Context1};
        _Status -> {'error', cb_context:validation_errors(Context1)}
    end.

-spec validate_collection_resource_patch(kz_json:object(), cb_context:context()) ->
          {'ok', cb_context:context()} |
          {'error', kz_json:object()}.
validate_collection_resource_patch(PatchJObj, Context) ->
    PatchedJObj = kz_json:merge(cb_context:doc(Context), kz_doc:public_fields(PatchJObj)),
    Context1 = update(kz_doc:id(PatchedJObj)
                     ,cb_context:set_req_data(Context, PatchedJObj)
                     ),
    case cb_context:resp_status(Context1) of
        'success' -> {'ok', Context1};
        _Status -> {'error', cb_context:validation_errors(Context1)}
    end.

-spec validate_jobs(cb_context:context(), http_method()) -> cb_context:context().
validate_jobs(Context, ?HTTP_GET) ->
    jobs_summary(Context);
validate_jobs(Context, ?HTTP_PUT) ->
    create_job(Context).

-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, ?COLLECTION) ->
    collection_process(Context);
post(Context, Id) ->
    do_post(Context, Id).

-spec do_post(cb_context:context(), path_token()) -> cb_context:context().
do_post(Context, _Id) ->
    Db = cb_context:db_name(Context),
    Context1 = crossbar_doc:save(Context),
    maybe_aggregate_resource(Context1, Db, cb_context:resp_status(Context1)).

-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, Id) -> do_post(Context, Id).

-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    Db = cb_context:db_name(Context),
    Context1 = crossbar_doc:save(Context),
    maybe_aggregate_resource(Context1, Db, cb_context:resp_status(Context1)).

-spec put(cb_context:context(), path_token()) -> cb_context:context().
put(Context, ?COLLECTION) ->
    collection_process(Context);
put(Context, ?JOBS) ->
    Context1 = crossbar_doc:save(cb_context:set_db_name(Context, cb_context:account_modb(Context))),

    case cb_context:resp_status(Context1) of
        'success' ->
            _ = crossbar_jobs_listener:publish_new_job(Context),
            crossbar_util:response_202(<<"Job scheduled">>, cb_context:resp_data(Context1), Context1);
        _Status ->
            Context1
    end.

-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, ResourceId) ->
    Context1 = crossbar_doc:delete(Context),
    maybe_remove_aggregate(Context1, ResourceId, cb_context:db_name(Context1), cb_context:resp_status(Context1)).

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec maybe_aggregate_resource(cb_context:context(), kz_term:ne_binary(), crossbar_status()) -> cb_context:context().
maybe_aggregate_resource(Context, ?KZ_OFFNET_DB, 'success') ->
    _ = reload_trusted(),
    Context;
maybe_aggregate_resource(Context, _AccountDb, 'success') ->
    ResourceId = kz_doc:id(cb_context:doc(Context)),
    _ = aggregate_resource(kz_doc:set_id(cb_context:doc(Context), ResourceId)),
    _ = reload_trusted(),
    Context;
maybe_aggregate_resource(Context, _, _) ->
    Context.

-spec maybe_remove_aggregate(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary(), crossbar_status()) -> cb_context:context().
maybe_remove_aggregate(Context, _ResourceId, ?KZ_OFFNET_DB, 'success') ->
    _ = reload_trusted(),
    Context;
maybe_remove_aggregate(Context, ResourceId, _AccountDb, 'success') ->
    _ = remove_aggregate(ResourceId),
    _ = reload_trusted(),
    Context;
maybe_remove_aggregate(Context, _, _, _) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc Load an instance from the database
%% @end
%%------------------------------------------------------------------------------
-spec read(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
read(Id, Context) ->
    crossbar_doc:load(Id, Context, ?TYPE_CHECK_OPTION(<<"resource">>)).

-spec read_job(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
read_job(Context, ?MATCH_MODB_PREFIX(Year,Month,_) = JobId) ->
    Modb = kzs_util:format_account_id(cb_context:account_id(Context), kz_term:to_integer(Year), kz_term:to_integer(Month)),
    add_metadata_for_job_fields(crossbar_doc:load(JobId, cb_context:set_db_name(Context, Modb), ?TYPE_CHECK_OPTION(<<"resource_job">>)));
read_job(Context, ?MATCH_MODB_PREFIX_M1(Year,Month,_) = JobId) ->
    Modb = kzs_util:format_account_id(cb_context:account_id(Context), kz_term:to_integer(Year), kz_term:to_integer(Month)),
    add_metadata_for_job_fields(crossbar_doc:load(JobId, cb_context:set_db_name(Context, Modb), ?TYPE_CHECK_OPTION(<<"resource_job">>)));
read_job(Context, JobId) ->
    lager:debug("invalid job id format: ~s", [JobId]),
    crossbar_util:response_bad_identifier(JobId, Context).

-spec add_metadata_for_job_fields(cb_context:context()) -> cb_context:context().
add_metadata_for_job_fields(Context) ->
    add_metadata_for_job_fields(Context, cb_context:resp_status(Context)).

add_metadata_for_job_fields(Context, 'success') ->
    JObj = cb_context:doc(Context),
    Metadata = [{<<"timestamp">>, kz_doc:created(JObj)}
               ,{<<"status">>, kz_json:get_value(<<"pvt_status">>, JObj)}
               ],
    cb_context:set_resp_data(Context, kz_json:set_values(Metadata, cb_context:resp_data(Context)));
add_metadata_for_job_fields(Context, _Status) -> Context.

%%------------------------------------------------------------------------------
%% @doc Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%------------------------------------------------------------------------------
-spec summary(cb_context:context()) -> cb_context:context().
summary(Context) ->
    crossbar_view:load(Context, ?CB_LIST, [{'mapper', crossbar_view:get_value_fun()}]).

%%------------------------------------------------------------------------------
%% @doc Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%------------------------------------------------------------------------------
-spec jobs_summary(cb_context:context()) -> cb_context:context().
jobs_summary(Context) ->
    crossbar_view:load_modb(Context, ?JOBS_LIST, [{'mapper', crossbar_view:get_doc_fun()}]).

%%------------------------------------------------------------------------------
%% @doc Create a new instance with the data provided, if it is valid
%% @end
%%------------------------------------------------------------------------------
-spec create(cb_context:context()) -> cb_context:context().
create(Context) ->
    OnSuccess = fun(C) -> on_successful_validation('undefined', C) end,
    cb_context:validate_request_data(<<"resources">>, Context, OnSuccess).

-spec create_job(cb_context:context()) -> cb_context:context().
create_job(Context) ->
    OnSuccess = fun(C) -> on_successful_job_validation('undefined', C) end,
    cb_context:validate_request_data(<<"resource_jobs">>, Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc Update an existing instance with the data provided, if it is
%% valid
%% @end
%%------------------------------------------------------------------------------
-spec update(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
update(Id, Context) ->
    OnSuccess = fun(C) -> on_successful_validation(Id, C) end,
    cb_context:validate_request_data(<<"resources">>, Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec on_successful_validation(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
on_successful_validation('undefined', Context) ->
    cb_context:set_doc(Context, kz_doc:set_type(cb_context:doc(Context), <<"resource">>));
on_successful_validation(Id, Context) ->
    crossbar_doc:load_merge(Id, Context, ?TYPE_CHECK_OPTION(<<"resource">>)).

-spec on_successful_job_validation('undefined', cb_context:context()) -> cb_context:context().
on_successful_job_validation('undefined', Context) ->
    Props = [{<<"_id">>, kazoo_modb_util:modb_id(kz_binary:rand_hex(8))}
            ,{<<"errors">>, kz_json:new()}
            ,{<<"pvt_status">>, <<"pending">>}
            ,{?KEY_SUCCESS, kz_json:new()}
            ,{<<"pvt_type">>, <<"resource_job">>}
            ],
    cb_context:set_doc(Context, kz_json:set_values(Props, cb_context:doc(Context))).

-spec reload_trusted() -> 'ok'.
reload_trusted() ->
    lager:info("published trusted reload"),
    _ = kz_amqp_worker:cast(kz_api:default_headers(?APP_NAME, ?APP_VERSION), fun kapi_trusted:publish_reload/1).

-spec collection_process(cb_context:context()) -> cb_context:context().
collection_process(Context) ->
    RespData = cb_context:resp_data(Context),

    case kz_term:is_empty(kz_json:get_value(<<"errors">>, RespData)) of
        'true' -> collection_process(Context, kz_json:get_value(?KEY_SUCCESS, RespData));
        'false' ->
            cb_context:set_resp_data(cb_context:set_resp_status(Context, 'success')
                                    ,kz_json:delete_key(?KEY_SUCCESS, RespData)
                                    )
    end.

-spec collection_process(cb_context:context(), kz_json:objects()) -> cb_context:context().
collection_process(Context, []) -> cb_context:set_resp_status(Context, 'success');
collection_process(Context, Successes) ->
    Resources = kz_json:values(Successes),
    lists:foreach(fun (R) -> lager:debug("save ~p", [R]) end, Resources),
    Context1 = crossbar_doc:save(cb_context:set_doc(Context, Resources)),
    case cb_context:resp_status(Context1) of
        'success' ->
            maybe_aggregate_resources((cb_context:db_name(Context1) =/= ?KZ_OFFNET_DB)
                                     ,Resources
                                     ),
            _ = reload_trusted(),
            summary(Context1);
        _Status -> Context1
    end.

maybe_aggregate_resources('true', Resources) ->
    lists:foreach(fun aggregate_resource/1, Resources);
maybe_aggregate_resources('false', _Resources) -> 'ok'.

-spec is_global_resource_request(cb_context:context()) -> boolean().
is_global_resource_request(Context) ->
    is_global_resource_request(cb_context:req_nouns(Context), cb_context:account_id(Context)).

-spec is_global_resource_request(req_nouns(), kz_term:api_binary()) -> boolean().
is_global_resource_request(_ReqNouns, 'undefined') ->
    lager:debug("request is for global resources"),
    'true';
is_global_resource_request(_ReqNouns, _AccountId) ->
    lager:debug("request is for local resources for account ~s", [_AccountId]),
    'false'.

%%%=============================================================================
%%% Local Resources functions
%%%=============================================================================
%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec aggregate_resource(kzd_resources:doc()) -> 'ok'.
aggregate_resource(ResourceJObj) ->
    lager:debug("adding resource to the sip auth aggregate"),
    Doc = kz_doc:delete_revision(ResourceJObj),
    Update = [{[<<"_read_only">>], 'null'} | kz_json:to_proplist(kz_json:flatten(Doc))],
    UpdateOptions = [{'update', Update}
                    ,{'create', []}
                    ,{'ensure_saved', 'true'}
                    ],
    {'ok', _} = kz_datamgr:update_doc(?KZ_SIP_DB, kz_doc:id(ResourceJObj), UpdateOptions),
    'ok'.

-spec remove_aggregate(kz_term:ne_binary()) -> 'ok'.
remove_aggregate(ResourceId) ->
    case kz_datamgr:del_doc(?KZ_SIP_DB, ResourceId) of
        {'ok', _JObj} ->
            lager:debug("removed resource from the sip auth aggregate");
        {'error', 'not_found'} ->
            lager:debug("resouce not found in sip auth aggregate")
    end.
