# Wordle

## About Wordle

Wordle is a daily game where players guess the word of the day (5-letter words by default) and receive hints as to what letters are in the right place, present but in the wrong spot, or not present at all.

This module is a playful attempt to add the ability to play Wordle from the Crossbar API. All guesses are correlated with the user ID of the auth token used.

At the moment, there is no restriction on how many guesses you may make for each days' wordle. Once the date changes (UTC timezone), the wordle can no longer receive guesses; the new wordle will be active.

## Schema



## Fetch the word of the day

> GET /v2/wordle

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/wordle
```

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": {
    "guesses": []
    ,"word_id": "{WORD_ID}"
  },
  "node": "{NODE}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "timestamp": "{TIMESTAMP}"
}

```

By default, 5-letter words are chosen. Include `?word_size=8` to get the 8-letter daily wordle.

## Fetch your status on a particular wordle

> GET /v2/wordle/{WORD_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/wordle/{WORD_ID}
```

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": {
    "guesses": [
      {
        "guess": "SLATE",
        "is_match": false,
        "match_output": [
          {
            "S": "black"
          },
          {
            "L": "black"
          },
          {
            "A": "black"
          },
          {
            "T": "green"
          },
          {
            "E": "black"
          }
        ],
        "timestamp": 63812363744
      },
      {
        "guess": "CRATE",
        "is_match": false,
        "match_output": [
          {
            "C": "black"
          },
          {
            "R": "yellow"
          },
          {
            "A": "black"
          },
          {
            "T": "green"
          },
          {
            "E": "black"
          }
        ],
        "timestamp": 63812363534
      }
    ],
    "word_id": "{WORD_ID}"
  },
  "node": "{NODE}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "timestamp": "{TIMESTAMP}"
}

```

### Guess history

Once you've made some guesses, the status

## Make a guess

> POST /v2/wordle/{WORD_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/wordle/{WORD_ID}
    -d '{"data":{"guess":"{GUESS}"}}'
```

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": {
    "guess": "CRATE",
    "is_match": false,
    "match_output": [
      {
        "C": "black"
      },
      {
        "R": "yellow"
      },
      {
        "A": "black"
      },
      {
        "T": "green"
      },
      {
        "E": "black"
      }
    ],
    "timestamp": 63812363534,
    "word_id": "{WORD_ID}"
  },
  "node": "{NODE}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "timestamp": "{TIMESTAMP}"
}
```

`match_output` shows the colors associated with each character in the guess:

- `green`: The letter is in the correct place in the word
- `yellow`: The letter appears in the wordle but is in the wrong place in the guess
- `black`: The letter does not appear in the wordle

### Successful guess

```json
{
  "data": {
    "guess": "FIRTH",
    "is_match": true,
    "match_output": [
      {
        "F": "green"
      },
      {
        "I": "green"
      },
      {
        "R": "green"
      },
      {
        "T": "green"
      },
      {
        "H": "green"
      }
    ],
    "timestamp": 63812364177,
    "word_id": "{WORD_ID}"
  }
}
```

### Making a guess on a different day's wordle

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": [
    "{WORD_ID}"
  ],
  "error": "404",
  "message": "bad identifier",
  "node": "{NODE}",
  "request_id": "{REQUST_ID}",
  "status": "error",
  "timestamp": "{TIMESTAMP}"
}
```

## System administration

When Crossbar initializes the wordle module (`sup crossbar_maintenance start_module cb_wordle` to enable), the word dictionary is read and processed into an ETS table.

This means any restarts of Crossbar will clear both the words ETS table and the guesses ETS table, so users' progress is not persistent across invocations.

The word list is also shuffled after reading, so each restart will potentially put a different word for a given day.

Default wordlist is pulled from `/usr/share/dict/words` if present; adjust path accordingly in `system_config/crossbar.wordle`.
