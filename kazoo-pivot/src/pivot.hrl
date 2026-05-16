-ifndef(PIVOT_HRL).

%% Typical includes needed
-include_lib("kazoo_stdlib/include/kz_types.hrl").
-include_lib("kazoo_stdlib/include/kz_log.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(APP, 'pivot').
-define(APP_NAME, <<"pivot">>).
-define(APP_VERSION, <<"4.0.0">>).

-define(CONFIG_CAT, <<"pivot">>).
-define(STREAM_CONFIG_CAT, <<(?CONFIG_CAT)/binary, ".stream">>).

-define(PIVOT_HRL, 'true').
-endif.
