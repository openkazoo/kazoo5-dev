-ifndef(SKEL_HRL).
%% helpful macros and type definitions
-include_lib("kazoo_stdlib/include/kz_types.hrl").

%% logging-related macros, parse transforms, etc
-include_lib("kazoo_stdlib/include/kz_log.hrl").

%% macros for system databases and account/modb formatting
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(APP, 'skel').

%% used when building AMQP payloads
-define(APP_NAME, <<"skel">>).
-define(APP_VERSION, <<"5.0.0">> ).

%% used for an app's local ETS cache
-define(CACHE_NAME, 'skel_cache').

%% avoid double-inclusions (compile error)
-define(SKEL_HRL, 'true').
-endif.
