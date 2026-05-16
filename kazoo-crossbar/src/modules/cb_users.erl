%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2025, 2600Hz
%%% @doc Users module
%%% Handle client requests for user documents
%%%
%%%
%%% @author Karl Anderson
%%% @author James Aimonetti
%%% @author SIPLABS, LLC (Ilya Ashchepkov)
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_users).

-export([init/0
        ,allowed_methods/0, allowed_methods/1, allowed_methods/2
        ,content_types_provided/1, content_types_provided/2, content_types_provided/3
        ,resource_exists/0, resource_exists/1, resource_exists/2
        ,validate_resource/1, validate_resource/2, validate_resource/3, validate_resource/4
        ,authenticate/1
        ,authorize/1
        ,validate/1, validate/2, validate/3
        ,put/1
        ,post/2, post/3
        ,delete/2, delete/3
        ,patch/2
        ]).

-include("crossbar.hrl").

-define(LIST_BY_PRESENCE_ID, <<"devices/listing_by_presence_id">>).
-define(CROSSBAR_LISTING_BY_OWNER_ID, <<"crossbar_listings/by_ownerid">>).
-define(CROSSBAR_LISTING_BY_OWNER_ID_TYPE, <<"crossbar_listings/by_ownerid_type">>).

-define(VCARD, <<"vcard">>).
-define(PHOTO, <<"photo">>).
-define(QRCODE, <<"qrcode">>).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.users">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.content_types_provided.users">>, ?MODULE, 'content_types_provided'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.users">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.authenticate.users">>, ?MODULE, 'authenticate'),
    _ = crossbar_bindings:bind(<<"*.authorize.users">>, ?MODULE, 'authorize'),
    _ = crossbar_bindings:bind(<<"*.validate_resource.users">>, ?MODULE, 'validate_resource'),
    _ = crossbar_bindings:bind(<<"*.validate.users">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.put.users">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.users">>, ?MODULE, 'post'),
    _ = crossbar_bindings:bind(<<"*.execute.delete.users">>, ?MODULE, 'delete'),
    _ = crossbar_bindings:bind(<<"*.execute.patch.users">>, ?MODULE, 'patch'),
    'ok'.

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
allowed_methods(_UserId) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_DELETE, ?HTTP_PATCH].

-spec allowed_methods(path_token(), path_token()) -> http_methods().
allowed_methods(_UserId, ?PHOTO) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_DELETE];
allowed_methods(_UserId, ?QRCODE) ->
    [?HTTP_GET];
allowed_methods(_UserId, ?VCARD) ->
    [?HTTP_GET].

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

-spec content_types_provided(cb_context:context()) ->
          cb_context:context().
content_types_provided(Context) ->
    Context.

-spec content_types_provided(cb_context:context(), path_token()) ->
          cb_context:context().
content_types_provided(Context, _UserId) ->
    Context.

-spec content_types_provided(cb_context:context(), path_token(), path_token()) ->
          cb_context:context().
content_types_provided(Context, _UserId, ?VCARD) ->
    cb_context:set_content_types_provided(Context, [{'to_binary', [{<<"text">>, <<"x-vcard">>}
                                                                  ,{<<"text">>, <<"directory">>}
                                                                  ]}
                                                   ]);
content_types_provided(Context, _UserId, ?PHOTO) ->
    case cb_context:method(Context) of
        ?HTTP_GET ->
            cb_context:set_content_types_provided(Context
                                                 ,[{'to_binary', [{<<"application">>, <<"octet-stream">>}
                                                                 ,{<<"application">>, <<"base64">>}
                                                                 ]}
                                                  ]);
        _ -> Context
    end;
content_types_provided(Context, _UserId, ?QRCODE) ->
    case cb_context:method(Context) of
        ?HTTP_GET ->
            cb_context:set_content_types_provided(Context, [{'to_binary', [{<<"image">>, <<"png">>}]}]);
        _ -> Context
    end;
content_types_provided(Context, _UserId, _PathToken) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc This function determines if the provided list of Nouns are valid.
%% Failure here returns `404 Not Found'.
%% @end
%%------------------------------------------------------------------------------

-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_UserId) -> 'true'.

-spec resource_exists(path_token(), path_token()) -> 'true'.
resource_exists(_UserId, ?VCARD) -> 'true';
resource_exists(_UserId, ?PHOTO) -> 'true';
resource_exists(_UserId, ?QRCODE) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

-spec authenticate(cb_context:context()) -> 'true'.
authenticate(Context) ->
    authenticate_users(cb_context:req_nouns(Context), cb_context:req_verb(Context)).

authenticate_users(?USERS_QCALL_NOUNS(_UserId, _Number), ?HTTP_GET) ->
    lager:debug("authenticating request"),
    'true';
authenticate_users(_Nouns, _Verb) -> 'false'.

-spec authorize(cb_context:context()) -> 'true'.
authorize(Context) ->
    authorize_users(cb_context:req_nouns(Context), cb_context:req_verb(Context)).

authorize_users(?USERS_QCALL_NOUNS(_UserId, _Number), ?HTTP_GET) ->
    lager:debug("authorizing request"),
    'true';
authorize_users(_Nouns, _Verb) -> 'false'.

%%------------------------------------------------------------------------------
%% @doc This function determines if the provided list of Nouns and Resource Ids are valid.
%% If valid, updates Context with userId
%%
%% Failure here returns `404 Not Found'.
%% @end
%%------------------------------------------------------------------------------

-spec validate_resource(cb_context:context()) -> cb_context:context().
validate_resource(Context) -> Context.

-spec validate_resource(cb_context:context(), path_token()) -> cb_context:context().
validate_resource(Context, UserId) ->
    validate_user_id(UserId, Context).

-spec validate_resource(cb_context:context(), path_token(), path_token()) -> cb_context:context().
validate_resource(Context, UserId, _Token) ->
    validate_user_id(UserId, Context).

-spec validate_resource(cb_context:context(), path_token(), path_token(), path_token()) -> cb_context:context().
validate_resource(Context, UserId, _Token1, _Token2) -> validate_user_id(UserId, Context).

-spec validate_user_id(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
validate_user_id(UserId, Context) ->
    case kz_datamgr:open_cache_doc(cb_context:db_name(Context), UserId) of
        {'ok', Doc} -> validate_user_id(UserId, Context, Doc);
        {'error', 'not_found'} ->
            cb_context:add_system_error('bad_identifier'
                                       ,kz_json:from_list([{<<"cause">>, UserId}])
                                       ,Context
                                       );
        {'error', _R} -> crossbar_util:response_db_fatal(Context)
    end.

-spec validate_user_id(kz_term:api_binary(), cb_context:context(), kz_json:object()) -> cb_context:context().
validate_user_id(UserId, Context, Doc) ->
    case kz_doc:is_soft_deleted(Doc) of
        'true' ->
            Msg = kz_json:from_list([{<<"cause">>, UserId}]),
            cb_context:add_system_error('bad_identifier', Msg, Context);
        'false'->
            cb_context:setters(Context
                              ,[{fun cb_context:set_user_id/2, UserId}
                               ,{fun cb_context:set_resp_status/2, 'success'}
                               ])
    end.

%%------------------------------------------------------------------------------
%% @doc This function determines if the parameters and content are correct
%% for this request
%%
%% Failure here returns 400.
%% @end
%%------------------------------------------------------------------------------

-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_users(Context, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, UserId) ->
    validate_user(Context, UserId, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token(), path_token()) -> cb_context:context().
validate(Context, UserId, ?VCARD) ->
    Context1 = load_user(UserId, Context),
    case cb_context:has_errors(Context1) of
        'true' -> Context1;
        'false' -> convert_to_vcard(Context1)
    end;
validate(Context, UserId, ?PHOTO) ->
    validate_photo(Context, UserId, cb_context:req_verb(Context));
validate(Context, UserId, ?QRCODE) ->
    validate_qrcode(Context, UserId).

validate_users(Context, ?HTTP_GET) ->
    load_users_summary(Context);
validate_users(Context, ?HTTP_PUT) ->
    validate_request('undefined', Context).

validate_user(Context, UserId, ?HTTP_GET) ->
    load_user(UserId, Context);
validate_user(Context, UserId, ?HTTP_POST) ->
    UserJObj = kzd_users:maybe_migrate_user_addresses(cb_context:req_data(Context)),
    Context1 = load_user(UserId, cb_context:set_req_data(Context, UserJObj)),
    validate_request(UserId, Context1);
validate_user(Context, UserId, ?HTTP_DELETE) ->
    validate_delete(Context, UserId);
validate_user(Context, UserId, ?HTTP_PATCH) ->
    validate_patch(UserId, Context).

validate_photo(Context, UserId, ?HTTP_POST) ->
    load_user(UserId, Context);
validate_photo(Context, UserId, ?HTTP_DELETE) ->
    load_user(UserId, Context);
validate_photo(Context, UserId, ?HTTP_GET) ->
    load_attachment(UserId, ?PHOTO, Context).

validate_qrcode(Context, UserId) ->
    {'ok', QRCode} = kz_auth_qrcode:create(cb_context:account_id(Context), UserId),
    Headers =
        #{<<"content-disposition">> => <<"attachment; filename=qr-", UserId/binary, ".png">>
         ,<<"content-type">> => <<"image/png">>
         },
    cb_context:setters(Context
                      ,[{fun cb_context:set_resp_data/2, QRCode}
                       ,{fun cb_context:set_resp_etag/2, kz_binary:md5(QRCode)}
                       ,{fun cb_context:add_resp_headers/2, Headers}
                       ,{fun cb_context:set_resp_status/2, 'success'}
                       ]).

-spec validate_delete(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
validate_delete(Context, UserId) ->
    Context1 = cb_context:validate_request_data(<<"users_delete">>, Context),
    ObjectTypes = cb_context:req_value(Context, <<"object_types">>),
    maybe_load_user_objects(UserId, load_user(UserId, Context1), ObjectTypes).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, UserId) ->
    Context1 = cb_modules_util:take_sync_field(Context),
    sync_sip_data(Context1),
    Context2 = crossbar_doc:save(cb_modules_util:remove_plaintext_password(Context1)),
    case cb_context:resp_status(Context2) of
        'success' ->
            _ = maybe_update_devices_presence(Context2),
            _ = maybe_send_desktop_welcome_email(Context2),
            _ = crossbar_notify_util:maybe_notify_user_features_enabled(Context2, UserId),
            cb_context:add_metadata_values(Context2, user_metadata(cb_context:doc(Context)));
        _ -> Context2
    end.

-spec sync_sip_data(cb_context:context()) -> 'ok'.
sync_sip_data(Context) ->
    NewDoc = cb_context:doc(Context),
    AccountId = cb_context:account_id(Context),
    ShouldReboot = cb_context:req_value(Context, <<"reboot">>),

    case cb_context:fetch(Context, 'sync') of
        'false' -> 'ok';
        'true' -> provisioner_util:sync_user(AccountId, ShouldReboot);
        'force' -> provisioner_util:force_sync_user(AccountId, NewDoc, ShouldReboot)
    end.

-spec post(cb_context:context(), kz_term:ne_binary(), path_token()) -> cb_context:context().
post(Context, UserId, ?PHOTO) ->
    [{_FileName, FileObj}] = cb_context:req_files(Context),
    Headers = kz_json:get_value(<<"headers">>, FileObj),
    CT = kz_json:get_value(<<"content_type">>, Headers),
    Content = kz_json:get_value(<<"contents">>, FileObj),
    Opts = [{'content_type', CT}],
    crossbar_doc:save_attachment(UserId, ?PHOTO, Content, Context, Opts).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    Context1 = crossbar_doc:save(Context),
    case cb_context:resp_status(Context1) of
        'success' ->
            _ = maybe_send_email(Context1),
            Context1;
        _ -> Context1
    end.

%%%%------------------------------------------------------------------------------
%% @doc
%% If `object_types' was declared and `object_types /= all':
%%     Default to delete: user (of course, duh), callflow, vmbox.
%%      DELETE /v2/accounts/{ACCOUNT_ID}/callflows/{CALLFLOW_ID}
%%      DELETE /v2/accounts/{ACCOUNT_ID}/vmboxes/{VMBOX_ID}
%%      DELETE /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}
%%
%%     Default to unassign: device, conference, number.
%%      POST /v2/accounts/{ACCOUNT_ID}/devices/{DEVICE_ID} -d {DEVICE_OBJECT_WITHOUT_OWNER_ID}
%%      DELETE /callflows request will also cause numbers associated to this callflow to be released/unassigned.
%% Else:
%%     Only delete the user:
%%     DELETE /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}
%%%% @end
%%%%------------------------------------------------------------------------------
-spec delete(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
delete(Context, UserId) ->
    delete(Context, UserId, cb_context:req_value(Context, <<"object_types">>, [])).

-spec delete(cb_context:context(), kz_term:ne_binary(), path_token() | kz_term:api_ne_binary() | kz_term:ne_binaries()) -> cb_context:context().
delete(Context, _UserId, []) ->
    lager:debug("not object_types specified to be deleted along ~p user", [_UserId]),
    crossbar_doc:delete(Context);
delete(Context, UserId, ?PHOTO) ->
    lager:debug("deleting user's photo"),
    crossbar_doc:delete_attachment(UserId, ?PHOTO, Context);
delete(Context, _UserId, _ObjectTypes) ->
    lager:debug("deleting ~p object_types owned by ~p user", [_ObjectTypes, _UserId]),
    UserJObjsResps = delete_user_objects(Context),
    Context1 = crossbar_doc:delete(Context),
    RespData = kz_json:set_value(<<"object_types">>, UserJObjsResps, cb_context:resp_data(Context1)),
    Context2 = cb_context:set_resp_data(Context1, RespData),
    case 'success' =:= cb_context:resp_status(Context2)
        andalso did_any_user_object_delete_failed(UserJObjsResps)
    of
        'true' ->
            %% If user itself was deleted successfully and any of the requests to delete any of the user's
            %% objects failed, set "custom" failure response.
            Setters = [{fun cb_context:set_resp_status/2, 'error'}
                      ,{fun cb_context:set_resp_error_code/2, 500}
                      ,{fun cb_context:set_resp_error_msg/2
                       ,<<"At least one object failed to be deleted">>
                       }
                      ],
            cb_context:setters(Context2, Setters);
        'false' ->
            %% Either user failed to be deleted or everything (user + user_objects) was deleted successfully.
            Context2
    end.

-spec did_any_user_object_delete_failed(kz_json:objects()) -> boolean().
did_any_user_object_delete_failed(UserJObjsResps) ->
    lists:any(fun(RespJObj) ->
                      'success' =/= kz_json:get_atom_value(<<"status">>, RespJObj)
              end
             ,UserJObjsResps
             ).

%%------------------------------------------------------------------------------
%% @doc Delete all the objects loaded in Context's doc field.
%%
%% Returns a list of JSON objects, one for each object that was tried to be deleted.
%% By default, every response has these keys: type, id, and status. If DELETE request failed, the
%% response will have these extra keys: error_code, and error_msg.
%% See build_and_log_user_object_response/3 function for more details.
%% @end
%%------------------------------------------------------------------------------
-spec delete_user_objects(cb_context:context()) -> kz_json:objects().
delete_user_objects(Context) ->
    UserObjects = cb_context:fetch(Context, <<"objects">>, []),
    lager:debug("maybe deleting: ~p", [[{kz_doc:type(Obj), kz_doc:id(Obj)} || Obj <- UserObjects]]),
    lists:foldl(fun(JObj, Acc) ->
                        fold_delete_user_objects(Context, {kz_doc:type(JObj), JObj}, Acc)
                end
               ,[]
               ,UserObjects
               ).

-spec fold_delete_user_objects(cb_context:context(), {kz_term:ne_binary(), kz_doc:doc()}, kz_json:objects()) ->
          kz_json:objects().
fold_delete_user_objects(Context, {<<"callflow">>=Type, JObj}=ToDelete, Acc) ->
    ObjTypes = cb_context:req_value(Context, <<"object_types">>),
    %% Even though callflow may not be going to be deleted, maybe the numbers associated to it should
    %% be deleted. In which case, callflow numbers' list should be updated.
    Acc1 = case <<"all">> =:= ObjTypes
               orelse lists:member(Type, ObjTypes)
           of
               'true' -> maybe_delete_user_object(Context, ToDelete, Acc);
               'false' -> maybe_update_user_callflow(Context, JObj, Acc)
           end,
    maybe_delete_cf_numbers(Context, {<<"phone_numbers">>, kzd_callflows:numbers(JObj)}, Acc1);
fold_delete_user_objects(Context, ToDelete, Acc) ->
    maybe_delete_user_object(Context, ToDelete, Acc).

-spec maybe_update_user_callflow(cb_context:context(), kzd_callflows:doc(), kz_json:objects()) ->
          kz_json:objects().
maybe_update_user_callflow(Context, CFDoc, Acc) ->
    CFId = kz_doc:id(CFDoc),
    CFNumbers = kzd_callflows:numbers(CFDoc),
    case CFNumbers -- [Num || Num <- CFNumbers, knm_converters:is_reconcilable(Num)] of
        CFNumbers ->
            lager:debug("not reconcilable numbers found, not need to update callflow/~s", [CFId]),
            Acc;
        NewCFNums ->
            lager:debug("updating callflow/~s", [CFId]),
            Setters = [{fun cb_context:set_req_data/2, kzd_callflows:set_numbers(CFDoc, NewCFNums)}
                      ,{fun cb_context:set_req_verb/2, ?HTTP_POST}
                      ],
            Context1 = cb_context:setters(Context, Setters),
            [validate_and_maybe_run_cb_action(Context1, <<"callflow">>, 'post', CFId) | Acc]
    end.

-spec maybe_delete_cf_numbers(cb_context:context(), {kz_term:ne_binary(), kz_term:ne_binaries()}, kz_json:objects()) ->
          kz_json:objects().
maybe_delete_cf_numbers(Context, {<<"phone_numbers">>=Type, Nums}, Acc) ->
    ObjTypes = cb_context:req_value(Context, <<"object_types">>),
    Numbers = [Num || Num <- Nums, knm_converters:is_reconcilable(Num)],
    case (<<"all">> =:= ObjTypes
          orelse lists:member(<<"phone_numbers">>, ObjTypes))
        %% If there are not numbers, do not try to delete "it", otherwise, it may generate confusing
        %% errors like 404 and will cause the whole user's delete request to be marked as failed.
        andalso length(Numbers) > 0
    of
        'true' ->
            lager:debug("deleting ~s/~s/~p", [Type, ?NUMBERS_COLLECTION, Numbers]),
            Context1 = cb_context:set_req_data(Context, kz_json:from_list([{<<"numbers">>, Numbers}])),
            [validate_and_maybe_run_cb_action(Context1, Type, ?NUMBERS_COLLECTION) | Acc];
        'false' ->
            lager:debug("not deleting numbers or not numbers to delete were found"),
            Acc
    end.

-spec maybe_delete_user_object(cb_context:context(), {kz_term:ne_binary(), kz_doc:doc()}, kz_json:objects()) ->
          kz_json:objects().
maybe_delete_user_object(Context, {<<Type/binary>>, JObj}, Acc) ->
    DocId = kz_doc:id(JObj),
    lager:debug("deleting ~s/~s", [Type, DocId]),
    [validate_and_maybe_run_cb_action(Context, Type, DocId) | Acc].

-spec validate_and_maybe_run_cb_action(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          kz_json:object().
validate_and_maybe_run_cb_action(Context, <<Type/binary>>, <<ObjId/binary>>) ->
    validate_and_maybe_run_cb_action(Context, Type, 'delete', ObjId).

-type cb_action() :: 'post' | 'delete'.
-spec validate_and_maybe_run_cb_action(cb_context:context(), kz_term:ne_binary(), cb_action(), kz_term:ne_binary()) ->
          kz_json:object().
validate_and_maybe_run_cb_action(Context, <<Type/binary>>, Action, <<ObjId/binary>>) ->
    Mod = cb_module_by_type(Type),
    Context1 = maybe_run_cb_action(Mod:validate(Context, ObjId), Mod, Action, ObjId),
    %% When `Type=phone_numbers', `ObjId=?NUMBERS_COLLECTION', and since the ObjId is being used for
    %% building the response, it makes more sense to use the actual numbers as the id instead of the
    %% ?NUMBERS_COLLECTION path token.
    Id = case Type of
             <<"phone_numbers">> -> kz_json:get_list_value(<<"numbers">>, cb_context:req_data(Context));
             _ -> ObjId
         end,
    build_and_log_user_object_response(Type, Id, Context1).

-spec maybe_run_cb_action(cb_context:context(), cb_module(), cb_action(), kz_term:ne_binary()) ->
          cb_context:context().
maybe_run_cb_action(Context, Mod, Action, <<ObjId/binary>>) ->
    case cb_context:resp_status(Context) of
        'success' -> Mod:Action(Context, ObjId);
        _ -> Context
    end.

-spec build_and_log_user_object_response(kz_term:ne_binary(), kz_term:ne_binary() | kz_term:ne_binaries(), cb_context:context()) ->
          kz_json:object().
build_and_log_user_object_response(<<Type/binary>>, Id, Context) ->
    Status = cb_context:resp_status(Context),
    BaseResp = kz_json:from_list([{<<"type">>, Type}
                                 ,{<<"id">>, Id}
                                 ,{<<"status">>, kz_term:to_binary(Status)}
                                 ]),
    Resp = case Status of
               'success' ->
                   BaseResp;
               _ ->
                   kz_json:set_values([{<<"error_code">>, cb_context:resp_error_code(Context)}
                                      ,{<<"error_msg">>, cb_context:resp_error_msg(Context)}
                                      ]
                                     ,BaseResp
                                     )
           end,
    lager:debug("DELETE ~s/~s -> ~s: ~p", [Type, Id, Status, Resp]),
    Resp.

-type cb_module() :: atom().
-spec cb_module_by_type(kz_term:ne_binary()) -> cb_module().
cb_module_by_type(<<"phone_numbers">>) -> 'cb_phone_numbers';
cb_module_by_type(<<"callflow">>) -> 'cb_callflows';
cb_module_by_type(<<"vmbox">>) -> 'cb_vmboxes';
cb_module_by_type(<<"device">>) -> 'cb_devices';
cb_module_by_type(<<"conference">>) -> 'cb_conferences';
cb_module_by_type(<<"faxbox">>) -> 'cb_faxboxes';
cb_module_by_type(<<"media">>) -> 'cb_media'. %% vmbox unavailable greeting.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, UserId) ->
    post(Context, UserId).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

-spec load_attachment(kz_term:ne_binary(), cb_context:context()) ->
          cb_context:context().
load_attachment(AttachmentId, Context) ->
    Headers =
        #{<<"content-disposition">> => <<"attachment; filename=", AttachmentId/binary>>
         ,<<"content-type">> => kz_doc:attachment_content_type(cb_context:doc(Context), AttachmentId)
         },
    LoadedContext = crossbar_doc:load_attachment(cb_context:doc(Context)
                                                ,AttachmentId
                                                ,?TYPE_CHECK_OPTION(kzd_users:type())
                                                ,Context
                                                ),
    cb_context:add_resp_headers(LoadedContext, Headers).

-spec load_attachment(kz_term:ne_binary(), kz_term:ne_binary(), cb_context:context()) ->
          cb_context:context().
load_attachment(UserId, AttachmentId, Context) ->
    Context1 = load_user(UserId, Context),
    case cb_context:resp_status(Context1) of
        'success' -> load_attachment(AttachmentId, Context1);
        _ -> Context1
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec maybe_update_devices_presence(cb_context:context()) -> 'ok'.
maybe_update_devices_presence(Context) ->
    DbDoc = cb_context:fetch(Context, 'db_doc'),
    Doc = cb_context:doc(Context),
    case kzd_users:presence_id(DbDoc) =:= kzd_users:presence_id(Doc) of
        'true' ->
            lager:debug("presence_id did not change, ignoring");
        'false' ->
            update_devices_presence(Context)
    end.

-spec update_devices_presence(cb_context:context()) -> 'ok'.
update_devices_presence(Context) ->
    case user_devices(Context) of
        {'error', _R} ->
            lager:error("failed to query view ~s: ~p", [?LIST_BY_PRESENCE_ID, _R]);
        {'ok', []} ->
            lager:debug("no presence IDs found for user");
        {'ok', DeviceDocs} ->
            update_devices_presence(Context, DeviceDocs)
    end.

-spec update_devices_presence(cb_context:context(), kzd_devices:docs()) -> 'ok'.
update_devices_presence(Context, DeviceDocs) ->
    lists:foreach(fun(DeviceDoc) -> update_device_presence(Context, DeviceDoc) end
                 ,DeviceDocs
                 ).

-spec user_devices(cb_context:context()) ->
          {'ok', kzd_devices:docs()} |
          {'error', any()}.
user_devices(Context) ->
    UserId = kz_doc:id(cb_context:doc(Context)),
    AccountDb = cb_context:db_name(Context),

    Options = [{'key', UserId}, 'include_docs'],
    case kz_datamgr:get_results(AccountDb, ?LIST_BY_PRESENCE_ID, Options) of
        {'error', _}=E -> E;
        {'ok', JObjs} ->
            {'ok', [kz_json:get_value(<<"doc">>, JObj) || JObj <- JObjs]}
    end.

-spec update_device_presence(cb_context:context(), kzd_devices:doc()) -> pid().
update_device_presence(Context, DeviceDoc) ->
    AuthToken = cb_context:auth_token(Context),
    ReqId = cb_context:req_id(Context),

    lager:debug("re-provisioning device ~s", [kz_doc:id(DeviceDoc)]),

    kz_process:spawn(fun() ->
                             kz_log:put_callid(ReqId),
                             provisioner_v5:update_device(DeviceDoc, AuthToken)
                     end).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec maybe_send_email(cb_context:context()) -> 'ok'.
maybe_send_email(Context) ->
    case kz_term:is_true(cb_context:req_value(Context, <<"send_email_on_creation">>, 'true')) of
        'false' -> 'ok';
        'true' -> send_email(Context)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec send_email(cb_context:context()) -> 'ok'.
send_email(Context) ->
    lager:debug("trying to publish new user notification"),
    Doc = cb_context:doc(Context),
    Req = [{<<"Account-ID">>, cb_context:account_id(Context)}
          ,{<<"User-ID">>, kz_doc:id(Doc)}
          ,{<<"Password">>, cb_context:fetch(Context, <<"req_password">>)}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    kapps_notify_publisher:cast(Req, fun kapi_notifications:publish_new_user/1).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec maybe_send_desktop_welcome_email(cb_context:context()) -> 'ok'.
maybe_send_desktop_welcome_email(Context) ->
    WasEnabled = kz_json:is_true([<<"desktop">>, <<"enabled">>], cb_context:fetch(Context, 'db_doc')),
    NowEnabled = kz_json:is_true([<<"desktop">>, <<"enabled">>], cb_context:doc(Context)),

    maybe_send_desktop_welcome_email(Context, WasEnabled, NowEnabled).

maybe_send_desktop_welcome_email(Context, 'false', 'true') ->
    lager:debug("publishing desktop app welcome notification"),
    Doc = cb_context:doc(Context),

    WebphoneId = kz_json:get_ne_binary_value([<<"webphone">>, <<"device_id">>], Doc),

    Req = [{<<"Account-ID">>, cb_context:account_id(Context)}
          ,{<<"User-ID">>, kz_doc:id(Doc)}
          ,{<<"Webphone-Enabled">>, kz_term:is_not_empty(WebphoneId)}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    kapps_notify_publisher:cast(Req, fun kapi_notifications:publish_desktop_app_welcome/1);
maybe_send_desktop_welcome_email(Context, 'true', 'true') ->
    WasEnabled = kz_json:get_ne_binary_value([<<"webphone">>, <<"device_id">>], cb_context:fetch(Context, 'db_doc')),
    NowEnabled = kz_json:get_ne_binary_value([<<"webphone">>, <<"device_id">>], cb_context:doc(Context)),

    maybe_send_webphone_enabled_email(Context, WasEnabled, NowEnabled);
maybe_send_desktop_welcome_email(_Context, _WasEnabled, _NowEnabled) ->
    'ok'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec maybe_send_webphone_enabled_email(cb_context:context(), kz_term:api_ne_binary(), kz_term:api_ne_binary()) -> 'ok'.
maybe_send_webphone_enabled_email(_Context, 'undefined', 'undefined') ->
    'ok';
maybe_send_webphone_enabled_email(_Context, DeviceId, DeviceId) ->
    'ok';
maybe_send_webphone_enabled_email(Context, <<_/binary>>, <<_/binary>>) ->
    send_webphone_enabled_email(Context);
maybe_send_webphone_enabled_email(Context, 'undefined', <<_/binary>>) ->
    send_webphone_enabled_email(Context);
maybe_send_webphone_enabled_email(_Context, _, _) ->
    'ok'.

-spec send_webphone_enabled_email(cb_context:context()) -> 'ok'.
send_webphone_enabled_email(Context) ->
    lager:debug("publishing desktop app welcome notification"),
    Doc = cb_context:doc(Context),

    Req = [{<<"Account-ID">>, cb_context:account_id(Context)}
          ,{<<"User-ID">>, kz_doc:id(Doc)}
          | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    kapps_notify_publisher:cast(Req, fun kapi_notifications:publish_desktop_webphone_enabled/1).

%%------------------------------------------------------------------------------
%% @doc Attempt to load list of accounts, each summarized. Or a specific
%% account summary.
%% @end
%%------------------------------------------------------------------------------
-spec load_users_summary(cb_context:context()) -> cb_context:context().
load_users_summary(Context) ->
    Options = [{'doc_type', <<"user">>}
              ,{'mapper', crossbar_view:get_value_fun()}
              ],
    Selector = [{'start', [{<<"doc_type">>, <<"user">>}]}
               ,{'end', [{<<"doc_type">>, <<"user">>}]}
               ],
    crossbar_view:find(Context, <<"crossbar_listings/by_type_id">>, Selector, Options).

%%------------------------------------------------------------------------------
%% @doc Load a user document from the database
%% @end
%%------------------------------------------------------------------------------
-spec load_user(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
load_user(UserId, Context0) ->
    case kzd_users:fetch(cb_context:account_id(Context0), UserId) of
        {'ok', UserJObj0} ->
            lager:info("fetched user ~s", [UserId]),
            %% Migrate old-format vcard addresses (pre KZOO-310) to new format addresses object
            UserJObj1 = kzd_users:maybe_migrate_user_addresses(UserJObj0),

            Context1 = cb_context:setters(crossbar_doc:handle_json_success(UserJObj1, Context0)
                                         ,[{fun cb_context:add_metadata_values/2, user_metadata(UserJObj1)}
                                          ,{fun cb_context:store/3, 'db_doc', UserJObj0}
                                          ]
                                         ),
            add_has_avatar(Context1);
        {'error', Error} ->
            crossbar_doc:handle_datamgr_errors(Error, UserId, Context0)
    end.

user_metadata(UserJObj) ->
    [{<<"password_expiration_timestamp">>, kzd_users:password_expiration_timestamp(UserJObj)}
    ,{<<"is_password_expired">>, kzd_users:is_password_expired(UserJObj)}
    ].

%%------------------------------------------------------------------------------
%% @doc This function tries to load the user's document and all the object_types' documents listed
%% (if any) that belong to the user.
%% @end
%%------------------------------------------------------------------------------
-spec maybe_load_user_objects(kz_term:ne_binary(), cb_context:context(), kz_term:api_ne_binary() | kz_term:ne_binaries()) ->
          cb_context:context().
maybe_load_user_objects(<<_UserId/binary>>, Context, 'undefined') ->
    Context;
maybe_load_user_objects(<<UserId/binary>>, Context, ObjectTypes) ->
    case cb_context:resp_status(Context) of
        'success' ->
            UserJObj = cb_context:doc(Context), %% Backup.
            LoadUserRespData = cb_context:resp_data(Context),
            Options = load_user_objects_options(UserId, ObjectTypes),
            lager:debug("loading user objects from ~p with options: ~p",
                        [?CROSSBAR_LISTING_BY_OWNER_ID_TYPE, Options]),
            Context1 = crossbar_view:load(Context, ?CROSSBAR_LISTING_BY_OWNER_ID_TYPE, Options),
            UserJObjs = cb_context:doc(Context1),
            lager:debug("loaded user objects: ~p",
                        [[{kz_doc:type(JObj), kz_doc:id(JObj)} || JObj <- UserJObjs]]),
            case cb_context:resp_status(Context1) of
                'success' ->
                    cb_context:setters(Context1
                                      ,[{fun cb_context:store/3, <<"objects">>, UserJObjs}
                                       ,{fun cb_context:set_doc/2, UserJObj}
                                       ,{fun cb_context:set_resp_data/2, LoadUserRespData}
                                       ]
                                      );
                _ ->
                    Context1
            end;
        _ ->
            Context
    end.

-spec load_user_objects_base_options() -> crossbar_view:options().
load_user_objects_base_options() ->
    [{'mapper', crossbar_view:get_doc_fun()}, 'include_docs'].

-spec load_user_objects_options(kz_term:ne_binary()
                               ,kz_term:ne_binary() | kz_term:ne_binaries()
                               ) -> crossbar_view:options().
load_user_objects_options(UserId, <<"all">>) ->
    [{'startkey', [UserId]}, {'endkey', [UserId, kz_term:high_unicode_value()]}
    | load_user_objects_base_options()
    ];
load_user_objects_options(UserId, ObjectTypes) ->
    %% If `phone_numbers' was included in the list of object_types to be deleted along the user,
    %% callflows owned by the user need to be loaded in order to get those numbers. Even in the
    %% cases when the callflows are not requested to be deleted along the user.
    ObjTypes = case lists:member(<<"phone_numbers">>, ObjectTypes)
                   %% If an object type is duplicated, it will be loaded twice, and then, the API
                   %% will try to delete it twice as well, getting a 404 error for the second request.
                   andalso not lists:member(<<"callflow">>, ObjectTypes)
               of
                   %% Needed to be able to access the numbers that are going to be deleted from
                   %% callflows that belongs to the user being deleted.
                   'true' -> [<<"callflow">> | ObjectTypes];
                   'false' -> ObjectTypes
               end,
    ObjTypes1 = lists:usort(ObjTypes), %% Remove possible duplicates, just in case :shrugh:
    [{'keys', [[UserId, ObjType] || ObjType <- ObjTypes1, ObjType /= <<"phone_numbers">>]}
    | load_user_objects_base_options()
    ].

%%------------------------------------------------------------------------------
%% @doc Validate PATCH request.
%% @end
%%------------------------------------------------------------------------------
-spec validate_patch(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
validate_patch(UserId, Context) ->
    UserJObj = kzd_users:maybe_migrate_user_addresses(cb_context:req_data(Context)),
    Context1 = load_user(UserId, cb_context:set_req_data(Context, UserJObj)),
    crossbar_doc:patch_and_validate_doc(UserId, Context1, fun validate_request/2).

%%------------------------------------------------------------------------------
%% @doc Validate the request JObj passes all validation checks and add / alter
%% any required fields.
%% @end
%%------------------------------------------------------------------------------
-spec validate_request(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
validate_request(UserId, Context0) ->
    ReqUser = cb_context:req_data(Context0),
    AccountId = cb_context:account_id(Context0),

    Context = cb_context:store(Context0
                              ,<<"req_password">>
                              ,kzd_users:password(ReqUser)
                              ),

    case kzd_users:validate(AccountId, UserId, ReqUser) of
        {'true', UserJObj} when is_binary(UserId) ->
            lager:debug("successfully validated user object update"),
            %% NOTE: We need to load the current (unmodified) user document
            %% into the cb_context KVS db_doc because billing uses that to
            %% determine what changed and charge accordingly
            cb_context:update_successfully_validated_request(load_user(UserId, Context), UserJObj);
        {'true', UserJObj} ->
            lager:debug("successfully validated user object creation"),
            cb_context:update_successfully_validated_request(Context, UserJObj);
        {'validation_errors', ValidationErrors} ->
            lager:info("validation errors on user"),
            cb_context:add_doc_validation_errors(Context, ValidationErrors);
        {'system_error', Error} when is_atom(Error) ->
            lager:info("system error validating user: ~p", [Error]),
            cb_context:add_system_error(Error, Context);
        {'system_error', {Error, Message}} ->
            lager:info("system error validating user: ~p, ~p", [Error, Message]),
            cb_context:add_system_error(Error, Message, Context)
    end.

%%------------------------------------------------------------------------------
%% @doc Converts context to vcard
%% @end
%%------------------------------------------------------------------------------
-spec convert_to_vcard(cb_context:context()) -> cb_context:context().
convert_to_vcard(Context) ->
    JObj = cb_context:doc(Context),
    JProfile = kz_json:get_value(<<"profile">>, JObj, kz_json:new()),
    JObj1 = kz_json:merge_jobjs(JObj, JProfile),
    JObj2 = set_photo(JObj1, Context),
    JObj3 = set_org(JObj2, Context),
    RespData = kzd_users:to_vcard(JObj3),
    cb_context:set_resp_data(Context, [RespData, <<"\n">>]).

-spec set_photo(kz_json:object(), cb_context:context()) -> kz_json:object().
set_photo(JObj, Context) ->
    UserId = kz_doc:id(cb_context:doc(Context)),
    Attach = crossbar_doc:load_attachment(UserId, ?PHOTO, ?TYPE_CHECK_OPTION(kzd_users:type()), Context),
    case cb_context:resp_status(Attach) of
        'error' -> JObj;
        'success' ->
            Data = cb_context:resp_data(Attach),
            CT = kz_doc:attachment_content_type(cb_context:doc(Context), ?PHOTO),
            kz_json:set_value(?PHOTO, kz_json:from_list([{CT, Data}]), JObj)
    end.

-spec set_org(kz_json:object(), cb_context:context()) -> kz_json:object().
set_org(JObj, Context) ->
    case kz_json:get_value(<<"org">>
                          ,cb_context:doc(crossbar_doc:load(cb_context:account_id(Context)
                                                           ,Context
                                                           ,?TYPE_CHECK_OPTION(kzd_accounts:type())
                                                           )
                                         )
                          )
    of
        'undefined' -> JObj;
        Val -> kz_json:set_value(<<"org">>, Val, JObj)
    end.

%%------------------------------------------------------------------------------
%% @doc This function validate if user's document has a photo, if it has, it
%% will set a new property as avatar = true or false
%% @end
%%------------------------------------------------------------------------------
-spec add_has_avatar(cb_context:context()) -> cb_context:context().
add_has_avatar(Context) ->
    RespData = cb_context:resp_data(Context),
    RespData1 = kzd_users:set_has_avatar(RespData, kzd_users:has_avatar(cb_context:doc(Context))),
    cb_context:set_resp_data(Context, RespData1).
