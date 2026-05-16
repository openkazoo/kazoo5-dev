%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(webhooks_init).

-export([start_link/0
        ,init_modules/0, init_module/1
        ,existing_modules/0
        ,maybe_init_account/2
        ]).

-include("webhooks.hrl").

-spec start_link() -> 'ignore'.
start_link() ->
    kz_log:put_callid(?MODULE),
    _ = kz_process:spawn(fun do_init/0),
    'ignore'.

-spec do_init() -> 'ok'.
do_init() ->
    init_dbs(),
    init_modules().

-spec do_init(kz_term:ne_binary()) -> 'ok'.
do_init(MasterAccountDb) ->
    init_master_account_db(MasterAccountDb),
    init_modules().

-spec init_dbs() -> 'ok'.
init_dbs() ->
    _ = init_master_account_db(),
    webhooks_util:init_webhook_db().

-spec maybe_init_account(kz_json:object(), kz_term:proplist()) -> 'ok' | 'false'.
maybe_init_account(JObj, _Props) ->
    Database = kapi_conf:get_database(JObj),
    kz_datamgr:db_classification(Database) =:= 'account'
        andalso do_init(Database).

-spec init_master_account_db() -> 'ok'.
init_master_account_db() ->
    case kapps_util:get_master_account_db() of
        {'ok', MasterAccountDb} ->
            init_master_account_db(MasterAccountDb),
            remove_old_notifications_webhooks(MasterAccountDb);
        {'error', _} ->
            lager:debug("master account hasn't been created yet"),
            webhooks_shared_listener:add_account_bindings()
    end.

-spec init_master_account_db(kz_term:ne_binary()) -> 'ok'.
init_master_account_db(MasterAccountDb) ->
    _ = kapps_maintenance:refresh(MasterAccountDb),
    lager:debug("loaded view into master db ~s", [MasterAccountDb]).

-spec remove_old_notifications_webhooks(kz_term:ne_binary()) -> 'ok'.
remove_old_notifications_webhooks(MasterAccountDb) ->
    ToRemove = [<<"webhooks_callflow">>
               ,<<"webhooks_inbound_fax">>
               ,<<"webhooks_outbound_fax">>
               ],
    case kz_datamgr:del_docs(MasterAccountDb, ToRemove) of
        {'ok', _} ->
            lager:debug("old notifications webhooks deleted");
        {'error', _Reason} ->
            lager:debug("failed to remove old notifications webhooks: ~p", [_Reason])
    end.

-spec init_modules() -> 'ok'.
init_modules() ->
    lists:foreach(fun init_module/1, existing_modules()),
    lager:debug("finished initializing modules").

-spec init_module(atom()) -> 'ok'.
init_module(Module) ->
    lager:debug("initializing ~s", [Module]),
    try Module:init() of
        _ -> lager:debug("~s initialized", [Module])
    catch
        'error':'undef' ->
            lager:debug("~s doesn't export init/0", [Module]);
        _E:_R ->
            lager:debug("~s failed: ~s: ~p", [Module, _E, _R])
    end.

-spec existing_modules() -> kz_term:atoms().
existing_modules() ->
    AppFiles = filelib:wildcard(filename:join([code:lib_dir('webhooks'), "..", "*", "ebin", "*.app"])),
    app_modules(AppFiles, []).

app_modules([], WebhookModules) -> WebhookModules;
app_modules([AppFile | AppFiles], WebhookModules) ->
    Modules = webhook_modules(AppFile),
    app_modules(AppFiles, Modules ++ WebhookModules).

webhook_modules(AppFile) ->
    App = kz_term:to_atom(filename:basename(AppFile, <<".app">>), 'true'),
    webhook_modules(App, application:load(App)).

webhook_modules(App, 'ok') ->
    {'ok', Modules} = application:get_key(App, 'modules'),
    [Module || Module <- Modules, is_webhook_module(Module)];
webhook_modules(App, {'error',{'already_loaded', App}}) ->
    {'ok', Modules} = application:get_key(App, 'modules'),
    [Module || Module <- Modules, is_webhook_module(Module)];
webhook_modules(_App, {'error', _}) ->
    %% when no .app file actually exists
    [].

is_webhook_module(Module) ->
    has_webhook_exports(Module)
        orelse is_webhook_behaviour(Module).

is_webhook_behaviour(Module) ->
    kz_module:has_behaviour(Module, 'gen_webhook').

has_webhook_exports(Module) ->
    kz_module:is_exported(Module, 'init', 0)
        andalso kz_module:is_exported(Module, 'bindings_and_responders', 0).
