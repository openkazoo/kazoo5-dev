%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2025, 2600Hz
%%% @doc Crossbar API for external numbers.
%%% @author Karl Anderson
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_external_numbers).

-export([init/0
        ,allowed_methods/0, allowed_methods/1, allowed_methods/2
        ,resource_exists/0, resource_exists/1, resource_exists/2
        ,validate/1, validate/2, validate/3
        ,put/1, put/3
        ,post/3
        ,delete/2
        ]).

-include("crossbar.hrl").

-define(VERIFY, <<"verify">>).
-define(PVT_TYPE, kzd_external_numbers:type()).

-define(MOD_CONFIG_CAT, <<(?CONFIG_CAT)/binary, ".external_numbers">>).

-define(SMS_VERIFY_TEMPLATE, <<"Your verification code is {{verify.code}}">>).
-define(SMS_VERIFY_BODY_KEY, <<"sms_verify_message">>).
-define(DEFAULT_SMS_VERIFY_BODY, kapps_config:get_ne_binary(?MOD_CONFIG_CAT, ?SMS_VERIFY_BODY_KEY, ?SMS_VERIFY_TEMPLATE)).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.external_numbers">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.external_numbers">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.external_numbers">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.get.external_numbers">>, ?MODULE, 'get'),
    _ = crossbar_bindings:bind(<<"*.execute.put.external_numbers">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.external_numbers">>, ?MODULE, 'post'),
    _ = crossbar_bindings:bind(<<"*.execute.delete.external_numbers">>, ?MODULE, 'delete').

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_ExternalNumberId) ->
    [?HTTP_GET, ?HTTP_DELETE].

-spec allowed_methods(path_token(), path_token()) -> http_methods().
allowed_methods(_ExternalNumberId, ?VERIFY) ->
    [?HTTP_PUT, ?HTTP_POST].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% @end
%%------------------------------------------------------------------------------

-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_) -> 'true'.

-spec resource_exists(path_token(), path_token()) -> 'true'.
resource_exists(_, ?VERIFY) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% @end
%%------------------------------------------------------------------------------

-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_external_numbers(Context, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, Id) ->
    validate_external_number(Context, Id, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token(), path_token()) -> cb_context:context().
validate(Context, Id, ?VERIFY) ->
    validate_external_number_verify(Context, Id, cb_context:req_verb(Context)).

-spec validate_external_numbers(cb_context:context(), http_method()) -> cb_context:context().
validate_external_numbers(Context, ?HTTP_GET) ->
    summary(Context);
validate_external_numbers(Context, ?HTTP_PUT) ->
    create(Context).

-spec validate_external_number(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_external_number(Context, Id, ?HTTP_GET) ->
    read(Id, Context);
validate_external_number(Context, Id, ?HTTP_DELETE) ->
    read(Id, Context).

-spec validate_external_number_verify(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_external_number_verify(Context, Id, ?HTTP_PUT) ->
    OnSuccess = fun(C) -> read(Id, C) end,
    cb_context:validate_request_data(<<"external_number_verify">>, Context, OnSuccess);
validate_external_number_verify(Context, Id, ?HTTP_POST) ->
    OnSuccess = fun(C) -> read(Id, C) end,
    case cb_context:is_superduper_admin(Context) of
        'true' -> OnSuccess(Context);
        'false' ->
            cb_context:validate_request_data(<<"external_number_claim">>, Context, OnSuccess)
    end.

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is PUT, execute the actual action, usually a db save.
%% @end
%%------------------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_doc:save(Context).

-spec put(cb_context:context(), path_token(), path_token()) -> cb_context:context().
put(Context, _Id, ?VERIFY) ->
    Context1 = crossbar_doc:save(update_code(Context)),
    case cb_context:resp_status(Context1) of
        'success' -> send_verification_code(Context1);
        _Else -> Context1
    end.

-spec update_code(cb_context:context()) -> cb_context:context().
update_code(Context) ->
    Doc = cb_context:doc(Context),
    Code = kz_term:to_binary(kz_term:rand_integer(1000, 9999)),
    Setters = [{fun kzd_external_numbers:set_attestation/2, kz_json:new()}
              ,{fun kzd_external_numbers:set_pvt_code/2, Code}
              ,{fun kzd_external_numbers:set_pvt_verified/2, 'false'}
              ],
    cb_context:set_doc(Context, kz_doc:setters(Doc, Setters)).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is POST, execute the actual action, usually a db save
%% (after a merge perhaps).
%% @end
%%------------------------------------------------------------------------------
-spec post(cb_context:context(), path_token(), path_token()) -> cb_context:context().
post(Context, _Id, ?VERIFY) ->
    Doc = cb_context:doc(Context),
    Code = kzd_external_number_claim:code(cb_context:req_data(Context)),
    case Code =:= kzd_external_numbers:pvt_code(Doc)
        orelse (kz_term:is_empty(Code)
                andalso cb_context:is_superduper_admin(Context)
               )
    of
        'true' -> number_verified(Context);
        'false' ->
            cb_context:add_validation_error(<<"code">>, <<"invalid">>, <<"code does not match">>, Context)
    end.

-spec number_verified(cb_context:context()) -> cb_context:context().
number_verified(Context) ->
    lager:debug("number ~s has been verified."
               ,[kzd_external_numbers:number(cb_context:doc(Context))]
               ),
    Doc = cb_context:doc(Context),
    AccountId = cb_context:auth_account_id(Context),
    UserId = cb_context:auth_user_id(Context),
    Setters = [{fun kzd_external_numbers:set_attestation_date/2, kz_time:now_s()}
              ,{fun kzd_external_numbers:set_attestation_token_method/2
               ,kz_json:get_ne_binary_value(<<"method">>, cb_context:auth_doc(Context))
               }
              ,{fun kzd_external_numbers:set_attestation_token_source/2
               ,cb_context:client_ip(Context)
               }
              ,{fun kzd_external_numbers:set_attestation_account_id/2, AccountId}
              ,{fun kzd_external_numbers:set_attestation_account_name/2
               ,kzd_accounts:fetch_name(AccountId)
               }
              ,{fun kzd_external_numbers:set_attestation_user_id/2, UserId}
              ,{fun kzd_external_numbers:set_attestation_user_name/2, <<>>}
              ,{fun kzd_external_numbers:set_pvt_adopted/2, 'false'}
              ,{fun kzd_external_numbers:set_pvt_verified/2, 'true'}
              ,{fun kzd_external_numbers:set_pvt_code/2, 'undefined'}
              ],
    crossbar_doc:save(cb_context:set_doc(Context, kz_doc:setters(Doc, Setters))).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is DELETE, execute the actual action, usually a db delete
%% @end
%%------------------------------------------------------------------------------
-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _) ->
    crossbar_doc:delete(Context).

%%------------------------------------------------------------------------------
%% @doc Create a new instance with the data provided, if it is valid
%% @end
%%------------------------------------------------------------------------------
-spec create(cb_context:context()) -> cb_context:context().
create(Context) ->
    OnSuccess = fun additional_create_validation/1,
    cb_context:validate_request_data(<<"external_numbers">>, Context, OnSuccess).

-spec additional_create_validation(cb_context:context()) -> cb_context:context().
additional_create_validation(Context) ->
    Routines = [fun validate_number_reconcilable/1
               ,fun validate_number_unique/1
               ],
    lists:foldl(fun(F, C) -> F(C) end, initalize_fields(Context), Routines).

-spec initalize_fields(cb_context:context()) -> cb_context:context().
initalize_fields(Context) ->
    Doc = cb_context:doc(Context),
    Number = knm_converters:normalize(
               kzd_external_numbers:number(Doc)
              ),
    Setters = [{fun kzd_external_numbers:set_number/2, Number}
              ,{fun kzd_external_numbers:set_attestation/2, kz_json:new()}
              ,{fun kzd_external_numbers:set_pvt_verified/2, 'false'}
              ,{fun kz_doc:set_type/2, ?PVT_TYPE}
              ],
    cb_context:set_doc(Context, kz_doc:setters(Doc, Setters)).

-spec validate_number_reconcilable(cb_context:context()) -> cb_context:context().
validate_number_reconcilable(Context) ->
    Number = kzd_external_numbers:number(cb_context:doc(Context)),
    case knm_converters:is_reconcilable(Number) of
        'true' -> Context;
        'false' ->
            cb_context:add_validation_error(<<"number">>, <<"invalid">>, <<"number is not an external number">>, Context)
    end.

-spec validate_number_unique(cb_context:context()) -> cb_context:context().
validate_number_unique(Context) ->
    Number = kzd_external_numbers:number(cb_context:doc(Context)),
    AccountId = cb_context:account_id(Context),
    PhoneNumbers = props:get_keys(knm_numbers:account_listing(AccountId)),
    case lists:member(Number, PhoneNumbers) of
        'true' ->
            cb_context:add_validation_error(<<"number">>, <<"unique">>, <<"number is already assigned as a phone number">>, Context);
        'false' ->
            ExternalNumbers = get_external_numbers(Context),
            case lists:member(Number, ExternalNumbers) of
                'true' ->
                    cb_context:add_validation_error(<<"number">>, <<"unique">>, <<"number is already assigned as an external number">>, Context);
                'false' ->
                    Context
            end
    end.

-spec get_external_numbers(cb_context:context()) -> kz_term:ne_binaries().
get_external_numbers(Context) ->
    AccountId = cb_context:account_id(Context),
    ViewOptions = [{'startkey', [kzd_external_numbers:type()]}
                  ,{'endkey', [kzd_external_numbers:type(), kz_json:new()]}
                  ],
    case kz_datamgr:get_results(AccountId, <<"crossbar_listings/by_type_number">>, ViewOptions) of
        {'ok', JObjs} ->
            [kzd_external_numbers:number(
               kz_json:get_json_value(<<"value">>, JObj)
              )
             || JObj <- JObjs
            ];
        _Else -> []
    end.

%%------------------------------------------------------------------------------
%% @doc Load an instance from the database
%% @end
%%------------------------------------------------------------------------------
-spec read(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
read(Id, Context) ->
    crossbar_doc:load(Id, Context, ?TYPE_CHECK_OPTION(?PVT_TYPE)).

%%------------------------------------------------------------------------------
%% @doc Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%------------------------------------------------------------------------------
-spec summary(cb_context:context()) -> cb_context:context().
summary(Context) ->
    Options = [{'doc_type', ?PVT_TYPE}
              ,{'mapper', crossbar_view:get_value_fun()}
              ],
    Selector = [{'start', [{<<"doc_type">>, ?PVT_TYPE}]}
               ,{'end', [{<<"doc_type">>, ?PVT_TYPE}]}
               ],
    crossbar_view:find(Context, <<"crossbar_listings/by_type_number">>, Selector, Options).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec send_verification_code(cb_context:context()) -> cb_context:context().
send_verification_code(Context) ->
    case kzd_external_number_verify:method(cb_context:req_data(Context)) of
        <<"sms">> -> send_sms_code(Context);
        <<"voice">> -> send_voice_code(Context);
        <<"ivr">> -> ivr_verify(Context)
    end.

-spec send_sms_code(cb_context:context()) -> cb_context:context().
send_sms_code(Context) ->
    Doc = cb_context:doc(Context),
    Number = kzd_external_numbers:number(Doc),
    Code = kzd_external_numbers:pvt_code(Doc),
    {CIDNumber, _CIDName} = caller_id(Context),
    Body = case get_message(Context) of
               'undefined' ->
                   Template = ?SMS_VERIFY_TEMPLATE,
                   Code = kzd_external_numbers:pvt_code(cb_context:doc(Context)),
                   binary:replace(Template, <<"{{verify.code}}">>, Code, ['global']);
               Message -> Message
           end,
    Request = [{<<"Message-ID">>, kz_binary:rand_hex(16)}
              ,{<<"Body">>, Body}
              ,{<<"From">>, CIDNumber}
              ,{<<"To">>, Number}
              ,{<<"Account-ID">>, cb_context:account_id(Context)}
              ,{<<"Route-Type">>, <<"offnet">>}
               %%,{<<"Application-ID">>, ?APP_ID}
              ,{<<"Event-Category">>, <<"sms">>}
              | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
              ],
    _ = kz_amqp_worker:cast(Request, fun kapi_im:publish_outbound/1),
    cb_context:set_resp_data(Context, kz_json:new()).

-spec send_voice_code(cb_context:context()) -> cb_context:context().
send_voice_code(Context) ->
    case place_call(Context) of
        {'ok', JObj} ->
            play_code(Context, kz_json:get_value(<<"Call">>, JObj));
        {'timeout', _} ->
            cb_context:add_system_error(<<"call failure">>, Context);
        {'error', E} ->
            cb_context:add_system_error(E, Context)
    end.

-spec play_code(cb_context:context(), kz_term:api_object()) -> cb_context:context().
play_code(Context, 'undefined') ->
    cb_context:add_system_error(<<"call failure">>, Context);
play_code(Context, JObj) ->
    Doc = cb_context:doc(Context),
    Code = kzd_external_numbers:pvt_code(Doc),
    Call = kapps_call:from_json(JObj),
    %% NOTE: this process is not bound for call
    %%   events because we can just queue all the commands
    %%   in ecallmgr and let it handle executing them
    %%   since its just a static sequence.
    %%   (fire and forget)
    kapps_call_command:wait_for_answer(Call),

    _ = play_message_code(Call, Code, get_message(Context)),

    kapps_call_command:queued_hangup(Call),
    cb_context:set_resp_data(Context, kapps_call:to_public_json(Call)).

play_message_code(Call, Code, 'undefined') ->
    _ = kapps_call_command:audio_macro(
          [{'prompt', <<"general-hello">>}
          ,{'prompt', <<"external-number-request_for">>}
          ,{'say', kapps_call:request_user(Call), <<"telephone_number">>}
          ,{'prompt', <<"external-number-description">>}
          ], Call),
    _ = kapps_call_command:audio_macro(
          [{'prompt', <<"general-authorization_code">>}
          | say_number_by_number(Code)
          ], Call),
    _ = kapps_call_command:audio_macro(
          [{'prompt', <<"general-again">>}
          ,{'prompt', <<"general-authorization_code">>}
          | say_number_by_number(Code)
          ], Call),
    _ = kapps_call_command:audio_macro(
          [{'prompt', <<"general-once_more">>}
          ,{'prompt', <<"general-authorization_code">>}
          | say_number_by_number(Code)
          ], Call),
    kapps_call_command:prompt(<<"general-goodbye">>, Call);
play_message_code(Call, _Code, Message) ->
    kapps_call_command:tts(Message, Call).

-spec say_number_by_number(kz_term:ne_binary()) -> kz_term:proplist().
say_number_by_number(Number) ->
    say_number_by_number(Number, []).

say_number_by_number(<<>>, Say) ->
    lists:reverse(Say);
say_number_by_number(<<Number, Rest/binary>>, Say) ->
    say_number_by_number(Rest, [{'say', Number} | Say]).

-spec ivr_verify(cb_context:context()) -> cb_context:context().
ivr_verify(Context) ->
    case place_call(Context) of
        {'ok', JObj} ->
            execute_ivr(Context, kz_json:get_json_value(<<"Call">>, JObj));
        {'timeout', _} ->
            cb_context:add_system_error(<<"call failure">>, Context);
        {'error', E} ->
            cb_context:add_system_error(E, Context)
    end.

-spec execute_ivr(cb_context:context(), kz_term:api_object()) -> cb_context:context().
execute_ivr(Context, 'undefined') ->
    cb_context:add_system_error(<<"call failure">>, Context);
execute_ivr(Context, JObj) ->
    Call = kapps_call:from_json(JObj),
    %% NOTE: this process is bound for call events
    %%   because we need to be able to receive
    %%   a digit during the prompt indicating
    %%   the user has confirmed they have the number.
    _ = kz_events:bind_call_id(kapps_call:call_id(Call)),
    kapps_call_command:wait_for_answer(Call),

    _ = send_ivr_message(Call, get_message(Context)),

    Context1 = verify_ivr_number(Context, Call),

    _ = kapps_call_command:prompt(<<"general-goodbye">>, Call),
    kapps_call_command:queued_hangup(Call),
    Context1.

verify_ivr_number(Context, Call) ->
    case kapps_call_command:collect_digits(1, 25 * ?MILLISECONDS_IN_SECOND, Call) of
        {'ok', <<"1">>} -> number_verified(Context);
        _Else ->
            lager:info("user did not accept IVR verification"),
            Context
    end.

send_ivr_message(Call, 'undefined') ->
    kapps_call_command:audio_macro(
      [{'prompt', <<"general-hello">>}
      ,{'prompt', <<"external-number-request_for">>}
      ,{'say', kapps_call:request_user(Call), <<"telephone_number">>}
      ,{'prompt', <<"external-number-ivr_verification">>}
      ], Call);
send_ivr_message(Call, Message) ->
    kapps_call_command:tts(Message, Call).

-spec place_call(cb_context:context()) -> kz_amqp_worker:request_return().
place_call(Context) ->
    AccountId = cb_context:account_id(Context),
    Realm = kzd_accounts:fetch_realm(AccountId),
    Number = kzd_external_numbers:number(cb_context:doc(Context)),
    {CIDNumber, CIDName} = caller_id(Context),
    Request = props:filter_undefined(
                [{<<"Account-ID">>, AccountId}
                ,{<<"Account-Realm">>, Realm}
                ,{<<"To-DID">>, Number}
                ,{<<"Outbound-Caller-ID-Name">>, CIDName}
                ,{<<"Outbound-Caller-ID-Number">>, CIDNumber}
                ,{<<"Resource-Type">>, <<"originate">>}
                ,{<<"Application-Name">>, <<"park">>}
                ,{<<"Originate-Immediate">>, 'true'}
                ,{<<"Timeout">>, 30}
                ,{<<"Hunt-Account-ID">>, get_hunt_account_id(AccountId)}
                ,{<<"Flags">>, get_flags(AccountId)}
                | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
                ]),
    kz_amqp_worker:call(Request
                       ,fun kapi_offnet_resource:publish_req/1
                       ,fun kapi_offnet_resource:resp_v/1
                       ,30 * ?MILLISECONDS_IN_SECOND
                       ).

-spec get_flags(kz_term:ne_binary()) -> kz_term:ne_binaries().
get_flags(AccountId) ->
    Funs = [{fun kapps_call:set_account_id/2, AccountId}
           ,{fun kapps_call:set_account_db/2, kzs_util:format_account_db(AccountId)}
           ],
    kz_attributes:get_flags(?APP_NAME, kapps_call:exec(Funs, kapps_call:new())).

-spec get_hunt_account_id(kz_term:ne_binary()) -> kz_term:api_ne_binary().
get_hunt_account_id(AccountId) ->
    case kapps_call:should_use_local_resources(AccountId) of
        'false' -> 'undefined';
        'true' -> kapps_call:hunt_account_id(AccountId)
    end.

-spec caller_id(cb_context:context()) -> {kz_term:ne_binary(), kz_term:ne_binary()}.
caller_id(Context) ->
    case kzd_accounts:fetch(cb_context:account_id(Context)) of
        {'error', _R} ->
            lager:warning("unable to determine caller id, account document fetch returned error ~p", _R),
            {kz_privacy:anonymous_caller_id_number(), kz_privacy:anonymous_caller_id_name()};
        {'ok', JObj} ->
            CallerIds = kzd_accounts:caller_id(JObj),
            Number = kz_json:get_first_defined([[<<"external">>, <<"number">>]
                                               ,[<<"default">>, <<"number">>]
                                               ]
                                              ,CallerIds
                                              ,kz_privacy:anonymous_caller_id_number()
                                              ),
            Name = kz_json:get_first_defined([[<<"external">>, <<"name">>]
                                             ,[<<"default">>, <<"name">>]
                                             ]
                                            ,CallerIds
                                            ,kzd_accounts:name(JObj)
                                            ),
            {Number, Name}
    end.

-spec get_message(cb_context:context()) -> kz_term:api_ne_binary().
get_message(Context) ->
    case kzd_external_number_verify:message(cb_context:req_data(Context)) of
        'undefined' -> 'undefined';
        Message ->
            Code = kzd_external_numbers:pvt_code(cb_context:doc(Context)),
            binary:replace(Message, <<"{{verify.code}}">>, Code, ['global'])
    end.
