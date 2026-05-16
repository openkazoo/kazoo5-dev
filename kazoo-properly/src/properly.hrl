-ifndef(KAZOO_PROPER_HRL).
-include_lib("kazoo_stdlib/include/kz_types.hrl").
-include_lib("kazoo_stdlib/include/kz_log.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(BASE_URL, kz_network_utils:get_hostname()).

-define(APP_NAME, <<"properly">>).
-define(APP_VERSION, <<"5.0">>).

-define(FAILED_RESPONSE, <<"{}">>).

-define(DEBUG(Fmt)
       ,_ = data:debug(pqc_log:log_info(), Fmt)
       ).

-define(DEBUG(Fmt, Args)
       ,_ = data:debug(pqc_log:log_info(), Fmt, Args)
       ).

-define(INFO(Fmt)
       ,_ = data:info(pqc_log:log_info(), Fmt)
       ).

-define(INFO(Fmt, Args)
       ,_ = data:info(pqc_log:log_info(), Fmt, Args)
       ).

-define(ERROR(Fmt)
       ,_ = data:error(pqc_log:log_info(), Fmt)
       ).

-define(ERROR(Fmt, Args)
       ,_ = data:error(pqc_log:log_info(), Fmt, Args)
       ).

-type request_headers() :: [{kz_term:text(), string() | non_neg_integer()}].

-record('dedicated', {ip :: kz_term:api_ne_binary()
                     ,host :: kz_term:api_ne_binary()
                     ,zone :: kz_term:api_ne_binary()
                     }).
-define(DEDICATED(IP, Host, Zone)
       ,#dedicated{ip=IP, host=Host, zone=Zone}
       ).

-define(KAZOO_PROPER_HRL, 'true').
-endif.
