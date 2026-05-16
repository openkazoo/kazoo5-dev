%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2018-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_doc_generator).

-export([create_all/2, create_all/3
        ,create/3, create/4
        ,generators/0
        ]).

-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kz_types.hrl").

-elvis([{elvis_style, no_debug_call, disable}]).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec create_all(AccountId::kz_term:ne_binary(), DbName::kz_term:ne_binary()) -> kz_json:objects().
create_all(AccountId, Db) ->
    create_all(AccountId, Db, []).

-spec create_all(AccountId::kz_term:ne_binary(), DbName::kz_term:ne_binary(), Options::kz_term:proplist()) -> kz_json:objects().
create_all(AccountId, Db, Options) ->
    [create(Type, AccountId, Db, Options, Generator)
     || {Type, Generator} <- lists:usort(maps:to_list(generators()))
    ].

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec create(Type::kz_term:ne_binary() | 'all', AccountId::kz_term:ne_binary(), DbName::kz_term:ne_binary()) -> kz_json:object().
create(Type, AccountId, Db) ->
    create(Type, AccountId, Db, []).

-spec create(Type::kz_term:ne_binary() | 'all', AccountId::kz_term:ne_binary(), DbName::kz_term:ne_binary(), Options::kz_term:proplist()) -> kz_json:object().
create('all', AccountId, Db, Options) ->
    create_all(AccountId, Db, Options);
create(Type, AccountId, Db, Options) ->
    create(Type, AccountId, Db, Options, maps:get(Type, generators())).

create(Type, AccountId, Db, Options, #{'fun' := Fun}=Generator) ->
    maybe_log(Options, "creating '~s'", [Type]),
    JObj = Fun(AccountId, Db, Options),
    case props:is_true('validate_doc', Options, 'false') of
        'true' ->
            validate_doc(JObj, Type, Options, maps:get('schema', Generator, 'undefined'));
        'false' ->
            JObj
    end.

validate_doc(JObj, _, _, 'undefined') ->
    JObj;
validate_doc(JObj, Type, Options, <<Schema/binary>>) ->
    case kz_json_schema:fload(Schema) of
        {'ok', SchemaJObj} ->
            validate_doc_with_schema(JObj, Type, Options, SchemaJObj);
        {'error', _Error} ->
            maybe_log(Options, "unable to find '~s' schema '~s': ~p~n", [Type, Schema, _Error]),
            JObj
    end.

validate_doc_with_schema(JObj, Type, Options, SchemaJObj) ->
    case kz_json_schema:validate(SchemaJObj, kz_doc:public_fields(JObj)) of
        {'ok', _} -> JObj;
        {'error', Errors} ->
            handle_schema_errors(JObj, Type, Options, Errors)
    end.

handle_schema_errors(JObj, Type, Options, Errors) ->
    case props:is_true('stop_on_error', Options, 'false') of
        'true' ->
            maybe_log(Options, "JObj~n~p~n", [JObj]),
            throw({'error', Errors});
        'false' ->
            maybe_log(Options, "~n'~s' validation failed:~nJObj:~n~p~nErrors:~n~100p~n"
                     ,[Type, JObj, Errors]
                     ),
            JObj
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec generators() -> map().
generators() ->
    #{<<"account">> =>
          #{'fun' => fun create_account/3
           ,'schema' => <<"accounts">>
           }
     ,<<"app">> =>
          #{'fun' => fun create_app/3
           ,'schema' => <<"app">>
           }
     ,<<"blacklist">> =>
          #{'fun' => fun create_blacklist/3
           ,'schema' => <<"blacklists">>
           }
     ,<<"callflow_contact_id">> =>
          #{'fun' => fun create_callflow_contact_id/3
           ,'schema' => <<"callflows">>
           }
     ,<<"callflow_device">> =>
          #{'fun' => fun create_callflow_device/3
           ,'schema' => <<"callflows">>
           }
     ,<<"callflow_featurecode">> =>
          #{'fun' => fun create_callflow_featurecode/3
           ,'schema' => <<"callflows">>
           }
     ,<<"callflow_featurecode_no_action">> =>
          #{'fun' => fun create_callflow_featurecode_no_action/3
           ,'schema' => <<"callflows">>
           }
     ,<<"callflow_number">> =>
          #{'fun' => fun create_callflow_number/3
           ,'schema' => <<"callflows">>
           }
     ,<<"callflow_pattern">> =>
          #{'fun' => fun create_callflow_pattern/3
           ,'schema' => <<"callflows">>
           }
     ,<<"callflow_simple">> =>
          #{'fun' => fun create_callflow_simple/3
           ,'schema' => <<"callflows">>
           }
     ,<<"callflow_tts">> =>
          #{'fun' => fun create_callflow_tts/3
           ,'schema' => <<"callflows">>
           }
     ,<<"callflow_user">> =>
          #{'fun' => fun create_callflow_user/3
           ,'schema' => <<"callflows">>
           }
     ,<<"callflow_user_vmbox">> =>
          #{'fun' => fun create_callflow_user_vmbox/3
           ,'schema' => <<"callflows">>
           }
     ,<<"click2call">> =>
          #{'fun' => fun create_click2call/3
           ,'schema' => <<"clicktocall">>
           }
     ,<<"conference">> =>
          #{'fun' => fun create_conference/3
           ,'schema' => <<"conferences">>
           }
     ,<<"conference_number">> =>
          #{'fun' => fun create_conference_number/3
           ,'schema' => <<"conferences">>
           }
     ,<<"contact_list_excluded_user">> =>
          #{'fun' => fun create_contact_list_excluded_user/3
           ,'schema' => <<"user">>
           }
     ,<<"contact_list_excluded_device">> =>
          #{'fun' => fun create_contact_list_excluded_device/3
           ,'schema' => <<"user">>
           }
     ,<<"device">> =>
          #{'fun' => fun create_device/3
           ,'schema' => <<"devices">>
           }
     ,<<"device_simple">> =>
          #{'fun' => fun create_device_simple/3
           ,'schema' => <<"devices">>
           }
     ,<<"directory">> =>
          #{'fun' => fun create_directory/3
           ,'schema' => <<"devices">>
           }
     ,<<"directory_owner">> =>
          #{'fun' => fun create_directory_owner/3
           ,'schema' => <<"users">>
           }
     ,<<"faxbox">> =>
          #{'fun' => fun create_faxbox/3
           ,'schema' => <<"faxbox">>
           }
     ,<<"faxbox_email_permissions">> =>
          #{'fun' => fun create_faxbox_email_permissions/3
           ,'schema' => <<"faxbox">>
           }
     ,<<"faxbox_owner">> =>
          #{'fun' => fun create_faxbox_owner/3
           ,'schema' => <<"faxbox">>
           }
     ,<<"group">> =>
          #{'fun' => fun create_group/3
           ,'schema' => <<"groups">>
           }
     ,<<"hotdesked_device">> =>
          #{'fun' => fun create_hotdesked_device/3
           ,'schema' => <<"devices">>
           }
     ,<<"hotdesking_user">> =>
          #{'fun' => fun create_hotdesking_user/3
           ,'schema' => <<"users">>
           }
     ,<<"list">> =>
          #{'fun' => fun create_list/3
           ,'schema' => <<"lists">>
           }
     ,<<"list_entry">> =>
          #{'fun' => fun create_list_entry/3
           ,'schema' => <<"list_entries">>
           }
     ,<<"list_entry_number">> =>
          #{'fun' => fun create_list_entry_number/3
           ,'schema' => <<"list_entries">>
           }
     ,<<"list_entry_pattern">> =>
          #{'fun' => fun create_list_entry_pattern/3
           ,'schema' => <<"list_entries">>
           }
     ,<<"list_entry_prefix">> =>
          #{'fun' => fun create_list_entry_prefix/3
           ,'schema' => <<"list_entries">>
           }
     ,<<"list_entry_regexp">> =>
          #{'fun' => fun create_list_entry_regexp/3
           ,'schema' => <<"list_entries">>
           }
     ,<<"menu">> =>
          #{'fun' => fun create_menu/3
           ,'schema' => <<"menus">>
           }
     ,<<"message_number">> =>
          #{'fun' => fun create_message_number/3
           ,'schema' => <<"callflows">>
           }
     ,<<"message_pattern">> =>
          #{'fun' => fun create_message_pattern/3
           ,'schema' => <<"callflows">>
           }
     ,<<"metaflow_device">> =>
          #{'fun' => fun create_metaflow_device/3
           ,'schema' => <<"devices">>
           }
     ,<<"metaflow_user">> =>
          #{'fun' => fun create_metaflow_user/3
           ,'schema' => <<"users">>
           }
     ,<<"mobile">> =>
          #{'fun' => fun create_mobile/3
           ,'schema' => <<"devices">>
           }
     ,<<"multi_factor_provider">> =>
          #{'fun' => fun create_multi_factor_provider/3
           ,'schema' => <<"multi_factor_provider">>
           }
     ,<<"notification">> =>
          #{'fun' => fun create_notification/3
           ,'schema' => <<"notifications">>
           }
     ,<<"number">> =>
          #{'fun' => fun create_number/3
           ,'schema' => <<"phone_numbers">>
           }
     ,<<"parked_call">> =>
          #{'fun' => fun create_parked_call/3
           ,'schema' => 'undefined'
           }
     ,<<"parked_call_call_id">> =>
          #{'fun' => fun create_parked_call_call_id/3
           ,'schema' => 'undefined'
           }
     ,<<"parked_call_no_slot">> =>
          #{'fun' => fun create_parked_call_no_slot/3
           ,'schema' => 'undefined'
           }
     ,<<"rate_limits_account">> =>
          #{'fun' => fun create_rate_limits_account/3
           ,'schema' => <<"account_rate_limits">>
           }
     ,<<"rate_limits_device">> =>
          #{'fun' => fun create_rate_limits_device/3
           ,'schema' => <<"device_rate_limits">>
           }
     ,<<"resource">> =>
          #{'fun' => fun create_resource/3
           ,'schema' => <<"resources">>
           }
     ,<<"resource_template">> =>
          #{'fun' => fun create_resource_template/3
           ,'schema' => <<"resources">>
           }
     ,<<"service_plan">> =>
          #{'fun' => fun create_service_plan/3
           ,'schema' => 'undefined'
           }
     ,<<"temporal_rule">> =>
          #{'fun' => fun create_temporal_rule/3
           ,'schema' => <<"temporal_rules">>
           }
     ,<<"temporal_rule_set">> =>
          #{'fun' => fun create_temporal_rule_set/3
           ,'schema' => <<"temporal_rules_sets">>
           }
     ,<<"trunkstore">> =>
          #{'fun' => fun create_trunkstore/3
           ,'schema' => <<"connectivity">>
           }
     ,<<"user">> =>
          #{'fun' => fun create_user/3
           ,'schema' => <<"users">>
           }
     ,<<"user_bare">> =>
          #{'fun' => fun create_user_bare/3
           ,'schema' => <<"users">>
           }
     ,<<"user_simple">> =>
          #{'fun' => fun create_user_simple/3
           ,'schema' => <<"users">>
           }
     ,<<"vmbox">> =>
          #{'fun' => fun create_vmbox/3
           ,'schema' => <<"vmboxes">>
           }
     }.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
create_account(AccountId, Db, Options) ->
    Metaflow = create_metaflow(AccountId, Db, Options),
    kz_doc:setters(kzd_accounts:new()
                  ,[{fun kzd_accounts:set_language/2, <<"en-US">>}
                   ,{fun kzd_accounts:set_name/2, kz_binary:rand_hex(6)}
                   ,{fun kzd_accounts:set_timezone/2, <<"America/Los_Angeles">>}
                   ,{fun kzd_accounts:set_realm/2, kz_binary:rand_hex(6)}
                   ,{fun set_metaflows/2, Metaflow}
                   ,{fun kz_doc:set_id/2, AccountId}
                   ,{fun kz_doc:set_account_id/2, AccountId}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, kzd_accounts:type()}
                   ]).

set_metaflows(JObj, Metaflows) -> kz_json:set_value(<<"metaflows">>, Metaflows, JObj).

create_app(_AccountId, Db, _Options) ->
    I18n = kz_json:from_list(
             [{<<"label">>, kz_binary:rand_hex(5)}
             ,{<<"description">>, kz_binary:rand_hex(5)}
             ,{<<"features">>, [kz_binary:rand_hex(6)]}
             ]),
    kz_doc:setters(kzd_app:new()
                  ,[{fun kzd_app:set_i18n/2, kz_json:from_list([{<<"en-US">>, I18n}])}
                   ,{fun kzd_app:set_tags/2, [kz_binary:rand_hex(3)]}
                   ,{fun kzd_app:set_icon/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_app:set_author/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_app:set_version/2, <<"1.0">>}
                   ,{fun kzd_app:set_license/2, <<"-">>}
                   ,{fun kzd_app:set_screenshots/2, [kz_binary:rand_hex(4)]}
                   ,{fun kzd_app:set_name/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_app:set_api_url/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_app:set_price/2, 0}
                   ,{fun kzd_app:set_phase/2, hd(kz_term:shuffle_list([<<"alpha">>,<<"beta">>,<<"gold">>]))}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"app">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_blacklist(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_blacklists:new()
                  ,[{fun kzd_blacklists:set_name/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_blacklists:set_should_block_anonymous/2, 'true'}
                   ,{fun kzd_blacklists:set_numbers/2, kz_json:from_list([{random_us_did_e164(), kz_json:new()}
                                                                         ,{random_us_did_e164(), kz_json:new()}
                                                                         ])
                    }
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"blacklist">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_callflow_simple(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_callflows:new()
                  ,[{fun kzd_callflows:set_name/2, kz_binary:rand_hex(5)}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"callflow">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]
                  ).

create_callflow_contact_id(AccountId, Db, Options) ->
    Module = hd(kz_term:shuffle_list(
                  [<<"menu">>, <<"conference">>, <<"directory">>
                  ,<<"receive_fax">>, <<"voicemail">>
                  ])),
    kz_doc:setters(create_callflow_simple(AccountId, Db, Options)
                  ,[{fun kzd_callflows:set_flow/2
                    ,kz_json:from_list_recursive(
                       [{<<"children">>, kz_json:new()}
                       ,{<<"data">>, callflow_module_data(Module)}
                       ,{<<"module">>, Module}
                       ])
                    }
                   ,{fun kzd_callflows:set_numbers/2, [rand_num_string(7000, 9000)]}
                   ]).

create_callflow_device(AccountId, Db, Options) ->
    kz_doc:setters(create_callflow_simple(AccountId, Db, Options)
                  ,[{fun kzd_callflows:set_flow/2
                    ,kz_json:from_list_recursive(
                       [{<<"children">>, kz_json:new()}
                       ,{<<"data">>, [{<<"id">>, kz_binary:rand_hex(16)}]}
                       ,{<<"module">>, <<"device">>}
                       ])
                    }
                   ,{fun kzd_callflows:set_numbers/2, [random_us_did_e164(), rand_num_string(300, 7000)]}
                   ]).

create_callflow_featurecode(AccountId, Db, Options) ->
    Module = hd(kz_term:shuffle_list(
                  [<<"call_forward">>, <<"disa">>
                  ,<<"do_not_disturb">>, <<"dynamic_cid">>
                  ,<<"hotdesk">>, <<"intercom">>
                  ,<<"manual_presence">>, <<"park">>
                  ,<<"privacy">>, <<"record_call">>
                  ,<<"voicemail">>
                  ])),
    kz_doc:setters(create_callflow_pattern(AccountId, Db, Options)
                  ,[{fun kzd_callflows:set_flow/2
                    ,kz_json:from_list_recursive(
                       [{<<"children">>, kz_json:new()}
                       ,{<<"data">>, callflow_module_data(Module)}
                       ,{<<"module">>, Module}

                        %% non featruecode modules
                       ,{<<"menu">>, <<"conference">>}
                       ,{<<"directory">>, <<"receive_fax">>}
                       ])
                    }
                   ,{fun kzd_callflows:set_featurecode_name/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_callflows:set_featurecode_number/2, rand_num_string(10, 80)}
                   ]).

callflow_module_data(<<"call_forward">>) ->
    [{<<"action">>, hd(kz_term:shuffle_list(
                         [<<"activate">>, <<"deactivate">>
                         ,<<"update">>, <<"toggle">>, <<"menu">>
                         ])
                      )
     }
    ];
callflow_module_data(<<"conference">>) ->
    [{<<"id">>, kz_binary:rand_hex(16)}];
callflow_module_data(<<"directory">>) ->
    [{<<"id">>, kz_binary:rand_hex(16)}];
callflow_module_data(<<"disa">>) ->
    kz_json:new();
callflow_module_data(<<"do_not_disturb">>) ->
    [{<<"action">>, hd(kz_term:shuffle_list(
                         [<<"activate">>, <<"deactivate">>, <<"toggle">>]
                        ))
     }
    ,{<<"id">>, kz_binary:rand_hex(16)}
    ];
callflow_module_data(<<"dynamic_cid">>) ->
    [{<<"action">>, hd(kz_term:shuffle_list(
                         [<<"list">>, <<"lists">>
                         ,<<"manual">>, <<"static">>
                         ]
                        ))
     }
    ,{<<"id">>, kz_binary:rand_hex(16)}
    ];
callflow_module_data(<<"hotdesk">>) ->
    [{<<"action">>, hd(kz_term:shuffle_list(
                         [<<"login">>, <<"logout">>
                         ,<<"toggle">>, <<"bridge">>
                         ]
                        ))
     }
    ,{<<"id">>, kz_binary:rand_hex(16)}
    ];
callflow_module_data(<<"intercom">>) ->
    kz_json:new();
callflow_module_data(<<"manual_presence">>) ->
    [{<<"presence_id">>, kz_binary:rand_hex(16)}];
callflow_module_data(<<"menu">>) ->
    [{<<"id">>, kz_binary:rand_hex(16)}];
callflow_module_data(<<"park">>) ->
    [{<<"action">>, hd(kz_term:shuffle_list(
                         [<<"direct_park">>, <<"park">>
                         ,<<"auto">>, <<"retrieve">>
                         ]
                        ))
     }
    ];
callflow_module_data(<<"privacy">>) ->
    kz_json:new();
callflow_module_data(<<"receive_fax">>) ->
    [{<<"owner_id">>, kz_binary:rand_hex(16)}];
callflow_module_data(<<"record_call">>) ->
    [{<<"action">>, hd(kz_term:shuffle_list(
                         [<<"start">>
                         ,<<"stop">>
                         ]
                        ))
     }
    ];
callflow_module_data(<<"tts">>) ->
    [{<<"text">>, kz_binary:rand_hex(16)}];
callflow_module_data(<<"voicemail">>) ->
    [{<<"id">>, kz_binary:rand_hex(16)}
    ,{<<"action">>, hd(kz_term:shuffle_list([<<"compose">>, <<"check">>]))}
    ];
callflow_module_data(<<"user">>) ->
    [{<<"id">>, kz_binary:rand_hex(16)}].

create_callflow_featurecode_no_action(AccountId, Db, Options) ->
    kz_doc:setters(create_callflow_pattern(AccountId, Db, Options)
                  ,[{fun kzd_callflows:set_flow/2
                    ,kz_json:from_list_recursive(
                       [{<<"children">>, kz_json:new()}
                       ,{<<"data">>, kz_json:new()}
                       ,{<<"module">>, <<"call_forward">>}
                       ])
                    }
                   ,{fun kzd_callflows:set_featurecode_name/2, <<"call_forward[action=toggle]">>}
                   ,{fun kzd_callflows:set_featurecode_number/2, <<"74">>}
                   ]).

create_callflow_number(AccountId, Db, Options) ->
    kz_doc:setters(create_callflow_simple(AccountId, Db, Options)
                  ,[{fun kzd_callflows:set_numbers/2, [rand_num_string(100, 8000)]}
                   ]).

create_callflow_pattern(AccountId, Db, Options) ->
    kz_doc:setters(create_callflow_simple(AccountId, Db, Options)
                  ,[{fun kzd_callflows:set_patterns/2, [kz_binary:rand_hex(6)]}
                   ]).

create_callflow_tts(AccountId, Db, Options) ->
    kz_doc:setters(create_callflow_number(AccountId, Db, Options)
                  ,[{fun kzd_callflows:set_flow/2
                    ,kz_json:from_list_recursive(
                       [{<<"children">>, kz_json:new()}
                       ,{<<"data">>, callflow_module_data(<<"tts">>)}
                       ,{<<"module">>, <<"tts">>}
                       ])
                    }
                   ,{fun kzd_callflows:set_numbers/2, [rand_num_string(7000, 9000)]}
                   ,{fun delete_name/2, 'undefined'}
                   ]).

delete_name(JObj, _V) -> kz_json:delete_key(<<"name">>, JObj).

create_callflow_user(AccountId, Db, Options) ->
    kz_doc:setters(create_callflow_simple(AccountId, Db, Options)
                  ,[{fun kzd_callflows:set_flow/2
                    ,kz_json:from_list_recursive(
                       [{<<"children">>, kz_json:new()}
                       ,{<<"data">>, callflow_module_data(<<"user">>)}
                       ,{<<"module">>, <<"user">>}
                       ])
                    }
                   ,{fun kzd_callflows:set_numbers/2, [random_us_did_e164(), rand_num_string(300, 7000)]}
                   ]).

create_callflow_user_vmbox(AccountId, Db, Options) ->
    kz_doc:setters(create_callflow_number(AccountId, Db, Options)
                  ,[{fun kzd_callflows:set_flow/2
                    ,kz_json:from_list_recursive(
                       [{<<"children">>, [{<<"_">>, [{<<"children">>, kz_json:new()}
                                                    ,{<<"data">>, callflow_module_data(<<"voicemail">>)}
                                                    ,{<<"module">>, <<"voicemail">>}
                                                    ]
                                          }
                                         ]
                        }
                       ,{<<"data">>, callflow_module_data(<<"user">>)}
                       ,{<<"module">>, <<"user">>}
                       ])
                    }
                   ,{fun kzd_callflows:set_numbers/2, [rand_num_string(7000, 9000)]}
                   ]).

create_click2call(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_clicktocall:new()
                  ,[{fun kzd_clicktocall:set_name/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_clicktocall:set_extension/2, <<"2600">>}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kzd_clicktocall:set_caller_id_number/2, random_us_did_e164()}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"click2call">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_conference(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_conferences:new()
                  ,[{fun kzd_conferences:set_name/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_conferences:set_owner_id/2, kz_binary:rand_hex(16)}
                   ,{fun kzd_conferences:set_max_participants/2, 20}
                   ,{fun kzd_conferences:set_member_pins/2, [rand_num_string(1000, 5000)]}
                   ,{fun kzd_conferences:set_moderator_pins/2, [rand_num_string(1000, 5000)]}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"conference">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]
                  ).

create_conference_number(AccountId, Db, Options) ->
    kz_doc:setters(create_conference(AccountId, Db, Options)
                  ,[{fun kzd_conferences:set_conference_numbers/2, [rand_num_string(4000, 7000)]}
                   ,{fun kzd_conferences:set_member_numbers/2, [random_us_did()]}
                   ,{fun kzd_conferences:set_moderator_numbers/2, [random_us_did()]}
                   ]
                  ).

create_contact_list_excluded_user(AccountId, Db, Options) ->
    kz_json:set_value([<<"contact_list">>, <<"excluded">>], 'true', create_user_simple(AccountId, Db, Options)).

create_contact_list_excluded_device(AccountId, Db, Options) ->
    kz_json:set_value([<<"contact_list">>, <<"excluded">>], 'true', create_device_simple(AccountId, Db, Options)).

create_device_simple(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_devices:new()
                  ,[{fun kzd_devices:set_name/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_devices:set_mac_address/2, rand_num_string(100000000000, 999999999999)}
                   ,{fun kzd_devices:set_sip_password/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_devices:set_sip_username/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_devices:set_sip_expire_seconds/2, 300}
                   ,{fun kzd_devices:set_sip_invite_format/2, <<"contact">>}
                   ,{fun kzd_devices:set_sip_method/2, <<"password">>}
                   ,{fun kz_doc:set_type/2, <<"device">>}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_device(AccountId, Db, Options) ->
    Combos = kz_json:from_list(
               [{<<"0">>, kz_json:from_list([{<<"type">>, <<"line">>}])}
               ,{<<"1">>, kz_json:from_list(
                            [{<<"type">>, <<"presence">>}
                            ,{<<"value">>, kz_binary:rand_hex(16)}
                            ])
                }
               ,{<<"2">>, kz_json:from_list(
                            [{<<"type">>, <<"presence">>}
                            ,{<<"value">>, kz_json:from_list(
                                             [{<<"label">>, <<"FunnyUser">>}
                                             ,{<<"value">>, kz_binary:rand_hex(16)}
                                             ])
                             }
                            ])
                }
               ,{<<"3">>, kz_json:from_list(
                            [{<<"type">>, <<"personal_parking">>}
                            ,{<<"value">>, kz_binary:rand_hex(16)}
                            ])
                }
                %% FIXME: how to make validation accept null??
                %% ,{<<"4">>, null}
                %% ,{<<"5">>, null}
               ]),
    kz_doc:setters(create_device_simple(AccountId, Db, Options)
                  ,[{fun kzd_devices:set_presence_id/2, kz_binary:rand_hex(6)}
                   ,{fun kzd_devices:set_owner_id/2, kz_binary:rand_hex(16)}
                   ,{fun kzd_devices:set_provision_combo_keys/2, Combos}
                   ,{fun kzd_devices:set_provision_feature_keys/2, Combos}
                   ]).

create_directory(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_directories:new()
                  ,[{fun kzd_directories:set_name/2, kz_binary:rand_hex(5)}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"directory">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_directory_owner(AccountId, Db, Options) ->
    kz_doc:setters(create_user(AccountId, Db, Options)
                  ,[{fun kzd_users:set_directories/2
                    ,kz_json:from_list([{kz_binary:rand_hex(16), kz_binary:rand_hex(16)} %% callflow
                                       ,{kz_binary:rand_hex(16), kz_binary:rand_hex(16)} %% callflow
                                       ])
                    }
                   ]).

create_faxbox(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_faxbox:new()
                  ,[{fun kzd_faxbox:set_caller_name/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_faxbox:set_caller_id/2, random_us_did_e164()}
                   ,{fun kzd_faxbox:set_fax_identity/2, random_us_did_e164()}
                   ,{fun kzd_faxbox:set_name/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_faxbox:set_retries/2, 3}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"faxbox">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_faxbox_owner(AccountId, Db, Options) ->
    kz_doc:setters(create_faxbox(AccountId, Db, Options)
                  ,[{fun kzd_devices:set_owner_id/2, kz_binary:rand_hex(16)}
                   ]).

create_faxbox_email_permissions(AccountId, Db, Options) ->
    kz_doc:setters(create_faxbox(AccountId, Db, Options)
                  ,[{fun kzd_faxbox:set_smtp_permission_list/2, [kz_binary:rand_hex(5) || _ <- lists:seq(1,5)]}
                   ]).

create_group(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_groups:new()
                  ,[{fun kzd_groups:set_name/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_groups:set_endpoints/2
                    ,kz_json:from_list_recursive(
                       [{kz_binary:rand_hex(16), [{<<"type">>, <<"user">>}]}
                       ,{kz_binary:rand_hex(16), [{<<"type">>, <<"user">>}]}
                       ,{kz_binary:rand_hex(16), [{<<"type">>, <<"device">>}]}
                       ])
                    }
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"group">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]
                  ).

create_hotdesking_user(AccountId, Db, Options) ->
    kz_doc:setters(create_user_simple(AccountId, Db, Options)
                  ,[{fun kzd_users:set_hotdesk_id/2, kz_term:to_binary(uniform_int(6000, 7000))}
                   ,{fun kzd_users:set_hotdesk_enabled/2, 'false'}
                   ,{fun kzd_users:set_hotdesk_pin/2, kz_term:to_binary(uniform_int(6000, 8000))}
                   ,{fun kzd_users:set_hotdesk_require_pin/2, 'true'}
                   ]
                  ).

create_hotdesked_device(AccountId, Db, Options) ->
    Hotdesk = kz_json:from_list(
                [{<<"users">>, kz_json:from_list(
                                 [{kz_binary:rand_hex(16), kz_json:new()}
                                 ,{kz_binary:rand_hex(16), kz_json:new()}
                                 ])
                 }
                ]
               ),
    kz_doc:setters(create_device_simple(AccountId, Db, Options)
                  ,[{fun kzd_devices:set_hotdesk/2, Hotdesk}]
                  ).

create_list(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_lists:new()
                  ,[{fun kzd_lists:set_name/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_lists:set_description/2, kz_binary:rand_hex(5)}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"list">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_list_entry(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_list_entries:new()
                  ,[{fun kzd_list_entries:set_capture_group_key/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_list_entries:set_capture_group_length/2, uniform_int(0, 5)}
                   ,{fun kzd_list_entries:set_firstname/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_list_entries:set_list_id/2, kz_binary:rand_hex(16)}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"list_entry">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_list_entry_number(AccountId, Db, Options) ->
    kz_json:set_value(<<"number">>, random_us_did_e164(), create_list_entry(AccountId, Db, Options)).

create_list_entry_prefix(AccountId, Db, Options) ->
    kz_json:set_value(<<"prefix">>, uniform_int(300, 700), create_list_entry(AccountId, Db, Options)).

create_list_entry_regexp(AccountId, Db, Options) ->
    kz_json:set_value(<<"regexp">>, kz_binary:rand_hex(4), create_list_entry(AccountId, Db, Options)).

create_list_entry_pattern(AccountId, Db, Options) ->
    kz_json:set_value(<<"pattern">>, kz_binary:rand_hex(4), create_list_entry(AccountId, Db, Options)).

create_menu(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_menus:new()
                  ,[{fun kzd_menus:set_name/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_menus:set_flags/2, []}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"menu">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_message_number(AccountId, Db, Options) ->
    kz_doc:set_type(create_callflow_number(AccountId, Db, Options), <<"textflow">>).

create_message_pattern(AccountId, Db, Options) ->
    kz_doc:set_type(create_callflow_pattern(AccountId, Db, Options), <<"textflow">>).

create_metaflow_device(AccountId, Db, Options) ->
    kz_json:set_value(<<"metaflows">>
                     ,create_metaflow(AccountId, Db, Options)
                     ,create_device_simple(AccountId, Db, Options)
                     ).

create_metaflow_user(AccountId, Db, Options) ->
    kz_json:set_value(<<"metaflows">>
                     ,create_metaflow(AccountId, Db, Options)
                     ,create_user_simple(AccountId, Db, Options)
                     ).

%% to be used by other generators only
create_metaflow(_AccountId, _Db, _Options) ->
    Module = hd(kz_term:shuffle_list(
                  [<<"audio_level">>
                  ,<<"break">>
                  ,<<"callflow">>
                  ,<<"hangup">>
                  ,<<"hold_control">>
                  ,<<"hold">>
                  ,<<"intercept">>
                  ,<<"move">>
                  ,<<"pivot">>
                  ,<<"play">>
                  ,<<"record_call">>
                  ,<<"relate">>
                  ,<<"resume">>
                  ,<<"say">>
                  ,<<"sound_touch">>
                  ,<<"transfer">>
                  ,<<"tts">>
                  ])),
    kz_doc:setters(kz_json:new()
                  ,[{fun kzd_metaflows:set_patterns/2
                    ,kz_json:from_list_recursive(
                       [{kz_binary:rand_hex(2), [{<<"data">>, metaflow_data(Module)}
                                                ,{<<"module">>, Module}
                                                ]
                        }
                       ])
                    }
                   ]).

metaflow_data(<<"audio_level">>) -> kz_json:new();
metaflow_data(<<"break">>) -> kz_json:new();
metaflow_data(<<"callflow">>) -> kz_json:new();
metaflow_data(<<"hangup">>) -> kz_json:new();
metaflow_data(<<"hold_control">>) -> kz_json:new();
metaflow_data(<<"hold">>) -> kz_json:new();
metaflow_data(<<"intercept">>) -> kz_json:new();
metaflow_data(<<"move">>) -> kz_json:new();
metaflow_data(<<"pivot">>) -> [{<<"voice_url">>, <<"https://", (kz_binary:rand_hex(4))/binary>>}];
metaflow_data(<<"play">>) -> kz_json:new();
metaflow_data(<<"record_call">>) -> kz_json:new();
metaflow_data(<<"relate">>) ->
    [{<<"participant_id">>, kz_binary:rand_hex(4)}
    ,{<<"other_participant">>, kz_binary:rand_hex(4)}
    ,{<<"conference_id">>, kz_binary:rand_hex(16)}
    ];
metaflow_data(<<"resume">>) -> kz_json:new();
metaflow_data(<<"say">>) -> kz_json:new();
metaflow_data(<<"sound_touch">>) -> kz_json:new();
metaflow_data(<<"transfer">>) -> kz_json:new();
metaflow_data(<<"tts">>) -> kz_json:new().

create_mobile(AccountId, Db, Options) ->
    kz_doc:setters(create_device_simple(AccountId, Db, Options)
                  ,[{fun kzd_devices:set_name/2, <<"mobile ", (kz_binary:rand_hex(4))/binary>>}
                   ,{fun kzd_devices:set_device_type/2, <<"mobile">>}
                   ,{fun set_mobile_id/2, kz_binary:rand_hex(6)}
                   ,{fun set_mobile_mdn/2, random_us_did_e164()}
                   ]).

create_notification(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_notifications:new()
                  ,[{fun kzd_notifications:set_friendly_name/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_notifications:set_category/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_notifications:set_from/2, rand_email()}
                   ,{fun kzd_notifications:set_subject/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_notifications:set_to/2, kz_json:from_list(
                                                       [{<<"email_addresses">>, [rand_email()]}
                                                       ,{<<"type">>, hd(kz_term:shuffle_list(
                                                                          [<<"original">>, <<"specified">>, <<"admins">>]
                                                                         )
                                                                       )
                                                        }
                                                       ])
                    }
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"notification">>}
                   ,{fun kz_doc:set_id/2, <<"notification.", (kz_binary:rand_hex(5))/binary>>}
                   ]).

set_mobile_id(JObj, Id) -> kz_json:set_value([<<"mobile">>, <<"id">>], Id, JObj).
set_mobile_mdn(JObj, MDN) -> kz_json:set_value([<<"mobile">>, <<"mdn">>], MDN, JObj).

create_parked_call_no_slot(_AccountId, Db, _Options) ->
    kz_doc:setters(kz_json:new()
                  ,[{fun set_slot/2, kz_json:new()}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"parked_call">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

set_slot(JObj, Slot) -> kz_json:set_value(<<"slot">>, Slot, JObj).

create_parked_call(AccountId, Db, Options) ->
    Slot = kz_json:from_list(
             [{<<"Attended">>, kz_binary:rand_hex(6)}
             ,{<<"Slot-Call-ID">>, kz_binary:rand_hex(6)}
             ,{<<"Switch-URI">>, kz_binary:rand_hex(6)}
             ,{<<"From-Tag">>, kz_binary:rand_hex(6)}
             ,{<<"To-Tag">>, kz_binary:rand_hex(6)}
             ,{<<"Parker-Call-ID">>, kz_binary:rand_hex(6)}
             ,{<<"Ringback-ID">>, kz_binary:rand_hex(6)}
             ,{<<"Presence-User">>, kz_binary:rand_hex(6)}
             ,{<<"Presence-Realm">>, kz_binary:rand_hex(6)}
             ,{<<"Presence-ID">>, <<(kz_binary:rand_hex(6))/binary, "@", (kz_binary:rand_hex(6))/binary>>}
             ,{<<"Node">>, kz_binary:rand_hex(6)}
             ,{<<"CID-Number">>, kz_binary:rand_hex(6)}
             ,{<<"CID-Name">>, kz_binary:rand_hex(6)}
             ,{<<"CID-URI">>, kz_binary:rand_hex(6)}
             ,{<<"Hold-Media">>, kz_binary:rand_hex(6)}
             ,{<<"Presence-Type">>, kz_binary:rand_hex(6)}
             ]),
    kz_json:set_value(<<"slot">>, Slot, create_parked_call_no_slot(AccountId, Db, Options)).

create_parked_call_call_id(AccountId, Db, Options) ->
    kz_json:set_value([<<"slot">>, <<"Call-ID">>], kz_binary:rand_hex(10), create_parked_call(AccountId, Db, Options)).

create_multi_factor_provider(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_multi_factor_provider:new()
                  ,[{fun kzd_multi_factor_provider:set_name/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_multi_factor_provider:set_enabled/2, 'true'}
                   ,{fun kzd_multi_factor_provider:set_provider_name/2, kz_binary:rand_hex(5)}
                   ,{fun set_pvt_provider_type/2, <<"multi_factor">>}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"provider">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]
                  ).

set_pvt_provider_type(JObj, Type) -> kz_json:set_value(<<"pvt_provider_type">>, Type, JObj).

create_number(AccountId, _Db, _Options) ->
    Number = random_us_did_e164(),
    kz_doc:setters(kzd_phone_numbers:new()
                  ,[{fun kzd_phone_numbers:set_pvt_module_name/2, <<"knm_bandwidth2">>}
                   ,{fun kzd_phone_numbers:set_pvt_ported_in/2, 'false'}
                   ,{fun kzd_phone_numbers:set_pvt_state/2, <<"in_service">>}
                   ,{fun kzd_phone_numbers:set_pvt_db_name/2, knm_converters:to_db(Number)}
                   ,{fun kzd_phone_numbers:set_pvt_assigned_to/2, AccountId}
                   ,{fun kz_doc:set_created/2, kz_time:now_s()}
                   ,{fun kz_doc:set_modified/2, kz_time:now_s()}
                   ,{fun kz_doc:set_type/2, <<"number">>}
                   ,{fun kz_doc:set_id/2, Number}
                   ]).

create_rate_limits_account(_AccountId, Db, _Options) ->
    RateThing = [{<<"pvt_type">>, <<"rate_limits">>}
                ,{<<"pvt_owner_id">>, kz_binary:rand_hex(16)}
                ,{<<"pvt_queryname">>, kz_binary:rand_hex(6)}
                ,{<<"pvt_owner_type">>, <<"account">>}
                ],
    Rate1 = kz_json:from_list(
              [{<<"account">>, rate_limits()}
              ,{<<"device">>, rate_limits()}
              | RateThing
              ]),
    kz_doc:setters(Rate1
                  ,[{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"rate_limits">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

rate_limits() ->
    kz_json:from_list_recursive(
      [{<<"per_minute">>, [{<<"registrations">>, uniform_int(0, 100)}
                          ,{<<"invites">>, uniform_int(50, 100)}
                          ,{<<"total_packets">>, uniform_int(100, 1000)}
                          ]
       }
      ,{<<"per_second">>, [{<<"registrations">>, uniform_int(0, 5)}
                          ,{<<"invites">>, uniform_int(0, 5)}
                          ,{<<"total_packets">>, uniform_int(0, 20)}
                          ]
       }
      ]).

create_rate_limits_device(_AccountId, Db, _Options) ->
    Rate = rate_limits(),
    RateThing = [{<<"pvt_type">>, <<"rate_limits">>}
                ,{<<"pvt_owner_id">>, kz_binary:rand_hex(16)}
                ,{<<"pvt_queryname">>, kz_binary:rand_hex(6)}
                ,{<<"pvt_owner_type">>, <<"device">>}
                ],
    kz_doc:setters(kz_json:set_values(RateThing, Rate)
                  ,[{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"rate_limits">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_resource_template(AccountId, Db, Options) ->
    kz_doc:set_type(create_resource(AccountId, Db, Options), <<"resource_template">>).

create_resource(_AccountId, Db, _Options) ->
    IP = kz_binary:join(
           [uniform_int(10, 255), uniform_int(0, 255)
           ,uniform_int(0, 255), uniform_int(0, 255)
           ], <<$.>>),
    Classifier = <<"did_us">>,
    kz_json:exec_first([{fun kzd_resources:set_name/2, kz_binary:rand_hex(5)}
                       ,{fun kzd_resources:set_weight_cost/2, 40}
                       ,{fun kzd_resources:set_gateways/2
                        ,[kz_json:from_list(
                            [{<<"privacy_mode">>, <<"sip">>}
                            ,{<<"progress_timeout">>, 8}
                            ,{<<"server">>, IP}
                            ])
                         ]
                        }
                       ,{fun kzd_resources:set_classifier_enabled/3, Classifier, 'true'}
                       ,{fun kzd_resources:set_classifier_prefix/3, Classifier, <<>>}
                       ,{fun kzd_resources:set_classifier_suffix/3, Classifier, <<>>}
                       ,{fun kzd_resources:set_classifier_emergency/3, Classifier, hd(kz_term:shuffle_list(['false', 'true']))}
                       ,{fun kzd_resources:set_classifier_weight_cost/3, Classifier, 50}
                       ,{fun set_template_name/2, kz_binary:rand_hex(5)}
                       ,{fun kz_doc:update_pvt_parameters/2, Db}
                       ,{fun kz_doc:set_type/2, <<"resource">>}
                       ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                       ]
                      ,kzd_resources:new()).

set_template_name(JObj, Name) -> kz_json:set_value(<<"template_name">>, Name, JObj).

create_service_plan(_AccountId, Db, _Options) ->
    Plan = kz_json:from_list_recursive(
             [{<<"devices">>, [<<"_all">>, 10]}
             ,{<<"users">>, [<<"_all">>, 10]}
             ]),
    kz_doc:setters(kzd_service_plan:new()
                  ,[{fun kzd_service_plan:set_plan/2, Plan}
                   ,{fun set_name/2, <<"Gold">>}
                   ,{fun kzd_service_plan:set_grouping_category/2, <<"Fake">>}
                   ,{fun kzd_service_plan:set_applications/2, kz_json:new()}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"service_plan">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

set_name(JObj, Name) -> kz_json:set_value(<<"name">>, Name, JObj).

create_temporal_rule(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_temporal_rules:new()
                  ,[{fun kzd_temporal_rules:set_time_window_start/2, 3600 * uniform_int(0, 6)}
                   ,{fun kzd_temporal_rules:set_time_window_stop/2, 3600 * uniform_int(7, 24)}
                   ,{fun kzd_temporal_rules:set_days/2, [uniform_int(1, 28) || _ <- lists:seq(1, uniform_int(0, 12))]}
                   ,{fun kzd_temporal_rules:set_name/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_temporal_rules:set_cycle/2, hd(kz_term:shuffle_list([<<"weekly">>, <<"daily">>, <<"yearly">>]))}
                   ,{fun kzd_temporal_rules:set_start_date/2, 62586115200}
                   ,{fun kzd_temporal_rules:set_month/2, 12}
                   ,{fun kzd_temporal_rules:set_ordinal/2, <<"every">>}
                   ,{fun kzd_temporal_rules:set_interval/2, 1}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"temporal_rule">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_temporal_rule_set(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_temporal_rules_sets:new()
                  ,[{fun kzd_temporal_rules_sets:set_name/2, kz_binary:rand_hex(16)}
                   ,{fun kzd_temporal_rules_sets:set_temporal_rules/2
                    ,[kz_binary:rand_hex(16) || _ <- lists:seq(1,4)]
                    }
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"temporal_rule_set">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_trunkstore(AccountId, Db, _Options) ->
    ServerBase =
        kz_json:from_list(
          [{<<"DIDs">>, kz_json:from_list_recursive([{random_us_did_e164(), [{<<"force_outbound">>, 'true'}]}])}
          ,{<<"options">>, kz_json:from_list([{<<"enabled">>, 'true'}])}
          ,{<<"permissions">>, kz_json:from_list([{<<"users">>, []}])}
          ,{<<"monitor">>, kz_json:from_list([{<<"monitor_enabled">>, 'false'}])}
          ,{<<"server_name">>, kz_binary:rand_hex(4)}
          ,{<<"server_type">>, <<"FreeSWITCH">>}
          ,{<<"enabled">>, 'true'}
          ]),
    IP = kz_binary:join(
           [uniform_int(10, 255), uniform_int(0, 255)
           ,uniform_int(0, 255), uniform_int(0, 255)
           ], <<$.>>),
    IPServer = kz_json:set_values([{[<<"auth">>, <<"auth_method">>], hd(kz_term:shuffle_list([<<"IP">>, <<"ip">>]))}
                                  ,{[<<"auth">>, <<"ip">>], IP}
                                  ]
                                 ,ServerBase
                                 ),
    PassServer = kz_json:set_values([{[<<"server_name">>], kz_binary:rand_hex(4)}
                                    ,{[<<"auth">>, <<"auth_method">>], hd(kz_term:shuffle_list([<<"Password">>, <<"password">>]))}
                                    ,{[<<"auth">>, <<"auth_user">>], kz_binary:rand_hex(4)}
                                    ,{[<<"auth">>, <<"auth_password">>], kz_binary:rand_hex(4)}
                                    ,{[<<"DIDs">>], kz_json:from_list_recursive(
                                                      [{random_us_did_e164(), [{<<"force_outbound">>, 'true'}]}]
                                                     )
                                     }
                                    ]
                                   ,ServerBase
                                   ),
    kz_doc:setters(kz_json:set_value(<<"billing_account_id">>, AccountId, kzd_trunkstore:new())
                  ,[{fun kzd_trunkstore:set_servers/2, [PassServer, IPServer]}
                   ,{fun kzd_trunkstore:set_account_auth_realm/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_trunkstore:set_account_credits_prepay/2, uniform_int(0,1) * rand:uniform()}
                   ,{fun kzd_trunkstore:set_account_trunks/2, uniform_int(0, 10)}
                   ,{fun kzd_trunkstore:set_type/2, <<"sys_info">>}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"sys_info">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_user_bare(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_users:new()
                  ,[{fun kzd_users:set_first_name/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_users:set_last_name/2, kz_binary:rand_hex(4)}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"user">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]).

create_user_simple(_AccountId, Db, Options) ->
    kz_doc:setters(create_user_bare(_AccountId, Db, Options)
                  ,[{fun kzd_users:set_username/2, kz_binary:rand_hex(4)}
                   ,{fun kzd_users:set_email/2, <<(kz_binary:rand_hex(4))/binary, "@test.com">>}
                   ,{fun set_md5/2, kz_binary:rand_hex(16)}
                   ,{fun set_sha1/2, kz_binary:rand_hex(16)}
                   ]).

set_md5(JObj, MD5) -> kz_json:set_value(<<"pvt_md5_auth">>, MD5, JObj).
set_sha1(JObj, SHA1) -> kz_json:set_value(<<"pvt_sha1_auth">>, SHA1, JObj).

create_user(AccountId, Db, Options) ->
    User = create_user_simple(AccountId, Db, Options),
    Name = <<(kzd_users:first_name(User))/binary, " ", (kzd_users:last_name(User))/binary>>,
    Extension = rand_num_string(1000, 3000),
    kz_doc:setters(User
                  ,[{fun kzd_users:set_caller_id/2
                    ,kz_doc:setters(kzd_caller_id:new()
                                   ,[{fun kzd_caller_id:set_internal_name/2, Name}
                                    ,{fun kzd_caller_id:set_internal_number/2, Extension}
                                    ,{fun kzd_caller_id:set_external_name/2, kz_binary:rand_hex(4)}
                                    ,{fun kzd_caller_id:set_external_number/2, kz_binary:rand_hex(16)}
                                    ,{fun kzd_caller_id:set_emergency_name/2, kz_binary:rand_hex(4)}
                                    ,{fun kzd_caller_id:set_emergency_number/2, kz_binary:rand_hex(16)}
                                    ])
                    }
                   ,{fun kzd_users:set_presence_id/2, Extension}
                   ]).

create_vmbox(_AccountId, Db, _Options) ->
    kz_doc:setters(kzd_vmboxes:new()
                  ,[{fun kzd_vmboxes:set_mailbox/2, rand_num_string(1000, 3000)}
                   ,{fun kzd_vmboxes:set_owner_id/2, kz_binary:rand_hex(16)}
                   ,{fun kzd_vmboxes:set_name/2, kz_binary:rand_hex(16)}
                   ,{fun kz_doc:update_pvt_parameters/2, Db}
                   ,{fun kz_doc:set_type/2, <<"vmbox">>}
                   ,{fun kz_doc:set_id/2, kz_binary:rand_hex(16)}
                   ]
                  ).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
rand_num_string(From, To) ->
    kz_term:to_binary(uniform_int(From, To)).

random_us_did_e164() ->
    <<"+1", (random_us_did())/binary>>.

random_us_did() ->
    %% ^(\+?1)?([2-9][0-9]{2}[2-9][0-9]{6})
    kz_term:to_binary(
      [kz_term:to_binary(I)
       || I <- [uniform_int(2, 9)
               ,uniform_int(0, 9)
               ,uniform_int(0, 9)
               ,uniform_int(2, 9)
               | [uniform_int(0, 9) || _ <- lists:seq(1, 6)]
               ]
      ]
     ).

uniform_int(Min, Max) ->
    kz_math:floor(uniform(Min, Max)).

uniform(Min, Max) ->
    rand:uniform_real() * (Max - Min + 1) + Min.

rand_email() ->
    kz_term:to_binary(
      [kz_binary:rand_hex(3), $@, kz_binary:rand_hex(2),".com"]
     ).

maybe_log(Options, Fmt0, Args0) ->
    CallerInfo = case erlang:process_info(self(), 'current_stacktrace') of
                     {'current_stacktrace', [_, {M,F,A,[{'file',File},{'line',L}]} | _]} ->
                         io_lib:format("in function  ~s:~s/~b (~s, line ~b): ", [M, F, A, File, L]);
                     _ ->
                         <<>>
                 end,
    Fmt = "~s" ++ Fmt0,
    Args = [CallerInfo] ++ Args0,
    case props:get_value('verbose_log', Options, 'false') of
        'false' -> 'ok';
        'true' -> lager:debug(Fmt, Args);
        'user' -> io:format('user', Fmt ++ "~n", Args);
        'console' -> io:format(Fmt ++ "~n", Args);
        {Sink, Level} ->
            Metadata = [{'application', 'properly'}, {'module', ?MODULE}
                       ,{'function', 'maybe_log'}, {'line', ?LINE}
                       ,{'pid', pid_to_list(self())}, {'node', node()}
                       | lager:md()
                       ],
            lager:log(Sink, Level, Metadata, Fmt, Args);
        Level ->
            Metadata = [{'application', 'properly'}, {'module', ?MODULE}
                       ,{'function', 'maybe_log'}, {'line', ?LINE}
                       ,{'pid', pid_to_list(self())}, {'node', node()}
                       | lager:md()
                       ],
            lager:log(Level, Metadata, Fmt, Args)
    end.
