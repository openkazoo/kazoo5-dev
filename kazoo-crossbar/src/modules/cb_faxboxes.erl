%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2023, 2600Hz
%%% @doc Fax Box API
%%% @author Luis Azedo
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_faxboxes).

-export([init/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,validate/1, validate/2
        ,validate_resource/1, validate_resource/2
        ,put/1
        ,post/2
        ,patch/2
        ,delete/2
        ]).

-include("crossbar.hrl").

-define(DEFAULT_FAX_SMTP_DOMAIN, <<"fax.kazoo.io">>).

-define(SMTP_EMAIL_FIELD, {<<"pvt_smtp_email_address">>, <<"custom_smtp_address">>}).

-define(METADATA_FIELDS, [?SMTP_EMAIL_FIELD]).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.faxboxes">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.faxboxes">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.faxboxes">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.validate_resource.faxboxes">>, ?MODULE, 'validate_resource'),
    _ = crossbar_bindings:bind(<<"*.execute.put.faxboxes">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.faxboxes">>, ?MODULE, 'post'),
    _ = crossbar_bindings:bind(<<"*.execute.patch.faxboxes">>, ?MODULE, 'patch'),
    crossbar_bindings:bind(<<"*.execute.delete.faxboxes">>, ?MODULE, 'delete').

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_FaxboxId) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_PATCH, ?HTTP_DELETE].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% For example:
%%
%% ```
%%    /faxes => []
%%    /faxes/foo => [<<"foo">>]
%%    /faxes/foo/bar => [<<"foo">>, <<"bar">>]
%% '''
%% @end
%%------------------------------------------------------------------------------

-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_BoxId) -> 'true'.

-spec validate_resource(cb_context:context()) -> cb_context:context().
validate_resource(Context) -> Context.

-spec validate_resource(cb_context:context(), path_token()) -> cb_context:context().
validate_resource(Context, FaxboxId) ->
    case kz_datamgr:open_cache_doc(cb_context:account_id(Context), FaxboxId) of
        {'ok', JObj} -> cb_context:store(Context, <<"faxbox">>, JObj);
        _ -> Context
    end.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /faxes might load a list of fax objects
%% /faxes/123 might load the fax object 123
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%------------------------------------------------------------------------------

-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_faxboxes(Context, cb_context:req_verb(Context)).

validate_faxboxes(Context, ?HTTP_PUT) ->
    validate_email_address(create_faxbox(Context));
validate_faxboxes(Context, ?HTTP_GET) ->
    faxbox_listing(Context).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, Id) ->
    validate_faxbox(Context, Id, cb_context:req_verb(Context)).

validate_faxbox(Context, Id, ?HTTP_GET) ->
    read(Id, Context);
validate_faxbox(Context, Id, ?HTTP_POST) ->
    validate_email_address(update_faxbox(Id, Context));
validate_faxbox(Context, Id, ?HTTP_PATCH) ->
    validate_patch(crossbar_doc:patch_and_validate(Id, Context, fun update_faxbox/2));
validate_faxbox(Context, Id, ?HTTP_DELETE) ->
    delete_faxbox(Id, Context).

-spec validate_email_address(cb_context:context()) -> cb_context:context().
validate_email_address(Context) ->
    ReqDoc = cb_context:doc(Context),
    validate_email_address(Context
                          ,ReqDoc
                          ,kzd_faxbox:custom_smtp_email_address(ReqDoc)
                          ).

-spec validate_email_address(cb_context:context(), kz_json:object(), kz_term:api_ne_binary()) ->
          cb_context:context().
validate_email_address(Context, _ReqDoc, 'undefined') -> Context;
validate_email_address(Context, ReqDoc, Email) ->
    case is_faxbox_email_global_unique(Email, kz_doc:id(ReqDoc)) of
        'true' -> Context;
        'false' ->
            cb_context:add_validation_error(<<"custom_smtp_email_address">>
                                           ,<<"unique">>
                                           ,kz_json:from_list(
                                              [{<<"message">>, <<"email address must be unique">>}
                                              ,{<<"cause">>, Email}
                                              ])
                                           ,Context
                                           )
    end.

%% doc is already patched from the request data
-spec validate_patch(cb_context:context()) -> cb_context:context().
validate_patch(Context) ->
    case is_email_unique(Context) of
        'true' -> Context;
        'false' ->
            cb_context:add_validation_error(<<"custom_smtp_email_address">>
                                           ,<<"unique">>
                                           ,<<"email address must be unique">>
                                           ,Context
                                           )
    end.

is_email_unique(Context) ->
    case kzd_faxbox:custom_smtp_email_address(cb_context:doc(Context)) of
        'undefined' -> 'true';
        CustomEmail -> is_faxbox_email_global_unique(CustomEmail, kz_doc:id(cb_context:doc(Context)))
    end.

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is PUT, execute the actual action, usually a db save.
%% @end
%%------------------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    save_faxbox_doc(Context, 'create').

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is POST, execute the actual action, usually a db save
%% (after a merge perhaps).
%% @end
%%------------------------------------------------------------------------------
-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, _Id) ->
    save_faxbox_doc(Context, 'update').

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is PATCH, execute the actual action, usually a db save
%% (after a merge).
%% @end
%%------------------------------------------------------------------------------
-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, Id) ->
    post(Context, Id).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is DELETE, execute the actual action, usually a db delete
%% @end
%%------------------------------------------------------------------------------
-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, Id) ->
    lager:debug("deleting faxbox from aggregation db"),
    _ = crossbar_doc:delete(
          read(Id, cb_context:set_db_name(Context, ?KZ_FAXES_DB))
         ),
    lager:debug("deleting faxbox from account db"),
    crossbar_doc:delete(Context).

-spec create_faxbox(cb_context:context()) -> cb_context:context().
create_faxbox(Context) ->
    OnSuccess = fun(C) -> on_faxbox_successful_validation('undefined', C) end,
    cb_context:validate_request_data(<<"faxbox">>, Context, OnSuccess).

-spec delete_faxbox(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
delete_faxbox(Id, Context) ->
    read(Id, Context).

%%------------------------------------------------------------------------------
%% @doc Load an instance from the database
%% @end
%%------------------------------------------------------------------------------
-spec read(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
read(Id, Context) ->
    read(Id, Context, cb_context:req_verb(Context)).

-spec read(kz_term:ne_binary(), cb_context:context(), http_method()) -> cb_context:context().
read(Id, Context, ?HTTP_DELETE) ->
    do_read(Id, Context, ?TYPE_CHECK_OPTION(kzd_fax_box:type()));
read(Id, Context, _) ->
    Options = ?TYPE_CHECK_OPTION(kzd_fax_box:type()),
    do_read(Id, Context, Options).

-spec do_read(kz_term:ne_binary(), cb_context:context(), crossbar_doc:load_options()) ->
          cb_context:context().
do_read(Id, Context, Options) ->
    ReadContext = crossbar_doc:load(Id, Context, Options),
    case cb_context:resp_status(ReadContext) of
        'success' -> add_metadata_fields(ReadContext);
        _ -> ReadContext
    end.

-spec add_metadata_fields(cb_context:context()) -> cb_context:context().
add_metadata_fields(Context) ->
    lists:foldl(fun add_metadata_field/2, Context, ?METADATA_FIELDS).

-spec add_metadata_field(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
add_metadata_field(<<"pvt_", K1/binary>> = K, Context) ->
    Doc = cb_context:doc(Context),
    case kz_json:get_value(K, Doc) of
        'undefined' -> Context;
        Value -> add_metadata_field_value(K1, Value, Context)
    end;
add_metadata_field({<<PvtFieldName/binary>>, <<PublicFieldName/binary>>}, Context) ->
    Doc = cb_context:doc(Context),
    case kz_json:get_value(PvtFieldName, Doc) of
        'undefined' -> Context;
        Value -> add_metadata_field_value(PublicFieldName, Value, Context)
    end;
add_metadata_field(_K, Context) -> Context.

-spec add_metadata_field_value(kz_term:ne_binary(), kz_json:json_term(), cb_context:context()) ->
          cb_context:context().
add_metadata_field_value(Key, Value, Context) ->
    cb_context:add_metadata_value(Context, Key, Value).

%%------------------------------------------------------------------------------
%% @doc Update an existing instance with the data provided, if it is
%% valid
%% @end
%%------------------------------------------------------------------------------
-spec update_faxbox(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
update_faxbox(Id, Context) ->
    OnSuccess = fun(C) -> on_faxbox_successful_validation(Id, C) end,
    cb_context:validate_request_data(<<"faxbox">>, Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec on_faxbox_successful_validation(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
on_faxbox_successful_validation('undefined', Context) ->
    cb_context:set_doc(Context
                      ,kz_json:set_values([{<<"pvt_type">>, kzd_fax_box:type()}
                                          ,{<<"pvt_account_id">>, cb_context:account_id(Context)}
                                          ,{<<"pvt_account_db">>, cb_context:db_name(Context)}
                                          ,{<<"pvt_reseller_id">>, cb_context:reseller_id(Context)}
                                          ,{<<"_id">>, kz_binary:rand_hex(16)}
                                          ,{<<"pvt_smtp_email_address">>, generate_email_address(Context)}
                                          ]
                                         ,cb_context:doc(Context)
                                         )
                      );
on_faxbox_successful_validation(DocId, Context) ->
    crossbar_doc:load_merge(DocId, Context, ?TYPE_CHECK_OPTION(kzd_fax_box:type())).

-spec generate_email_address(cb_context:context()) -> kz_term:ne_binary().
generate_email_address(Context) ->
    ResellerId =  cb_context:reseller_id(Context),
    Domain = kapps_account_config:get_global(ResellerId, <<"fax">>, <<"default_smtp_domain">>, ?DEFAULT_FAX_SMTP_DOMAIN),
    New = kz_binary:rand_hex(4),
    <<New/binary, ".", Domain/binary>>.

%%------------------------------------------------------------------------------
%% @doc Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%------------------------------------------------------------------------------
-spec faxbox_listing(cb_context:context()) -> cb_context:context().
faxbox_listing(Context) ->
    crossbar_view:find(Context
                      ,<<"crossbar_listings/by_type_id">>
                      ,faxbox_listing_selector()
                      ,faxbox_listing_options()
                      ).

faxbox_listing_selector() ->
    [{'start', [{<<"doc_type">>, kzd_fax_box:type()}]}
    ,{'end', [{<<"doc_type">>, kzd_fax_box:type()}]}
    ].

faxbox_listing_options() ->
    [{'doc_type', kzd_fax_box:type()}
    ,{'mapper', fun normalize_view_results/2}
    ,{'field_key', 'filtermap'}
    ,'include_docs'
    ].

-spec normalize_view_results(kz_json:object(), kz_json:objects()) -> kz_json:objects().
normalize_view_results(JObj, Acc) ->
    [kz_json:get_json_value(<<"doc">>, JObj) | Acc].

-spec is_faxbox_email_global_unique(kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
is_faxbox_email_global_unique(Email, FaxBoxId) ->
    ViewOptions = [{'key', kz_term:to_lower_binary(Email)}],
    case kz_datamgr:get_results(?KZ_FAXES_DB, <<"faxbox/email_address">>, ViewOptions) of
        {'ok', []} -> 'true';
        {'ok', [JObj]} -> kz_doc:id(JObj) =:= FaxBoxId;
        {'error', 'not_found'} -> 'true';
        _Resp ->
            lager:info("email results not unique: ~p", [_Resp]),
            'false'
    end.

-spec save_faxbox_doc(cb_context:context(), 'create' | 'update') -> cb_context:context().
save_faxbox_doc(Context0, Action) ->
    ContextAccount = save_faxbox_in_account_db(Context0),
    case cb_context:resp_status(ContextAccount) of
        'success' ->
            ContextFaxDb = save_doc_to_faxdb(ContextAccount, Action),
            case cb_context:resp_status(ContextFaxDb) of
                'success' ->
                    add_metadata_fields(ContextAccount);
                _ ->
                    _ = rollback_doc(ContextAccount, Action),
                    ContextFaxDb
            end;
        _ ->
            ContextAccount
    end.

-spec save_faxbox_in_account_db(cb_context:context()) -> cb_context:context().
save_faxbox_in_account_db(Context) ->
    crossbar_doc:save(Context).

-spec save_doc_to_faxdb(cb_context:context(), 'create' | 'update') -> cb_context:context().
save_doc_to_faxdb(Context0, Action) ->
    Context1 = load_merge_from_faxdb(Context0, Action),
    case cb_context:resp_status(Context1) of
        'success' ->
            crossbar_doc:save(Context1);
        _ ->
            Context1
    end.

-spec rollback_doc(cb_context:context(), 'create' | 'update') -> cb_context:context().
rollback_doc(Context, 'create') ->
    lager:error("failed to save doc to faxes db, rolling back"),
    crossbar_doc:delete(Context);
rollback_doc(Context, 'update') ->
    lager:debug("failed to save to faxdb, revert doc in account db"),
    crossbar_doc:save(cb_context:set_doc(Context, cb_context:fetch(Context, 'db_doc'))).

-spec load_merge_from_faxdb(cb_context:context(), 'create' | 'update') -> cb_context:context().
load_merge_from_faxdb(Context, Action) ->
    ToSave = kz_json:set_values([{kz_doc:path_account_db(), ?KZ_FAXES_DB}
                                ,{kz_doc:path_revision(), 'null'}
                                ]
                               ,cb_context:doc(Context)
                               ),
    Context1 = cb_context:setters(Context
                                 ,[{fun cb_context:set_db_name/2, ?KZ_FAXES_DB}
                                  ,{fun cb_context:set_doc/2, ToSave}
                                  ]),
    maybe_load_merge(Context1, Action).

-spec maybe_load_merge(cb_context:context(), 'create' | 'update') -> cb_context:context().
maybe_load_merge(Context, 'create') ->
    Context;
maybe_load_merge(Context, 'update') ->
    DocId = kz_doc:id(cb_context:doc(Context)),
    crossbar_doc:load_merge(DocId, Context, ?TYPE_CHECK_OPTION(kzd_fax_box:type())).
