-module(my_status_node).
-export([start/0]).

-define(YB, "\e[103;30m").
-define(R,  "\e[0m").

start() ->
    io:format("~n"),
    io:format(?YB ++ "  +----------------------------+  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  |  >>> STATUS NODE <<<       |  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  |  generic unix sensor node  |  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  +----------------------------+  " ++ ?R ++ "~n~n"),
    {ok, _} = my_status_node_sup:start_link(),
    receive after infinity -> ok end.
