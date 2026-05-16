%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Commland interaction
%%% @author Sean Wysor
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_commland).

-export([init/0
        ,authorize/2
        ,authenticate/2
        ,allowed_methods/1
        ,resource_exists/1
        ,validate/2
        ]).

-include("crossbar.hrl").

-define(DOT, <<".">>).
-define(COMPAT, <<"compatibility">>).
-define(COMPAT_NOUNS, [{<<"commland">>,[<<"compatibility">>]}]).
-define(COMMLAND_CONFIG_CAT, <<"crossbar.commland">>).
-define(BASE_URL, kapps_config:get_ne_binary(?COMMLAND_CONFIG_CAT, <<"base_url">>, <<"https://packages.2600hz.com/commland/dist/compatibility">>)).
-define(BASE_VERSION, kapps_config:get_ne_binary(?COMMLAND_CONFIG_CAT, <<"base_version">>, <<"5.1">>)).
-define(BASE_SALT, kapps_config:get_ne_binary(?COMMLAND_CONFIG_CAT, <<"base_salt">>, <<"7f613340-1ebf-4710-ad57-fb4d3041af4c">>)).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.commland">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.authorize.commland">>, ?MODULE, 'authorize'),
    _ = crossbar_bindings:bind(<<"*.authenticate.commland">>, ?MODULE, 'authenticate'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.commland">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.commland">>, ?MODULE, 'validate'),
    _ = ?BASE_SALT,
    'ok'.

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(?COMPAT) -> [?HTTP_GET].

-spec authorize(cb_context:context(), path_token()) ->
          boolean() |
          {'stop', cb_context:context()}.
authorize(Context, ?COMPAT) ->
    authorize_commland(Context, cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authorize_commland(cb_context:context(), http_method(), req_nouns()) ->
          boolean() |
          {'stop', cb_context:context()}.
authorize_commland(_Context, ?HTTP_GET, ?COMPAT_NOUNS) ->
    lager:debug("bypassing authorizing for request to compatibility url" ),
    'true';
authorize_commland(Context, _, [{<<"commland">>, _Nouns}]) ->
    {'stop', cb_context:add_system_error('forbidden', Context)};
authorize_commland(_Context, _Verb, _Nouns) ->
    'false'.

-spec authenticate(cb_context:context(), path_token()) ->
          {'true', cb_context:context()} |
          'false'.
authenticate(Context, ?COMPAT) ->
    authenticate_commland(Context, cb_context:req_verb(Context), cb_context:req_nouns(Context)).

-spec authenticate_commland(cb_context:context(), http_method(), req_nouns()) ->
          {'true', cb_context:context()} |
          'false'.
authenticate_commland(Context, ?HTTP_GET, ?COMPAT_NOUNS) ->
    {'true', Context};
authenticate_commland(_Context, _, _Nouns) ->
    'false'.

%%------------------------------------------------------------------------------
%% @doc This function determines if the provided list of Nouns are valid.
%% Failure here returns `404 Not Found'.
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists(path_token()) -> 'true'.
resource_exists(_) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc This function determines if the parameters and content are correct
%% for this request
%%
%% Failure here returns 400.
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ?COMPAT) ->
    validate_commland(Context, cb_context:req_verb(Context)).

-spec validate_commland(cb_context:context(), http_method()) -> cb_context:context().
validate_commland(Context, ?HTTP_GET) ->
    case cb_context:req_nouns(Context) of
        ?COMPAT_NOUNS -> compatibility(Context);
        _Nouns ->
            lager:debug("invalid request ~p", [_Nouns]),
            Context
    end.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Display the current version of kazoo
%% @end
%%---------------------------`---------------------------------------------------
-spec compatibility(cb_context:context()) -> cb_context:context().
compatibility(Context) ->
    Url = get_redirect_url(),
    lager:debug("returning upgrade url ~p", [Url]),
    crossbar_util:response(kz_json:from_list([{<<"auto_updater_url">>, Url}]), Context).

-spec get_redirect_url() -> kz_term:ne_binary().
get_redirect_url() ->
    kz_binary:join([?BASE_URL, get_hashed_version()], <<"/">>).

-spec get_hashed_version() -> kz_term:ne_binary().
get_hashed_version() ->
    get_hashed_version(binary:split(kapps_util:kazoo_version(), ?DOT, ['global'])).

-spec get_hashed_version(list()) -> kz_term:ne_binary().
get_hashed_version([Major, Minor|_]) ->
    lager:debug("compatible version found is ~s~s~s", [Major, ?DOT, Minor]),
    to_hash(to_dotted_version(Major, Minor));
get_hashed_version(_) ->
    lager:debug("no compatible version found using base ~s", [?BASE_VERSION]),
    to_hash(?BASE_VERSION).

-spec to_dotted_version(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
to_dotted_version(Major, Minor) ->
    <<Major/binary, ?DOT/binary, Minor/binary>>.

-spec to_hash(kz_term:ne_binary()) -> kz_term:ne_binary().
to_hash(Version) ->
    to_hash(Version, ?BASE_SALT).

to_hash(Version, Salt) ->
    kz_binary:md5(<<Version/binary, Salt/binary>>).
