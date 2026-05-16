%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_pushes_tests).

-include_lib("eunit/include/eunit.hrl").
-define(_x_assertEqual(Expected, Received), ?_assert(kz_json:are_equal(Expected, Received))).

to_push_payload_test_() ->
    Test = fun(JObj) -> cb_pushes:to_push_payload(JObj, []) end,
    Test2 = fun cb_pushes:to_push_payload/2,
    ToJSON = fun kz_json:from_list_recursive/1,

    TestJObj = ToJSON([{<<"apns">>
                       ,[{<<"alert">>
                         ,[{<<"subtitle_key">>, <<"subtitle">>}
                          ,{<<"subtitle_params">>, <<"params">>}
                          ]
                         }
                        ,{<<"thread_id">>, <<"so-me-id">>}
                        ,{<<"topic">>, <<"topic">>}
                        ]
                       }
                      ,{<<"fcm">>, <<"some value">>}
                      ]),
    ExplicitReplaces = [{<<"apns">>, <<"APNs">>}
                       ,{<<"subtitle">>, <<"Sub-Title">>}
                       ,{<<"fcm">>, <<"FCM">>}
                       ],

    [{"\"simple\" object"
     ,?_x_assertEqual(ToJSON([{<<"Three-Words-Key">>, <<"value">>}])
                     ,Test(ToJSON([{<<"three_words_key">>, <<"value">>}]))
                     )
     }
    ,{"single word key"
     ,?_x_assertEqual(ToJSON([{<<"Key">>, <<"value">>}])
                     ,Test(ToJSON([{<<"key">>, <<"value">>}]))
                     )
     }
    ,{"already normalized key"
     ,?_x_assertEqual(ToJSON([{<<"Normalized-Key">>, <<"value">>}])
                     ,Test(ToJSON([{<<"Normalized-Key">>, <<"value">>}]))
                     )
     }
    ,{"id -> ID: \"id\" should be all upper cased when present"
     ,[?_x_assertEqual(ToJSON([{<<"Some-ID">>, <<"value">>}])
                      ,Test(ToJSON([{<<"some_id">>, <<"value">>}]))
                      )
      ,?_x_assertEqual(ToJSON([{<<"ID">>, <<"unique-id">>}])
                      ,Test(ToJSON([{<<"id">>, <<"unique-id">>}]))
                      )
      ,?_x_assertEqual(ToJSON([{<<"ID">>, <<"other id">>}])
                      ,Test(ToJSON([{<<"_id">>, <<"other id">>}]))
                      )
       %% Even though an explicit replace for "id" is provided, the normalized value should be "ID".
      ,?_x_assertEqual(ToJSON([{<<"ID">>, <<"ran-dom-id">>}])
                      ,Test2(ToJSON([{<<"id">>, <<"ran-dom-id">>}])
                            ,[{'explicit_replaces', [{<<"id">>, <<"iD">>}]}]
                            )
                      )
      ]
     }
    ,{"empty nested object"
     ,?_x_assertEqual(ToJSON([{<<"Empty-Object-Value">>, kz_json:new()}])
                     ,Test(ToJSON([{<<"empty_object_value">>, kz_json:new()}]))
                     )
     }
     %% Only outer keys should be normalized.
    ,{"nested objects with convert_nested_keys=false"
     ,[{"no explicit_replaces list provided"
       ,?_x_assertEqual(ToJSON([{<<"Apns">> %% Normalized.
                                ,[{<<"alert">>
                                  ,[{<<"subtitle_key">>, <<"subtitle">>}
                                   ,{<<"subtitle_params">>, <<"params">>}
                                   ]
                                  }
                                 ,{<<"thread_id">>, <<"so-me-id">>}
                                 ,{<<"topic">>, <<"topic">>}
                                 ]
                                }
                               ,{<<"Fcm">>, <<"some value">>} %% Normalized.
                               ])
                       ,Test(TestJObj)
                       )
       }
      ,{"explicit_replaces list provided"
       ,?_x_assertEqual(ToJSON([{<<"APNs">> %% Normalized, explicitly replaced.
                                ,[{<<"alert">>
                                  ,[{<<"subtitle_key">>, <<"subtitle">>}
                                   ,{<<"subtitle_params">>, <<"params">>}
                                   ]
                                  }
                                 ,{<<"thread_id">>, <<"so-me-id">>}
                                 ,{<<"topic">>, <<"topic">>}
                                 ]
                                }
                               ,{<<"FCM">>, <<"some value">>} %% Normalized, explicitly replaced.
                               ])
                       ,Test2(TestJObj, [{'explicit_replaces', ExplicitReplaces}])
                       )
       }
      ]
     }
     %% All the keys should be normalized.
    ,{"nested objects with convert_nested_keys=true"
     ,[{"no explicit_replaces list provided"
       ,?_x_assertEqual(ToJSON([{<<"Apns">> %% Normalized.
                                ,[{<<"Alert">> %% Normalized.
                                  ,[{<<"Subtitle-Key">>, <<"subtitle">>} %% Normalized.
                                   ,{<<"Subtitle-Params">>, <<"params">>} %% Normalized.
                                   ]
                                  }
                                 ,{<<"Thread-ID">>, <<"so-me-id">>} %% Normalized.
                                 ,{<<"Topic">>, <<"topic">>} %% Normalized.
                                 ]
                                }
                               ,{<<"Fcm">>, <<"some value">>} %% Normalized.
                               ])
                       ,Test2(TestJObj, [{'convert_nested_keys', 'true'}])
                       )
       }
      ,{"explicit_replaces list provided"
       ,?_x_assertEqual(ToJSON([{<<"APNs">> %% Normalized, and explicitly replaced.
                                ,[{<<"Alert">> %% Normalized.
                                  ,[{<<"Sub-Title-Key">>, <<"subtitle">>} %% Normalized, and explicitly replaced.
                                   ,{<<"Sub-Title-Params">>, <<"params">>} %% Normalized, and explicitly replaced.
                                   ]
                                  }
                                 ,{<<"Thread-ID">>, <<"so-me-id">>} %% Normalized.
                                 ,{<<"Topic">>, <<"topic">>} %% Normalized.
                                 ]
                                }
                               ,{<<"FCM">>, <<"some value">>} %% Normalized, and explicitly replaced.
                               ])
                       ,Test2(TestJObj, [{'convert_nested_keys', 'true'}
                                        ,{'explicit_replaces', ExplicitReplaces}
                                        ])
                       )
       }
      ]
     }
    ].
