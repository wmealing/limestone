-module(my_status_node).
-export([start/0]).

-define(YB,  "\e[103;30m").   %% bright yellow background, black text
-define(C,   "\e[1;36m").     %% bold cyan
-define(Y,   "\e[1;33m").     %% bold yellow
-define(R,   "\e[0m").        %% reset

-define(OK,  "\e[1;36m[x]\e[0m").   %% cyan  [x]
-define(WARN, "\e[1;33m[!]\e[0m").  %% yellow [!]
-define(INFO, "\e[1;36m[*]\e[0m").  %% cyan  [*]

-define(WIFI_CONFIG, [
    {ssid, <<"RED-LEADER-2">>},
    {psk,  <<"Somethinghard55!!">>},
    {dhcp_hostname, <<"firstpico">>}
]).

start() ->
    io:format("~n"),
    io:format(?YB ++ "  +----------------------------+  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  |  >>> STATUS NODE <<<       |  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  |  pico-w sensor reporter    |  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  +----------------------------+  " ++ ?R ++ "~n~n"),
    go().

go() ->
    loop().

loop() ->
    case network:wait_for_sta(?WIFI_CONFIG, 15000) of
        {ok, {Address, _Netmask, _Gateway}} ->
            io:format(?OK ++ " " ++ ?Y ++ "IP acquired:" ++ ?R ++ " ~p~n", [Address]),
            networking:post_sensor_data();
        {error, {already_started, _Pid}} ->
            io:format(?OK ++ " already connected, posting...~n"),
            networking:post_sensor_data();
        {error, Reason} ->
            io:format(?WARN ++ " network failed: ~p~n", [Reason])
    end,
    io:format(?INFO ++ ?C ++ " sleeping 60s..." ++ ?R ++ "~n"),
    receive after 1000 -> ok end,
    loop().
