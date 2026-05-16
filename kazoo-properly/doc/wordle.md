# Wordle

Play wordle from the Erlang shell!

```erlang
%% create your API (adjust account/username/password as appropriate)
f(API), API = pqc_cb_api:authenticate(<<"admin">>, <<"admin">>, <<"admin">>).

%% fetch today's 5-letter word
io:format("~s~n", [pqc_cb_wordle:fetch(API, 5)]).
{"timestamp":"2022-02-18T00:29:57Z","node":"qg1oaL-5Urqhl1DWLVLFxA","request_id":"981a7bf04c-63812363397169","tokens":{"consumed":0,"remaining":100},"auth_token":"{AUTH_TOKEN}","data":{"word_id":"2a22709e8e8763012df7fa1cc4eb8464","guesses":[]},"status":"success"}

%% Save the word ID
WordId = <<"2a22709e8e8763012df7fa1cc4eb8464">>.

%% current status
io:format("~s~n", [pqc_cb_wordle:status(API, WordId)]).
{"version":"handle-list-of-strings.0.1","timestamp":"2022-02-18T00:30:24Z","node":"qg1oaL-5Urqhl1DWLVLFxA","request_id":"981a7bf04c-63812363424861","tokens":{"consumed":0,"remaining":100},"auth_token":"{AUTH_TOKEN}","data":{"word_id":"582aa933e1dc4fde273f636c7b943bef","guesses":[]},"status":"success"}

%% Make a guess
io:format("~s~n", [pqc_cb_wordle:guess(API, WordId, <<"CRATE">>)]).
{"request_id":"981a7bf04c-63812363534318","tokens":{"consumed":0,"remaining":100},"auth_token":"{AUTH_TOKEN}","data":{"guess":"CRATE","timestamp":63812363534,"is_match":false,"match_output":[{"C":"black"},{"R":"yellow"},{"A":"black"},{"T":"green"},{"E":"black"}],"word_id":"582aa933e1dc4fde273f636c7b943bef"},"status":"success"}

%% guess history
io:format("~s~n", [pqc_cb_wordle:status(API, WordId)]).
{"request_id":"981a7bf04c-63812365301709","tokens":{"consumed":0,"remaining":100},"auth_token":"{AUTH_TOKEN}","data":{"word_id":"582aa933e1dc4fde273f636c7b943bef","guesses":[{"guess":"FIRTH","timestamp":63812364177,"is_match":true,"match_output":[{"F":"green"},{"I":"green"},{"R":"green"},{"T":"green"},{"H":"green"}]},{"guess":"SLATE","timestamp":63812363744,"is_match":false,"match_output":[{"S":"black"},{"L":"black"},{"A":"black"},{"T":"green"},{"E":"black"}]},{"guess":"CRATE","timestamp":63812363534,"is_match":false,"match_output":[{"C":"black"},{"R":"yellow"},{"A":"black"},{"T":"green"},{"E":"black"}]}]},"status":"success"}

```
