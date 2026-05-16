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
-module(cb_wordle_tests).

-include_lib("eunit/include/eunit.hrl").

-spec wordle_test_() -> any().
wordle_test_() ->
    Tests = [{<<"WORDLE">>, <<"WARDEN">>, {'false', [{<<"W">>, <<"green">>}
                                                    ,{<<"A">>, <<"black">>}
                                                    ,{<<"R">>, <<"green">>}
                                                    ,{<<"D">>, <<"green">>}
                                                    ,{<<"E">>, <<"yellow">>}
                                                    ,{<<"N">>, <<"black">>}
                                                    ]
                                          }
             }
            ,{<<"MOTOR">>, <<"MOTER">>, {'false', [{<<"M">>, <<"green">>}
                                                  ,{<<"O">>, <<"green">>}
                                                  ,{<<"T">>, <<"green">>}
                                                  ,{<<"E">>, <<"black">>}
                                                  ,{<<"R">>, <<"green">>}
                                                  ]
                                        }
             }
            ,{<<"MOTEO">>, <<"MOORO">>, {'false', [{<<"M">>, <<"green">>}
                                                  ,{<<"O">>, <<"green">>}
                                                  ,{<<"O">>, <<"black">>}
                                                  ,{<<"R">>, <<"black">>}
                                                  ,{<<"O">>, <<"green">>}
                                                  ]
                                        }
             }

            ,{<<"HACKS">>, <<"BAKER">>, {'false', [{<<"B">>, <<"black">>}
                                                  ,{<<"A">>, <<"green">>}
                                                  ,{<<"K">>, <<"yellow">>}
                                                  ,{<<"E">>, <<"black">>}
                                                  ,{<<"R">>, <<"black">>}
                                                  ]
                                        }
             }
            ,{<<"HACKS">>, <<"TANKS">>, {'false', [{<<"T">>, <<"black">>}
                                                  ,{<<"A">>, <<"green">>}
                                                  ,{<<"N">>, <<"black">>}
                                                  ,{<<"K">>, <<"green">>}
                                                  ,{<<"S">>, <<"green">>}
                                                  ]
                                        }
             }
            ,{<<"HACKS">>, <<"HACKS">>, {'true', [{<<"H">>, <<"green">>}
                                                 ,{<<"A">>, <<"green">>}
                                                 ,{<<"C">>, <<"green">>}
                                                 ,{<<"K">>, <<"green">>}
                                                 ,{<<"S">>, <<"green">>}
                                                 ]
                                        }
             }

            ,{<<"SHIRE">>, <<"ADIEU">>, {'false', [{<<"A">>, <<"black">>}
                                                  ,{<<"D">>, <<"black">>}
                                                  ,{<<"I">>, <<"green">>}
                                                  ,{<<"E">>, <<"yellow">>}
                                                  ,{<<"U">>, <<"black">>}
                                                  ]
                                        }
             }
            ,{<<"SHIRE">>, <<"SHIPS">>, {'false', [{<<"S">>, <<"green">>}
                                                  ,{<<"H">>, <<"green">>}
                                                  ,{<<"I">>, <<"green">>}
                                                  ,{<<"P">>, <<"black">>}
                                                  ,{<<"S">>, <<"black">>}
                                                  ]
                                        }
             }
            ,{<<"SHIRE">>, <<"SHIVE">>, {'false', [{<<"S">>, <<"green">>}
                                                  ,{<<"H">>, <<"green">>}
                                                  ,{<<"I">>, <<"green">>}
                                                  ,{<<"V">>, <<"black">>}
                                                  ,{<<"E">>, <<"green">>}
                                                  ]
                                        }
             }
            ,{<<"SHIRE">>, <<"SHISE">>, {'false', [{<<"S">>, <<"green">>}
                                                  ,{<<"H">>, <<"green">>}
                                                  ,{<<"I">>, <<"green">>}
                                                  ,{<<"S">>, <<"black">>}
                                                  ,{<<"E">>, <<"green">>}
                                                  ]
                                        }
             }
            ,{<<"SHIRE">>, <<"SHIRE">>, {'true', [{<<"S">>, <<"green">>}
                                                 ,{<<"H">>, <<"green">>}
                                                 ,{<<"I">>, <<"green">>}
                                                 ,{<<"R">>, <<"green">>}
                                                 ,{<<"E">>, <<"green">>}
                                                 ]
                                        }
             }

            ,{<<"RENTS">>, <<"CRATE">>, {'false', [{<<"C">>, <<"black">>}
                                                  ,{<<"R">>, <<"yellow">>}
                                                  ,{<<"A">>, <<"black">>}
                                                  ,{<<"T">>, <<"green">>}
                                                  ,{<<"E">>, <<"yellow">>}
                                                  ]
                                        }
             }
            ,{<<"SHIPS">>, <<"HSSIP">>, {'false', [{<<"H">>, <<"yellow">>}
                                                  ,{<<"S">>, <<"yellow">>}
                                                  ,{<<"S">>, <<"yellow">>}
                                                  ,{<<"I">>, <<"yellow">>}
                                                  ,{<<"P">>, <<"yellow">>}
                                                  ]
                                        }
             }
            ,{<<"SHIPS">>, <<"HIPSS">>, {'false', [{<<"H">>, <<"yellow">>}
                                                  ,{<<"I">>, <<"yellow">>}
                                                  ,{<<"P">>, <<"yellow">>}
                                                  ,{<<"S">>, <<"yellow">>}
                                                  ,{<<"S">>, <<"green">>}
                                                  ]
                                        }
             }
            ],
    [?_assertEqual(Expected, cb_wordle:wordle(Wordle, Guess))
     || {Wordle, Guess, Expected} <- Tests
    ].
