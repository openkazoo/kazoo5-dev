%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2018-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_account_cb_listings_view).

-export([compare/1
        ,compare_designs/2
        ,compare_views/2
        ]).

-export([generate_and_save_docs/1, generate_and_save_docs/2, generate_and_save_docs/3
        ,generate_docs/3

        ,create_old_views/1,create_old_view/2
        ,create_cb_view/1
        ,create_views_from_paths/2

        ,account_views/0
        ]).

-export([rand_account_id/0]).
-export([remove_docs/1
        ,clean_db/1
        ]).

-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kz_types.hrl").

-elvis([{elvis_style, no_debug_call, disable}]).

%%
%%
%% We need the database name to be a valid account ID because kzc module would check
%% the database classification.
%% If you need to db name to not be account ID then you have to change get_new_result
%% to not uses kzv* modules.
%%
%%

-spec compare(AccountId::kz_term:ne_binary()) -> any().
compare(AccountId) ->
    io:format("======== Compare views in ~s =======~n", [kzs_util:to_database(AccountId)]),
    case kz_datamgr:db_exists(AccountId) of
        'true' ->
            Result = [compare(AccountId, Design, Views) || {Design, Views} <- lists:sort(maps:to_list(account_views()))],
            io:format("==================================================================================~n"),
            log_result(Result);
        'false' ->
            io:format("database ~s does not exists!", [AccountId])
    end.

-spec compare_designs(AccountId::kz_term:ne_binary(), Designs::kz_term:ne_binaries()) -> any().
compare_designs(AccountId, Designs) ->
    io:format("======== Compare views in ~s =======~n", [kzs_util:to_database(AccountId)]),
    case kz_datamgr:db_exists(AccountId) of
        'true' ->
            AccountViews = account_views(),
            Result = [compare(AccountId, Design, Views)
                      || Design <- lists:usort(Designs),
                         Views <- [maps:get(Design, AccountViews)]
                     ],
            io:format("==================================================================================~n"),
            log_result(Result);
        'false' ->
            io:format("database ~s does not exists!", [AccountId])
    end.

-spec compare_views(AccountId::kz_term:ne_binary(), DesignViews::kz_term:ne_binaries()) -> any().
compare_views(AccountId, DesignViews) ->
    io:format("======== Compare views in ~s =======~n", [kzs_util:to_database(AccountId)]),
    case kz_datamgr:db_exists(AccountId) of
        'true' ->
            AccountViews = account_views(),
            DVs = lists:foldl(fun(Elm, Acc) ->
                                      [Design, View] = binary:split(Elm, <<"/">>),
                                      DM = maps:get(Design, AccountViews),
                                      VM = maps:get(View, DM),
                                      DmAcc = maps:get(Design, Acc, #{}),
                                      Acc#{Design => DmAcc#{View => VM}}
                              end
                             ,#{}
                             ,lists:usort(DesignViews)
                             ),
            Result = [compare(AccountId, Design, Views) || {Design, Views} <- lists:sort(maps:to_list(DVs))],
            io:format("==================================================================================~n"),
            log_result(Result);
        'false' ->
            io:format("database ~s does not exists!", [AccountId])
    end.

-spec generate_and_save_docs(Generators::kz_term:ne_binaries() | kz_term:ne_binary() | 'all') -> any().
generate_and_save_docs(Generators) ->
    AccountId = rand_account_id(),
    io:format("using ~p as account id~n", [AccountId]),
    {AccountId, generate_and_save_docs(AccountId, Generators)}.

-spec generate_and_save_docs(AccountId::kz_term:ne_binary(), Generators::kz_term:ne_binaries() | kz_term:ne_binary() | 'all') -> any().
generate_and_save_docs(AccountId, Generators) ->
    generate_and_save_docs(AccountId, Generators, 1).

-spec generate_and_save_docs(AccountId::kz_term:ne_binary(), Generators::kz_term:ne_binaries() | kz_term:ne_binary() | 'all', Count::pos_integer()) -> any().
generate_and_save_docs(AccountId, Generators, Count) ->
    Docs = generate_docs(AccountId, Generators, Count),
    save_docs(AccountId, Docs).

-spec generate_docs(AccountId::kz_term:ne_binary(), Generators::kz_term:ne_binaries() | kz_term:ne_binary() | 'all', Count::pos_integer()) -> any().
generate_docs(AccountId, <<Generator/binary>>, Count) ->
    generate_docs(AccountId, [Generator], Count);
generate_docs(AccountId, Generators, Count) ->
    Start = kz_time:start_time(),
    Docs = lists:flatten(
             [[pqc_doc_generator:create(Generator, AccountId, kzs_util:format_account_db(AccountId))
               || Generator <- Generators
              ]
              || _ <- lists:seq(1, Count)
             ]),
    io:format("created ~b documents in ~p ms~n", [length(Docs), kz_time:elapsed_ms(Start)]),
    Docs.

-spec create_old_views(AccountId::kz_term:ne_binary()) -> any().
create_old_views(AccountId) ->
    create_views_from_paths(AccountId, [old_view_path(D) || D <- maps:keys(account_views())]).

-spec create_old_view(AccountId::kz_term:ne_binary(), Design::kz_term:ne_binary()) -> any().
create_old_view(AccountId, Design) ->
    create_views_from_paths(AccountId, [Design]).

-spec create_cb_view(AccountId::kz_term:ne_binary()) -> any().
create_cb_view(AccountId) ->
    create_views_from_paths(AccountId, [priv_path('kazoo_couch', ["couchdb/views/account-crossbar_listings.json"])]).

-spec create_views_from_paths(AccountId::kz_term:ne_binary(), Paths::kz_term:ne_binaries()) -> any().
create_views_from_paths(AccountId, Paths) ->
    save_docs(AccountId, [read_view(P) || P <- Paths]).

%% @private
save_docs(AccountId, Docs) ->
    Start = kz_time:start_time(),
    case kz_datamgr:db_exists(AccountId)
        orelse kz_datamgr:db_create(AccountId)
    of
        'false' ->
            io:format("failed to create dummy test database: ~s~n", [AccountId]),
            {'error', {kz_time:elapsed_ms(Start), kz_binary:format("cannot create dummy test db '~s'", [AccountId])}};
        'true' ->
            io:format("saving ~b docs to database: ~s~n", [length(Docs), AccountId]),
            Result = kz_datamgr:save_docs(AccountId, Docs),
            ElapsedMs = kz_time:elapsed_ms(Start),
            io:format("saved ~b documents to ~s db in ~p ms~n", [length(Docs), AccountId, ElapsedMs]),
            case Result of
                {'ok', _} -> {'ok', {ElapsedMs, length(Docs)}};
                {'error', Reason} -> {'error', {ElapsedMs, Reason}}
            end
    end.
-spec rand_account_id() -> kz_term:ne_binary().
rand_account_id() ->
    <<"properly_kzc_account_db_", (kz_binary:rand_hex(4))/binary>>.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec remove_docs(Db::kz_term:ne_binary()) ->
          {'ok', kz_json:objects()} |
          kazoo_data:data_error().
remove_docs(Db) ->
    {'ok', JObjs} = kz_datamgr:all_docs(Db),
    kz_datamgr:del_docs(Db
                       ,[kz_doc:setters(kz_json:new()
                                       ,[{fun kz_doc:set_id/2, kz_doc:id(JObj)}
                                        ,{fun kz_doc:set_revision/2, kz_doc:revision(JObj)}
                                        ])
                         || JObj <- JObjs,
                            not is_design(JObj)
                        ]
                       ).

-spec clean_db(Db::kz_term:ne_binary()) -> any().
clean_db(Db) ->
    {'ok', JObjs} = kz_datamgr:all_docs(Db),
    _ = kz_datamgr:del_docs(Db
                           ,[kz_doc:setters(kz_json:new()
                                           ,[{fun kz_doc:set_id/2, kz_doc:id(JObj)}
                                            ,{fun kz_doc:set_revision/2, kz_doc:revision(JObj)}
                                            ])
                             || JObj <- JObjs
                            ]
                           ),
    kz_datamgr:db_view_cleanup(Db),
    kz_datamgr:db_compact(Db).

-spec account_views() -> map().
account_views() ->
    #{<<"apps_store">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_name">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_name'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"app">>]
                 ,old_query_fields => <<"name">>
                 ,new_to_old => fun(_, [_, Name]) -> Name end
                 ,doc_type => <<"app">>
                 }
           }
     ,<<"attributes">> =>
          #{<<"endpoints_lookup">> =>
                #{new_view => <<"endpoints_lookup">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_endpoints_lookup'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"account">>, <<"user">>, <<"device">>]
                 ,old_query_fields => [<<"caller_id_number">>, <<"caller_id_type">>]
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => 'any'
                 }
           ,<<"groups">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"group">>]
                 ,old_query_fields => 'null'
                 ,new_to_old => fun(_, _) -> 'null' end
                 ,compare_values =>
                      fun (Old, New) ->
                              io:format("    compare (id: ~s): checking value is correctly moved to 'group_endpoints'~n", [r_id(Old)]),
                              compare_json_values(r_id(Old)
                                                 ,r_value(Old)
                                                 ,kz_json:get_value(<<"group_endpoints">>, r_value(New), kz_json:new())
                                                 )
                      end
                 ,doc_type => <<"group">>
                 }
           ,<<"hotdesk_id">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"hotdesking_user">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"hotdesk">>
                 }
           ,<<"hotdesk_users">> =>
                #{new_view => <<"by_type_ownerid">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_ownerid'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"hotdesked_device">>]
                 ,old_query_fields => <<"owner_id">>
                 ,new_to_old => fun(_, [_, OwnerId]) -> OwnerId end
                 ,compare_values => fun (Old, _) -> compare_values(r_id(Old), r_value(Old), 'null')end
                 ,doc_type => <<"hotdesk">>
                 }
           ,<<"mailbox_number">> =>
                #{new_view => <<"by_type_number">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_number'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"vmbox">>]
                 ,old_query_fields => <<"number">>
                 ,new_to_old => fun(_, [_, Number]) -> Number end
                 ,doc_type => <<"vmbox">>
                 }
           ,<<"owned">> =>
                #{new_view => <<"by_ownerid_type">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_ownerid_type'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"device">>, <<"group">>, <<"rate_limits_account">>, <<"directory_owner">>]
                 ,old_query_fields => [<<"owner_id">>, <<"doc_type">>]
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => 'any'
                 }
           ,<<"owner">> =>
                #{new_view => <<"owners_by_docid_type">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_owners_by_docid_type'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"device">>, <<"group">>, <<"rate_limits_account">>, <<"device_rate_limits">>, <<"faxbox_owner">>, <<"directory_owner">>]
                 ,old_query_fields => <<"doc_id">>
                 ,new_to_old => fun(_, [DocId, _]) -> DocId end
                 ,doc_type => 'any'
                 }
           ,<<"sip_username">> =>
                #{new_view => <<"by_sip_usernames">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_sip_usernames'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"device">>, <<"trunkstore">>]
                 ,old_query_fields => <<"username">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => 'any'
                 }
           ,<<"temporal_rules">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"temporal_rule">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, DocId]) -> DocId end
                 ,compare_values => fun (Old, _) -> compare_values(r_id(Old), r_value(Old), 'null')end
                 ,doc_type => <<"temporal_rule">>
                 }
           }
     ,<<"auth">> =>
          #{<<"providers_by_type">> =>
                #{new_view => <<"auth_providers_type">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_auth_providers_type'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"multi_factor_provider">>]
                 ,old_query_fields => [<<"provider_type">>, <<"doc_id">>]
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"provider">>
                 }
           }
     ,<<"blacklists">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"blacklist">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"blacklist">>
                 }
           }
     ,<<"callflows">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"callflow_simple">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"callflow">>
                 }
           ,<<"listing_by_number">> =>
                #{new_view => <<"by_type_number">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_number'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"callflow_number">>]
                 ,old_query_fields => <<"number">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"callflow">>
                 }
           ,<<"listing_by_pattern">> =>
                #{new_view => <<"flow_patterns">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_flow_patterns'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"callflow_pattern">>]
                 ,old_query_fields => <<"pattern">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"callflow">>
                 }
           ,<<"msisdn">> =>
                #{new_view => <<"flow_msisdn">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_flow_msisdn'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"callflow_device">>, <<"callflow_user">>]
                 ,old_query_fields => [<<"module">>, <<"data_id">>, <<"number">>]
                 ,new_to_old => fun(_, [_ | Keys]) -> Keys end
                 ,doc_type => <<"callflow">>
                 }
           }
     ,<<"click2call">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"click2call">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"click2call">>
                 }
           }
     ,<<"conference">> =>
          #{<<"listing_by_number">> =>
                #{new_view => <<"by_type_number">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_number'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"conference_number">>]
                 ,old_query_fields => <<"number">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"conference">>
                 }
           }
     ,<<"conferences">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"conference">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"conference">>
                 }
           }
     ,<<"contact_list">> =>
          #{<<"excluded">> =>
                #{new_view => <<"contact_list_excluded">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_contact_list_excluded'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"contact_list_excluded">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => 'any'
                 }
           ,<<"extensions">> =>
                #{new_view => <<"contact_list_extensions">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_contact_list_extensions'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"callflow_device">>, <<"callflow_user">>, <<"callflow_user_vmbox">>
                                ,<<"callflow_featurecode">>, <<"callflow_feature_no_action">>, <<"callflow_no_name">>
                                ,<<"callflow_tts">>, <<"callflow_contact_id">>
                                ]
                 ,old_query_fields => <<"extension_type">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"callflow">>
                 }
           ,<<"names">> =>
                #{new_view => <<"contact_list_names">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_contact_list_names'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"menu">>, <<"device">>, <<"user">>, <<"vmbox">>, <<"conference">>]
                 ,old_query_fields => 'null'
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => 'any'
                 }
           }
     ,<<"devices">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"device_simple">>, <<"device">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"device">>
                 }
           ,<<"listing_by_macaddress">> =>
                #{new_view => <<"device_mac_addresses">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_device_mac_addresses'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"device_simple">>]
                 ,old_query_fields => <<"mac_address">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"device">>
                 }
           ,<<"listing_by_owner">> =>
                #{new_view => <<"by_type_ownerid">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_ownerid'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"mobile">>, <<"hotdesked_device">>, <<"device">>]
                 ,old_query_fields => <<"owner_id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"device">>
                 }
           ,<<"listing_by_presence_id">> =>
                #{new_view => <<"device_presence_ids">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_device_presence_ids'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"device">>]
                 ,old_query_fields => <<"presence_id">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"device">>
                 }
           ,<<"sip_credentials">> =>
                #{new_view => <<"by_sip_credentials">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_sip_credentials'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"device">>, <<"mobile">>]
                 ,old_query_fields => <<"username">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"device">>
                 }
           }
     ,<<"directories">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"directory">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"directory">>
                 }
           ,<<"users_listing">> =>
                #{new_view => <<"owners_by_docid_type">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_owners_by_docid_type'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"directory_owner">>]
                 ,old_query_fields => [<<"doc_id">>, <<"ignore_me">>]
                 ,new_to_old => fun(N, [DirectoryDocId, _Type]) -> [DirectoryDocId, r_id(N)] end
                 ,doc_type => <<"directory">>
                 }
           }
     ,<<"faxbox">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"faxbox">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"faxbox">>
                 }
           ,<<"email_permissions">> =>
                #{new_view => <<"faxbox_email_permissions">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_faxbox_email_permissions'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"faxbox_email_permissions">>]
                 ,old_query_fields => <<"permission_tag">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"faxbox">>
                 }
           ,<<"list_by_ownerid">> =>
                #{new_view => <<"by_type_ownerid">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_ownerid'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"faxbox_owner">>]
                 ,old_query_fields => <<"owner_id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"faxbox">>
                 }
           }
     ,<<"groups">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"group">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"group">>
                 }
           ,<<"crossbar_listing_by_user">> =>
                #{new_view => <<"by_type_ownerid">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_ownerid'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"group">>]
                 ,old_query_fields => <<"owner_id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"group">>
                 }
           }
     ,<<"hotdesks">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_ownerid">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_ownerid'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"hotdesked_device">>]
                 ,old_query_fields => <<"owner_id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"hotdesk">>
                 }
           }
     ,<<"lists">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"list">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"list">>
                 }
           ,<<"entries">> =>
                #{new_view => <<"list_entries">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_list_entries'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"list_entry">>]
                 ,old_query_fields => <<"list_id">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"list_entry">>
                 }
           ,<<"match_prefix_in_list">> =>
                #{new_view => <<"list_prefixes">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_list_prefixes'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"list_entry_number">>, <<"list_entry_prefix">>]
                 ,old_query_fields => [<<"list_id">>, <<"prefix">>]
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"list_entry">>
                 }
           ,<<"regexps_in_list">> =>
                #{new_view => <<"list_patterns">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_list_patterns'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"list_entry_regexp">>, <<"list_entry_pattern">>]
                 ,old_query_fields => <<"list_id">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"list_entry">>
                 }
           }
     ,<<"menus">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"menu">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"menu">>
                 }
           }
     ,<<"message">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"message_number">>, <<"message_pattern">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"textflow">>
                 }
           ,<<"listing_by_number">> =>
                #{new_view => <<"by_type_number">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_number'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"message_number">>]
                 ,old_query_fields => <<"number">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"textflow">>
                 }
           ,<<"listing_by_pattern">> =>
                #{new_view => <<"flow_patterns">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_flow_patterns'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"message_pattern">>]
                 ,old_query_fields => <<"pattern">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"textflow">>
                 }
           ,<<"msisdn">> =>
                #{new_view => <<"flow_msisdn">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_flow_msisdn'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => []
                 ,old_query_fields => [<<"module">>, <<"data_id">>, <<"number">>]
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"textflow">>
                 }
           }
     ,<<"metaflows">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"metaflow_device">>, <<"metaflow_user">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"metaflow">>
                 }
           }
     ,<<"mobile">> =>
          #{<<"listing_by_mdn">> =>
                #{new_view => <<"mobile_mdns">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_mobile_mdns'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"mobile">>]
                 ,old_query_fields => <<"mdn">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"device">>
                 }
           }
     ,<<"notifications">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_name">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_name'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"notification">>]
                 ,old_query_fields => <<"name">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"notification">>
                 }
           }
     ,<<"parking">> =>
          #{<<"parked_call">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"parked_call_no_slot">>, <<"parked_call">>, <<"parked_call_call_id">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"parked_call_id">>
                 }
           ,<<"parked_calls">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"parked_call_no_slot">>, <<"parked_call">>, <<"parked_call_call_id">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"parked_call">>
                 }
           }
     ,<<"phone_numbers">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"number">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"number">>
                 }
           }
     ,<<"rate_limits">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"rate_limits">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_rate_limits'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"rate_limits_account">>, <<"rate_limits_device">>]
                 ,old_query_fields => [<<"name">>, <<"sip_method">>]
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"rate_limits">>
                 }
           ,<<"list_by_owner">> =>
                #{new_view => <<"by_type_ownerid">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_ownerid'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"rate_limits_account">>, <<"rate_limits_device">>]
                 ,old_query_fields => <<"owner_id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"rate_limits">>
                 }
           }
     ,<<"resources">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"resource">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"resource">>
                 }
           ,<<"listing_by_id">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"resource">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,compare_values => fun (Old, New) ->
                                            io:format("    compare (id: ~s): checking value (as a single string) 'name' is correctly set in the new value object~n"
                                                     ,[r_id(Old)]
                                                     ),
                                            compare_values(r_id(Old), r_value(Old), kz_json:get_value(<<"name">>, r_value(New)))
                                    end
                 ,doc_type => <<"resource">>
                 }
           ,<<"resource_templates">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"resource_template">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"resource_template">>
                 }
           }
     ,<<"service_plans">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"service_plan">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"service_plan">>
                 }
           }
     ,<<"temporal_rules_sets">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"temporal_rule_set">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"temporal_rule_set">>
                 }
           }
     ,<<"temporal_rules">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"temporal_rule">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"temporal_rule">>
                 }
           }
     ,<<"trunkstore">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"trunkstore">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"sys_info">>
                 }
           ,<<"lookup_did">> =>
                #{new_view => <<"by_type_number">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_number'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"trunkstore">>]
                 ,old_query_fields => <<"number">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"sys_info">>
                 }
           ,<<"lookup_user_flags">> =>
                #{new_view => <<"trunkstore_lookup_user_flags">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_trunkstore_lookup_user_flags'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"trunkstore">>]
                 ,old_query_fields => [<<"auth_realm">>, <<"auth_user">>]
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"sys_info">>
                 }
           }
     ,<<"users">> =>
          #{<<"creds_by_md5">> =>
                #{new_view => <<"user_creds_md5">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_user_creds_md5'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"user_bare">>, <<"user">>]
                 ,old_query_fields => <<"cred">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"user">>
                 }
           ,<<"creds_by_sha">> =>
                #{new_view => <<"user_creds_sha1">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_user_creds_sha1'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"user">>]
                 ,old_query_fields => <<"cred">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"user">>
                 }
           ,<<"crossbar_listing">> =>
                #{new_view => <<"by_type_name">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_name'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"user">>]
                 ,old_query_fields => <<"name">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"user">>
                 }
           ,<<"list_by_email">> =>
                #{new_view => <<"user_emails">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_user_emails'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"user">>]
                 ,old_query_fields => <<"email">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"user">>
                 }
           ,<<"list_by_hotdesk_id">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"hotdesking_user">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"hotdesk">>
                 }
           ,<<"list_by_id">> =>
                #{new_view => <<"by_type_id">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_id'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"user">>]
                 ,old_query_fields => <<"id">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"user">>
                 }
           ,<<"list_by_username">> =>
                #{new_view => <<"user_usernames">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_user_usernames'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"user">>]
                 ,old_query_fields => <<"username">>
                 ,new_to_old => fun(_, Key) -> Key end
                 ,doc_type => <<"user">>
                 }
           }
     ,<<"vmboxes">> =>
          #{<<"crossbar_listing">> =>
                #{new_view => <<"by_type_name">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_name'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"vmbox">>]
                 ,old_query_fields => <<"name">>
                 ,new_to_old => fun(_, [_, Key]) -> Key end
                 ,doc_type => <<"vmbox">>
                 }
           ,<<"listing_by_mailbox">> =>
                #{new_view => <<"by_type_number">>
                 ,new_design => <<"crossbar_listings">>
                 ,kzv => 'kzv_by_type_number'
                 ,kzc => 'kzc_account_crossbar_listings'
                 ,generators => [<<"vmbox">>]
                 ,old_query_fields => <<"number">>
                 ,new_to_old => fun(_, [_, Key]) -> kz_term:to_integer(Key) end
                 ,doc_type => <<"vmbox">>
                 }
           }
     }.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

log_result([]) ->
    io:format("There were no views to test~n");
log_result(Result) ->
    GetFailed = fun(D, V, P, F) ->
                        case props:get_value('result', P) of
                            'failed' -> [<<D/binary, "/", V/binary>> | F];
                            'passed' -> F
                        end
                end,
    ProcessD = fun(D, {V, Prop}, {Vs, Fs}) ->
                       {Vs+1, GetFailed(D, V, Prop, Fs)}
               end,
    {DCount, VCount, Failed} =
        lists:foldl(fun({D, _, DVs}, {DC, VC, F}) ->
                            {Vs, Fs} = lists:foldl(fun(Elm, Acc) -> ProcessD(D, Elm, Acc) end
                                                  ,{0, F}
                                                  ,DVs
                                                  ),
                            {DC+1, VC+Vs, Fs}
                    end
                   ,{0, 0, []}
                   ,Result
                   ),
    case Failed of
        [] ->
            io:format("All ~b view tests (in ~b design documents) 'passed'.~n", [VCount, DCount]);
        _ ->
            io:format("~b views (in ~b design documents) were tested~n", [VCount, DCount]),
            io:format("**Some tests were 'failed'**~n~n"),
            _ = [io:format("view ~s test 'failed'~n", [View]) || View <- Failed],
            'ok'
    end.

compare(AccountId, Design, Views) ->
    io:format("design ~s~n", [Design]),
    Start = kz_time:start_time(),
    PerView = lists:foldl(fun({View, Map}, Acc) ->
                                  compare(AccountId, Design, View, Map, Acc)
                          end
                         ,[]
                         ,lists:sort(maps:to_list(Views))
                         ),
    ElapsedMs = kz_time:elapsed_ms(Start),
    io:format("[done in ~b ms]~n", [ElapsedMs]),
    {Design, ElapsedMs, PerView}.

compare(AccountId, OldDesign, OldView, Map, Acc) ->
    io:format("  view ~s~n", [OldView]),
    Start = kz_time:start_time(),
    {Elapsed1, OldResult} = get_old_result(AccountId, <<OldDesign/binary, "/", OldView/binary>>),
    {Elapsed2, NewResult} = get_new_result(AccountId, Map),
    {'passed', Elapsed3} = compare_results(Map, OldResult, NewResult),
    Elapsed4 = kz_time:elapsed_ms(Start),
    io:format("~n  [done in ~b ms]~n", [Elapsed4]),
    [{OldView, [{'old', Elapsed1}, {'new', Elapsed2}
               ,{'compare', Elapsed3}, {'total', Elapsed4}
               ,{'result', 'passed'}
               ]
     }
    | Acc
    ].

get_old_result(AccountId, DesignView) ->
    Start = kz_time:start_time(),
    Options = [{'no_create_view', 'true'} %% we do not want to trigger refresh_views and services and etc...
              ,{'group', 'false'}
              ,{'reduce', 'false'}
              ],
    %% io:format("    kz_datamgr:get_results(~p, ~p, ~1000p): ", [AccountId, DesignView, Options]),
    io:format("    old view: "),
    case kz_datamgr:get_results(AccountId, DesignView, Options) of
        {'ok', JObjs} ->
            ElapsedMs = kz_time:elapsed_ms(Start),
            io:format("got ~b results...[~b ms]~n", [length(JObjs), ElapsedMs]),
            {ElapsedMs, JObjs};
        {'error', _Reason} ->
            ElapsedMs = kz_time:elapsed_ms(Start),
            io:format("error...~n~p~n~n**failed**~n[~b ms]~n", [_Reason, ElapsedMs]),
            {ElapsedMs, 'error'}
    end.

get_new_result(AccountId, #{kzv := KzvMod
                           ,kzc := KzcMod
                           ,new_view := View
                           }=Map) ->
    Start = kz_time:start_time(),
    QueryFields = KzcMod:metadata('query_fields', View),
    {_Fmt, Args} = build_new_args(QueryFields, Map),
    Options = [{'no_create_view', 'true'} %% we do not want to trigger refresh_views and services and etc...
              ,{'group', 'false'}
              ,{'reduce', 'false'}
              ],
    %% io:format("    ~s:find_all(~p~s, ~1000p]): ", [KzvMod, AccountId, _Fmt, Options]),
    io:format("    new view: "),
    case apply(KzvMod, 'find_all', [AccountId | Args] ++ [Options]) of
        {'ok', JObjs} ->
            ElapsedMs = kz_time:elapsed_ms(Start),
            io:format("got ~b results...[~b ms]~n", [length(JObjs), ElapsedMs]),
            {ElapsedMs, JObjs};
        {'error', _Reason} ->
            ElapsedMs = kz_time:elapsed_ms(Start),
            io:format("error...~n~p~n~n**failed**~n[~b ms]~n", [_Reason, ElapsedMs]),
            {ElapsedMs, 'error'}
    end.

%% for */crossbar_listing we need doc type to narrow down the result
%% to old view behaviour.
build_new_args(<<Field/binary>>, Map) ->
    build_new_args([Field], Map);
build_new_args([<<"doc_type">>|_], #{doc_type := 'any'}) ->
    {[], []};
build_new_args([<<"doc_type">>|_], #{doc_type := DocType}) ->
    {<<", <<\"", DocType/binary, "\">>">>, [DocType]};
build_new_args(_, _) ->
    {[], []}.

compare_results(_, 'error', _) ->
    io:format("    **failed** compare: no old~n    compare: **failed**...[0 ms]~n"),
    {'failed', 0};
compare_results(_, _,'error') ->
    io:format("    **failed** compare: no new~n    compare: **failed**...[0 ms]~n"),
    {'failed', 0};
compare_results(_, [], []) ->
    io:format("    **failed** compare: both empty~n    compare: **failed**...[0 ms]~n"),
    {'failed', 0};
compare_results(_, [], [_|_]) ->
    io:format("    **failed** compare: old result is empty, new is plenty~n    compare: **failed**...[0 ms]~n"),
    {'failed', 0};
compare_results(_, [_|_], []) ->
    io:format("    **failed** compare: old result is plenty, new is empty~n    compare: **failed**...[0 ms]~n"),
    {'failed', 0};
compare_results(Map, Olds, News) ->
    Start = kz_time:start_time(),
    do_compare_results(Map, Olds, News, Start, 'passed').

do_compare_results(_, [], _News, Start, Acc) ->
    Elapsed = kz_time:elapsed_ms(Start),
    LogThing = log_thing(Acc),
    io:format("    compare: ~s...[~b ms]~n", [LogThing, Elapsed]),
    {Acc, Elapsed};
do_compare_results(#{new_to_old := Fun}=Map, [OldJObj|Olds], News, Start, Acc) ->
    OldId = r_id(OldJObj),
    OldKey = r_key(OldJObj),
    case get_new(Fun, OldId, OldKey, News) of
        {'missing', NewNews} ->
            io:format("    **failed** compare: old view doc with id ~s is missing from new view~n", [OldId]),
            do_compare_results(Map, Olds, NewNews, Start, 'failed');
        {NewJObj, NewNews} ->
            compare_values(Map, OldId, OldJObj, NewJObj),
            do_compare_results(Map, Olds, NewNews, Start, Acc)
    end.

log_thing('failed') -> "**failed**";
log_thing(Acc) -> Acc.

get_new(_, _, _, []) -> {'missing', []};
get_new(Fun, OldId, OldKey, [N|Ns]) ->
    case {r_id(N), Fun(N, r_key(N))} of
        {OldId, OldKey} ->
            {N, Ns};
        {_I, OldKey} ->
            ?DEV_LOG("~nOId ~p~nOK ~p~nNId ~p~nNK ~p~n"
                    ,[OldId, OldKey, _I, OldKey]
                    ),
            %% Should we continuing here?
            %%
            %% We want to make sure the new view is working as same as old view,
            %% so it doesn't return extra result with the same key.
            %%
            %% But in the other hand the new view could've been fixed something
            %% or is simply returning more result with the same key than previous because
            %% it is doing more job?
            %% (for example contact lists / excluded)
            throw({'error', 'same_key_different_id'});
        {_, NewKey} when OldKey < NewKey ->
            {'missing', [N|Ns]};
        {_, NewKey} when OldKey > NewKey ->
            get_new(Fun, OldId, OldKey, Ns)
    end.

compare_values(#{compare_values := Fun}, _, Old, New) ->
    %% returns 'passed' or 'failed'
    Fun(Old, New);
compare_values(_, Id, Old, New) ->
    compare_values(Id, r_value(Old), r_value(New)).

compare_values(_, Same, Same) -> 'passed';
compare_values(Id, Old, New) ->
    case {kz_json:is_json_object(Old)
         ,kz_json:is_json_object(New)
         }
    of
        {'true', 'true'} ->
            compare_json_values(Id, Old, New);
        {'false', 'false'} ->
            io:format("    **failed** compare (id: ~s): values are different~nOld: ~p~nNew: ~p~n", [Id, Old, New]),
            'failed';
        {_, _} ->
            io:format("    **failed**compare (id: ~s): got values in different format~nOld: ~p~nNew: ~p~n", [Id, Old, New]),
            'failed'
    end.

compare_json_values(Id, Old, New) ->
    Diff = kz_json:diff(Old, New),
    case kz_json:is_empty(Diff) of
        'true' -> 'passed';
        'false' ->
            io:format("    **failed** compare (id: ~s): ~nMissing values~n~p~n", [Id, Diff]),
            'failed'
    end.

r_key(J) -> kz_json:get_value(<<"key">>, J).
r_value(J) -> kz_json:get_value(<<"value">>, J).
r_id(J) -> kz_doc:id(J).

priv_path(App, Path) ->
    filename:join([code:priv_dir(App) | Path]).

old_view_path(View) ->
    priv_path('properly', ["rest-in-peace-views", kz_term:to_binary([View, ".json"])]).

read_view(Path) ->
    {'ok', View} = kz_json:fixture(Path),
    kz_datamgr:maybe_adapt_multilines(kz_json:delete_key(<<"kazoo">>, View)).

is_design(<<"_design/", _/binary>>) -> 'true';
is_design(<<"_design%2F", _/binary>>) -> 'true';
is_design(<<"_design%2f", _/binary>>) -> 'true';
is_design(JObj) ->
    'true' = kz_json:is_json_object(JObj),
    is_design(kz_doc:id(JObj)).
