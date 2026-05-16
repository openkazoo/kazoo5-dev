%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2023, 2600Hz
%%% @doc
%%% @author Navoda Ginige
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_websites).

-export([init/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,content_types_provided/2
        ,content_types_accepted/2
        ,validate/1, validate/2
        ,put/1
        ,post/2
        ,delete/2
        ,patch/2
        ,acceptable_content_types/0
        ]).

-include("crossbar.hrl").

-define(WEBSITE_LOGO_MIME_TYPES, ?IMAGE_CONTENT_TYPES ++ ?BASE64_CONTENT_TYPES).
%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    Bindings = [{<<"*.allowed_methods.websites">>, 'allowed_methods'}
               ,{<<"*.content_types_accepted.websites">>, 'content_types_accepted'}
               ,{<<"*.content_types_provided.websites">>, 'content_types_provided'}
               ,{<<"*.execute.delete.websites">>, 'delete'}
               ,{<<"*.execute.patch.websites">>, 'patch'}
               ,{<<"*.execute.post.websites">>, 'post'}
               ,{<<"*.execute.put.websites">>, 'put'}
               ,{<<"*.resource_exists.websites">>, 'resource_exists'}
               ,{<<"*.validate.websites">>, 'validate'}
               ],
    cb_modules_util:bind(?MODULE, Bindings),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc Add content types accepted and provided by this module
%% @end
%%------------------------------------------------------------------------------

-spec acceptable_content_types() -> [cowboy_content_type()].
acceptable_content_types() ->
    ?WEBSITE_LOGO_MIME_TYPES.

-spec content_types_provided(cb_context:context(), path_token()) ->
          cb_context:context().
content_types_provided(Context, WebsiteId) ->
    Verb = cb_context:req_verb(Context),
    ContentType = cb_context:req_header(Context, <<"accept">>),
    case ?HTTP_GET =:= Verb
        andalso api_util:content_type_matches(ContentType, acceptable_content_types())
    of
        'false' ->
            Context;
        'true' ->
            content_types_provided(Context, WebsiteId, ?HTTP_GET)
    end.

-spec content_types_provided(cb_context:context(), path_token(), http_method()) ->
          cb_context:context().
content_types_provided(Context, WebsiteId, ?HTTP_GET) ->
    Context1 = load_website(WebsiteId, Context),
    case cb_context:resp_status(Context1) of
        'success' ->
            JObj = cb_context:doc(Context1),
            case kz_doc:attachment_names(JObj) of
                [] -> Context1;
                [Attachment|_] ->
                    CT = kz_doc:attachment_content_type(JObj, Attachment),
                    [Type, SubType] = binary:split(CT, <<"/">>),
                    cb_context:set_content_types_provided(Context, [{'to_binary', [{Type, SubType}]}])
            end;
        _Status ->
            cb_context:set_content_types_provided(Context1, [{'to_binary', ?IMAGE_CONTENT_TYPES}])
    end;
content_types_provided(Context, _WebsiteId, _Verb) ->
    Context.

-spec content_types_accepted(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
content_types_accepted(Context, _WebsiteId) ->
    Verb = cb_context:req_verb(Context),
    ContentType = cb_context:req_header(Context, <<"content-type">>),
    case ?HTTP_POST =:= Verb
        andalso api_util:content_type_matches(ContentType, acceptable_content_types())
    of
        'false' ->
            Context;
        'true' ->
            CTA = [{'from_binary', ?WEBSITE_LOGO_MIME_TYPES}],
            cb_context:set_content_types_accepted(Context, CTA)
    end.

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_WebsiteId) ->
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
resource_exists(_) -> 'true'.

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
    validate_websites(Context, cb_context:req_verb(Context)).

-spec validate_websites(cb_context:context(), http_method()) -> cb_context:context().
validate_websites(Context, ?HTTP_GET) ->
    load_summary(Context);
validate_websites(Context, ?HTTP_PUT) ->
    create(Context).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, WebsiteId) ->
    validate_website(Context, WebsiteId, cb_context:req_verb(Context)).

-spec validate_website(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_website(Context, WebsiteId, ?HTTP_GET) ->
    case api_util:content_type_matches(cb_context:req_header(Context, <<"accept">>)
                                      ,acceptable_content_types()
                                      )
    of
        'false' -> load_website(WebsiteId, Context);
        'true' -> validate_attachment(Context, WebsiteId, ?HTTP_GET)
    end;
validate_website(Context, WebsiteId, ?HTTP_POST) ->
    case api_util:content_type_matches(cb_context:req_header(Context, <<"content-type">>)
                                      ,acceptable_content_types()
                                      )
    of
        'false' ->
            validate_request(WebsiteId, Context);
        'true' ->
            validate_attachment(Context, WebsiteId, ?HTTP_POST)
    end;
validate_website(Context, WebsiteId, ?HTTP_PATCH) ->
    validate_patch(WebsiteId, load_website(WebsiteId, Context));
validate_website(Context, WebsiteId, ?HTTP_DELETE) ->
    load_website(WebsiteId, Context).

-spec validate_attachment(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_attachment(Context, WebsiteId, ?HTTP_GET) ->
    load_website_logo(WebsiteId, Context);
validate_attachment(Context, WebsiteId, ?HTTP_POST) ->
    validate_website_logo_post(Context, WebsiteId, cb_context:req_files(Context)).

-spec validate_website_logo_post(cb_context:context(), path_token(), any()) ->
          cb_context:context().
validate_website_logo_post(Context, _WebsiteId, []) ->
    cb_context:add_validation_error(<<"file">>
                                   ,<<"required">>
                                   ,kz_json:from_list([{<<"message">>, <<"Please provide an image file">>}])
                                   ,Context
                                   );
validate_website_logo_post(Context, WebsiteId, [{_Filename, FileJObj}]) ->
    validate_upload(Context, WebsiteId, FileJObj);
validate_website_logo_post(Context, _WebsiteId, _Files) ->
    cb_context:add_validation_error(<<"file">>
                                   ,<<"maxItems">>
                                   ,kz_json:from_list([{<<"message">>, <<"Please provide a single image file">>}])
                                   ,Context
                                   ).

-spec validate_upload(cb_context:context(), path_token(), kz_json:object()) ->
          cb_context:context().
validate_upload(Context, WebsiteId, FileJObj) ->
    Context1 = load_website(WebsiteId, Context),
    case cb_context:resp_status(Context) of
        'success' ->
            Props = [{<<"content_type">>, content_type(FileJObj)}
                    ,{<<"content_length">>, file_size(FileJObj)}
                    ],
            validate_request(WebsiteId
                            ,cb_context:set_req_data(Context1
                                                    ,kz_json:set_values(Props, cb_context:doc(Context))
                                                    )
                            );
        _Status -> Context1
    end.

-spec content_type(kz_json:object()) -> kz_term:ne_binary().
content_type(FileJObj) ->
    kz_json:get_value([<<"headers">>, <<"content_type">>]
                     ,FileJObj
                     ,<<"application/octet-stream">>
                     ).

-spec file_size(kz_json:object()) -> non_neg_integer().
file_size(FileJObj) ->
    case kz_json:get_integer_value([<<"headers">>, <<"content_length">>], FileJObj) of
        'undefined' ->
            byte_size(kz_json:get_value(<<"contents">>, FileJObj, <<>>));
        Size -> Size
    end.
%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, WebsiteId) ->
    case api_util:content_type_matches(cb_context:req_header(Context, <<"content-type">>)
                                      ,acceptable_content_types()
                                      )
    of
        'false' ->
            crossbar_doc:save(Context);
        'true' ->
            update_website_binary(WebsiteId, Context)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, _Id) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc Delete an instance from the database
%% @end
%%------------------------------------------------------------------------------
-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _) ->
    crossbar_doc:delete(Context).

%%------------------------------------------------------------------------------
%% @doc Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%------------------------------------------------------------------------------
-spec load_summary(cb_context:context()) -> cb_context:context().
load_summary(Context) ->
    case cb_context:req_nouns(Context) of
        [{<<"websites">>, []}, {<<"users">>, [UserId]} |_] ->
            user_summary(Context, UserId);
        [{<<"websites">>, []}, {<<"accounts">>, [_AccountId]} |_] ->
            lager:debug("getting account summary"),
            account_summary(Context, cb_context:account_id(Context));
        _Nouns ->
            lager:debug("unexpected nouns: ~p", [_Nouns]),
            crossbar_util:response_faulty_request(Context)
    end.

-spec account_summary(cb_context:context(), kz_term:api_ne_binary()) -> cb_context:context().
account_summary(Context, 'undefined') ->
    Message = kz_json:from_list([{<<"message">>, <<"account ID is required in url">>}]),
    cb_context:add_validation_error(<<"account_id">>, <<"required">>, Message, Context);
account_summary(Context, _AccountId) ->
    Options = [{'doc_type', kzd_websites:type()}
              ,{'mapper', crossbar_view:get_value_fun()}
              ],
    crossbar_view:load(Context, <<"websites/crossbar_listing">>, Options).

-spec user_summary(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
user_summary(Context, UserId) ->
    Options = [{'keys', [UserId, 'true']}
              ,{'mapper', crossbar_view:get_value_fun()}
              ],
    crossbar_view:load(Context, <<"websites/listing_by_user">>, Options).

%%------------------------------------------------------------------------------
%% @doc Load an instance from the database
%% @end
%%------------------------------------------------------------------------------
-spec load_website(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
load_website(Id, Context) ->
    crossbar_doc:load(Id, Context, ?TYPE_CHECK_OPTION(kzd_websites:type())).

%%------------------------------------------------------------------------------
%% @doc Create a new instance with the data provided, if it is valid
%% @end
%%------------------------------------------------------------------------------
-spec create(cb_context:context()) -> cb_context:context().
create(Context) ->
    OnSuccess = fun(C) -> on_successful_validation('undefined', C) end,
    cb_context:validate_request_data(kzd_websites:schema(), Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec on_successful_validation(kz_term:api_binary(), cb_context:context()) ->
          cb_context:context().
on_successful_validation('undefined', Context) ->
    Props = [{<<"pvt_type">>, kzd_websites:type()}],
    cb_context:set_doc(Context, kz_json:set_values(Props, cb_context:doc(Context)));
on_successful_validation(Id, Context) ->
    crossbar_doc:load_merge(Id, Context, ?TYPE_CHECK_OPTION(kzd_websites:type())).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_request(kz_term:ne_binary(), cb_context:context()) ->
          cb_context:context().
validate_request(WebsiteId, Context) ->
    OnSuccess = fun(C) -> on_successful_validation(WebsiteId, C) end,
    cb_context:validate_request_data(kzd_websites:schema(), Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc Validate an patch request.
%% @end
%%------------------------------------------------------------------------------
-spec validate_patch(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
validate_patch(WebsiteId, Context) ->
    crossbar_doc:patch_and_validate(WebsiteId, Context, fun validate_request/2).

%%------------------------------------------------------------------------------
%% @doc Update the binary attachment of a website doc
%% @end
%%------------------------------------------------------------------------------
-spec update_website_binary(path_token(), cb_context:context()) ->
          cb_context:context().
update_website_binary(WebsiteId, Context) ->
    JObj = cb_context:doc(Context),
    [{Filename, FileObj}] = cb_context:req_files(Context),
    Contents = kz_json:get_value(<<"contents">>, FileObj),
    CT = kz_json:get_value([<<"headers">>, <<"content_type">>], FileObj),
    Opts = [{'content_type', CT} | ?TYPE_CHECK_OPTION(kzd_websites:type())],

    JObj1 = case website_binary_meta(Context, WebsiteId) of
                'undefined' -> JObj;
                {AttachmentId, _} ->
                    kz_doc:delete_attachment(JObj, AttachmentId)
            end,
    AttachmentName = cb_modules_util:attachment_name(Filename, CT),
    Context1 = crossbar_doc:save(cb_context:set_doc(Context, JObj1)),
    case cb_context:resp_status(Context1) of
        'success' ->
            crossbar_doc:save_attachment(WebsiteId
                                        ,AttachmentName
                                        ,Contents
                                        ,Context
                                        ,Opts
                                        );
        _ ->
            Context1
    end.

-spec website_binary_meta(cb_context:context(), path_token()) ->
          'undefined' | {kz_term:ne_binary(), kz_json:object()}.
website_binary_meta(Context, WebsiteId) ->
    website_binary_meta(Context, WebsiteId, cb_context:doc(Context)).

website_binary_meta(Context, WebsiteId, JObj) ->
    case kz_doc:id(JObj) =:= WebsiteId
        orelse cb_context:resp_status(Context) =:= 'success'
    of
        'true' ->
            Attachments = kz_doc:attachments(JObj, kz_json:new()),
            case website_attachment_id(Attachments) of
                'undefined' -> 'undefined';
                AttachmentId ->
                    {AttachmentId, kz_json:get_json_value(AttachmentId, Attachments)}
            end;
        'false' -> 'undefined'
    end.

-spec website_attachment_id(kz_json:object()) -> kz_term:api_ne_binary().
website_attachment_id(Attachments) ->
    case kz_json:get_keys(Attachments) of
        [] -> 'undefined';
        [AttachmentId] -> AttachmentId;
        _Else -> 'undefined'
    end.

-spec load_website_logo(path_token(), cb_context:context()) -> cb_context:context().
load_website_logo(WebsiteId, Context) ->
    Context1 = load_website(WebsiteId, Context),
    case cb_context:resp_status(Context1) of
        'success' ->
            case kz_doc:attachment_names(cb_context:doc(Context1)) of
                [] -> crossbar_util:response_bad_identifier(WebsiteId, Context);
                [Attachment|_] ->
                    LoadedContext = crossbar_doc:load_attachment(cb_context:doc(Context1)
                                                                ,Attachment
                                                                ,?TYPE_CHECK_OPTION(kzd_websites:type())
                                                                ,Context1
                                                                ),
                    cb_context:add_resp_headers(LoadedContext
                                               ,#{<<"content-disposition">> => <<"attachment; filename=", Attachment/binary>>
                                                 ,<<"content-type">> => kz_doc:attachment_content_type(cb_context:doc(Context1), Attachment)
                                                 }
                                               )
            end;
        _Status ->
            Context1
    end.
