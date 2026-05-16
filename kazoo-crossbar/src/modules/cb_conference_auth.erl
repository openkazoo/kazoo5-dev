%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2024, 2600Hz
%%% @doc Conference auth module.
%%% @author Karl Anderson
%%% @author James Aimonetti
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_conference_auth).

-export([init/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,authorize/1, authorize/2
        ,authenticate/1, authenticate/2
        ,validate/1, validate/2
        ,put/1, put/2
        ]).

-include_lib("crossbar/src/crossbar.hrl").

-define(CONFERENCE_AUTH_TOKENS, kapps_config:get_integer(?CONFIG_CAT, <<"conference_auth_tokens">>, 35)).

-define(MOD_CONFIG_CAT, <<(?CONFIG_CAT)/binary, ".conference_auth">>).
-define(INVITE_ALLOWED_SCOPE, kapps_config:get_ne_binary(?MOD_CONFIG_CAT, <<"invite_link_allowed_scope">>, <<"crossbar:conference_join">>)).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.authenticate.conference_auth">>, ?MODULE, 'authenticate'),
    _ = crossbar_bindings:bind(<<"*.authorize.conference_auth">>, ?MODULE, 'authorize'),
    _ = crossbar_bindings:bind(<<"*.allowed_methods.conference_auth">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.conference_auth">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.conference_auth">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.put.conference_auth">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.conference_auth">>, ?MODULE, 'post'),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc This function determines the verbs that are appropriate for the
%% given Nouns. For example `/accounts/' can only accept `GET' and `PUT'.
%%
%% Failure here returns `405 Method Not Allowed'.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() -> [?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_ConferenceId) -> [?HTTP_PUT].

%%------------------------------------------------------------------------------
%% @doc This function determines if the provided list of Nouns are valid.
%% Failure here returns `404 Not Found'.
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_ConferenceId) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec authorize(cb_context:context()) -> boolean() | {'stop', cb_context:context()}.
authorize(Context) ->
    authorize_nouns(Context, cb_context:req_nouns(Context), cb_context:req_verb(Context)).

-spec authorize(cb_context:context(), path_token()) -> boolean() | {'stop', cb_context:context()}.
authorize(_, _) ->
    'false'.

-spec authorize_nouns(cb_context:context(), req_nouns(), req_verb()) -> boolean() | {'stop', cb_context:context()}.
authorize_nouns(_Context, [{<<"conference_auth">>, []}], ?HTTP_PUT) ->
    %% allow conference auth
    lager:debug("authorizing request"),
    'true';
authorize_nouns(_, _, _) ->
    'false'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec authenticate(cb_context:context()) -> boolean().
authenticate(Context) ->
    authenticate_nouns(cb_context:req_nouns(Context), cb_context:req_verb(Context)).

-spec authenticate(cb_context:context(), path_token()) -> boolean().
authenticate(_, _) ->
    'false'.

authenticate_nouns([{<<"conference_auth">>, []}], ?HTTP_PUT) ->
    'true';
authenticate_nouns(_, _) ->
    'false'.

%%------------------------------------------------------------------------------
%% @doc This function determines if the parameters and content are correct
%% for this request
%%
%% Failure here returns 400.
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    TokenCost = cb_modules_util:token_cost(Context, ?CONFERENCE_AUTH_TOKENS),
    case cb_modules_util:consume_tokens_until(Context, TokenCost) of
        {'true', Context1} ->
            AuthFun = fun(ContextNotLocked) ->
                              OnSuccess = fun(C) -> validate_conference_auth(C) end,
                              cb_context:validate_request_data(<<"conference_auth">>, ContextNotLocked, OnSuccess)
                      end,
            maybe_validate_auth_attempts(Context1, TokenCost, AuthFun);
        {'false', Context1} ->
            cb_context:add_system_error('too_many_requests', Context1)
    end.

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ConferenceId) ->
    TokenCost = cb_modules_util:token_cost(Context, ?CONFERENCE_AUTH_TOKENS),
    case cb_modules_util:consume_tokens_until(Context, TokenCost) of
        {'true', Context1} ->
            AuthFun = fun(ContextNotLocked) -> validate_link(ContextNotLocked, ConferenceId) end,
            maybe_validate_auth_attempts(Context1, TokenCost, AuthFun);
        {'false', Context1} ->
            cb_context:add_system_error('too_many_requests', Context1)
    end.

-spec maybe_validate_auth_attempts(cb_context:context(), non_neg_integer(), fun((cb_context:context()) -> cb_context:context())) ->
          cb_context:context().
maybe_validate_auth_attempts(Context, TokenCost, AuthFun) ->
    AuthBuckets = crossbar_auth:get_auth_account_info(Context),
    case crossbar_auth:is_account_locked(Context, AuthBuckets) of
        {'true', Context1} ->
            Context1;
        {'false', ContextNotLocked} ->
            Context1 = AuthFun(ContextNotLocked),
            case cb_context:resp_error_code(Context1) of
                401 ->
                    crossbar_auth:maybe_lock_account(Context1, AuthBuckets, TokenCost);
                _Other -> Context1
            end
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    create_auth_token(Context).

-spec put(cb_context:context(), path_token()) -> cb_context:context().
put(Context, _ConferenceId) ->
    create_conference_link(Context).

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec load_conference(cb_context:context(), kz_term:ne_binary()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
load_conference(Context, ConferenceId) ->
    Context1 = crossbar_doc:load(ConferenceId, Context, ?TYPE_CHECK_OPTION(kzd_conference:type())),
    case cb_context:resp_status(Context1) of
        'success' ->
            {'ok', cb_context:set_doc(Context, cb_context:doc(Context1))};
        _ ->
            {'error', Context1}
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_conference_auth(cb_context:context()) -> cb_context:context().
validate_conference_auth(Context) ->
    case kz_either:pipe(find_account_by_name(Context)
                       ,[fun maybe_account_is_enabled/1
                        ,fun maybe_account_is_expired/1
                        ,fun find_conferences_by_name/1
                        ,fun validate_allow_shareable_link/1
                        ,fun validate_has_member_pins/1
                        ,fun validate_req_pin/1
                        ,fun get_conference_domain/1
                        ,fun set_context_success/1
                        ]
                       )
    of
        {'ok', Context1} -> Context1;
        {'error', Context1} ->
            Reason = get_context_reason(Context1),
            lager:debug("validating conference auth failed with message: ~s", [Reason]),
            crossbar_auth:log_failed_auth(?MODULE, <<"conference_link">>, Reason, Context, cb_context:account_id(Context)),

            %% ignoring the error in context, always return invalid_conference. This is a public face login page
            %% and we don't want to expose any meaningful errors that either the pin or name is not macthing.
            cb_context:add_system_error(401, 'invalid_credentials', <<"invalid conference">>, Context)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_link(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
validate_link(Context, ConferenceId) ->
    {_, Context1} = kz_either:pipe(load_conference(Context, ConferenceId)
                                  ,[fun validate_allow_shareable_link/1
                                   ,fun validate_has_member_pins/1
                                   ,fun get_conference_domain/1
                                   ,fun set_context_success/1
                                   ]
                                  ),
    Context1.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec find_account_by_name(cb_context:context()) -> kz_either:either(cb_context:context(), cb_context:context()).
find_account_by_name(Context) ->
    AccountName = kzd_accounts:normalize_name(
                    kzd_conference_auth:account_name(cb_context:req_data(Context))
                   ),
    case kapps_util:get_accounts_by_name(AccountName) of
        {'ok', AccountDb} ->
            AccountId = kzs_util:format_account_id(AccountDb),
            lager:debug("found account by name '~s': ~s", [AccountName, AccountDb]),
            Setters = [{fun cb_context:set_account_id/2, AccountId}
                      ,{fun cb_context:set_db_name/2, AccountDb}
                      ,{fun cb_context:set_reseller_id/2, kz_services_reseller:find_id(AccountId)}
                      ],
            {'ok', cb_context:setters(Context, Setters)};
        {'multiples', _} ->
            Msg = kz_json:from_list([{<<"message">>, <<"The provided account name returned multiple results">>}
                                    ,{<<"cause">>, AccountName}
                                    ]),
            lager:debug("failed to find account by name: '~s'", [AccountName]),
            {'error', cb_context:add_validation_error(<<"account_name">>, <<"not_found">>, Msg, Context)};
        {'error', _Reason} ->
            Msg = kz_json:from_list([{<<"message">>, <<"The provided account name could not be found">>}
                                    ,{<<"cause">>, AccountName}
                                    ]),
            lager:debug("failed to find account by name '~s': ~p", [AccountName, _Reason]),
            {'error', cb_context:add_validation_error(<<"account_name">>, <<"not_found">>, Msg, Context)}
    end.

-spec maybe_account_is_enabled(cb_context:context()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
maybe_account_is_enabled(Context) ->
    AccountId = cb_context:account_id(Context),
    case kzd_accounts:is_enabled(AccountId) of
        'true' ->
            {'ok', Context};
        'false' ->
            lager:debug("account ~p is disabled", [AccountId]),
            Cause =
                kz_json:from_list(
                  [{<<"message">>, <<"account disabled">>}]
                 ),
            {'error', cb_context:add_validation_error(<<"account">>, <<"disabled">>, Cause, Context)}
    end.

-spec maybe_account_is_expired(cb_context:context()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
maybe_account_is_expired(Context) ->
    AccountId = cb_context:account_id(Context),
    case kzd_accounts:is_expired(AccountId) of
        'false' ->
            {'ok', Context};
        {'true', Expired} ->
            _ = kz_process:spawn(fun crossbar_util:maybe_disable_account/1, [AccountId]),
            Cause =
                kz_json:from_list(
                  [{<<"message">>, <<"account expired">>}
                  ,{<<"cause">>, Expired}
                  ]
                 ),
            lager:debug("account expired: ~p", [Expired]),
            {'error', cb_context:add_validation_error(<<"account">>, <<"expired">>, Cause, Context)}
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec find_conferences_by_name(cb_context:context()) -> kz_either:either(cb_context:context(), cb_context:context()).
find_conferences_by_name(Context) ->
    Name = kzd_conference_auth:conference_name(cb_context:req_data(Context)),
    Options = by_name_options(),
    Selector = [{'key', [{<<"doc_type">>, <<"conference">>}, {<<"name">>, Name}]}],
    case kz_view:find(cb_context:db_name(Context), <<"crossbar_listings/by_type_name">>, Selector, Options) of
        {'ok', []} ->
            lager:debug("no conference with name '~s' was found", [Name]),
            {'ok', cb_context:add_system_error('bad_identifier', Name,  Context)};
        {'ok', JObjs} ->
            lager:debug("found ~b conference by name", [length(JObjs)]),
            {'ok', cb_context:set_doc(Context, JObjs)};
        {'error', Reason} ->
            lager:debug("failed to query for conference name ~p", [Reason]),
            {'ok', cb_context:add_system_error('bad_identifier', Name,  Context)}
    end.

by_name_options() ->
    [{'doc_type', <<"conference">>}
    ,{'filtermap', crossbar_view:get_doc_fun()}
    ,{'should_paginate', 'false'}
    ,{'no_batch', 'true'}
    ,'include_docs'
    ].

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_allow_shareable_link(cb_context:context()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
validate_allow_shareable_link(Context) ->
    validate_allow_shareable_link(Context, cb_context:doc(Context)).

-spec validate_allow_shareable_link(cb_context:context(), kz_json:object() | kz_json:objects()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
%% this clause is only called by validate_conference_auth
validate_allow_shareable_link(Context, JObjs) when is_list(JObjs) ->
    case [JObj || JObj <- JObjs, kzd_conferences:allow_shareable_link(JObj)] of
        [] ->
            Error = kz_json:from_list([{<<"message">>, <<"Public link is disabled for the conference">>}]),
            {'error', cb_context:add_validation_error([<<"allow_shareable_link">>], <<"disabled">>, Error, Context)};
        Enabled ->
            {'ok', cb_context:set_doc(Context, Enabled)}
    end;
validate_allow_shareable_link(Context, JObj) ->
    case kzd_conferences:allow_shareable_link(JObj) of
        'true' ->
            {'ok', Context};
        'false' ->
            Error = kz_json:from_list([{<<"message">>, <<"Public link is disabled for the conference">>}]),
            {'error', cb_context:add_validation_error([<<"allow_shareable_link">>], <<"disabled">>, Error, Context)}
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_has_member_pins(cb_context:context()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
validate_has_member_pins(Context) ->
    validate_has_member_pins(Context, cb_context:doc(Context)).

-spec validate_has_member_pins(cb_context:context(), kz_json:object() | kz_json:objects()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
%% this clause is only called by validate_conference_auth
validate_has_member_pins(Context, JObjs) when is_list(JObjs) ->
    case [JObj || JObj <- JObjs,
                  kz_term:is_not_empty(
                    [P || P <- kzd_conferences:member_pins(JObj),
                          kz_term:is_ne_binary(P)
                    ])
         ]
    of
        [] ->
            Msg = <<"There is no participant PIN number defined for the conference">>,
            Error = kz_json:from_list([{<<"message">>, Msg}]),
            {'error', cb_context:add_validation_error([<<"member">>, <<"pins">>], <<"missing">>, Error, Context)};
        HasPins ->
            {'ok', cb_context:set_doc(Context, HasPins)}
    end;
validate_has_member_pins(Context, JObj) ->
    case [Pin || Pin <- kzd_conferences:member_pins(JObj),
                 kz_term:is_not_empty(Pin)
         ]
    of
        [] ->
            Msg = <<"There is no participant PIN number defined for the conference">>,
            Error = kz_json:from_list([{<<"message">>, Msg}]),
            {'error', cb_context:add_validation_error([<<"member">>, <<"pins">>], <<"missing">>, Error, Context)};
        _Pins ->
            {'ok', Context}
    end.

%%------------------------------------------------------------------------------
%% @doc
%% only called by validate_conference_auth
%% @end
%%------------------------------------------------------------------------------
-spec validate_req_pin(cb_context:context()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
validate_req_pin(Context) ->
    ReqPin = kzd_conference_auth:conference_pin(cb_context:req_data(Context)),
    case [JObj || JObj <- cb_context:doc(Context),
                  lists:member(ReqPin, kzd_conferences:member_pins(JObj))
         ]
    of
        [] ->
            lager:debug("req pin number does not match to any of conference member pin numbers"),
            {'error', cb_context:add_system_error('forbidden', Context)};
        [JObj] ->
            {'ok', cb_context:set_doc(Context, kzd_conferences:set_member_pins(JObj, [ReqPin]))};
        _O ->
            lager:debug("there are multiple conferences with same name and pin number"),
            {'error', cb_context:add_system_error('forbidden', Context)}
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec get_conference_domain(cb_context:context()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
get_conference_domain(Context) ->
    get_account_conference_domain(Context, cb_context:reseller_id(Context), cb_context:account_id(Context)).

-spec get_account_conference_domain(cb_context:context(), kz_term:api_ne_binary(), kz_term:ne_binary()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
get_account_conference_domain(Context, 'undefined', _) ->
    lager:debug("reseller is undefined, reading from system_config"),
    system_public_domain(Context);
get_account_conference_domain(Context, ResellerId, ResellerId) ->
    case fetch_conference_domain(ResellerId) of
        'undefined' ->
            lager:debug("reseller ~s doesn't have conference_public_domain, reading from system_config", [ResellerId]),
            system_public_domain(Context);
        Domain ->
            {'ok', cb_context:store(Context, 'domain', Domain)}
    end;
get_account_conference_domain(Context, Reseller, AccountId) ->
    case fetch_conference_domain(AccountId) of
        'undefined' ->
            lager:debug("account ~s doesn't have conference_public_domain, maybe reading from parent", [AccountId]),
            case kzd_accounts:get_parent_account_id(AccountId) of
                'undefined' ->
                    lager:debug("no parent account were found, reading from system_config"),
                    system_public_domain(Context);
                ParentId ->
                    lager:debug("reading from parent ~s account", [ParentId]),
                    get_account_conference_domain(Context, Reseller, ParentId)
            end;
        Domain ->
            lager:debug("using account ~s conference_public_domain", [AccountId]),
            {'ok', cb_context:store(Context, 'domain', Domain)}
    end.

-spec system_public_domain(cb_context:context()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
system_public_domain(Context) ->
    case kapps_config:get_ne_binary(?MOD_CONFIG_CAT, <<"conference_public_domain">>) of
        'undefined' ->
            error_no_public_domain(Context);
        Domain ->
            {'ok', cb_context:store(Context, 'domain', Domain)}
    end.

-spec fetch_conference_domain(kz_term:ne_binary()) -> kz_term:api_ne_binary().
fetch_conference_domain(AccountId) ->
    case kzd_whitelabel:fetch(AccountId) of
        {'ok', JObj} -> kzd_whitelabel:conference_public_domain(JObj);
        {'error', _} -> 'undefined'
    end.

-spec error_no_public_domain(cb_context:context()) -> {'error', cb_context:context()}.
error_no_public_domain(Context) ->
    Error = <<"no public conference domain is configured">>,
    lager:debug("~s", [Error]),
    {'error', cb_context:add_validation_error([<<"conference_public_domain">>], <<"missing">>, Error, Context)}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec set_context_success(cb_context:context()) ->
          kz_either:either(cb_context:context(), cb_context:context()).
set_context_success(Context) ->
    {'ok', cb_context:set_resp_status(Context, 'success')}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec get_context_reason(cb_context:context()) -> kz_term:ne_binary().
get_context_reason(Context) ->
    C1 = cb_context:import_errors(Context),
    {'error', {ErrorCode, ErrorMsg, RespData}} = cb_context:response(C1),
    case kz_json:is_json_object(RespData) of
        'true' ->
            kz_binary:format("~p ~s: ~s", [ErrorCode, ErrorMsg, kz_json:encode(RespData)]);
        'false' ->
            kz_binary:format("~p ~s: ~s", [ErrorCode, ErrorMsg, RespData])
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec create_auth_token(cb_context:context()) -> cb_context:context().
create_auth_token(Context) ->
    JObj = cb_context:doc(Context),
    [Pin|_] = kzd_conferences:member_pins(JObj),
    Prop = [{<<"Claims">>, [{<<"account_id">>, cb_context:account_id(Context)}
                           ,{<<"conference_id">>, kz_doc:id(JObj)}
                           ,{<<"pin_number">>, Pin}
                           ,{<<"scope">>, ?INVITE_ALLOWED_SCOPE}
                           ]
            }
           ],
    Setters = [{fun cb_context:store/3, 'auth_type', <<"conference_invite_link">>}
              ,{fun cb_context:set_doc/2, kz_json:from_list_recursive(Prop)}
              ,{fun cb_context:set_resp_status/2, 'success'}
              ],
    crossbar_auth:create_auth_token(cb_context:setters(Context, Setters), ?MODULE).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec create_conference_link(cb_context:context()) -> cb_context:context().
create_conference_link(Context) ->
    Domain = cb_context:fetch(Context, 'domain'),
    C1 = create_auth_token(Context),
    case cb_context:resp_status(C1) of
        'success' ->
            AuthToken = cb_context:auth_token(C1),
            RespData = kz_json:from_list([{<<"link">>, <<Domain/binary, "?auth=", AuthToken/binary>>}]),
            crossbar_doc:handle_json_success(RespData, Context);
        _ ->
            C1
    end.
