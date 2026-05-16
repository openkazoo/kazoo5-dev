%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023, 2600Hz
%%% @doc Pushes module
%%% Handle pushes requests for users and devices.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_pushes).

-compile({no_auto_import, [put/2]}).

-export([init/0
        ,allowed_methods/0
        ,resource_exists/0
        ,validate_resource/1
        ,validate/1
        ,put/1
        ]).

-ifdef(TEST).
-export([to_push_payload/2]).
-endif.

-include("crossbar.hrl").

-define(PUSH_PATH_TOKEN, <<"pushes">>).
-define(PUSH_NOUNS(API, EndpointId), [{?PUSH_PATH_TOKEN, []}
                                     ,{API, [EndpointId]}
                                     ,{?KZ_ACCOUNTS_DB, _AccountId}
                                     ]).
-define(IS_VALID_API(API), API =:= <<"users">>; API =:= <<"devices">>).
-define(PUSH_TYPE, <<"custom_push">>).

-type to_push_payload_options() :: [%% list of {WORD, REPLACE} pairs. Replaces every occurrence of WORD
                                    %% with REPLACE within fields' words.
                                    {'explicit_replaces', [{kz_term:ne_binary(), kz_term:ne_binary()}]}
                                    %% Whether or not to normalize nested keys along root keys. Defaults to false.
                                   |{'convert_nested_keys', boolean()}
                                   ].

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    Bindings = [{<<"*.allowed_methods.pushes">>, 'allowed_methods'}
               ,{<<"*.resource_exists.pushes">>, 'resource_exists'}
               ,{<<"*.validate_resource.pushes">>, 'validate_resource'}
               ,{<<"*.validate.pushes">>, 'validate'}
               ,{<<"*.execute.put.pushes">>, 'put'}
               ],
    cb_modules_util:bind(?MODULE, Bindings),
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
    [?HTTP_PUT].

%%------------------------------------------------------------------------------
%% @doc This function determines if the provided list of Nouns are valid.
%% Failure here returns `404 Not Found'.
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() ->
    'true'.

%%------------------------------------------------------------------------------
%% @doc This function determines if the provided list of Nouns and Resource Ids are valid.
%% If valid, load Endpoint resource within Context.
%%
%% Failure here returns `404 Not Found'.
%% @end
%%------------------------------------------------------------------------------
-spec validate_resource(cb_context:context()) -> cb_context:context().
validate_resource(Context) ->
    validate_resource(Context, cb_context:req_nouns(Context)).

-spec validate_resource(cb_context:context(), req_nouns()) -> cb_context:context().
validate_resource(Context, ?PUSH_NOUNS(_API, EndpointId)) when ?IS_VALID_API(_API) ->
    load_endpoint(EndpointId, Context).

%%------------------------------------------------------------------------------
%% @doc This function determines if the parameters and content are correct
%% for this request
%%
%% Failure here returns 400.
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate(Context, cb_context:req_nouns(Context)).

-spec validate(cb_context:context(), req_nouns()) -> cb_context:context().
validate(Context, ?PUSH_NOUNS(_API, _EndpointId)) when ?IS_VALID_API(_API) ->
    cb_context:validate_request_data(<<"pushes">>, Context).

%%------------------------------------------------------------------------------
%% @doc Take the payload of the request and publish AMQP message(s) and if resulting
%% device(s) has/have pusher enabled/configured, it will received the payload via
%% pusher application.
%% @end
%%------------------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    put(Context, cb_context:req_nouns(Context)).

-spec put(cb_context:context(), req_nouns()) -> cb_context:context().
put(Context, ?PUSH_NOUNS(_API, EndpointId)) when ?IS_VALID_API(_API) ->
    AccountId = cb_context:account_id(Context),
    EndpointType = kz_doc:type(cb_context:fetch(Context, 'db_doc')),
    lager:debug("pushing payload to ~s/~s/~s", [AccountId, EndpointType, EndpointId]),
    Req = kz_json:merge(push_payload_to_amqp_payload(cb_context:req_data(Context))
                       ,kz_json:from_list_recursive([{<<"Account-ID">>, AccountId}
                                                    ,{<<"Endpoint">>
                                                     ,[{<<"ID">>, EndpointId}
                                                      ,{<<"Type">>, EndpointType}
                                                      ]
                                                     }
                                                    | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
                                                    ])
                       ),
    {'ok', Resp} = kz_amqp_worker:call(Req, fun kapi_pusher:publish_endpoint_push_req/1),
    handle_push_response(Context, Resp).

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Load endpoint's document from the database.
%% @end
%%------------------------------------------------------------------------------
-spec load_endpoint(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
load_endpoint(EndpointId, Context) ->
    ExpectedTypes = ?TYPE_CHECK_OPTION([kzd_devices:type(), kzd_users:type()]),
    crossbar_doc:load(EndpointId, Context, ExpectedTypes).

%%------------------------------------------------------------------------------
%% @doc Convert received payload (_ separated lower case words as keys) into the
%% expected AMQP payload.
%% @end
%%------------------------------------------------------------------------------
-spec push_payload_to_amqp_payload(kz_json:object()) -> kz_json:object().
push_payload_to_amqp_payload(ReqData) ->
    ExplicitReplaces = [{<<"apns">>, <<"APNs">>}
                       ,{<<"fcm">>, <<"FCM">>}
                       ,{<<"ttl">>, <<"TTL">>}
                       ],
    Options = [{'explicit_replaces', ExplicitReplaces}
              ,{'convert_nested_keys', 'true'}
              ],

    {'value', ClientData, RD} = kz_json:take_value(<<"data">>, ReqData, kz_json:new()),
    %% "ClientData" (data.data) is a user-defined field, therefore do not normalize
    kz_json:set_value(<<"Data">>, add_push_type(ClientData), to_push_payload(RD, Options)).

%%------------------------------------------------------------------------------
%% @doc Handle pusher's response to pushes requests.
%% @end
%%------------------------------------------------------------------------------
-spec handle_push_response(cb_context:context(), kz_json:object()) -> cb_context:context().
handle_push_response(Context, JObj) ->
    'true' = kapi_pusher:endpoint_push_resp_v(JObj),
    Code = kz_json:get_integer_value(<<"Overall-Status">>, JObj),
    NormalizedResults = [kz_json:normalize(R) || R <- kz_json:get_list_value(<<"Results">>, JObj)],
    handle_push_response(Context, Code, NormalizedResults).

-spec handle_push_response(cb_context:context(), pos_integer(), kz_json:objects()) ->
          cb_context:context().
handle_push_response(Context, Code, NormalizedResults) when Code >= 400 ->
    Msg = <<"At least one push request failed. Check results field for more information.">>,
    handle_push_response(Context, Code, NormalizedResults, 'error', Msg);
handle_push_response(Context, Code, NormalizedResults) ->
    Msg = <<"All the push requests succeeded.">>,
    handle_push_response(Context, Code, NormalizedResults, 'success', Msg).

-spec handle_push_response(cb_context:context()
                          ,pos_integer()
                          ,kz_json:objects()
                          ,'error' | 'success'
                          ,kz_term:ne_binary()
                          ) ->
          cb_context:context().
handle_push_response(Context, Code, NormalizedResults, Status, Msg) ->
    Results = kz_json:from_list([{<<"results">>, NormalizedResults}]),
    crossbar_util:response(Status, Msg, Code, Results, Context).

%%------------------------------------------------------------------------------
%% @doc Normalize a JSON object to be sent within an AMQP message. Converts
%% Crossbar objects into AMQP objects.
%% All underscores are replaced by dashes, and uppercase the first character of
%% each word (separated by -) with a single exception, "id" should be returned
%% as "ID".
%%
%% Example:
%%  input:  `{[{<<"doc_id">>, <<"some id">>}, {<<"three_words_key">>, <<"value">>}]}'
%%  output: `{[{<<"Doc-ID">>, <<"some id">>}, {<<"Three-Words-Key">>, <<"value">>}]}'
%% @end
%%------------------------------------------------------------------------------
%% {
-spec to_push_payload(kz_json:object(), to_push_payload_options()) -> kz_json:object().
to_push_payload(JObj, Options) ->
    kz_json:foldl(fun(K, V, Acc) -> fold_to_push_payload(K, V, Acc, Options) end
                 ,kz_json:new()
                 ,JObj
                 ).

%%------------------------------------------------------------------------------
%% @doc if Value is a (nested) JSON object and `convert_nested_keys=true',
%% normalize it as well, otherwise, leave it as it is.
%% @end
%%------------------------------------------------------------------------------
-spec fold_to_push_payload(kz_json:key(), kz_json:json_term(), kz_json:object(), to_push_payload_options()) ->
          kz_json:object().
fold_to_push_payload(Key, Value, Acc, Options) ->
    NormalizedKey = to_push_payload_key(Key, Options),
    case kz_json:is_json_object(Value)
        andalso props:get_is_true('convert_nested_keys', Options, 'false')
    of
        'true' ->
            kz_json:set_value(NormalizedKey, to_push_payload(Value, Options), Acc);
        'false' ->
            kz_json:set_value(NormalizedKey, Value, Acc)
    end.

-spec to_push_payload_key(kz_json:key(), to_push_payload_options()) -> kz_json:key().
to_push_payload_key(Key, Options) ->
    %% Split by "_", maybe upper case first character in every word, and join list using "-".
    kz_binary:join([maybe_ucfirst(Word, Options)
                    || Word <- binary:split(Key, <<"_">>, ['global']),
                       %% Filter out empty words, e.g.: binary:split(<<"_id">>, <<"_">>) -> [<<>>, <<"id">>].
                       Word =/= <<>>
                   ]
                  ,<<"-">>
                  ).

%%------------------------------------------------------------------------------
%% @doc If explicit replace was provided for the given word, it will be used,
%% otherwise, the first letter of the given word will be upper cased.
%%
%% There is an exception to this behavior, if word="id", "ID" will be returned.
%% @end
%%------------------------------------------------------------------------------
-spec maybe_ucfirst(kz_term:ne_binary(), to_push_payload_options()) -> kz_json:key().
maybe_ucfirst(<<"id">>, _Options) ->
    %% Special case.
    <<"ID">>;
maybe_ucfirst(Word, Options) ->
    case props:get_value(Word, props:get_value('explicit_replaces', Options, [])) of
        'undefined' -> kz_binary:ucfirst(Word);
        Explicit -> Explicit
    end.
%% }

-spec add_push_type(kz_json:object()) -> kz_json:object().
add_push_type(DataJObj) ->
    kz_json:set_value(<<"Push-Type">>, ?PUSH_TYPE, DataJObj).
