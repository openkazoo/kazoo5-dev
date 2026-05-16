%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2013-2023, 2600Hz
%%% @doc Crossbar API for apps store.
%%% @author Peter Defebvre
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_apps_store).

-export([init/0
        ,allowed_methods/0, allowed_methods/1, allowed_methods/2, allowed_methods/3, allowed_methods/4
        ,resource_exists/0, resource_exists/1, resource_exists/2, resource_exists/3, resource_exists/4
        ,authenticate/1, authenticate/2, authenticate/3, authenticate/4, authenticate/5
        ,authorize/1, authorize/2, authorize/3, authorize/4, authorize/5
        ,validate/1, validate/2, validate/3, validate/4, validate/5
        ,content_types_provided/3 ,content_types_provided/4, content_types_provided/5
        ,content_types_accepted/4
        ,put/2, put/3
        ,post/2, post/3, post/4
        ,patch/2
        ,delete/2, delete/3, delete/4, delete/5
        ]).

-include("crossbar.hrl").

-define(ICON, <<"icon">>).
-define(SCREENSHOT, <<"screenshot">>).
-define(BLACKLIST, <<"blacklist">>).
-define(OVERRIDE, <<"override">>).

-define(MARKETPLACE, <<"marketplace">>).
-define(MARKET_ACTION_ENABLE, <<"enable">>).
-define(MARKET_ACTION_DISABLE, <<"disable">>).
-define(MARKET_ACTION_LINK, <<"link">>).
-define(MARKET_ACTION_UNLINK, <<"unlink">>).
-define(MARKET_ACTION_UPDATE, <<"update">>).

-define(WHITELABEL_MIME_TYPES, ?IMAGE_CONTENT_TYPES ++ ?BASE64_CONTENT_TYPES ++ ?MULTIPART_CONTENT_TYPES).

-define(EN_LANGUAGE, <<"en-US">>).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.content_types_provided.apps_store">>, ?MODULE, 'content_types_provided'),
    _ = crossbar_bindings:bind(<<"*.content_types_accepted.apps_store">>, ?MODULE, 'content_types_accepted'),
    _ = crossbar_bindings:bind(<<"*.allowed_methods.apps_store">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.apps_store">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.authenticate.apps_store">>, ?MODULE, 'authenticate'),
    _ = crossbar_bindings:bind(<<"*.authorize.apps_store">>, ?MODULE, 'authorize'),
    _ = crossbar_bindings:bind(<<"*.validate.apps_store">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.put.apps_store">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.apps_store">>, ?MODULE, 'post'),
    _ = crossbar_bindings:bind(<<"*.execute.patch.apps_store">>, ?MODULE, 'patch'),
    crossbar_bindings:bind(<<"*.execute.delete.apps_store">>, ?MODULE, 'delete').

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(?BLACKLIST) ->
    [?HTTP_GET, ?HTTP_POST];
allowed_methods(?MARKETPLACE) ->
    [?HTTP_GET, ?HTTP_PATCH];
allowed_methods(_AppId) ->
    [?HTTP_GET, ?HTTP_PUT, ?HTTP_POST, ?HTTP_DELETE].

-spec allowed_methods(path_token(), path_token()) -> http_methods().
allowed_methods(_AppId, ?ICON) ->
    [?HTTP_GET];
allowed_methods(_AppId, ?OVERRIDE) ->
    [?HTTP_GET, ?HTTP_PUT, ?HTTP_POST, ?HTTP_DELETE].

-spec allowed_methods(path_token(), path_token(), path_token()) -> http_methods().
allowed_methods(_AppId, ?OVERRIDE, ?ICON) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_DELETE];
allowed_methods(_AppId, ?OVERRIDE, ?SCREENSHOT) ->
    [?HTTP_POST];
allowed_methods(_AppId, ?SCREENSHOT, _AppScreenshotIndex) ->
    [?HTTP_GET].

-spec allowed_methods(path_token(), path_token(), path_token(), path_token()) -> http_methods().
allowed_methods(_AppId, ?OVERRIDE, ?SCREENSHOT, _AppScreenshotIndex) ->
    [?HTTP_GET, ?HTTP_DELETE].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% '''
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
resource_exists(_AppId, ?OVERRIDE, ?SCREENSHOT, _AppScreenshotIndex) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec content_types_provided(cb_context:context(), path_token(), path_token()) ->
          cb_context:context().
content_types_provided(Context, Id, ?ICON) ->
    app_content_types_provided(Context, Id, {<<"app">>, ?ICON}, cb_context:req_verb(Context));
content_types_provided(Context, _, _) -> Context.

-spec content_types_provided(cb_context:context(), path_token(), path_token(), path_token()) ->
          cb_context:context().
content_types_provided(Context, Id, ?OVERRIDE, ?ICON) ->
    app_content_types_provided(Context, Id, {?OVERRIDE, ?ICON}, cb_context:req_verb(Context));
content_types_provided(Context, Id, ?SCREENSHOT, Number) ->
    app_content_types_provided(Context, Id, {<<"app">>, {?SCREENSHOT, Number}}, cb_context:req_verb(Context));
content_types_provided(Context, _, _, _) -> Context.

-spec content_types_provided(cb_context:context(), path_token(), path_token(), path_token(), path_token()) ->
          cb_context:context().
content_types_provided(Context, Id, ?OVERRIDE, ?SCREENSHOT, Number) ->
    app_content_types_provided(Context, Id, {?OVERRIDE, {?SCREENSHOT, Number}}, cb_context:req_verb(Context)).

app_content_types_provided(Context, AppId, AttachType, ?HTTP_GET) ->
    case app_attachment_binary_meta(Context, AppId, AttachType) of
        {'ok', Context1} ->
            set_content_types_provided(Context1);
        {'error', Context1} ->
            Context1
    end;
app_content_types_provided(Context, _, _, _) -> Context.

-spec set_content_types_provided(cb_context:context()) -> cb_context:context().
set_content_types_provided(Context) ->
    Name = cb_context:fetch(Context, <<"attachment_id">>),
    JObj = cb_context:fetch(Context, <<"attachment_meta">>),

    case kz_doc:attachment_content_type(JObj, Name) of
        'undefined' ->
            Context;
        CT ->
            [Type, SubType] = binary:split(CT, <<"/">>),
            lager:debug("found attachment of content type: ~s/~s~n", [Type, SubType]),
            cb_context:set_content_types_provided(Context, [{'to_binary', [{Type, SubType}]}])
    end.

-spec content_types_accepted(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
content_types_accepted(Context, _AppId, ?OVERRIDE, ?ICON) ->
    content_types_accepted(Context, ?ICON, cb_context:req_verb(Context));
content_types_accepted(Context, _AppId, ?OVERRIDE, ?SCREENSHOT) ->
    content_types_accepted(Context, ?SCREENSHOT, cb_context:req_verb(Context)).

-spec content_types_accepted(cb_context:context(), path_token(), http_method()) ->
          cb_context:context().
content_types_accepted(Context, ?SCREENSHOT, ?HTTP_POST) ->
    CTA = [{'from_binary', ?WHITELABEL_MIME_TYPES}],
    cb_context:set_content_types_accepted(Context, CTA);
content_types_accepted(Context, ?ICON, ?HTTP_POST) ->
    CTA = [{'from_binary', ?WHITELABEL_MIME_TYPES}],
    cb_context:set_content_types_accepted(Context, CTA);
content_types_accepted(Context, _AttachType, _Verb) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec authenticate(cb_context:context()) -> boolean().
authenticate(Context) ->
    authenticate_nouns(cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authenticate(cb_context:context(), path_token()) -> boolean().
authenticate(Context, _) ->
    authenticate_nouns(cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authenticate(cb_context:context(), path_token(), path_token()) -> boolean().
authenticate(Context, _, _) ->
    authenticate_nouns(cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authenticate(cb_context:context(), path_token(), path_token(), path_token()) -> boolean().
authenticate(Context, _, _, _) ->
    authenticate_nouns(cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authenticate(cb_context:context(), path_token(), path_token(), path_token(), path_token()) -> boolean().
authenticate(Context, _, _, _, _) ->
    authenticate_nouns(cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authenticate_nouns(http_method(), req_nouns()) -> boolean().
authenticate_nouns(?HTTP_GET, [{<<"apps_store">>,[_Id, ?ICON]}]) ->
    lager:debug("authenticating request"),
    'true';
authenticate_nouns(?HTTP_GET, [{<<"apps_store">>,[_Id, ?SCREENSHOT, _Number]}]) ->
    lager:debug("authenticating request"),
    'true';
authenticate_nouns(_Verb, _Nouns) ->
    'false'.

-spec authorize(cb_context:context()) -> boolean().
authorize(Context) ->
    authorize_nouns(cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authorize(cb_context:context(), path_token()) ->
          boolean() |
          {'stop', cb_context:context()}.
authorize(Context, ?MARKETPLACE) ->
    case cb_context:is_superduper_admin(Context) of
        'true' -> 'true';
        'false' ->
            {'stop', cb_context:add_system_error('forbidden', Context)}
    end;
authorize(Context, _) ->
    authorize_nouns(cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authorize(cb_context:context(), path_token(), path_token()) -> boolean().
authorize(Context, _, _) ->
    authorize_nouns(cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authorize(cb_context:context(), path_token(), path_token(), path_token()) -> boolean().
authorize(Context, _, _, _) ->
    authorize_nouns(cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authorize(cb_context:context(), path_token(), path_token(), path_token(), path_token()) -> boolean().
authorize(Context, _, _, _, _) ->
    authorize_nouns(cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authorize_nouns(http_method(), req_nouns()) -> boolean().
authorize_nouns(?HTTP_GET, [{<<"apps_store">>,[_Id, ?ICON]}]) ->
    lager:debug("authorizing request"),
    'true';
authorize_nouns(?HTTP_GET, [{<<"apps_store">>,[_Id, ?SCREENSHOT, _Number]}]) ->
    lager:debug("authorizing request"),
    'true';
authorize_nouns(_Verb, _Nouns) ->
    'false'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    load_apps(Context).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ?BLACKLIST) ->
    validate_blacklist(Context, cb_context:req_verb(Context));
validate(Context, ?MARKETPLACE) ->
    case cb_context:req_verb(Context) of
        ?HTTP_GET ->
            send_marketplace_configs(Context);
        ?HTTP_PATCH ->
            validate_market_action(Context, cb_context:req_value(Context, <<"action">>))
    end;
validate(Context, Id) ->
    validate_app_id(Context, Id, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token(), path_token()) -> cb_context:context().
validate(Context, AppId, ?ICON) ->
    get_attachment(app_attachment_binary_meta(Context, AppId, {<<"app">>, ?ICON}));
validate(Context, AppId, ?OVERRIDE) ->
    validate_app_whitelabel_doc(Context, AppId, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
validate(Context, AppId, ?OVERRIDE, ?ICON) ->
    validate_app_whitelabel_binary(Context, AppId, ?ICON, cb_context:req_verb(Context));
validate(Context, AppId, ?OVERRIDE, ?SCREENSHOT) ->
    validate_app_whitelabel_binary(Context, AppId, ?SCREENSHOT, cb_context:req_verb(Context));
validate(Context, AppId, ?SCREENSHOT, Number) ->
    get_attachment(app_attachment_binary_meta(Context, AppId, {<<"app">>, {?SCREENSHOT, Number}})).

-spec validate(cb_context:context(), path_token(), path_token(), path_token(), path_token()) -> cb_context:context().
validate(Context, AppId, ?OVERRIDE, ?SCREENSHOT, Number) ->
    validate_app_whitelabel_binary(Context, AppId, ?SCREENSHOT, Number, cb_context:req_verb(Context)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, ?BLACKLIST) ->
    ReqData = cb_context:req_data(Context),
    Blacklist = kzd_apps_store:blacklist(ReqData),
    Doc = kzd_apps_store:set_blacklist(cb_context:doc(Context), Blacklist),
    return_only_blacklist(
      crossbar_doc:save(
        cb_context:set_doc(Context, Doc)
       )
     );
post(Context, AppId) ->
    Context1 = crossbar_doc:save(Context),
    case cb_context:resp_status(Context1) of
        'success' ->
            JObj = cb_context:doc(Context1),
            RespData = kz_json:get_value(AppId, kzd_apps_store:apps(JObj)),
            cb_context:set_resp_data(Context1, RespData);
        _Status -> Context1
    end.

-spec post(cb_context:context(), path_token(), path_token()) -> cb_context:context().
post(Context, _AppId, ?OVERRIDE) ->
    crossbar_doc:save(Context).

-spec post(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
post(Context, _AppId, ?OVERRIDE, ?ICON) ->
    post_media_binary(Context, ?ICON);
post(Context, _AppId, ?OVERRIDE, ?SCREENSHOT) ->
    post_media_binary(Context, ?SCREENSHOT).

-spec post_media_binary(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
post_media_binary(Context, AttachType) ->
    Language = get_lang(Context),
    {AttachmentId, ContentType, AttachBin} = post_media_binary_id(Context, AttachType, Language),

    Context1 = update_media_doc(Context, AttachmentId, AttachType, Language),
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

-spec update_media_doc(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> cb_context:context().
update_media_doc(Context, AttachmentId, AttachType, Language) ->
    Doc = cb_context:doc(Context),
    JObj0 = sanitize_attachments(set_attachment(Doc, AttachmentId, AttachType, Language)
                                ,AttachmentId
                                ,AttachType
                                ,Language
                                ),
    JObj = kz_doc:delete_attachment(JObj0, AttachmentId),
    crossbar_doc:save(cb_context:set_doc(Context, JObj)).

-spec set_attachment(kz_json:object(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          kz_json:object().
set_attachment(JObj, AttachmentId, ?ICON, Language) ->
    kzd_app:set_i18n_icon(JObj, Language, AttachmentId);
set_attachment(JObj, AttachmentId, ?SCREENSHOT, Language) ->
    Screenshots = [AttachmentId
                  | [A || A <- kzd_app:i18n_screenshots(JObj, Language, maybe_en_default(JObj, ?SCREENSHOT, Language)),
                          A =/= AttachmentId
                    ]
                  ],
    kzd_app:set_i18n_screenshots(JObj, Language, Screenshots).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec put(cb_context:context(), path_token()) -> cb_context:context().
put(Context, Id) ->
    Context1 = crossbar_doc:save(Context),
    case cb_context:resp_status(Context1) of
        'success' ->
            JObj = cb_context:doc(Context1),
            RespData = kz_json:get_value(Id, kzd_apps_store:apps(JObj)),
            cb_context:set_resp_data(Context1, RespData);
        _Status -> Context1
    end.

-spec put(cb_context:context(), path_token(), path_token()) -> cb_context:context().
put(Context, _AppId, ?OVERRIDE) ->
    crossbar_doc:save(Context).


%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, ?MARKETPLACE) ->
    patch_market_action(Context, cb_context:req_value(Context, <<"action">>)).

patch_market_action(Context, ?MARKET_ACTION_ENABLE) ->
    _ = appex_client_config:set_is_enabled('true'),
    send_marketplace_configs(Context);
patch_market_action(Context, ?MARKET_ACTION_DISABLE) ->
    %% don't stop kazoo_appex to let it clean out apps when they stop
    _ = appex_client_config:set_is_enabled('false'),
    send_marketplace_configs(Context);
patch_market_action(Context, ?MARKET_ACTION_LINK) ->
    Doc = cb_context:doc(Context),
    Settings = kz_json:get_json_value(<<"settings">>, Doc, kz_json:new()),
    Cluster = process_update_local_settings(Settings),
    AccessCode = kz_json:get_ne_binary_value(<<"access_code">>, Doc),
    case appex_client_client:link_cluster(kz_json:set_value(<<"access_code">>, AccessCode, Cluster)) of
        {'ok', RespData} ->
            crossbar_doc:handle_datamgr_success(RespData, Context);
        {'error', Error} ->
            cb_context:add_system_error(500, <<"appex_passthrough_error">>, Error, Context)
    end;
patch_market_action(Context, ?MARKET_ACTION_UNLINK) ->
    %% don't stop kazoo_appex to let it clean out apps when they stop
    case appex_client_client:unlink_cluster() of
        {'ok', _RespData} ->
            _ = appex_client_config:set_is_enabled('false'),
            send_marketplace_configs(Context);
        {'error', Error} ->
            cb_context:add_system_error(500, <<"appex_passthrough_error">>, Error, Context)
    end;
patch_market_action(Context, ?MARKET_ACTION_UPDATE) ->
    update_market_settings(Context).

update_market_settings(Context) ->
    Settings = kz_json:get_json_value(<<"settings">>, cb_context:doc(Context), kz_json:new()),
    Cluster = process_update_local_settings(Settings),
    update_remote_market_settings(Context, Cluster).

process_update_local_settings(Settings) ->
    LocalKeys = [<<"api_url">>, <<"is_aio_cluster">>],
    Cluster = update_local_settings(LocalKeys, Settings, kz_json:new()),
    Name = kz_json:get_ne_binary_value(<<"name">>, Settings, 'undefined'),
    kz_json:set_value(<<"name">>, Name, Cluster).

update_local_settings([], _Settings, Acc) ->
    Acc;
update_local_settings([<<"api_url">> = Key | Rest], JObj, Acc) ->
    case kz_json:get_ne_binary_value(Key, JObj) of
        'undefined' ->
            update_local_settings(Rest, JObj, Acc);
        ApiUrl ->
            _ = appex_client_config:set_api_url(ApiUrl),
            update_local_settings(Rest, JObj, Acc)
    end;
update_local_settings([<<"is_aio_cluster">> = Key | Rest], JObj, Acc) ->
    case kz_json:get_boolean_value(Key, JObj) of
        'undefined' ->
            update_local_settings(Rest, JObj, Acc);
        Bool ->
            _ = appex_client_config:set_is_aio_cluster(Bool),
            update_local_settings(Rest, JObj, kz_json:set_value(<<"is_aio">>, Bool, Acc))
    end;
update_local_settings([_|Keys], JObj, Acc) ->
    update_local_settings(Keys, JObj, Acc).

update_remote_market_settings(Context, Cluster) ->
    case appex_client_client:update_cluster(Cluster) of
        {'ok', RespData} ->
            crossbar_doc:handle_datamgr_success(RespData, Context);
        {'error', Error} ->
            cb_context:add_system_error(500, <<"appex_passthrough_error">>, Error, Context)
    end.

send_marketplace_configs(Context) ->
    case appex_client_config:get_public_configs() of
        {'ok', RespData} ->
            crossbar_doc:handle_datamgr_success(RespData, Context);
        {'error', Error} ->
            cb_context:add_system_error(500, <<"appex_passthrough_error">>, Error, Context)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _Id) ->
    Context1 = crossbar_doc:save(Context),
    case cb_context:resp_status(Context1) of
        'success' ->
            cb_context:set_resp_data(Context1, kz_json:new());
        _Status -> Context1
    end.

-spec delete(cb_context:context(), path_token(), path_token()) -> cb_context:context().
delete(Context, _AppId, ?OVERRIDE) ->
    crossbar_doc:delete(Context).

-spec delete(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
delete(Context, _AppId, ?OVERRIDE, ?ICON) ->
    AttachmentId = cb_context:fetch(Context, <<"attachment_id">>),
    JObj = delete_image_from_doc(cb_context:doc(Context), AttachmentId, ?ICON, get_lang(Context)),

    %% removing attachment stub will remove attachment from document
    crossbar_doc:save(cb_context:set_doc(Context, kz_doc:delete_attachment(JObj, AttachmentId))).

-spec delete(cb_context:context(), path_token(), path_token(), path_token(), path_token()) -> cb_context:context().
delete(Context, _AppId, ?OVERRIDE, ?SCREENSHOT, _Number) ->
    AttachmentId = cb_context:fetch(Context, <<"attachment_id">>),
    JObj = delete_image_from_doc(cb_context:doc(Context), AttachmentId, ?SCREENSHOT, get_lang(Context)),

    %% removing attachment stub will remove attachment from document
    crossbar_doc:save(cb_context:set_doc(Context, kz_doc:delete_attachment(JObj, AttachmentId))).

-spec delete_image_from_doc(kz_json:object(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          kz_json:object().
delete_image_from_doc(Doc, AttachmentId, ?ICON, Language) ->
    JObj = kz_json:delete_key(kzd_app:path_i18_icon(Language), Doc),
    sanitize_attachments(remove_path_if_empty(JObj, kzd_app:path_i18_lang(Language)), AttachmentId, ?ICON, Language);
delete_image_from_doc(Doc, AttachmentId, ?SCREENSHOT, Language) ->
    Screenshots = [A || A <- kzd_app:i18n_screenshots(Doc, Language, maybe_en_default(Doc, ?SCREENSHOT, Language)), A =/= AttachmentId],
    sanitize_attachments(remove_path_if_empty(kzd_app:set_i18n_screenshots(Doc, Language, Screenshots)
                                             ,kzd_app:path_i18_screenshots(Language)
                                             )
                        ,AttachmentId
                        ,?SCREENSHOT
                        ,Language
                        ).

maybe_en_default(JObj, ?SCREENSHOT, ?EN_LANGUAGE) -> kzd_app:screenshots(JObj);
maybe_en_default(JObj, ?ICON, ?EN_LANGUAGE) -> kzd_app:screenshots(JObj);
maybe_en_default(_, _, _) -> [].

%% Because we merge app whitelabel into app doc we need to be careful to not
%% leave empty list or object around to mess up with the merge in the future.
-spec remove_path_if_empty(kz_json:object(), kz_json:keys()) -> kz_json:object().
remove_path_if_empty(JObj, []) -> JObj;
remove_path_if_empty(JObj, Path) ->
    case kz_term:is_empty(kz_json:get_value(Path, JObj)) of
        'true' ->
            remove_path_if_empty(kz_json:delete_key(Path, JObj), lists:droplast(Path));
        'false' ->
            remove_path_if_empty(JObj, lists:droplast(Path))
    end.

sanitize_attachments(JObj, AttachmentId, Type, Language) ->
    Funs = [fun remove_root_keys/4
           ,fun sync_images/4
           ],
    lists:foldl(fun(Fun, Acc) -> Fun(Acc, AttachmentId, Type, Language) end
               ,JObj
               ,Funs
               ).

%% we already set `en' image in i18n part of document, removing from root
remove_root_keys(JObj, _AttachmentId, ?ICON, ?EN_LANGUAGE) ->
    kz_json:delete_keys([<<"icon">>], JObj);
remove_root_keys(JObj, _AttachmentId, ?SCREENSHOT, ?EN_LANGUAGE) ->
    kz_json:delete_keys([<<"screenshots">>], JObj);
remove_root_keys(JObj, _AttachmentId, _Type, _Language) ->
    JObj.

%% remove any attachments that is not in i18n part of document
sync_images(JObj, AttachmentId, _Type, _Language) ->
    sync_images(JObj, AttachmentId, kz_doc:attachments(JObj)).

sync_images(JObj, AttachmentId, 'undefined') ->
    lager:info("no images on ~s", [AttachmentId]),
    JObj;
sync_images(JObj, AttachmentId, DocAttachments) ->
    AllImages = all_i18n_images(kzd_app:i18n(JObj)),
    Attachments = [{Name, AttJObj}
                   || {Name, AttJObj} <- kz_json:to_proplist(DocAttachments),
                      maps:is_key(Name, AllImages)
                          orelse Name =:= AttachmentId
                  ],
    kz_json:set_value(kz_doc:path_attachments(), kz_json:from_list(Attachments), JObj).

all_i18n_images('undefined') -> #{};
all_i18n_images(Images) ->
    kz_json:foldl(fun i18n_image_fold/3
                 ,#{}
                 ,kz_json:flatten(Images)
                 ).

i18n_image_fold([Lang, <<"icon">>], Icon, Acc) ->
    Acc#{Icon => kzd_app:path_i18_icon(Lang)};
i18n_image_fold([Lang, <<"screenshots">>], Screenshots, Acc) ->
    maps:merge(Acc
              ,maps:from_list(
                 [{Screenshot, kzd_app:path_i18_screenshots(Lang)}
                  || Screenshot <- Screenshots
                 ]
                )
              );
i18n_image_fold(_Path, _Value, Acc) ->
    Acc.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_blacklist(cb_context:context(), http_method()) -> cb_context:context().
validate_blacklist(Context, ?HTTP_POST) ->
    validate_blacklist(Context);
validate_blacklist(Context, ?HTTP_GET) ->
    Context1 = validate_blacklist(Context),
    return_only_blacklist(Context1).

-spec validate_blacklist(cb_context:context()) -> cb_context:context().
validate_blacklist(Context) ->
    AuthAccountId = cb_context:auth_account_id(Context),
    AccountId = cb_context:account_id(Context),
    case kzd_accounts:is_in_account_hierarchy(AuthAccountId, AccountId) of
        'false' -> cb_context:add_system_error('forbidden', Context);
        'true' -> load_apps_store(Context)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_app_id(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_app_id(Context, Id, ?HTTP_GET) ->
    get_app(Context, Id);
validate_app_id(Context, Id, ReqMethod) ->
    validate_app_store(Context, Id, ReqMethod).

-spec validate_app_store(cb_context:context(), kz_term:ne_binary(), http_method()) -> cb_context:context().
validate_app_store(Context, Id, ?HTTP_PUT) ->
    Context1 = validate_apps_store_modification(Context, Id),
    case cb_context:resp_status(Context1) of
        'success' -> prepare_install(Context1, Id);
        _ -> Context1
    end;
validate_app_store(Context, Id, ?HTTP_DELETE) ->
    Context1 = validate_apps_store_modification(Context, Id),
    case cb_context:resp_status(Context1) of
        'success' -> prepare_uninstall(Context1, Id);
        _ -> Context1
    end;
validate_app_store(Context, Id, ?HTTP_POST) ->
    Context1 = validate_apps_store_modification(Context, Id),
    case cb_context:resp_status(Context1) of
        'success' -> prepare_update(Context1, Id);
        _ -> Context1
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_app_whitelabel_doc(cb_context:context(), kz_term:ne_binary(), http_method()) -> cb_context:context().
validate_app_whitelabel_doc(Context, AppId, ?HTTP_PUT) ->
    validate_request(Context, AppId, 'undefined');
validate_app_whitelabel_doc(Context, AppId, ?HTTP_POST) ->
    validate_request(Context, AppId, cb_apps_util:app_whitelabel_doc_id(AppId));
validate_app_whitelabel_doc(Context, AppId, ?HTTP_GET) ->
    load_app_whitelabel_doc(Context, AppId);
validate_app_whitelabel_doc(Context, AppId, ?HTTP_DELETE) ->
    load_app_whitelabel_doc(Context, AppId).

validate_app_whitelabel_binary(Context, AppId, ?ICON, ?HTTP_GET) ->
    get_attachment(app_attachment_binary_meta(Context, AppId, {?OVERRIDE, ?ICON}));
validate_app_whitelabel_binary(Context, AppId, ?ICON, ?HTTP_DELETE) ->
    validate_delete_app_whitelabel_binary(Context, AppId, ?ICON);
validate_app_whitelabel_binary(Context, AppId, ?ICON, ?HTTP_POST) ->
    validate_upload_app_whitelabel_binary(Context, AppId, cb_context:req_files(Context));
validate_app_whitelabel_binary(Context, AppId, ?SCREENSHOT, ?HTTP_POST) ->
    validate_upload_app_whitelabel_binary(Context, AppId, cb_context:req_files(Context)).

validate_app_whitelabel_binary(Context, AppId, ?SCREENSHOT, Number, ?HTTP_GET) ->
    get_attachment(app_attachment_binary_meta(Context, AppId, {?OVERRIDE, {?SCREENSHOT, Number}}));
validate_app_whitelabel_binary(Context, AppId, ?SCREENSHOT, Number, ?HTTP_DELETE) ->
    validate_delete_app_whitelabel_binary(Context, AppId, {?SCREENSHOT, Number}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_market_action(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
validate_market_action(Context, ?MARKET_ACTION_ENABLE) ->
    set_ctx_success(Context);
validate_market_action(Context, ?MARKET_ACTION_DISABLE) ->
    set_ctx_success(Context);
validate_market_action(Context, ?MARKET_ACTION_LINK) ->
    validate_market_settings(Context, <<"access_code">>);
validate_market_action(Context, ?MARKET_ACTION_UNLINK) ->
    set_ctx_success(Context);
validate_market_action(Context, ?MARKET_ACTION_UPDATE) ->
    validate_market_settings(Context);
validate_market_action(Context, 'undefined') ->
    Message = kz_json:from_list([{<<"message">>, <<"action is required but it is missing">>}]),
    cb_context:add_validation_error(<<"action">>, <<"required">>, Message, Context);
validate_market_action(Context, _BadAction) ->
    Message = kz_json:from_list([{<<"message">>, <<"invalid action">>}]),
    cb_context:add_system_error(400, 'bad_request', Message, Context).

-spec validate_market_settings(cb_context:context()) -> cb_context:context().
validate_market_settings(Context) ->
    OnSuccess = fun set_ctx_success/1,
    cb_context:validate_request_data(<<"marketplace_settings">>, Context, OnSuccess).

-spec validate_market_settings(cb_context:context(), kz_json:key()) -> cb_context:context().
validate_market_settings(Context, Key) ->
    OnSuccess = fun(C) -> on_successful_market_settings_validation(C, Key) end,
    cb_context:validate_request_data(<<"marketplace_settings">>, Context, OnSuccess).

-spec on_successful_market_settings_validation(cb_context:context(), kz_json:key()) -> cb_context:context().
on_successful_market_settings_validation(Context, Key) ->
    case kz_json:get_ne_value(Key, cb_context:doc(Context)) of
        'undefined' ->
            Message = kz_json:from_list([{<<"message">>, <<Key/binary, " is required but it is missing">>}]),
            cb_context:add_validation_error(Key, <<"required">>, Message, Context);
        _ ->
            set_ctx_success(Context)
    end.

-spec set_ctx_success(cb_context:context()) -> cb_context:context().
set_ctx_success(Context) ->
    cb_context:setters(Context
                      ,[{fun cb_context:set_resp_status/2, 'success'}
                       ,{fun cb_context:set_doc/2, kz_doc:public_fields(cb_context:req_data(Context))}
                       ]
                      ).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec load_apps(cb_context:context()) -> cb_context:context().
load_apps(Context) ->
    load_apps(Context, cb_context:account_id(Context)).

-spec load_apps(cb_context:context(), kz_term:api_ne_binary()) -> cb_context:context().
load_apps(Context, 'undefined') ->
    Message = kz_json:from_list([{<<"message">>, <<"account ID is required in url">>}]),
    cb_context:add_validation_error(<<"account_id">>, <<"required">>, Message, Context);
load_apps(Context, AccountId) ->
    Apps = [kz_json:from_list([{<<"doc">>, App}]) || App <- cb_apps_util:allowed_apps(AccountId)],
    Options = [{'mapper', fun normalize_apps_result/1}
              ,{'run_mapper', 'true'}
              ,{'field_key', 'filtermap'}
              ],
    crossbar_view:prepare_docs(cb_context:set_doc(Context, Apps), Options).

-spec normalize_apps_result(kz_json:objects()) -> kz_json:objects().
normalize_apps_result(Apps) ->
    normalize_apps_result(Apps, []).

-spec normalize_apps_result(kz_json:objects(), kz_json:objects()) -> kz_json:objects().
normalize_apps_result([], Acc) -> Acc;
normalize_apps_result([JObj|JObjs], Acc) ->
    App = kz_json:get_json_value(<<"doc">>, JObj),
    case kzd_app:is_published(App) of
        'false' -> normalize_apps_result(JObjs, Acc);
        'true' ->
            Prop = [{<<"account_id">>, kz_doc:account_id(App)}
                   ,{<<"masqueradable">>, kzd_app:masqueradable(App)}
                   ],
            normalize_apps_result(JObjs, [kz_json:set_values(Prop, kz_doc:public_fields(App))| Acc])
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec return_only_blacklist(cb_context:context()) -> cb_context:context().
return_only_blacklist(Context) ->
    case cb_context:resp_status(Context) of
        'success' ->
            RespData = cb_context:resp_data(Context),
            Blacklist = kzd_apps_store:blacklist(RespData),
            NewRespData =
                kz_json:from_list([
                                   {<<"blacklist">>, Blacklist}
                                  ]),
            cb_context:set_resp_data(Context, NewRespData);
        _ -> Context
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_apps_store_modification(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
validate_apps_store_modification(Context, Id) ->
    Context1 = can_modify_apps_store_doc(Context, Id),
    case cb_context:resp_status(Context1) of
        'success' -> load_apps_store(Context1);
        _ -> Context1
    end.

-spec can_modify_apps_store_doc(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
can_modify_apps_store_doc(Context, Id) ->
    AccountId = cb_context:account_id(Context),
    case cb_apps_util:allowed_app(AccountId, Id) of
        'undefined' ->
            Props = [{<<"details">>, Id}],
            cb_context:add_system_error('forbidden', kz_json:from_list(Props), Context);
        App ->
            cb_context:store(cb_context:set_resp_status(Context, 'success')
                            ,Id
                            ,App
                            )
    end.

-spec load_apps_store(cb_context:context()) -> cb_context:context().
load_apps_store(Context) ->
    Context1 = crossbar_doc:load(kzd_apps_store:id(), Context, ?TYPE_CHECK_OPTION_ANY),
    case {cb_context:resp_status(Context1)
         ,cb_context:resp_error_code(Context1)
         }
    of
        {'error', 404} ->
            AccountId = cb_context:account_id(Context),
            cb_context:setters(Context
                              ,[{fun cb_context:set_resp_status/2, 'success'}
                               ,{fun cb_context:set_resp_data/2, kz_json:new()}
                               ,{fun cb_context:set_doc/2, kzd_apps_store:new(AccountId)}
                               ]
                              );
        {'success', _} -> Context1;
        {'error', _} -> Context1
    end.

%%------------------------------------------------------------------------------
%% @doc install a new app on the account
%% @end
%%------------------------------------------------------------------------------
-spec prepare_install(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
prepare_install(Context, Id) ->
    Doc = cb_context:doc(Context),
    Apps = kzd_apps_store:apps(Doc),
    case kz_json:get_value(Id, Apps) of
        'undefined' ->
            Data = cb_context:req_data(Context),
            AppName = kz_json:get_value(<<"name">>, cb_context:fetch(Context, Id)),
            UpdatedApps =
                kz_json:set_value(Id
                                 ,kz_json:set_value(<<"name">>, AppName, Data)
                                 ,Apps
                                 ),
            UpdatedDoc = kzd_apps_store:set_apps(Doc, UpdatedApps),
            cb_context:set_doc(Context, UpdatedDoc);
        _ ->
            crossbar_util:response('error', <<"Application already installed">>, 400, Context)
    end.

%%------------------------------------------------------------------------------
%% @doc Remove app from account
%% valid
%% @end
%%------------------------------------------------------------------------------
-spec prepare_uninstall(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
prepare_uninstall(Context, Id) ->
    Doc = cb_context:doc(Context),
    Apps = kzd_apps_store:apps(Doc),
    case kz_json:get_value(Id, Apps) of
        'undefined' ->
            crossbar_util:response('error', <<"Application is not installed">>, 400, Context);
        _ ->
            UpdatedApps = kz_json:delete_key(Id, Apps),
            UpdatedDoc = kzd_apps_store:set_apps(Doc, UpdatedApps),
            cb_context:set_doc(Context, UpdatedDoc)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec prepare_update(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
prepare_update(Context, Id) ->
    Doc = cb_context:doc(Context),
    Apps = kzd_apps_store:apps(Doc),
    case kz_json:get_value(Id, Apps) of
        'undefined' ->
            crossbar_util:response('error', <<"Application is not installed">>, 400, Context);
        _ ->
            Data = cb_context:req_data(Context),
            AppName = kz_json:get_value(<<"name">>, cb_context:fetch(Context, Id)),
            UpdatedApps =
                kz_json:set_value(Id
                                 ,kz_json:set_value(<<"name">>, AppName, Data)
                                 ,Apps
                                 ),
            UpdatedDoc = kzd_apps_store:set_apps(Doc, UpdatedApps),
            cb_context:set_doc(Context, UpdatedDoc)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-type attach_type() :: {kz_term:ne_binary(), kz_term:ne_binary()} |
                       {kz_term:ne_binary(), {kz_term:ne_binary(), kz_term:ne_binary()}}.
validate_delete_app_whitelabel_binary(Context, AppId, Type) ->
    case app_attachment_binary_meta(Context, AppId, {?OVERRIDE, Type}) of
        {'ok', Context1} ->
            load_app_whitelabel_doc(Context1, AppId);
        {'error', Context1} ->
            Context1
    end.

-spec validate_upload_app_whitelabel_binary(cb_context:context(), kz_term:ne_binary(), any()) ->
          cb_context:context().
validate_upload_app_whitelabel_binary(Context, _AppId, []) ->
    cb_context:add_validation_error(<<"file">>
                                   ,<<"required">>
                                   ,kz_json:from_list([{<<"message">>, <<"Please provide an image file">>}])
                                   ,Context
                                   );
validate_upload_app_whitelabel_binary(Context, AppId, [{_Filename, _FileJObj}]) ->
    load_app_whitelabel_doc(Context, AppId);
validate_upload_app_whitelabel_binary(Context, _, _Files) ->
    cb_context:add_validation_error(<<"file">>
                                   ,<<"maxItems">>
                                   ,kz_json:from_list([{<<"message">>, <<"please provide a single html file">>}])
                                   ,Context
                                   ).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec get_app(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
get_app(Context, AppId) ->
    MaybeAccountId = maybe_find_account_id_from_domain(Context),
    case cb_context:is_context(MaybeAccountId) of
        'true' -> MaybeAccountId;
        'false' -> load_app_for_account(Context, AppId, MaybeAccountId)
    end.

-spec maybe_find_account_id_from_domain(cb_context:context()) ->
          kz_term:api_ne_binary() | cb_context:context().
maybe_find_account_id_from_domain(Context) ->
    maybe_find_account_id_from_domain(Context, props:get_value(<<"whitelabel">>, cb_context:req_nouns(Context))).

-spec maybe_find_account_id_from_domain(cb_context:context(), kz_term:api_ne_binaries()) ->
          kz_term:api_ne_binary() | cb_context:context().
maybe_find_account_id_from_domain(Context, 'undefined') ->
    cb_context:account_id(Context);
maybe_find_account_id_from_domain(Context, [Domain | _]) ->
    lager:debug("finding account id for domain '~s'", [Domain]),
    WhitelabelContext = cb_whitelabel:find_whitelabel_from_domain(Context, Domain),
    case {cb_context:resp_error_code(WhitelabelContext)
         ,cb_context:resp_status(WhitelabelContext)
         }
    of
        {404, 'error'} ->
            lager:debug("no account with domain '~s' were found, maybe get account id from path", [Domain]),
            cb_context:account_id(Context);
        {_, 'success'} ->
            cb_context:account_id(WhitelabelContext);
        _ ->
            %% Retuning error here only for non 404 error.
            %% This avoid returning different results in case of db timeout or other non 404 errors.
            lager:debug("failed to find account with domain ~s", [Domain]),
            WhitelabelContext
    end.

-spec load_app_for_account(cb_context:context(), kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          cb_context:context().
load_app_for_account(Context, AppId, 'undefined') ->
    lager:debug("no account id, loading app ~s from master account", [AppId]),
    load_app_from_master_account(Context, AppId);
load_app_for_account(Context, AppId, AccountId) ->
    lager:debug("getting app ~s for account ~s", [AppId, AccountId]),
    case cb_apps_util:allowed_app(AccountId, AppId) of
        'undefined' ->
            lager:debug("app ~s is not allowed for account ~s", [AppId, AccountId]),
            crossbar_doc:handle_datamgr_errors('not_found', AppId, Context);
        App ->
            JObj = kz_json:set_value(<<"account_id">>, kzd_app:account_id(App), App),
            Context1 = crossbar_doc:handle_datamgr_success(JObj, Context),
            Setters = [{fun cb_context:store/3, 'db_doc', JObj}
                      ,{fun cb_context:store/3, AppId, cb_context:doc(Context1)}
                      ],
            cb_context:setters(Context1, Setters)
    end.

-spec load_app_from_master_account(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
load_app_from_master_account(Context, AppId) ->
    load_app_from_master_account(Context, AppId, kapps_util:get_master_account_id()).

load_app_from_master_account(Context, AppId, {'ok', MasterAccountId}) ->
    Context1 = crossbar_doc:load(AppId, cb_context:set_db_name(Context, MasterAccountId), ?TYPE_CHECK_OPTION(<<"app">>)),
    case cb_context:resp_status(Context1) of
        'success' ->
            JObj = cb_apps_util:ensure_master_account_id(MasterAccountId, cb_context:doc(Context1)),
            AppJObj = kz_json:set_value(<<"account_id">>, MasterAccountId, JObj),
            cb_context:setters(Context1
                              ,[{fun cb_context:set_doc/2, AppJObj}
                               ,{fun cb_context:store/3, 'db_doc', AppJObj}
                               ]
                              );
        _ ->
            Context1
    end;
load_app_from_master_account(Context, AppId, {'error', _Reason}) ->
    lager:debug("failed to find master account id: ~p", [_Reason]),
    crossbar_doc:handle_datamgr_errors('not_found', AppId, Context).

%%------------------------------------------------------------------------------
%% @doc Load application whitelabel document from the database
%% @end
%%------------------------------------------------------------------------------
-spec load_app_whitelabel_doc(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
load_app_whitelabel_doc(Context, AppId) ->
    crossbar_doc:load(cb_apps_util:app_whitelabel_doc_id(AppId), Context, ?TYPE_CHECK_OPTION(<<"app_whitelabel">>)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_request(cb_context:context(), kz_term:ne_binary(), kz_term:api_ne_binary()) -> cb_context:context().
validate_request(Context, AppId, AppWhitelabelId) ->
    OnSuccess = fun(C) -> on_successful_validation(C, AppId, AppWhitelabelId) end,
    cb_context:validate_request_data(<<"app_whitelabel">>, Context, OnSuccess).

-spec on_successful_validation(cb_context:context(), kz_term:ne_binary(), kz_term:api_binary()) -> cb_context:context().
on_successful_validation(Context, AppId, 'undefined') ->
    Doc = kz_json:set_values([{<<"pvt_type">>, <<"app_whitelabel">>}
                             ,{<<"_id">>, cb_apps_util:app_whitelabel_doc_id(AppId)}
                             ], cb_context:doc(Context)),
    cb_context:set_doc(Context, Doc);
on_successful_validation(Context, _AppId, AppWhitelabelId) ->
    crossbar_doc:load_merge(AppWhitelabelId, Context, ?TYPE_CHECK_OPTION(<<"app_whitelabel">>)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec get_lang(cb_context:context()) -> kz_term:ne_binary().
get_lang(Context) ->
    case props:get_value(<<"i18n">>, cb_context:req_nouns(Context), []) of
        [Lang] -> Lang;
        _ -> ?EN_LANGUAGE
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec app_attachment_binary_meta(cb_context:context(), kz_term:ne_binary(), attach_type()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
app_attachment_binary_meta(Context, AppId, AttachType) ->
    case kz_term:is_not_empty(cb_context:fetch(Context, <<"attachment_id">>)) of
        'true' -> {'ok', Context};
        'false' ->
            attachment_binary_meta(Context, AttachType, load_attachment_doc(Context, AppId, AttachType))
    end.

-spec load_attachment_doc(cb_context:context(), kz_term:ne_binary(), attach_type()) ->
          cb_context:context().
load_attachment_doc(Context, AppId, {<<"app">>, _}) ->
    get_app(Context, AppId);
load_attachment_doc(Context, AppId, {?OVERRIDE, _}) ->
    load_app_whitelabel_doc(Context, AppId).

-spec attachment_binary_meta(cb_context:context(), attach_type(), cb_context:context()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
attachment_binary_meta(Context, AttachType, AppContext) ->
    case cb_context:resp_status(AppContext) of
        'success' ->
            Doc = cb_context:doc(AppContext),
            Lang = get_lang(Context),
            set_binary_meta(Context, AttachType, app_attachment_id(AttachType, Doc, Lang));
        _Status ->
            {'error', AppContext}
    end.

-spec set_binary_meta(cb_context:context(), attach_type()
                     ,kz_either:either('not_found', {kz_term:ne_binary(), kz_json:object()})
                     ) -> kz_either:either(cb_context:context(), cb_context:context()).
set_binary_meta(Context, _AttachType, {'ok', {AttachmentName, AttachmentObject}}) ->
    Setters = [{fun cb_context:store/3, <<"attachment_id">>, AttachmentName}
              ,{fun cb_context:store/3, <<"attachment_meta">>, AttachmentObject}
              ],
    {'ok', cb_context:setters(Context, Setters)};
set_binary_meta(Context, AttachType, {'error', Reason}) ->
    Type = attach_type_text(AttachType),
    lager:debug("failed to find attachment type ~p: ~p", [AttachType, Reason]),
    Message = kz_json:from_list(
                [{<<"message">>, <<"failed to find attachment">>}
                ,{<<"cause">>, Type}
                ]
               ),
    {'error', cb_context:add_system_error(404, 'not_found', Message,  Context)}.

attach_type_text({_, {_Screen, Index}}) ->
    <<"screenshot attachment at index ", (kz_term:to_binary(Index))/binary>>;
attach_type_text({_, T}) -> <<T/binary, " attachment">>.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec get_attachment(kz_either:either(cb_context:context(), cb_context:context())) ->
          cb_context:context().
get_attachment({'ok', Context}) ->
    Name = cb_context:fetch(Context, <<"attachment_id">>),
    JObj = cb_context:fetch(Context, <<"attachment_meta">>),

    AccountDb = kz_doc:account_db(JObj),

    crossbar_doc:load_attachment(kz_doc:id(JObj), Name, [], cb_context:set_db_name(Context, AccountDb));
get_attachment({'error', Context}) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec app_attachment_id(attach_type(), kz_json:object(), kz_term:ne_binary()) ->
          kz_either:either('not_found'
                          ,{AttachmentName::kz_term:ne_binary(), AttachmentObject::kz_json:object()}
                          ).
app_attachment_id({<<"app">>, ?ICON}, Doc, Language) ->
    cb_apps_util:find_attachment(Doc, kzd_app:i18n_icon(Doc, Language));
app_attachment_id({<<"app">>, {?SCREENSHOT, Number}}, Doc, Language) ->
    ScreenshotName = resolve_screenshot_name(kzd_app:i18n_screenshots(Doc, Language), Number),
    cb_apps_util:find_attachment(Doc, ScreenshotName);
app_attachment_id({?OVERRIDE, ?ICON}, Doc, Language) ->
    override_attachment_id(Doc, kzd_app:i18n_icon(Doc, Language));
app_attachment_id({?OVERRIDE, {?SCREENSHOT, Number}}, Doc, Language) ->
    ScreenshotName = resolve_screenshot_name(kzd_app:i18n_screenshots(Doc, Language), Number),
    override_attachment_id(Doc, ScreenshotName).

-spec override_attachment_id(kz_json:object(), kz_term:api_ne_binary()) ->
          kz_either:either('not_found'
                          ,{AttachmentName::kz_term:ne_binary(), AttachmentObject::kz_json:object()}
                          ).
override_attachment_id(_, 'undefined') ->
    {'error', 'not_found'};
override_attachment_id(Doc, AttachmentName) ->
    case kz_doc:attachment(Doc, AttachmentName) of
        'undefined' ->
            {'error', 'not_found'};
        Attachment ->
            case kz_json:is_empty(Attachment) of
                'true' ->
                    {'error', 'not_found'};
                'false' ->
                    {'ok', {AttachmentName, Doc}}
            end
    end.

-spec resolve_screenshot_name(kz_term:ne_binaries(), kz_term:ne_binary() | integer()) ->
          kz_term:api_ne_binary().
resolve_screenshot_name(Screenshots, Key) ->
    try lists:nth(kz_term:to_integer(Key) + 1, Screenshots)
    catch
        _:_ ->
            case lists:member(Key, Screenshots) of
                'true' -> Key;
                'false' -> 'undefined'
            end
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec post_media_binary_id(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          {kz_term:ne_binary(), kz_term:ne_binary(), binary()}.
post_media_binary_id(Context, AttachType, Language) ->
    [{Filename, FileObj}] = cb_context:req_files(Context),
    CT = kz_json:get_value([<<"headers">>, <<"content_type">>], FileObj, <<"application/octet-stream">>),
    Content = kz_json:get_value(<<"contents">>, FileObj),
    {attachment_name(Filename, CT, AttachType, Language), CT, Content}.

-spec attachment_name(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
attachment_name(Filename, CT, AttachType, Language) ->
    Generators = [fun maybe_create_basename/1
                 ,fun(A) -> maybe_add_extension(A, CT) end
                 ,fun(A) -> attachment_prefix(AttachType, Language, A) end
                 ],
    lists:foldl(fun(F, A) -> F(A) end, Filename, Generators).

-spec attachment_prefix(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
attachment_prefix(Type, Language) ->
    <<Type/binary, "-", Language/binary, "-">>.

-spec attachment_prefix(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
attachment_prefix(Type, Language, AttachName) ->
    <<(attachment_prefix(Type, Language))/binary, AttachName/binary>>.

-spec maybe_create_basename(kz_term:api_binary()) -> kz_term:ne_binary().
maybe_create_basename(A) ->
    case kz_term:is_empty(A) of
        'true' -> kz_binary:rand_hex(6);
        'false' -> A
    end.

-spec maybe_add_extension(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
maybe_add_extension(A, CT) ->
    case kz_term:is_empty(filename:extension(A)) of
        'false' -> A;
        'true' ->
            <<A/binary, ".", (kz_mime:to_extension(CT))/binary>>
    end.
