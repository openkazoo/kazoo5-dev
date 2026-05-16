%%% @doc When testing the crossbar api, we need to verify many parts of the
%%% response. This acts as a place to build up and evaluate expectations.
-module(pqc_cb_expect).

-export([expect/3
        ,run/2
        ,code/1
        ,codes/1
        ,header/2
        ,headers/1
        ,codes_and_headers/2
        ,body_is/1
        ,body_matches/1
        ]).

-type response_code() :: 200..600.

-type expected_codes() :: [response_code()].
-type expected_header_match() :: string() | {'match', string()}.
-type expected_header() :: {string(), expected_header_match()}.
-type expected_headers() :: [expected_header()].

-type log_message() :: {'error', kz_term:ne_binary()} | {'error', kz_term:ne_binary(), [any()]}.
-type body_expect() :: fun((binary()) -> 'ok' | log_message()).

-record(expectation, {codes = [] :: expected_codes(),
                      headers = [] :: expected_headers(),
                      body = 'undefined' :: 'undefined' | body_expect()
                     }).

-type expectation() :: #expectation{}.
-type expectations() :: [expectation()].

-export_type([expectation/0
             ,expectations/0
             ]).

%% @doc Create an expectation to be used in `run/2' later. The expectation is
%% met if the codes, headers, body all pass expection.
%% * Codes are met if the `Codes' is a non-empty list and the http result code
%%   matches at least 1.
%% * Headers are met if `Headers' is a non-empty list and _all_ the listed
%%   headers pass.
%% * Body is met if `Body' is a uninary function that returns 'ok' when called
%%   with the http result's body.
-spec expect(expected_codes(), expected_headers(), 'undefined' | body_expect()) -> expectation().
expect(Codes, Headers, Body) ->
    #expectation{codes = Codes
                ,headers = Headers
                ,body = Body
                }.

%% @doc Run the expectations against an http result. If _any_ expectation passes,
%% the run is successful. See {@link expect/3} for how an expectation passes.
-spec run(expectations(), kz_http:ret()) -> boolean().
run([_|_]=Expectations, {'ok', ActualCode, RespHeaders, RespBody}) ->
    lists:any(fun(Expectation) ->
                      expectation_met(Expectation, ActualCode, RespHeaders, RespBody)
              end
             ,Expectations
             );
run(_Expectations, Error) ->
    lager:warning("result of request was not successful: ~p", [Error]),
    'false'.

expectation_met(Expecation, ActualCode, RespHeaders, RespBody) ->
    and_then([fun() ->
                      codes_met(Expecation, ActualCode)
              end
             ,fun() ->
                      headers_met(Expecation, RespHeaders)
              end
             ,fun() ->
                      body_met(Expecation, RespBody)
              end
             ]).

%% @doc a dead simple 'and then' monad(ish). Ends at the first 'false'.
-spec and_then([fun(() -> boolean())]) -> boolean().
and_then(Funs) ->
    and_then(Funs, 'true').

and_then([], Result) -> Result;
and_then(_, 'false') -> 'false';
and_then([Fun | Tail], 'true') -> and_then(Tail, Fun()).

codes_met(#expectation{codes = []}, _) -> 'true';
codes_met(#expectation{codes = Codes}, Code) ->
    lists:member(Code, Codes).

headers_met(#expectation{headers = []}, _Headers) -> 'true';
headers_met(#expectation{headers = ExpectedHeaders}, Headers) ->
    lists:all(fun(ExpectedHeader) ->
                      header_met(ExpectedHeader, Headers)
              end
             ,ExpectedHeaders
             ).

header_met({ExpectedHeader, {'match', Match}}, RespHeaders) ->
    RespHeaderValue = kz_http_util:get_resp_header(ExpectedHeader, RespHeaders),
    case re:run(RespHeaderValue, Match) of
        {'match', _} -> 'true';
        'nomatch' ->
            lager:info("~p:~p ~/~ ~p", [ExpectedHeader, Match, RespHeaderValue]),
            'false'
    end;
header_met({ExpectedHeader, ExpectedValue}, RespHeaders) ->
    case kz_http_util:get_resp_header(ExpectedHeader, RespHeaders) of
        ExpectedValue -> 'true';
        _RespHeaderValue ->
            lager:info("~p:~p =/= ~p", [ExpectedHeader, ExpectedValue, _RespHeaderValue]),
            'false'
    end.

body_met(#expectation{body = 'undefined'}, _) -> 'true';
body_met(#expectation{body = Fun}, Body) ->
    case Fun(Body) of
        'ok' -> 'true';
        {'error', ErrMessage, Args} ->
            log_body_fail(Body, ErrMessage, Args);
        {'error', ErrMessage} ->
            log_body_fail(Body, ErrMessage, [])
    end.

log_body_fail(Body, ErrMessage, Args) ->
    BaseMessage = "body did not pass expectation.~n"
        "    Body: ~p~n",
    FullMessage = BaseMessage ++ ErrMessage,
    FullArgs = [Body | Args],
    lager:warning(FullMessage, FullArgs),
    'false'.

%% @doc Create an expectation where only a single code is valid.
-spec code(response_code()) -> expectation().
code(Code) ->
    codes([Code]).

%% @doc Any of the given codes will pass expectation.
-spec codes(expected_codes()) -> expectation().
codes(Codes) ->
    expect(Codes, [], 'undefined').

%% @doc Create an expectation for only a specific header.
-spec header(string(), expected_header_match()) -> expectation().
header(HeaderKey, HeaderVal) ->
    headers([{HeaderKey, HeaderVal}]).

%% @doc Create an expectation where the given headers must match, but nothing
%% else is checked.
-spec headers(expected_headers()) -> expectation().
headers(Headers) ->
    expect([], Headers, 'undefined').

%% @doc Create an expectation with codes and headers. Any code matching, and
%% all headers matching, is a pass.
-spec codes_and_headers(expected_codes(), expected_headers()) -> expectation().
codes_and_headers(Codes, Headers) ->
    expect(Codes, Headers, 'undefined').

%% @doc Create a body expectation where a pass is if there's an exact match.
%% The result of this should be passed in as the 3rd arg of {@link expect/3}.
-spec body_is('undefined' | string()) -> body_expect().
body_is(Expectation) ->
    fun(Got) ->
            body_is(Expectation, Got)
    end.

body_is(Expectation, Expectation) ->
    'true';
body_is(Expectation, Got) ->
    Message = "Body did not match expectation.~n"
        "    Expectation: ~s~n"
        "    Got: ~s",
    Args = [Expectation, Got],
    {Message, Args}.

%% @doc Create a body expectation where a pass is if the given regex finds a match
%% in the body. The result of this should be passed in as the 3rd arg of
%% {@link expect/3}.
-spec body_matches(re:regex()) -> body_expect().
body_matches(RegEx) ->
    fun(Got) ->
            body_matches(RegEx, Got)
    end.

body_matches(_, 'undefined') ->
    {"body was completely missing.", []};
body_matches(RegEx, Got) ->
    case re:run(Got, RegEx) of
        'nomatch' ->
            Message = "Body did not match expectation regex.~n"
                "    RegEx: ~s~n"
                "    Got: ~s",
            Args = [RegEx, Got],
            {Message, Args};
        _ ->
            'true'
    end.
