%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2026, 2600Hz
%%% @doc Endpoint for Applications
%%% @author Kevin Damas
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_applications).

-export([init/0
        ,authorize/1, authorize/2, authorize/3, authorize/4, authorize/5
        ,allowed_methods/0, allowed_methods/1, allowed_methods/2, allowed_methods/3, allowed_methods/4
        ,resource_exists/0, resource_exists/1, resource_exists/2, resource_exists/3, resource_exists/4
        ,content_types_provided/4, content_types_provided/5
        ,content_types_accepted/4
        ,validate/1, validate/2, validate/3, validate/4, validate/5
        ,put/3, put/4
        ,post/3, post/4
        ,patch/3
        ,delete/3, delete/4, delete/5
        ]).

-export([maybe_admin/1]).

-include("crossbar.hrl").

%% Views
-define(CB_LIST, <<"application/crossbar_listing">>).
-define(CB_BLOCKLISTS, <<"application/blocklists">>).
-define(CB_ENTITLEMENTS, <<"application/entitlements">>).

%% Path tokens
-define(APPLICATION, <<"application">>).
-define(ICON, <<"icon">>).
-define(SCREENSHOTS, <<"screenshots">>).
-define(BLOCKLISTS, <<"blocklists">>).
-define(BLOCK, <<"block">>).
-define(ENTITLEMENT, <<"entitlement">>).
-define(ENTITLEMENTS, <<"entitlements">>).

-define(EN_LANGUAGE, <<"en-US">>).
-define(WHITELABEL_MIME_TYPES, ?IMAGE_CONTENT_TYPES ++ ?BASE64_CONTENT_TYPES ++ ?MULTIPART_CONTENT_TYPES).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.applications">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.applications">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.applications">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.put.applications">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.applications">>, ?MODULE, 'post'),
    _ = crossbar_bindings:bind(<<"*.execute.patch.applications">>, ?MODULE, 'patch'),
    _ = crossbar_bindings:bind(<<"*.execute.delete.applications">>, ?MODULE, 'delete'),
    _ = crossbar_bindings:bind(<<"*.authorize.applications">>, ?MODULE, 'authorize'),
    _ = crossbar_bindings:bind(<<"*.content_types_provided.applications">>, ?MODULE, 'content_types_provided'),
    _ = crossbar_bindings:bind(<<"*.content_types_accepted.applications">>, ?MODULE, 'content_types_accepted').

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_AppType) ->
    [?HTTP_GET].

-spec allowed_methods(path_token(), path_token()) -> http_methods().
allowed_methods(?APPLICATION, _AppId) ->
    [?HTTP_GET, ?HTTP_PUT, ?HTTP_POST, ?HTTP_PATCH, ?HTTP_DELETE];
allowed_methods(_AppType, ?BLOCKLISTS) ->
    [?HTTP_GET];
allowed_methods(_AppType, ?ENTITLEMENTS) ->
    [?HTTP_GET];
allowed_methods(_AppType, _AppId) ->
    [?HTTP_GET].

-spec allowed_methods(path_token(), path_token(), path_token()) -> http_methods().
allowed_methods(?APPLICATION, _AppId, ?ICON) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_DELETE];
allowed_methods(?APPLICATION, _AppId, ?SCREENSHOTS) ->
    [?HTTP_POST];
allowed_methods(_AppType, _AppId, ?BLOCK) ->
    [?HTTP_GET, ?HTTP_PUT, ?HTTP_POST, ?HTTP_DELETE];
allowed_methods(_AppType, _AppId, ?ENTITLEMENT) ->
    [?HTTP_GET, ?HTTP_PUT, ?HTTP_POST, ?HTTP_DELETE];
allowed_methods(_AppType, _AppId, ?ICON) ->
    [?HTTP_GET].

-spec allowed_methods(path_token(), path_token(), path_token(), path_token()) -> http_methods().
allowed_methods(?APPLICATION, _AppId, ?SCREENSHOTS, _ScreenshotId) ->
    [?HTTP_GET, ?HTTP_DELETE];
allowed_methods(_AppType, _AppId, ?SCREENSHOTS, _ScreenshotId) ->
    [?HTTP_GET].

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_) -> 'true'.

-spec resource_exists(path_token(), path_token()) -> 'true'.
resource_exists(_, _) -> 'true'.

-spec resource_exists(path_token(), path_token(), path_token()) -> 'true'.
resource_exists(_, _, _) -> 'true'.

-spec resource_exists(path_token(), path_token(), path_token(), path_token()) -> 'true'.
resource_exists(_, _, _, _) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc Authorizes the incoming request, returning true if the requestor is
%% allowed to access the resource, or false if not.
%% @end
%%------------------------------------------------------------------------------
-spec authorize(cb_context:context()) ->
          'true' | {'stop', cb_context:context()}.
authorize(Context) ->
    maybe_reseller_or_master(Context).

-spec authorize(cb_context:context(), path_token()) ->
          'true' | {'stop', cb_context:context()}.
authorize(Context, _AppType) ->
    authorize_app_exchange(Context).

-spec authorize(cb_context:context(), path_token(), path_token()) ->
          'true' | {'stop', cb_context:context()}.
authorize(Context, ?APPLICATION, _AppId) ->
    maybe_reseller_or_master(Context);
authorize(Context, _AppType, ?BLOCKLISTS) ->
    maybe_reseller_or_master(Context);
authorize(Context, _AppType, ?ENTITLEMENTS) ->
    maybe_admin(Context);
authorize(Context, _AppType, _AppId) ->
    authorize_app_exchange(Context).

-spec authorize(cb_context:context(), path_token(), path_token(), path_token()) ->
          'true' | {'stop', cb_context:context()}.
authorize(Context, ?APPLICATION, _AppId, ?ICON) ->
    maybe_reseller_or_master(Context);
authorize(Context, ?APPLICATION, _AppId, ?SCREENSHOTS) ->
    maybe_reseller_or_master(Context);
authorize(Context, _AppType, _AppId, ?BLOCK) ->
    maybe_reseller_or_master(Context);
authorize(Context, _AppType, _AppId, ?ENTITLEMENT) ->
    maybe_admin(Context);
authorize(Context, _AppType, _AppId, ?ICON) ->
    authorize_app_exchange(Context).

-spec authorize(cb_context:context(), path_token(), path_token(), path_token(), path_token()) ->
          'true' | {'stop', cb_context:context()}.
authorize(Context, ?APPLICATION, _AppId, ?SCREENSHOTS, _Number) ->
    maybe_reseller_or_master(Context);
authorize(Context, _AppType, _AppId, ?SCREENSHOTS, _Number) ->
    authorize_app_exchange(Context).

-spec authorize_app_exchange(cb_context:context()) ->
          'true' | {'stop', cb_context:context()}.
authorize_app_exchange(Context) ->
    case {cb_context:account_id(Context)
         ,get_url_user_id(Context)
         }
    of
        {'undefined', 'undefined'} ->
            {'stop', cb_context:add_system_error('forbidden', Context)};
        {_AccountId, 'undefined'} ->
            maybe_admin(Context);
        {_AccountId, _UserId} ->
            'true'
    end.

-spec maybe_admin(cb_context:context()) ->
          'true' | {'stop', cb_context:context()}.
maybe_admin(Context) ->
    case cb_context:is_account_admin(Context)
        orelse cb_context:is_superduper_admin(Context)
    of
        'true' -> 'true';
        'false' ->
            {'stop', cb_context:add_system_error('forbidden', Context)}
    end.

-spec maybe_reseller_or_master(cb_context:context()) ->
          'true' | {'stop', cb_context:context()}.
maybe_reseller_or_master(Context) ->
    AuthAccountId = cb_context:auth_account_id(Context),
    case cb_context:is_superduper_admin(Context)
        orelse (cb_context:is_account_admin(Context)
                andalso kz_services_reseller:is_reseller(AuthAccountId)
               )
    of
        'true' -> 'true';
        'false' ->
            {'stop', cb_context:add_system_error('forbidden', Context)}
    end.

%%------------------------------------------------------------------------------
%% @doc What content-types will the module be using to respond (matched against
%% client's accept header).
%% Of the form `{atom(), [{Type, SubType}]} :: {to_json, [{<<"application">>, <<"json">>}]}'
%% @end
%%------------------------------------------------------------------------------
-spec content_types_provided(cb_context:context(), path_token(), path_token(), path_token()) ->
          cb_context:context().
content_types_provided(Context, ?APPLICATION, AppId, ?ICON) ->
    case cb_context:req_verb(Context) of
        ?HTTP_GET ->
            set_content_types_provided(load_account_attachment_metadata(Context, AppId, ?ICON));
        _ ->
            Context
    end;
content_types_provided(Context, AppType, AppId, ?ICON) ->
    Context1 = load_allowed_application(Context, AppType, AppId),
    set_content_types_provided(load_attachment_metadata(Context1, ?ICON));
content_types_provided(Context, _, _, _) ->
    Context.

-spec content_types_provided(cb_context:context(), path_token(), path_token(), path_token(), path_token()) ->
          cb_context:context().
content_types_provided(Context, ?APPLICATION, AppId, ?SCREENSHOTS, Number) ->
    case cb_context:req_verb(Context) of
        ?HTTP_GET ->
            set_content_types_provided(load_account_attachment_metadata(Context, AppId, {?SCREENSHOTS, Number}));
        _ ->
            Context
    end;
content_types_provided(Context, AppType, AppId, ?SCREENSHOTS, Number) ->
    Context1 = load_allowed_application(Context, AppType, AppId),
    set_content_types_provided(load_attachment_metadata(Context1, {?SCREENSHOTS, Number})).

-spec set_content_types_provided(kz_either:either(cb_context:context(), cb_context:context())) -> cb_context:context().
set_content_types_provided({'ok', Context}) ->
    Name = cb_context:fetch(Context, <<"attachment_name">>),
    JObj = cb_context:fetch(Context, <<"attachment_meta">>),

    case kz_doc:attachment_content_type(JObj, Name) of
        'undefined' ->
            lager:debug("attachment content type is undefined"),
            Context;
        CT ->
            [Type, SubType] = binary:split(CT, <<"/">>),
            lager:debug("found attachment of content type: ~s/~s~n", [Type, SubType]),
            cb_context:set_content_types_provided(Context, [{'to_binary', [{Type, SubType}]}])
    end;
set_content_types_provided({'error', Context}) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec content_types_accepted(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
content_types_accepted(Context, ?APPLICATION, _AppId, ?ICON) ->
    set_content_types_accepted(Context, ?ICON, cb_context:req_verb(Context));
content_types_accepted(Context, ?APPLICATION, _AppId, ?SCREENSHOTS) ->
    set_content_types_accepted(Context, ?SCREENSHOTS, cb_context:req_verb(Context));
content_types_accepted(Context, _, _, _) ->
    Context.

-spec set_content_types_accepted(cb_context:context(), path_token(), http_method()) ->
          cb_context:context().
set_content_types_accepted(Context, ?ICON, ?HTTP_POST) ->
    CTA = [{'from_binary', ?WHITELABEL_MIME_TYPES}],
    cb_context:set_content_types_accepted(Context, CTA);
set_content_types_accepted(Context, ?SCREENSHOTS, ?HTTP_POST) ->
    CTA = [{'from_binary', ?WHITELABEL_MIME_TYPES}],
    cb_context:set_content_types_accepted(Context, CTA);
set_content_types_accepted(Context, _AttachType, _Verb) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc Summary of apps defined in reseller account db.
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    Options = [{'mapper', crossbar_view:get_value_fun()}],
    crossbar_view:load(Context, ?CB_LIST, Options).

%% @doc Summary of allowed applications per type
-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, AppType) ->
    load_allowed_applications(Context, AppType, get_url_user_id(Context)).

-spec validate(cb_context:context(), path_token(), path_token()) -> cb_context:context().
validate(Context, ?APPLICATION, AppId) ->
    validate_application(Context, AppId, cb_context:req_verb(Context));
validate(Context, AppType, ?BLOCKLISTS) ->
    Options = [{'startkey', [AppType]}
              ,{'endkey', [AppType, kz_term:high_unicode_value()]}
              ,{'mapper', crossbar_view:get_value_fun()}
              ],
    crossbar_view:load(Context, ?CB_BLOCKLISTS, Options);
validate(Context, AppType, ?ENTITLEMENTS) ->
    Options = [{'startkey', [AppType]}
              ,{'endkey', [AppType, kz_term:high_unicode_value()]}
              ,{'mapper', crossbar_view:get_value_fun()}
              ],
    crossbar_view:load(Context, ?CB_ENTITLEMENTS, Options);
validate(Context, AppType, AppId) ->
    load_allowed_application(Context, AppType, AppId).

-spec validate(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
validate(Context, ?APPLICATION, AppId, ?ICON) ->
    validate_icon(Context, AppId, cb_context:req_verb(Context));
validate(Context, ?APPLICATION, AppId, ?SCREENSHOTS) ->
    validate_upload_attachment_binary(Context, AppId, cb_context:req_files(Context));
validate(Context, AppType, AppId, ?BLOCK) ->
    validate_blocklist(Context, AppType, AppId, cb_context:req_verb(Context));
validate(Context, AppType, AppId, ?ENTITLEMENT) ->
    validate_entitlement(Context, AppType, AppId, cb_context:req_verb(Context));
validate(Context, AppType, AppId, ?ICON) ->
    Context1 = load_allowed_application(Context, AppType, AppId),
    %% load_attachment(load_attachment_metadata(Context1, {?SCREENSHOTS, ScreenshotId})).
    load_attachment(load_attachment_metadata(Context1, ?ICON)).

-spec validate(cb_context:context(), path_token(), path_token(), path_token(), path_token()) -> cb_context:context().
validate(Context, ?APPLICATION, AppId, ?SCREENSHOTS, ScreenshotId) ->
    validate_screenshot(Context, AppId, ScreenshotId, cb_context:req_verb(Context));
validate(Context, AppType, AppId, ?SCREENSHOTS, ScreenshotId) ->
    Context1 = load_allowed_application(Context, AppType, AppId),
    load_attachment(load_attachment_metadata(Context1, {?SCREENSHOTS, ScreenshotId})).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec put(cb_context:context(), path_token(), path_token()) -> cb_context:context().
put(Context, ?APPLICATION, _AppId) ->
    crossbar_doc:save(Context).

-spec put(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
put(Context, _AppType, _AppId, ?BLOCK) ->
    crossbar_doc:save(Context);
put(Context, _AppType, _AppId, ?ENTITLEMENT) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec post(cb_context:context(), path_token(), path_token()) -> cb_context:context().
post(Context, ?APPLICATION, _AppId) ->
    crossbar_doc:save(Context).

-spec post(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
post(Context, ?APPLICATION, _AppId, ?ICON) ->
    post_media_binary(Context, ?ICON);
post(Context, ?APPLICATION, _AppId, ?SCREENSHOTS) ->
    post_media_binary(Context, ?SCREENSHOTS);
post(Context, _AppType, _AppId, ?BLOCK) ->
    crossbar_doc:save(Context);
post(Context, _AppType, _AppId, ?ENTITLEMENT) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec patch(cb_context:context(), path_token(), path_token()) -> cb_context:context().
patch(Context, ?APPLICATION, _AppId) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec delete(cb_context:context(), path_token(), path_token()) -> cb_context:context().
delete(Context, ?APPLICATION, _AppId) ->
    crossbar_doc:delete(Context).

-spec delete(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
delete(Context, ?APPLICATION, AppId, ?ICON) ->
    delete_media_binary(Context, AppId, ?ICON);
delete(Context, _AppType, _AppId, ?BLOCK) ->
    %% this api may be called repeatedly, let hard-deleting
    %% so admins can quickly set/delete this without interruption
    crossbar_doc:delete(Context, 'false');
delete(Context, _AppType, _AppId, ?ENTITLEMENT) ->
    %% this api may be called repeatedly, let hard-deleting
    %% so admins can quickly set/delete this without interruption
    crossbar_doc:delete(Context, 'false').

-spec delete(cb_context:context(), path_token(), path_token(), path_token(), path_token()) -> cb_context:context().
delete(Context, ?APPLICATION, AppId, ?SCREENSHOTS, _ScreenshotId) ->
    delete_media_binary(Context, AppId, ?SCREENSHOTS).

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec get_url_user_id(cb_context:context()) -> kz_term:api_ne_binary().
get_url_user_id(Context) ->
    case props:get_value(<<"users">>, cb_context:req_nouns(Context)) of
        [UserId|_] -> UserId;
        _ -> 'undefined'
    end.

-spec load_allowed_applications(cb_context:context(), path_token(), kz_term:api_ne_binary()) ->
          cb_context:context().
load_allowed_applications(Context, AppType, UserId) ->
    AccountId = cb_context:account_id(Context),
    %% wrapping in 'doc' because crossbar_view expect a valid get_result response
    %% to apply filter and fields
    Apps = [kz_json:from_list([{<<"doc">>, App}])
            || App <- cb_apps_util:allowed_applications(AppType, AccountId, UserId)
           ],
    Options = [{'mapper', fun normalize_apps_result/3}
              ,{'run_mapper', 'true'}
              ,{'field_key', 'filtermap'}
              ],
    crossbar_view:prepare_docs(cb_context:set_doc(Context, Apps), Options).

-spec normalize_apps_result(cb_context:context(), kz_json:object(), kz_json:objects()) -> kz_json:objects().
normalize_apps_result(Context, JObj, Acc) ->
    App = kz_json:get_json_value(<<"doc">>, JObj),
    case kzd_applications:published(App) of
        'false' ->
            case should_allow_admin_app_listing(Context, App) of
                'true' ->
                    [kz_doc:public_fields(App) | Acc];
                'false' ->
                    Acc
            end;
        'true' ->
            [kz_doc:public_fields(App) | Acc]
    end.

-spec load_allowed_application(cb_context:context(), path_token(), path_token()) ->
          cb_context:context().
load_allowed_application(Context, AppType, AppId) ->
    AccountId = cb_context:account_id(Context),
    UserId = get_url_user_id(Context),
    case cb_apps_util:allowed_application(AppType, AppId, AccountId, UserId) of
        {'error', Error} ->
            crossbar_doc:handle_datamgr_errors(Error, AppId, Context);
        {'ok', JObj} ->
            maybe_allowed_application(Context, JObj, kzd_applications:published(JObj))
    end.

-spec maybe_allowed_application(cb_context:context(), kz_json:object(), boolean()) ->
          cb_context:context().
maybe_allowed_application(Context, JObj, 'true') ->
    crossbar_doc:handle_json_success(JObj, Context);
maybe_allowed_application(Context, JObj, 'false') ->
    case should_allow_admin_app_listing(Context, JObj) of
        'true' ->
            crossbar_doc:handle_json_success(JObj, Context);
        'false' ->
            crossbar_doc:handle_datamgr_errors('not_found', kz_doc:id(JObj), Context)
    end.

%% only admins are allowed to list apps in app-exchange so they can enable/disable the app for their
%% account using entitlements.
%% The condition is to explicitly check auth user is admin and there is no user id in the url.
%% (a user id in url means a user wants to list and open their app and not an admin managing entitlements)
%%
%% Also explicitly check if the app is not published because of entitlement.
-spec should_allow_admin_app_listing(cb_context:context(), kz_json:object()) -> boolean().
should_allow_admin_app_listing(Context, JObj) ->
    IsEntiteAuthority = kzd_applications:pvt_authority(JObj) =:= <<"entitlement">>,
    IsAdmin = maybe_admin(Context) =:= 'true',
    case props:get_value(<<"users">>, cb_context:req_nouns(Context)) of
        'undefined' when IsEntiteAuthority
                         andalso IsAdmin ->
            'true';
        _ ->
            'false'
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_application(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_application(Context, AppId, ?HTTP_GET) ->
    crossbar_doc:load(AppId, Context, ?TYPE_CHECK_OPTION(kzd_applications:pvt_type()));
validate_application(Context, AppId, ?HTTP_PUT) ->
    OnSuccess = fun(C) -> create_application(C, AppId, kz_term:is_rfc4122_uuid(AppId)) end,
    cb_context:validate_request_data(kzd_applications:schema(), Context, OnSuccess);
validate_application(Context, AppId, ?HTTP_POST) ->
    update_application(Context, AppId);
validate_application(Context, AppId, ?HTTP_PATCH) ->
    OnSuccess = fun(_Id, C) ->
                        update_application(C, AppId)
                end,
    crossbar_doc:patch_and_validate(AppId, Context, OnSuccess);
validate_application(Context, AppId, ?HTTP_DELETE) ->
    crossbar_doc:load(AppId, Context, ?TYPE_CHECK_OPTION(kzd_applications:pvt_type())).

%% @doc check is this reseller or master creating/updating/overriding the app
%% if reseller then then check if the app exist in master to merge with payload
%% so effectively allowing reseller to override the app.
-spec create_application(cb_context:context(), path_token(), boolean()) -> cb_context:context().
create_application(Context, AppId, 'true') ->
    %% FIXME: app_uuid
    MasterId = cb_context:master_account_id(Context),
    case cb_context:account_id(Context) of
        'undefined'->
            Message = kz_json:from_list([{<<"message">>, <<"account id is required in the url">>}]),
            cb_context:add_validation_error(<<"account_id">>, <<"required">>, Message, Context);
        MasterId ->
            Setters = [{fun kz_doc:set_id/2, AppId}
                      ,{fun set_uuid/2, AppId}
                      ,{fun kz_doc:set_type/2, kzd_applications:pvt_type()}
                      ],
            cb_context:set_doc(Context, kz_doc:setters(cb_context:doc(Context), Setters));
        _AccountId ->
            load_merge_master_app(AppId, Context)
    end;
create_application(Context, _AppId, 'false') ->
    Message = kz_json:from_list([{<<"message">>, <<"uuid in the url is not valid">>}]),
    cb_context:add_validation_error(<<"uuid">>, <<"not_valid">>, Message, Context).

-spec set_uuid(kz_json:object(), kz_term:ne_binary()) -> kz_json:object().
set_uuid(JObj, Uuid) ->
    kz_json:set_value(<<"uuid">>, Uuid, JObj).

-spec update_application(cb_context:context(), path_token()) -> cb_context:context().
update_application(Context, AppId) ->
    OnSuccess = fun(C) -> on_successful_app_load(C, AppId) end,
    cb_context:validate_request_data(kzd_applications:schema(), Context, OnSuccess).

-spec load_merge_master_app(path_token(), cb_context:context()) ->
          cb_context:context().
load_merge_master_app(AppId, Context) ->
    OnSuccess = fun(C) ->
                        Ctx = cb_context:set_db_name(C, cb_context:master_account_id(C)),
                        on_successful_app_load(Ctx, AppId)
                end,
    Context1 = cb_context:validate_request_data(kzd_applications:schema(), Context, OnSuccess),
    ErrCode = cb_context:resp_error_code(Context1),
    case cb_context:resp_status(Context1) of
        'success' ->
            Setters = [{fun kz_doc:set_id/2, AppId}
                      ,{fun set_uuid/2, AppId}
                      ,{fun kz_doc:set_type/2, kzd_applications:pvt_type()}
                      ],
            JObj = kz_doc:setters(kz_doc:public_fields(cb_context:doc(Context1), 'false'), Setters),
            crossbar_doc:handle_json_success(JObj, Context);
        'error' when ErrCode =:= 404 ->
            JObj = kz_doc:setters(cb_context:req_data(Context)
                                 ,[{fun kz_doc:set_id/2, AppId}
                                  ,{fun set_uuid/2, AppId}
                                  ,{fun kz_doc:set_type/2, kzd_applications:pvt_type()}
                                  ]),
            validate_uuid(kz_term:is_rfc4122_uuid(AppId), JObj, Context);
        _ ->
            Context1
    end.

-spec validate_uuid(boolean(), kz_json:object(), cb_context:context()) -> cb_context:context().
validate_uuid('true', JObj, Context) ->
    crossbar_doc:handle_json_success(JObj, Context);
validate_uuid('false', _JObj, Context) ->
    Message = kz_json:from_list([{<<"message">>, <<"uuid is not valid">>}]),
    cb_context:add_validation_error(<<"uuid">>, <<"not_valid">>, Message, Context).

-spec on_successful_app_load(cb_context:context(), path_token()) ->
          cb_context:context().
on_successful_app_load(Context, AppId) ->
    crossbar_doc:load_merge(AppId, Context, ?TYPE_CHECK_OPTION(kzd_applications:pvt_type())).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec load_application(cb_context:context(), path_token()) -> cb_context:context().
load_application(Context, AppId) ->
    Options = ?TYPE_CHECK_OPTION(kzd_applications:pvt_type()),
    crossbar_doc:load(AppId, Context, Options).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_entitlement(cb_context:context(), path_token(), path_token(), http_method()) -> cb_context:context().
validate_entitlement(Context, AppType, AppId, ?HTTP_GET) ->
    load_entitlement(Context, AppType, AppId);
validate_entitlement(Context, AppType, AppId, ?HTTP_PUT) ->
    OnSuccess = fun(Ctx) -> on_successful_entitlement(Ctx, AppType, AppId, 'undefined') end,
    cb_context:validate_request_data(kzd_application_entitlement:schema(), Context, OnSuccess);
validate_entitlement(Context, AppType, AppId, ?HTTP_POST) ->
    DocId = kzd_application_entitlement:db_id(AppType, AppId),
    OnSuccess = fun(C) -> on_successful_entitlement(C, AppType, AppId, DocId) end,
    cb_context:validate_request_data(kzd_application_entitlement:schema(), Context, OnSuccess);
validate_entitlement(Context, AppType, AppId, ?HTTP_DELETE) ->
    load_entitlement(Context, AppType, AppId).

-spec load_entitlement(cb_context:context(), path_token(), path_token()) ->
          cb_context:context().
load_entitlement(Context, AppType, AppId) ->
    DocId = kzd_application_entitlement:db_id(AppType, AppId),
    crossbar_doc:load(DocId, Context, ?TYPE_CHECK_OPTION(kzd_application_entitlement:pvt_type())).

-spec on_successful_entitlement(cb_context:context(), path_token(), path_token(), kz_term:api_ne_binary()) ->
          cb_context:context().
on_successful_entitlement(Context, AppType, AppId, 'undefined') ->
    Setters = [{fun kzd_application_entitlement:set_app_id/2, AppId}
              ,{fun kzd_application_entitlement:set_app_type/2, AppType}
              ,{fun kz_doc:set_id/2, kzd_application_entitlement:db_id(AppType, AppId)}
              ,{fun kz_doc:set_type/2, kzd_application_entitlement:pvt_type()}
              ],
    cb_context:set_doc(Context, kz_doc:setters(cb_context:doc(Context), Setters));
on_successful_entitlement(Context, AppType, AppId, DocId) ->
    Setters = [{fun kzd_application_entitlement:set_app_id/2, AppId}
              ,{fun kzd_application_entitlement:set_app_type/2, AppType}
              ],
    Context1 = cb_context:set_doc(Context, kz_doc:setters(cb_context:doc(Context), Setters)),
    crossbar_doc:load_merge(DocId, Context1, ?TYPE_CHECK_OPTION(kzd_application_entitlement:pvt_type())).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_blocklist(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary(), http_method()) -> cb_context:context().
validate_blocklist(Context, AppType, AppId, ?HTTP_GET) ->
    load_blocklist(Context, AppType, AppId);
validate_blocklist(Context, AppType, AppId, ?HTTP_PUT) ->
    OnSuccess = fun(C) -> on_successful_blocklist(C, AppType, AppId, 'undefined') end,
    cb_context:validate_request_data(kzd_application_blocklist:schema(), Context, OnSuccess);
validate_blocklist(Context, AppType, AppId, ?HTTP_POST) ->
    DocId = kzd_application_blocklist:db_id(AppType, AppId),
    OnSuccess = fun(C) -> on_successful_blocklist(C, AppType, AppId, DocId) end,
    cb_context:validate_request_data(kzd_application_blocklist:schema(), Context, OnSuccess);
validate_blocklist(Context, AppType, AppId, ?HTTP_DELETE) ->
    load_blocklist(Context, AppType, AppId).

-spec load_blocklist(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          cb_context:context().
load_blocklist(Context, AppType, AppId) ->
    DocId = kzd_application_blocklist:db_id(AppType, AppId),
    crossbar_doc:load(DocId, Context, ?TYPE_CHECK_OPTION(kzd_application_blocklist:pvt_type())).

-spec on_successful_blocklist(cb_context:context(), path_token(), path_token(), kz_term:api_ne_binary()) ->
          cb_context:context().
on_successful_blocklist(Context, AppType, AppId, 'undefined') ->
    Setters = [{fun kzd_application_blocklist:set_app_id/2, AppId}
              ,{fun kzd_application_blocklist:set_app_type/2, AppType}
              ,{fun kz_doc:set_id/2, kzd_application_blocklist:db_id(AppType, AppId)}
              ,{fun kz_doc:set_type/2, kzd_application_blocklist:pvt_type()}
              ],
    cb_context:set_doc(Context, kz_doc:setters(cb_context:doc(Context), Setters));
on_successful_blocklist(Context, AppType, AppId, DocId) ->
    Setters = [{fun kzd_application_blocklist:set_app_id/2, AppId}
              ,{fun kzd_application_blocklist:set_app_type/2, AppType}
              ],
    Context1 = cb_context:set_doc(Context, kz_doc:setters(cb_context:doc(Context), Setters)),
    crossbar_doc:load_merge(DocId, Context1, ?TYPE_CHECK_OPTION(kzd_application_blocklist:pvt_type())).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_icon(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_icon(Context, AppId, ?HTTP_GET) ->
    load_attachment(load_account_attachment_metadata(Context, AppId, ?ICON));
validate_icon(Context, AppId, ?HTTP_POST) ->
    validate_upload_attachment_binary(Context, AppId, cb_context:req_files(Context));
validate_icon(Context, AppId, ?HTTP_DELETE) ->
    case load_account_attachment_metadata(Context, AppId, ?ICON) of
        {'ok', Context1} -> Context1;
        {'error', Context1} -> Context1
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_screenshot(cb_context:context(), path_token(), path_token(), http_method()) -> cb_context:context().
validate_screenshot(Context, AppId, ScreenshotId, ?HTTP_GET) ->
    load_attachment(load_account_attachment_metadata(Context, AppId, {?SCREENSHOTS, ScreenshotId}));
validate_screenshot(Context, AppId, ScreenshotId, ?HTTP_DELETE) ->
    case load_account_attachment_metadata(Context, AppId, {?SCREENSHOTS, ScreenshotId}) of
        {'ok', Context1} -> Context1;
        {'error', Context1} -> Context1
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-type attach_type() :: kz_term:ne_binary() | {kz_term:ne_binary(), kz_term:ne_binary()}.

-spec load_account_attachment_metadata(cb_context:context(), path_token(), attach_type()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
load_account_attachment_metadata(Context, AppId, AttachType) ->
    case kz_term:is_not_empty(cb_context:fetch(Context, <<"attachment_name">>)) of
        'true' ->
            %% already loaded
            {'ok', Context};
        'false' ->
            Context1 = load_application(Context, AppId),
            case cb_context:resp_status(Context1) of
                'success' ->
                    store_attachment_metadata(Context1, AttachType, find_attachment(Context1, AttachType));
                _Status ->
                    {'error', Context1}
            end
    end.

-spec load_attachment_metadata(cb_context:context(), attach_type()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
load_attachment_metadata(Context, AttachType) ->
    case kz_term:is_not_empty(cb_context:fetch(Context, <<"attachment_name">>)) of
        'true' ->
            %% already loaded
            {'ok', Context};
        'false' ->
            case cb_context:resp_status(Context) of
                'success' ->
                    store_attachment_metadata(Context, AttachType, find_attachment(Context, AttachType));
                _Status ->
                    {'error', Context}
            end
    end.

-spec store_attachment_metadata(cb_context:context(), attach_type()
                               ,kz_either:either('not_found', {kz_term:ne_binary(), kz_json:object()})
                               ) -> kz_either:either(cb_context:context(), cb_context:context()).
store_attachment_metadata(Context, _AttachType, {'ok', {AttachmentName, AttachmentObject}}) ->
    Setters = [{fun cb_context:store/3, <<"attachment_name">>, AttachmentName}
              ,{fun cb_context:store/3, <<"attachment_meta">>, AttachmentObject}
              ],
    {'ok', cb_context:setters(Context, Setters)};
store_attachment_metadata(Context, AttachType, {'error', Reason}) ->
    Cause = not_found_cause(AttachType),
    lager:debug("failed to find attachment type ~p: ~p", [AttachType, Reason]),
    Message = kz_json:from_list(
                [{<<"message">>, <<"failed to find attachment">>}
                ,{<<"cause">>, Cause}
                ]
               ),
    {'error', cb_context:add_system_error(404, 'not_found', Message, Context)}.

-spec not_found_cause(attach_type()) -> kz_term:ne_binary().
not_found_cause({?SCREENSHOTS, Index}) ->
    <<"screenshot attachment at index ", (kz_term:to_binary(Index))/binary>>;
not_found_cause(?ICON) -> <<"icon attachment">>.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec find_attachment(cb_context:context(), attach_type()) ->
          kz_either:either('not_found'
                          ,{AttachmentName :: kz_term:ne_binary(), AttachmentObject :: kz_json:object()}
                          ).
find_attachment(Context, ?ICON) ->
    Lang = get_lang(Context),
    Doc = cb_context:doc(Context),
    cb_apps_util:find_attachment(Doc, kzd_applications:lang_icon(Doc, Lang));
find_attachment(Context, {?SCREENSHOTS, Number}) ->
    Lang = get_lang(Context),
    Doc = cb_context:doc(Context),
    cb_apps_util:find_attachment(Doc, kzd_applications:lang_screenshot_at_index(Doc, Lang, Number)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec get_lang(cb_context:context()) -> kz_term:api_ne_binary().
get_lang(Context) ->
    get_lang(Context, 'default').

-spec get_lang(cb_context:context(), 'default' | 'undefined') -> kz_term:api_ne_binary().
get_lang(Context, Default) ->
    case props:get_value(<<"i18n">>, cb_context:req_nouns(Context), Default) of
        [Lang|_] -> Lang;
        _ when Default =:= 'default' -> ?EN_LANGUAGE;
        _ -> 'undefined'
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec load_attachment(kz_either:either(cb_context:context(), cb_context:context())) ->
          cb_context:context().
load_attachment({'ok', Context}) ->
    Name = cb_context:fetch(Context, <<"attachment_name">>),
    Attachment = cb_context:fetch(Context, <<"attachment_meta">>),
    AccountDb = kz_doc:account_db(Attachment),
    crossbar_doc:load_attachment(kz_doc:id(Attachment), Name, [], cb_context:set_db_name(Context, AccountDb));
load_attachment({'error', Context}) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_upload_attachment_binary(cb_context:context(), kz_term:ne_binary(), any()) ->
          cb_context:context().
validate_upload_attachment_binary(Context, _AppId, []) ->
    cb_context:add_validation_error(<<"file">>
                                   ,<<"required">>
                                   ,kz_json:from_list([{<<"message">>, <<"Please provide an image file">>}])
                                   ,Context
                                   );
validate_upload_attachment_binary(Context, AppId, [{_Filename, _FileJObj}]) ->
    load_application(Context, AppId);
validate_upload_attachment_binary(Context, _, _Files) ->
    cb_context:add_validation_error(<<"file">>
                                   ,<<"maxItems">>
                                   ,kz_json:from_list([{<<"message">>, <<"please provide a single image file">>}])
                                   ,Context
                                   ).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec post_media_binary(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
post_media_binary(Context, AttachType) ->
    Language = get_lang(Context, 'undefined'),
    {AttachmentId, ContentType, AttachBin} = post_media_binary_id(Context, AttachType, Language),

    Context1 = update_doc_on_media_upload(Context, AttachmentId, AttachType, Language),
    case cb_context:resp_status(Context1) of
        'success' ->
            AttachOpts = [{'content_type', ContentType}],
            crossbar_doc:save_attachment(kz_doc:id(cb_context:doc(Context1))
                                        ,AttachmentId
                                        ,AttachBin
                                        ,Context1
                                        ,AttachOpts
                                        );
        _ ->
            Context1
    end.

-spec post_media_binary_id(cb_context:context(), kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          {kz_term:ne_binary(), kz_term:ne_binary(), binary()}.
post_media_binary_id(Context, AttachType, Language) ->
    [{Filename, FileObj}] = cb_context:req_files(Context),
    CT = kz_json:get_value([<<"headers">>, <<"content_type">>], FileObj, <<"application/octet-stream">>),
    Content = kz_json:get_value(<<"contents">>, FileObj),
    {kzd_applications:sanitize_attachment_name(Filename, CT, AttachType, Language), CT, Content}.

-spec update_doc_on_media_upload(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          cb_context:context().
update_doc_on_media_upload(Context, AttachmentId, AttachType, Language) ->
    Doc = set_attachment(cb_context:doc(Context), AttachmentId, AttachType, Language),
    crossbar_doc:save(cb_context:set_doc(Context, Doc)).

-spec set_attachment(kz_json:object(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          kz_json:object().
set_attachment(JObj, AttachmentId, ?ICON, 'undefined') ->
    kzd_applications:set_icon(JObj, AttachmentId);
set_attachment(JObj, AttachmentId, ?ICON, Language) ->
    kzd_applications:set_lang_icon(JObj, Language, AttachmentId);
set_attachment(JObj, AttachmentId, ?SCREENSHOTS, 'undefined') ->
    Screenshots = [A || A <- kzd_applications:screenshots(JObj, []),
                        A =/= AttachmentId
                  ],
    kzd_applications:set_screenshots(JObj, Screenshots ++ [AttachmentId]);
set_attachment(JObj, AttachmentId, ?SCREENSHOTS, Language) ->
    Screenshots = [A || A <- kzd_applications:lang_screenshots(JObj, Language, []),
                        A =/= AttachmentId
                  ],
    kzd_applications:set_lang_screenshots(JObj, Language, Screenshots ++ [AttachmentId]).

-spec delete_media_binary(cb_context:context(), path_token(), kz_term:ne_binary()) ->
          cb_context:context().
delete_media_binary(Context, AppId, AttachType) ->
    AName = cb_context:fetch(Context, <<"attachment_name">>),
    Doc = delete_media_from_key(Context, AttachType, get_lang(Context, 'undefined')),
    Context1 = crossbar_doc:save(cb_context:set_doc(Context, Doc)),
    case cb_context:resp_status(Context1) of
        'success' ->
            crossbar_doc:delete_attachment(AppId, AName, Context1);
        _ ->
            Context1
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec delete_media_from_key(cb_context:context(), kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          kz_json:object().
delete_media_from_key(Context, ?ICON, 'undefined') ->
    Doc = cb_context:doc(Context),
    kz_json:set_value(<<"icon">>, 'null', Doc);
delete_media_from_key(Context, ?ICON, Lang) ->
    Doc = cb_context:doc(Context),
    kz_json:set_value(kzd_applications:path_lang_icon(Lang), 'null', Doc);
delete_media_from_key(Context, ?SCREENSHOTS, 'undefined') ->
    Doc = cb_context:doc(Context),
    Screenshots = kzd_applications:screenshots(Doc, []),
    AName = cb_context:fetch(Context, <<"attachment_name">>),
    kzd_applications:set_screenshots(Doc, [S || S <- Screenshots, S =/= AName]);
delete_media_from_key(Context, ?SCREENSHOTS, Lang) ->
    Doc = cb_context:doc(Context),
    Screenshots = kzd_applications:lang_screenshots(Doc, Lang, []),
    AName = cb_context:fetch(Context, <<"attachment_name">>),
    kzd_applications:set_screenshots(Doc, [S || S <- Screenshots, S =/= AName]).
