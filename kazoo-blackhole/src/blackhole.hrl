-ifndef(BLACKHOLE_HRL).

%% Typical includes needed
-include_lib("kazoo_stdlib/include/kz_types.hrl").
-include_lib("kazoo_stdlib/include/kz_log.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(APP, 'blackhole').
-define(APP_NAME, <<"blackhole">>).
-define(APP_VERSION, <<"5.0.0">>).
-define(CONFIG_CAT, <<"blackhole">>).

-define(DEFAULT_MODULES, ['bh_token_auth'
                         ,'bh_call'
                         ,'bh_object'
                         ,'bh_fax'
                         ,'bh_conference'
                         ,'bh_presence'
                         ,'bh_stream'
                         ]).

-define(COMMAND_MODULES, ['bh_events'
                         ,'bh_limits'
                         ,'bh_authz_subscribe'
                         ,'bh_api'
                         ,'bh_ping'
                         ]).

-type bh_subscribe_result() :: {'ok', bh_context:context()} | {'error', kz_term:ne_binary()}.

-define(BLACKHOLE_HRL, 'true').

-endif.
