%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2024, 2600Hz
%%% @doc Match list module
%%% Handle client requests for match list documents, api v2
%%%
%%%
%%% @author SIPLABS, LLC (Ilya Ashchepkov)
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_lists).

-export([init/0
        ,authorize/1, authorize/2
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,content_types_provided/1, content_types_provided/2
        ,validate/1, validate/2
        ,put/1
        ,post/2
        ,patch/2
        ,delete/2
        ]).

-include("crossbar.hrl").

-define(CROSSBAR_LISTING_BY_OWNER_ID_TYPE, <<"contacts/listing_by_owner">>).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    Bindings = [{<<"*.allowed_methods.lists">>, 'allowed_methods'}
               ,{<<"*.resource_exists.lists">>, 'resource_exists'}
               ,{<<"*.content_types_provided.lists">>, 'content_types_provided'}
               ,{<<"*.validate.lists">>, 'validate'}
               ,{<<"*.execute.put.lists">>, 'put'}
               ,{<<"*.execute.post.lists">>, 'post'}
               ,{<<"*.execute.patch.lists">>, 'patch'}
               ,{<<"*.execute.delete.lists">>, 'delete'}
               ,{<<"*.authorize.lists">>, 'authorize'}
               ],
    cb_modules_util:bind(?MODULE, Bindings),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_ListId) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_PATCH, ?HTTP_DELETE].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% For example:
%%
%% ```
%%    /lists => []
%%    /lists/foo => [<<"foo">>]
%%    /lists/foo/bar => [<<"foo">>, <<"bar">>]
%% '''
%% @end
%%------------------------------------------------------------------------------

-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_IdOrTag) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc Authorizes the incoming request, returning true if the requestor is
%% allowed to access the resource, or false if not.
%% @end
%%------------------------------------------------------------------------------
-spec authorize(cb_context:context()) ->
          'true' | {'stop', cb_context:context()}.
authorize(Context) ->
    case is_admin(Context) of
        'true' -> 'true';
        'false' -> maybe_authorize_user_level_req(Context)
    end.

-spec authorize(cb_context:context(), path_token()) ->
          'true' | {'stop', cb_context:context()}.
authorize(Context, _IdOrTag) ->
    case is_admin(Context) of
        'true' -> 'true';
        'false' -> maybe_authorize_user_level_req(Context)
    end.

-spec is_admin(cb_context:context()) -> boolean().
is_admin(Context) ->
    cb_context:is_account_admin(Context)
        orelse cb_context:is_superduper_admin(Context).

-spec maybe_authorize_user_level_req(cb_context:context()) -> 'true' | {'stop', cb_context:context()}.
maybe_authorize_user_level_req(Context) ->
    case is_user_level_req(Context) of
        {'true', UserId} ->
            authorize_user_level_req(Context, UserId);
        'false' ->
            authorize_account_level_req(Context, cb_context:req_verb(Context))
    end.

-spec is_user_level_req(cb_context:context()) -> {'true', kz_term:ne_binary()} | 'false'.
is_user_level_req(Context) ->
    case cb_context:req_nouns(Context) of
        [_lists, {<<"users">>, [UserId]} |_] ->
            {'true', UserId};
        _Nouns ->
            'false'
    end.

-spec authorize_user_level_req(cb_context:context(), kz_term:api_ne_binary()) ->
          'true' | {'stop', cb_context:context()}.
authorize_user_level_req(Context, UserId) ->
    case cb_context:auth_user_id(Context) =:=  UserId of
        'true' -> 'true';
        'false' ->
            Msg = <<"auth token user and requested user doesn't match">>,
            {'stop', cb_context:add_system_error(403, 'forbidden', Msg, Context)}
    end.

-spec authorize_account_level_req(cb_context:context(), path_token()) ->
          'true' | {'stop', cb_context:context()}.
authorize_account_level_req(_Context, ?HTTP_GET) ->
    'true';
authorize_account_level_req(Context, _ReqVerb) ->
    Msg = <<"only admins have permissions for this operation">>,
    {'stop', cb_context:add_system_error(403, 'forbidden', Msg, Context)}.

%%------------------------------------------------------------------------------
%% @doc Add content types accepted and provided by this module
%% @end
%%------------------------------------------------------------------------------

-spec content_types_provided(cb_context:context()) ->
          cb_context:context().
content_types_provided(Context) ->
    Context.

-spec content_types_provided(cb_context:context(), path_token()) ->
          cb_context:context().
content_types_provided(Context, _) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /lists might load a list of contact objects
%% /lists/123 might load the contact object 123
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%------------------------------------------------------------------------------

-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_request(Context, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, PathToken) ->
    case is_tag_based_req(PathToken) of
        'true' ->
            validate_tag_based_request(Context, PathToken, cb_context:req_verb(Context));
        'false' ->
            validate_request(Context, PathToken, cb_context:req_verb(Context))
    end.

-spec validate_request(cb_context:context(), path_token()) ->
          cb_context:context().
validate_request(Context, ?HTTP_GET) ->
    load(Context);
validate_request(Context, ?HTTP_PUT) ->
    create(Context).

-spec validate_request(cb_context:context(), path_token(), path_token()) ->
          cb_context:context().
validate_request(Context, Id, ?HTTP_GET) ->
    load_contact(Context, Id);
validate_request(Context, Id, ?HTTP_POST) ->
    validate_post(Id, Context);
validate_request(Context, Id, ?HTTP_PATCH) ->
    validate_patch(load_contact(Context, Id), Id);
validate_request(Context, Id, ?HTTP_DELETE) ->
    load_contact(Context, Id).

-spec is_tag_based_req(path_token()) -> boolean().
is_tag_based_req(PathToken) ->
    case binary:match(PathToken, <<"tag-">>) of
        'nomatch' -> 'false';
        {0, _} -> 'true';
        _ -> 'false'
    end.

-spec validate_tag_based_request(cb_context:context(), path_token(), path_token()) ->
          cb_context:context().
validate_tag_based_request(Context, PathToken, ?HTTP_GET) ->
    load_tag_based_contacts(Context, PathToken).

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
post(Context, _ListId) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, _ListId) ->
    crossbar_doc:save(Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _Id) ->
    crossbar_doc:delete(Context).

%%------------------------------------------------------------------------------
%% @doc loads contacts user level and account level
%% @end
%%------------------------------------------------------------------------------
-spec load(cb_context:context()) ->
          cb_context:context().
load(Context) ->
    Keys = case cb_context:user_id(Context) of
               'undefined' -> [];
               UserId -> [UserId]
           end,
    Options = [{'keys', ['null'|Keys]}
              ,{'mapper', crossbar_view:get_value_fun()}
              ,{'doc_type', kzd_contacts:type()}
              ],
    crossbar_view:load(Context, ?CROSSBAR_LISTING_BY_OWNER_ID_TYPE, Options).

%%------------------------------------------------------------------------------
%% @doc Load an instance from the database
%% @end
%%------------------------------------------------------------------------------
-spec load_contact(cb_context:context(), path_token()) -> cb_context:context().
load_contact(Context, Id) ->
    check_owner(crossbar_doc:load(Id, Context, ?TYPE_CHECK_OPTION(kzd_contacts:type()))).

-spec check_owner(cb_context:context()) -> cb_context:context().
check_owner(Context) ->
    case cb_context:user_id(Context) =:= kzd_contacts:owner_id(cb_context:doc(Context)) of
        'true' ->
            Context;
        'false' ->
            Message = kz_json:from_list([{<<"message">>, <<"request userid token and contact owner_id doesn't match">>}]),
            cb_context:add_validation_error(<<"owner_id">>, <<"missmatch">>, Message, Context)
    end.
%%------------------------------------------------------------------------------
%% @doc Load instances from the database where tag is matched
%% @end
%%------------------------------------------------------------------------------
-spec load_tag_based_contacts(cb_context:context(), kz_term:ne_binary()) ->
          cb_context:context().
load_tag_based_contacts(Context, <<"tag-", Tag/binary>>) ->
    Keys = case cb_context:user_id(Context) of
               'undefined' -> [];
               UserId -> [UserId]
           end,
    Options = [{'keys', ['null'|Keys]}
              ,{'mapper', fun(JObjs) -> filter_tags(Tag, JObjs) end}
              ,{'doc_type', kzd_contacts:type()}
              ],
    crossbar_view:load(Context, ?CROSSBAR_LISTING_BY_OWNER_ID_TYPE, Options).

filter_tags(Tag, JObjs) ->
    lists:filtermap(fun(Contact) ->
                            Value = kz_json:get_value(<<"value">>, Contact),
                            case lists:member(Tag , kzd_contacts:tags(Value, [])) of
                                'true' ->
                                    {'true', Value};
                                'false' ->
                                    'false'
                            end
                    end,
                    JObjs
                   ).

%%------------------------------------------------------------------------------
%% @doc Create a new instance with the data provided, if it is valid
%% @end
%%------------------------------------------------------------------------------
-spec create(cb_context:context()) -> cb_context:context().
create(Context) ->
    OnSuccess = fun(C) -> on_successful_validation('undefined', C) end,
    cb_context:validate_request_data(kzd_contacts:schema(), Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_post(kz_term:ne_binary(), cb_context:context()) ->
          cb_context:context().
validate_post(Id, Context) ->
    OnSuccess = fun(C) -> on_successful_validation(Id, C) end,
    cb_context:validate_request_data(kzd_contacts:schema(), Context, OnSuccess).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_patch(cb_context:context(), kz_term:api_binary()) -> cb_context:context().
validate_patch(Context, Id) ->
    crossbar_doc:patch_and_validate(Id, Context, fun validate_post/2).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec on_successful_validation(kz_term:api_binary(), cb_context:context()) ->
          cb_context:context().
on_successful_validation('undefined', Context) ->
    Props = props:filter_undefined([{<<"pvt_type">>, kzd_contacts:type()}
                                   ,{<<"pvt_owner_id">>, cb_context:user_id(Context)}
                                   ]),
    validate_contacts_data(cb_context:set_doc(Context
                                             ,kz_json:set_values(Props, cb_context:doc(Context))
                                             ));

on_successful_validation(Id, Context) ->
    Context1 = load_contact(Context, Id),
    case 'success' =:= cb_context:resp_status(Context1) of
        'false' -> Context1;
        'true' ->
            validate_contacts_data(crossbar_doc:load_merge(Id
                                                          ,Context
                                                          ,?TYPE_CHECK_OPTION(kzd_contacts:type())
                                                          ))
    end.

-spec validate_contacts_data(cb_context:context()) -> cb_context:context().
validate_contacts_data(Context) ->
    case is_contact_type_primary_unique(Context) of
        'true' -> Context;
        'false' ->
            Message = kz_json:from_list([{<<"message">>, <<"more than one primary contact for a contact type">>}]),
            cb_context:add_validation_error(<<"contacts">>, <<"primary">>, Message, Context)
    end.

-spec is_contact_type_primary_unique(cb_context:context()) -> boolean().
is_contact_type_primary_unique(Context) ->
    ContactsArray = kzd_contacts:contacts(cb_context:doc(Context)),
    [{Status, _}] = lists:foldl(fun check_primary_unique/2
                               ,[{'true', []}]
                               ,ContactsArray
                               ),
    Status.

check_primary_unique(_Contact, [{'false', _PrimaryTypes}]=Acc) ->
    Acc;
check_primary_unique(Contact, [{_Status, PrimaryTypes}]=Acc) ->
    ContactType = kzd_contacts:get_type_contact(Contact),
    case {kzd_contacts:is_primary_contact(Contact)
         ,lists:member(ContactType, PrimaryTypes)}
    of
        {'true', 'true'} -> [{'false', PrimaryTypes}];
        {'true', 'false'} -> [{'true', [ContactType|PrimaryTypes]}];
        _ -> Acc
    end.
