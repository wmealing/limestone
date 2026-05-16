-module(config).

-export([get/0]).

get() ->
    #{
      server => "cobalt-mellowed-blossom-1379.fly.dev",
      host => {192, 168, 34, 102},
      port => 4000
    }.
