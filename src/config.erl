-module(config).

-export([get/0]).

get() ->
    #{
        host => {192, 168, 34, 102},
        port => 4000 
    }.
