%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Module for Crossbar API implementing the wordle game
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_wordle).

-export([init/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,validate/1, validate/2
        ,post/2
        ]).

%% gen_server callbacks
-export([start_link/0
        ,init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_info/2
        ,terminate/2
        ,code_change/3
        ]).

%% useful helpers
-export([word_of_day/0, word_of_day/1
        ,make_attempt/3, attempts/2
        ,wordle/2
        ]).

-include_lib("crossbar/src/crossbar.hrl").

-define(CB_CONFIG_CAT, <<?CONFIG_CAT/binary, ".wordle">>).

%% We define the API endpoint name by the collection name. This
%% module's {COLLECTION} would be "skels" while the {RESOURCE}
%% provided would be "skel".
%%
%% A JSON schema should be added that matches the collection name (so
%% "{COLLECTION}.json" in this case). When `make ci-docs` is run from
%% the KAZOO root, an accessor module in core/kazoo_documents will be
%% created: `kzd_{COLLECTION}.erl`
%%
%% Two functions to add to the kzd module are `schema/0` and `type/0`
%% which return the name of the schema (generally {COLLECTION}) and
%% pvt_type (generally {RESOURCE}).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    Bindings = [{<<"*.allowed_methods.wordle">>, 'allowed_methods'}
               ,{<<"*.resource_exists.wordle">>, 'resource_exists'}
               ,{<<"*.validate.wordle">>, 'validate'}
               ,{<<"*.execute.post.wordle">>, 'post'}
               ],
    cb_modules_util:bind(?MODULE, Bindings),

    _ = start_server(),
    'ok'.

start_server() ->
    crossbar_module_sup:start_child(?MODULE).

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET]. % get today's wordle

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_WordId) ->
    %% get  - user's guesses for word
    %% post - user's next guess for current word
    [?HTTP_GET, ?HTTP_POST].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% For example:
%%
%% ```
%%    /skels => []
%%    /skels/foo => [<<"foo">>]
%%    /skels/foo/bar => [<<"foo">>, <<"bar">>]
%% '''
%% @end
%%------------------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(WordId) ->
    case get_word_by_id(WordId) of
        {'ok', _Date, _Wordle} -> 'true';
        _ -> 'false'
    end.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /skels might load a list of skel objects
%% /skels/123 might load the skel object 123
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_wordles(Context, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, WordId) ->
    validate_wordle(Context, WordId, cb_context:req_verb(Context)).

-spec validate_wordles(cb_context:context(), http_method()) -> cb_context:context().
validate_wordles(Context, ?HTTP_GET) ->
    get_wordle(Context, kz_term:to_integer(cb_context:req_value(Context, <<"word_size">>, 5))).

get_wordle(Context, WordSize) ->
    {'ok', WordId, _Wordle} = word_of_day(WordSize),
    lager:debug("word of day: ~s (~s)", [_Wordle, WordId]),
    validate_wordle(Context, WordId, ?HTTP_GET).

guesses_to_json(Guesses) ->
    [guess_to_json(Guess) || Guess <- Guesses].

guess_to_json({Guess, Timestamp, {IsMatch, Output}}) ->
    kz_json:from_list([{<<"guess">>, Guess}
                      ,{<<"timestamp">>, Timestamp}
                      ,{<<"is_match">>, IsMatch}
                      ,{<<"match_output">>, colors_to_json(Output)}
                      ]).

colors_to_json(Colors) ->
    [kz_json:from_list([{Char, Color}]) || {Char, Color} <- Colors].

-spec validate_wordle(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_wordle(Context, WordId, ?HTTP_GET) ->
    Guesses = attempts(cb_context:auth_user_id(Context), WordId),

    lager:info("guesses so far: ~p", [Guesses]),
    crossbar_util:response(kz_json:from_list([{<<"word_id">>, WordId}
                                             ,{<<"guesses">>, guesses_to_json(Guesses)}
                                             ])
                          ,Context
                          );
validate_wordle(Context, WordId, ?HTTP_POST) ->
    Guess = cb_context:req_value(Context, <<"guess">>),
    case make_attempt(cb_context:auth_user_id(Context), WordId, Guess) of
        {'error', 'not_found'} ->
            lager:info("wordle ~s not found for today", [WordId]),
            crossbar_util:response_bad_identifier(WordId, Context);
        _ ->
            [Latest | _] = attempts(cb_context:auth_user_id(Context), WordId),

            lager:info("latest guess: ~p", [Latest]),
            crossbar_util:response(kz_json:set_value(<<"word_id">>, WordId, guess_to_json(Latest))
                                  ,Context
                                  )
    end.

-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, _WordId) ->
    cb_context:set_resp_status(Context, 'success').

-spec wordle(kz_term:ne_binary(), kz_term:ne_binary()) -> {boolean(), kz_term:proplist()}.
wordle(Wordle, Guess) ->
    Pos = lists:seq(1, byte_size(Wordle)),
    Ws = lists:zip(binary_to_list(Wordle), Pos),
    Gs = lists:zip(binary_to_list(Guess), Pos),

    match_wordle(#{wordle => Ws
                  ,guess => Gs
                  ,result => [{'undefined', P} || P <- Pos]
                  ,pos => Pos
                  }
                ).

match_wordle(Game) ->
    GreenGame = match_green(Game),
    YellowGame = match_yellow(GreenGame),
    result(YellowGame).

result(#{result := Result
        ,guess := Guess
        }
      ) ->
    result(Result, Guess, {'true', []}).

result([], [], {Bool, Output}) -> {Bool, lists:reverse(Output)};
result([{'green', Pos} | Rs], [{G, Pos} | Gs], {Bool, Output}) ->
    result(Rs, Gs, {Bool, [green(G) | Output]});
result([{'yellow', Pos} | Rs], [{G, Pos} | Gs], {_, Output}) ->
    result(Rs, Gs, {'false', [yellow(G) | Output]});
result([{_, Pos} | Rs], [{G, Pos} | Gs], {_, Output}) ->
    result(Rs, Gs, {'false', [black(G) | Output]}).

%% matches all characters in the correct position
match_green(#{pos := Pos}=Game) ->
    lists:foldl(fun match_green_fold/2, Game, Pos).

-spec match_green_fold(integer(), map()) -> map().
match_green_fold(Pos, #{wordle := Wordle
                       ,guess := Guess
                       ,result := Result
                       }=Game
                ) ->
    %% compare chars at same position for equality
    case lists:keyfind(Pos, 2, Wordle) =:= lists:keyfind(Pos, 2, Guess) of
        'true' ->
            Game#{result => lists:keyreplace(Pos, 2, Result, {'green', Pos})};
        'false' ->
            Game
    end.

%% marks any correct character, but in the wrong position
match_yellow(#{result := Result}=Game) ->
    lists:foldl(fun match_yellow_fold/2, Game, Result).

match_yellow_fold({'green', _Pos}, Game) -> Game;
match_yellow_fold({'undefined', Pos}
                 ,#{wordle := Wordle
                   ,guess := Guess
                   ,result := Result
                   }=Game
                 ) ->
    {GuessChar, Pos} = lists:keyfind(Pos, 2, Guess),
    case [WordlePos || {WordleChar, WordlePos} <- Wordle,
                       %% wordle has the guess character
                       WordleChar =:= GuessChar,
                       %% wordle char isn't tagged yet
                       {Color, _WPos} <- [lists:keyfind(WordlePos, 2, Result)],
                       Color =/= 'green'
         ]
    of
        [] ->
            %% no char from guess in wordle, mark black
            Game#{result => lists:keyreplace(Pos, 2, Result, {'black', Pos})};
        [_WordlePos | _] ->
            %% tag position as yellow in result
            Game#{result => lists:keyreplace(Pos, 2, Result, {'yellow', Pos})}
    end.

green(G) ->
    {<<G>>, <<"green">>}.

yellow(G) ->
    {<<G>>, <<"yellow">>}.

black(G) ->
    {<<G>>, <<"black">>}.

%% Server functionality
-record(word, {id :: kz_term:ne_binary()
              ,word :: kz_term:ne_binary() | '$2'
              ,date :: kz_time:date() | '$1'
              ,word_size :: pos_integer() | '_'
              }).

-type guess() :: {kz_term:ne_binary(), kz_time:gregorian_seconds(), {boolean(), kz_term:proplist()}}.
-type guesses() :: [guess()].

-record(attempt, {id :: {kz_term:ne_binary(), kz_term:ne_binary()} % {word_id, auth_user_id}
                 ,auth_user_id :: kz_term:ne_binary()
                 ,word_id :: kz_term:ne_binary()
                 ,guesses = [] :: guesses() % [{guess, timestamp, result}]
                 }).
-type attempt() :: #attempt{}.

-define(ETS_WORDS, 'wordle_words').
-define(ETS_ATTEMPTS, 'wordle_attempts').

-spec start_link() -> kz_types:startlink_ret().
start_link() ->
    gen_server:start_link({'local', ?MODULE}, ?MODULE, [], []).

-spec attempts(kz_term:ne_binary(), kz_term:ne_binary()) -> guesses().
attempts(UserId, WordId) ->
    case ets:lookup(?ETS_ATTEMPTS, {WordId, UserId}) of
        [] -> [];
        [#attempt{guesses=Guesses}] -> Guesses
    end.

-spec make_attempt(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          {boolean(), kz_term:proplist()} |
          {'error', 'not_found'}.
make_attempt(UserId, WordId, Guess) ->
    Today = erlang:date(),
    case get_word_by_id(WordId) of
        {'ok', Today, Wordle} ->
            maybe_make_attempt(UserId, WordId, kz_term:to_upper_binary(Guess), Wordle);
        {'ok', _OtherDay, _Wordle} ->
            {'error', 'not_found'};
        {'error', 'not_found'} ->
            {'error', 'not_found'}
    end.

-spec get_word_by_id(kz_term:ne_binary()) ->
          {'ok', kz_time:date(), kz_term:ne_binary()} |
          {'error', 'not_found'}.
get_word_by_id(WordId) ->
    case ets:match(?ETS_WORDS, #word{id=WordId, date='$1', word='$2', _='_'}) of
        [[Date, Wordle]] ->
            {'ok', Date, Wordle};
        _ -> {'error', 'not_found'}
    end.

-spec get_attempt(kz_term:ne_binary(), kz_term:ne_binary()) ->
          attempt() | 'undefined'.
get_attempt(UserId, WordId) ->
    case ets:lookup(?ETS_ATTEMPTS, {WordId, UserId}) of
        [] -> 'undefined';
        [#attempt{}=Attempt] -> Attempt
    end.

-spec maybe_make_attempt(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          {boolean(), kz_term:proplist()}.
maybe_make_attempt(UserId, WordId, Guess, Wordle) ->
    Result = wordle(Wordle, Guess),
    lager:debug("w: ~s g: ~s", [Wordle, Guess]),
    case get_attempt(UserId, WordId) of
        'undefined' ->
            'true' = ets:insert_new(?ETS_ATTEMPTS
                                   ,#attempt{id={WordId, UserId}
                                            ,auth_user_id=UserId
                                            ,word_id=WordId
                                            ,guesses=[{Guess, kz_time:now_s(), Result}]
                                            }
                                   );
        #attempt{guesses=Guesses}=Attempt ->
            'true' = ets:insert(?ETS_ATTEMPTS
                               ,Attempt#attempt{guesses=[{Guess, kz_time:now_s(), Result} | Guesses]}
                               )
    end,
    Result.

%% @doc {ok, WordId, Wordle}
-spec word_of_day() ->
          {'ok', kz_term:ne_binary(), kz_term:ne_binary()} |
          {'error', 'not_found'}.
word_of_day() ->
    word_of_day(5).

-spec word_of_day(pos_integer()) ->
          {'ok', kz_term:ne_binary(), kz_term:ne_binary()} |
          {'error', 'not_found'}.
word_of_day(WordSize) when is_integer(WordSize), WordSize > 0 ->
    word_of_day(WordSize, erlang:date()).

word_of_day(WordSize, Date) ->
    word_of_day_by_size(WordSize, ets:lookup(?ETS_WORDS, Date)).

word_of_day_by_size(_WordSize, []) -> {'error', 'not_found'};
word_of_day_by_size(WordSize, [#word{word_size=WordSize, word=Word, id=Id} | _]) ->
    {'ok', Id, Word};
word_of_day_by_size(WordSize, [#word{} | Words]) ->
    word_of_day_by_size(WordSize, Words).

-record(state, {words :: ets:tid()
               ,attempts :: ets:tid()
               }).
-type state() :: #state{}.

-spec init(any()) -> {'ok', state()}.
init(_) ->
    WordsETS = ets:new(?ETS_WORDS, [{'keypos', #word.date}
                                   ,'named_table'
                                   ,'bag'
                                   ,'protected'
                                   ,{'read_concurrency', 'true'}
                                   ]
                      ),
    lager:info("started words ETS: ~p", [WordsETS]),
    AttemptsETS = ets:new(?ETS_ATTEMPTS, [{'keypos', #attempt.id}
                                         ,'named_table'
                                         ,'set'
                                         ,'public'
                                         ]
                         ),
    lager:info("started attempts ETS: ~p", [AttemptsETS]),

    gen_server:cast(self(), 'init_words'),

    {'ok', #state{words = WordsETS
                 ,attempts = AttemptsETS
                 }}.

-spec handle_call(any(), kz_term:pid_ref(), state()) -> kz_types:handle_call_ret_state(state()).
handle_call(_Req, _From, State) ->
    {'noreply', State}.

-spec handle_cast(any(), state()) -> kz_types:handle_cast_ret_state(state()).
handle_cast('init_words', #state{words=WordsETS}=State) ->
    init_words(WordsETS),
    {'noreply', State};
handle_cast(_Req, State) ->
    {'noreply', State}.

-spec handle_info(any(), state()) -> kz_types:handle_info_ret_state(state()).
handle_info(_Req, State) ->
    {'noreply', State}.

-spec terminate(any(), state()) -> 'ok'.
terminate(_Reason, _State) ->
    'ok'.

-spec code_change(any(), state(), any()) -> {'ok', state()}.
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.

init_words(ETS) ->
    init_words(ETS, kapps_config:get_ne_binary(?CB_CONFIG_CAT
                                              ,<<"path_to_words">>
                                              ,<<"/usr/share/dict/words">>
                                              )
              ).

init_words(ETS, <<Path/binary>>) ->
    case file:read_file(Path) of
        {'ok', Words} ->
            init_words(ETS, #{}, kz_term:shuffle_list(binary:split(Words, <<"\n">>, ['global'])));
        {'error', _E} ->
            lager:warning("failed to read ~s: ~p", [Path, _E])
    end.

init_words(_ETS, _WordDates, []) -> 'ok';
init_words(_ETS, _WordDates, [<<>>]) -> 'ok';
init_words(ETS, WordDates, [Word | Words]) ->
    WordDates1 = init_word(ETS, WordDates, Word),
    init_words(ETS, WordDates1, Words).

init_word(ETS, WordDates, Word) ->
    case binary:match(Word, <<"'">>) of
        {_, _} -> WordDates; % skip words with apostrophes
        'nomatch' ->
            init_word(ETS, WordDates, Word, byte_size(Word))
    end.

init_word(ETS, WordDates, Word, WordSize) ->
    Date = case maps:get(WordSize, WordDates, 'undefined') of
               'undefined' -> erlang:date();
               {Y,M,D} -> kz_date:normalize({Y, M, D+1})
           end,

    'true' = ets:insert(ETS, #word{date=Date
                                  ,word=kz_term:to_upper_binary(Word)
                                  ,word_size=WordSize
                                  ,id=word_id(Date, Word)
                                  }),

    WordDates#{WordSize => Date}.

word_id({Y, M, D}, Word) ->
    Bin = iolist_to_binary([io_lib:format("~p.~p.~p", [Y, M, D]), Word]),
    kz_binary:md5(Bin).
