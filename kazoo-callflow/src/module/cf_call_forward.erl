%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Callflow action to control call forwarding feature.
%%%
%%% <h4>Data options:</h4>
%%% <dl>
%%%   <dt>`action'</dt>
%%%   <dd>The action to be done: `activate', `deactivate', `update', `toggle' and `menu'.</dd>
%%% </dl>
%%%
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_call_forward).

-behaviour(gen_cf_action).

-include("callflow.hrl").

-export([handle/2]).

%% more for properly testing than anything
-export([get_call_forward/1
        ,update_callfwd/2
        ,set_active/1, set_deactive/1
        ,toggle_active/1
        ,set_number/2
        ]).

-ifdef(TEST).
-export([update_call_forward/3]).
-endif.

-define(MOD_CONFIG_CAT, <<(?CF_CONFIG_CAT)/binary, ".call_forward">>).
-define(KEY_LENGTH, 1).

-define(MIN_CALLFWD_NUMBER_LENGTH
       ,max(kapps_config:get_integer(?MOD_CONFIG_CAT, <<"min_callfwd_number_length">>, 3), 1)
       ).
-define(MAX_CALLFWD_NUMBER_LENGTH
       ,kapps_config:get_integer(?MOD_CONFIG_CAT, <<"max_callfwd_number_length">>, 20)
       ).
-define(CALLFWD_NUMBER_TIMEOUT
       ,kapps_config:get_integer(?MOD_CONFIG_CAT, <<"callfwd_number_timeout">>, 8000)
       ).

-define(DEFAULT_MENU_RETRIES, 3).

-define(KEY_TOGGLE
       ,kapps_config:get_ne_binary(?MOD_CONFIG_CAT, [<<"keys">>, <<"menu_toggle_option">>], <<"1">>)
       ).
-define(KEY_CHANGE
       ,kapps_config:get_ne_binary(?MOD_CONFIG_CAT, [<<"keys">>, <<"menu_change_number">>], <<"2">>)
       ).

-record(keys, {menu_toggle_cf = ?KEY_TOGGLE :: kz_term:ne_binary()
              ,menu_change_number = ?KEY_CHANGE :: kz_term:ne_binary()
              }).
-type keys() :: #keys{}.

-record(callfwd, {keys = #keys{} :: keys()
                 ,doc_id :: kz_term:api_ne_binary()
                 ,enabled = 'false' :: boolean()
                 ,number = 'undefined' :: kz_term:api_binary()
                 ,require_keypress = 'true' :: boolean()
                 ,keep_caller_id = 'true' :: boolean()
                 ,interdigit_timeout = kapps_call_command:default_interdigit_timeout() :: pos_integer()
                 ,menu_retries = ?DEFAULT_MENU_RETRIES :: non_neg_integer()
                 }).
-type callfwd() :: #callfwd{}.

%%------------------------------------------------------------------------------
%% @doc Entry point for this module, attempts to call an endpoint as defined
%% in the Data payload.  Returns continue if fails to connect or
%% stop when successful.
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    case get_call_forward(Call) of
        {'error', 'not_found'} ->
            catch({'ok', _} = kapps_call_command:b_prompt(<<"cf-not_available">>, Call)),
            cf_exe:stop(Call);
        #callfwd{}=CF ->
            handle(Data, Call, CF#callfwd{menu_retries=menu_retries(Data)})
    end.

menu_retries(Data) ->
    kz_json:get_integer_value(<<"menu_retries">>, Data, ?DEFAULT_MENU_RETRIES).

handle(Data, Call, CF) ->
    {'ok', _} = kapps_call_command:b_answer(Call),

    CaptureGroup = kapps_call:kvs_fetch('cf_capture_group', 'undefined', Call),

    CF1 = case kz_json:get_ne_binary_value(<<"action">>, Data) of
              <<"activate">> -> cf_activate(CF, CaptureGroup, Call);       %% Support for NANPA *72
              <<"deactivate">> -> cf_deactivate(CF, Call);                 %% Support for NANPA *73
              <<"update">> -> cf_update_number(CF, CaptureGroup, Call);    %% Support for NANPA *56
              <<"toggle">> -> cf_toggle(CF, CaptureGroup, Call);
              <<"menu">> -> cf_menu(CF, CaptureGroup, Call)
          end,
    {'ok', _} = update_callfwd(CF1, Call),
    cf_exe:continue(Call).

%%------------------------------------------------------------------------------
%% @doc This function provides a menu with the call forwarding options
%% @end
%%------------------------------------------------------------------------------
-spec cf_menu(callfwd(), kz_term:api_binary(), kapps_call:call()) -> callfwd().
cf_menu(#callfwd{menu_retries=0}, _CaptureGroup, _Call) ->
    lager:info("menu retries exhausted");
cf_menu(#callfwd{menu_retries=RetriesLeft}=CF, CaptureGroup, Call) ->
    NoopId = play_menu_prompt(Call, CF),

    case collect_menu_option(CF, NoopId, Call) of
        {'ok', 'toggle'} ->
            CF1 = cf_toggle(CF, CaptureGroup, Call),
            cf_menu(CF1, CaptureGroup, Call);
        {'ok', 'update_number'} ->
            CF1 = cf_update_number(CF, CaptureGroup, Call),
            cf_menu(CF1, CaptureGroup, Call);
        {'error', 'retry'} ->
            lager:info("retrying (~p left) menu", [RetriesLeft]),
            cf_menu(CF#callfwd{menu_retries=RetriesLeft-1}, CaptureGroup, Call);
        {'error', _E} ->
            CF
    end.

collect_menu_option(#callfwd{keys=#keys{menu_toggle_cf=Toggle
                                       ,menu_change_number=ChangeNum
                                       }
                            ,interdigit_timeout=Interdigit
                            }
                   ,NoopId
                   ,Call
                   ) ->
    case kapps_call_command:collect_digits(?KEY_LENGTH
                                          ,?CALLFWD_NUMBER_TIMEOUT
                                          ,Interdigit
                                          ,NoopId
                                          ,Call
                                          )
    of
        {'ok', Toggle} -> {'ok', 'toggle'};
        {'ok', ChangeNum} -> {'ok', 'update_number'};
        {'ok', _Key} -> {'error', 'retry'};
        {'error', _E}=Error ->
            lager:info("failed to collect digits: ~p", [_E]),
            Error
    end.

play_menu_prompt(Call, #callfwd{enabled='true'}) ->
    Prompt = kapps_call:get_prompt(Call, <<"cf-enabled_menu">>),
    play_menu_prompt(Call, Prompt);
play_menu_prompt(Call, #callfwd{enabled='false'}) ->
    Prompt = kapps_call:get_prompt(Call, <<"cf-disabled_menu">>),
    play_menu_prompt(Call, Prompt);
play_menu_prompt(Call, Prompt) ->
    _  = kapps_call_command:b_flush(Call),
    lager:info("playing call forwarding menu"),
    kapps_call_command:play(Prompt, Call).

%%------------------------------------------------------------------------------
%% @doc This function will update the call forwarding enabling it if it is
%% not, and disabling it if it is
%% @end
%%------------------------------------------------------------------------------
-spec cf_toggle(callfwd(), kz_term:api_binary(), kapps_call:call()) -> callfwd().
cf_toggle(#callfwd{enabled='true'}=CF, _CaptureGroup, Call) ->
    lager:info("toggling to disabled"),
    cf_deactivate(CF, Call);
cf_toggle(#callfwd{enabled='false', number='undefined'}=CF
         ,CaptureGroup
         ,Call
         ) ->
    lager:info("toggling to active"),
    cf_activate(CF, CaptureGroup, Call);
cf_toggle(#callfwd{enabled='false', number = <<>>}=CF
         ,CaptureGroup
         ,Call
         ) ->
    lager:info("toggling to active"),
    cf_activate(CF, CaptureGroup, Call);
cf_toggle(#callfwd{enabled='false', number = <<Number/binary>>}=CF
         ,_CaptureGroup
         ,Call
         ) ->
    lager:info("toggle to enabled, forward to existing '~s'", [Number]),
    play_forwarded_to(Call, Number),
    set_active(CF).

play_forwarded_to(Call, Number) ->
    NoopId = kapps_call_command:audio_macro([{'prompt', <<"cf-now_forwarded_to">>}
                                            ,{'say', Number}
                                            ]
                                           ,Call
                                           ),
    _ = kapps_call_command:wait_for_noop(Call, NoopId),
    lager:debug("played forwarded to ~s", [Number]).

%%------------------------------------------------------------------------------
%% @doc This function will update the call forwarding object on the owner
%% document to enable call forwarding
%% @end
%%------------------------------------------------------------------------------
-spec cf_activate(callfwd(), kz_term:api_binary(), kapps_call:call()) -> callfwd().
cf_activate(CF, 'undefined', Call) ->
    cf_activate(CF, <<>>, Call);
cf_activate(#callfwd{number='undefined'}=CF0, <<>>, Call) ->
    lager:info("no capture group, no number configured, asking caller for new"),
    CF1 = #callfwd{number=Number} = cf_update_number(CF0, <<>>, Call),
    play_forwarded_to(Call, Number),
    set_active(CF1);
cf_activate(#callfwd{number=_OldNumber}=CF0, <<>>, Call) ->
    lager:info("no capture group, old number '~s' configured, asking caller for new", [_OldNumber]),
    CF1 = #callfwd{number=Number} = cf_update_number(CF0, <<>>, Call),
    play_forwarded_to(Call, Number),
    set_active(CF1);
cf_activate(#callfwd{}=CF, <<CaptureGroup/binary>>, Call) ->
    lager:info("activating call forwarding with captured number '~s'", [CaptureGroup]),
    play_forwarded_to(Call, CaptureGroup),
    set_active(set_number(CF, CaptureGroup)).

-spec set_active(callfwd()) -> callfwd().
set_active(#callfwd{}=CF) -> CF#callfwd{enabled='true'}.

-spec set_deactive(callfwd()) -> callfwd().
set_deactive(#callfwd{}=CF) -> CF#callfwd{enabled='false'}.

-spec set_number(callfwd(), kz_term:api_ne_binary()) -> callfwd().
set_number(#callfwd{}=CF, 'undefined') -> CF;
set_number(#callfwd{}=CF, <<Number/binary>>) -> CF#callfwd{number=Number}.

-spec toggle_active(callfwd()) -> callfwd().
toggle_active(#callfwd{enabled=Enabled}=CF) -> CF#callfwd{enabled=not Enabled}.

%%------------------------------------------------------------------------------
%% @doc This function will update the call forwarding object on the owner
%% document to disable call forwarding
%% @end
%%------------------------------------------------------------------------------
-spec cf_deactivate(callfwd(), kapps_call:call()) -> callfwd().
cf_deactivate(CF, Call) ->
    lager:info("deactivating call forwarding"),
    _ = kapps_call_command:b_prompt(<<"cf-disabled">>, Call),
    set_deactive(CF).

%%------------------------------------------------------------------------------
%% @doc This function will update the call forwarding object on the owner
%% document with a new number
%% @end
%%------------------------------------------------------------------------------
-spec cf_update_number(callfwd(), kz_term:api_binary(), kapps_call:call()) -> callfwd().
cf_update_number(CF, 'undefined', Call) ->
    cf_update_number(CF, <<>>, Call);
cf_update_number(CF, <<>>, Call) ->
    lager:info("no capture group, prompting for new call forward number"),
    Min = ?MIN_CALLFWD_NUMBER_LENGTH,

    case collect_cfwd_number(CF, Call) of
        {'ok', Short} when byte_size(Short) < Min ->
            lager:info("too short of input(~p): '~s'", [Min, Short]),
            cf_update_number(CF, <<>>, Call);
        {'ok', Number} ->
            _ = kapps_call_command:b_prompt(<<"vm-saved">>, Call),
            lager:info("updating call forwarding number with ~s", [Number]),
            set_number(CF, Number);
        {'error', _E} ->
            lager:info("error collecting digits: ~p", [_E]),
            exit('normal')
    end;
cf_update_number(CF, <<CaptureGroup/binary>>, _Call) ->
    lager:info("update call forwarding number with captured '~s'", [CaptureGroup]),
    set_number(CF, CaptureGroup).

collect_cfwd_number(#callfwd{interdigit_timeout=Interdigit}, Call) ->
    NoopId = kapps_call_command:prompt(<<"cf-enter_number">>, Call),
    kapps_call_command:collect_digits(?MAX_CALLFWD_NUMBER_LENGTH
                                     ,?CALLFWD_NUMBER_TIMEOUT
                                     ,Interdigit
                                     ,NoopId
                                     ,Call
                                     ).

%%------------------------------------------------------------------------------
%% @doc This is a helper function to update a document, and corrects the
%% rev tag if the document is in conflict
%% @end
%%------------------------------------------------------------------------------
-spec update_callfwd(callfwd(), kapps_call:call()) ->
          {'ok', kz_json:object()} |
          kz_datamgr:data_error().
update_callfwd(#callfwd{doc_id=Id
                       ,enabled=Enabled
                       ,number=Num
                       }=CF
              ,Call
              ) ->
    lager:info("updating call forwarding settings on ~s / ~s", [kapps_call:account_id(Call), Id]),
    {'ok', Endpoint} = kz_datamgr:open_cache_doc(kapps_call:account_id(Call), Id),

    UpdatedCallForwards = update_call_forward(kzd_endpoint:call_forward(Endpoint), Enabled, Num),
    lager:info("new forwarding options: ~p", [UpdatedCallForwards]),

    case kz_datamgr:save_doc(kapps_call:account_id(Call)
                            ,kzd_endpoint:set_call_forward(Endpoint, UpdatedCallForwards)
                            )
    of
        {'error', 'conflict'} ->
            lager:info("update conflicted, trying again"),
            update_callfwd(CF, Call);
        {'ok', _Saved}=OK ->
            lager:info("updated endpoint ~s (~s) call forwarding"
                      ,[kz_doc:id(_Saved), kz_doc:revision(_Saved)]
                      ),
            OK;
        {'error', _R}=E ->
            lager:info("failed to update call forwarding in db ~w", [_R]),
            E
    end.

-spec update_call_forward(kzd_call_forward_types:doc() | 'undefined', boolean(), kz_term:ne_binary()) ->
          kzd_call_forward_types:doc().
update_call_forward('undefined', Enabled, Number) ->
    update_call_forward(kz_json:new(), Enabled, Number);
update_call_forward(CallForwardTypes, Enabled, Number) ->
    case kzd_call_forward_types:unconditional(CallForwardTypes) of
        'undefined' ->
            lager:info("no unconditional, updating using legacy format"),
            basic_call_forward(Enabled, Number, CallForwardTypes);
        Unconditional ->
            lager:info("updating unconditional call forwarding"),
            kzd_call_forward_types:set_unconditional(CallForwardTypes
                                                    ,basic_call_forward(Enabled, Number, Unconditional)
                                                    )
    end.

basic_call_forward(Enabled, Number, Cfwd) ->
    Updates = [{fun kzd_call_forward:set_enabled/2, Enabled}
              ,{fun kzd_call_forward:set_number/2, Number}
              ],
    kz_doc:setters(Cfwd, Updates).

%%------------------------------------------------------------------------------
%% @doc This function will load the call forwarding record
%% @end
%%------------------------------------------------------------------------------
-spec get_call_forward(kapps_call:call()) ->
          callfwd() |
          {'error', 'not_found'}.
get_call_forward(Call) ->
    maybe_get_call_forward(Call, get_endpoint_id(Call)).

get_endpoint_id(Call) ->
    AuthorizingId = kapps_call:authorizing_id(Call),
    get_endpoint_id(AuthorizingId, kz_attributes:owner_id(AuthorizingId, Call)).

get_endpoint_id('undefined', 'undefined') ->
    lager:info("no authz or owner id to use"),
    'undefined';
get_endpoint_id(AuthzId, 'undefined') ->
    lager:info("using authz id ~s for endpoint", [AuthzId]),
    AuthzId;
get_endpoint_id(_AuthzId, OwnerId) ->
    lager:info("using owner id ~s for endpoint", [OwnerId]),
    OwnerId.

-spec maybe_get_call_forward(kapps_call:call(), kz_term:api_ne_binary()) ->
          callfwd() |
          {'error', 'not_found'}.
maybe_get_call_forward(_Call, 'undefined') ->
    lager:debug("cannot get endpoint from call"),
    {'error', 'not_found'};
maybe_get_call_forward(Call, EndpointId) ->
    case kz_datamgr:open_cache_doc(kapps_call:account_id(Call), EndpointId) of
        {'ok', EndpointJObj} ->
            endpoint_to_callfwd(EndpointJObj);
        {'error', R} ->
            lager:info("failed to load endpoint ~s: ~p", [EndpointId, R]),
            {'error', 'not_found'}
    end.

endpoint_to_callfwd(EndpointJObj) ->
    lager:info("loaded endpoint ~s for call forwarding", [kz_doc:id(EndpointJObj)]),
    CallForwardTypes = kzd_endpoint:call_forward(EndpointJObj),
    lager:info("call forward settings: ~p", [CallForwardTypes]),

    maybe_legacy_callfwd(kz_doc:id(EndpointJObj), CallForwardTypes).

maybe_legacy_callfwd(DocId, 'undefined') ->
    lager:info("no call forwarding setup yet"),

    legacy_callfwd(DocId, kz_json:new());
maybe_legacy_callfwd(DocId, CallForwardTypes) ->
    case kzd_call_forward_types:unconditional(CallForwardTypes) of
        'undefined' ->
            lager:info("no unconditional call forwarding configured, loading from legacy settings"),
            legacy_callfwd(DocId, CallForwardTypes);
        %% if enabled is unset, not legacy
        Unconditional ->
            lager:info("loading from unconditional settings"),
            legacy_callfwd(DocId, Unconditional)
    end.

legacy_callfwd(DocId, CallForward) ->
    Defaults = kzd_call_forward:new(),

    #callfwd{doc_id = DocId
            ,enabled = kzd_call_forward:enabled(CallForward, kzd_call_forward:enabled(Defaults))
            ,number = kzd_call_forward:number(CallForward, kzd_call_forward:number(Defaults, 'undefined'))
            ,require_keypress = kzd_call_forward:require_keypress(CallForward, kzd_call_forward:require_keypress(Defaults, 'true'))
            ,keep_caller_id = kzd_call_forward:keep_caller_id(CallForward, kzd_call_forward:keep_caller_id(Defaults, 'true'))
            }.
