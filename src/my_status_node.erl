-module(my_status_node).
-export([start/0]).

-define(YB,  "\e[103;30m").   %% bright yellow background, black text
-define(C,   "\e[1;36m").     %% bold cyan
-define(Y,   "\e[1;33m").     %% bold yellow
-define(R,   "\e[0m").        %% reset

-define(M,   "\e[1;35m").     %% bold magenta
-define(BR,  "\e[1;91m").    %% bright red

-define(OK,   "\e[1;36m[x]\e[0m").
-define(INFO, "\e[1;36m[*]\e[0m").
-define(ERR,  "\e[1;35m[!]\e[0m \e[105;30m NET-FAIL \e[0m \e[1;35m::\e[0m \e[1;91m").

-define(WIFI_CONFIG, [
    {ssid, <<"TEST-NETWORK">>},
    {psk,  <<"TEST-PASSWORD">>},
    {dhcp_hostname, <<"firstpico">>}
]).

start() ->
    UseSsl = false,
    io:format("~n"),
    io:format(?YB ++ "  +----------------------------+  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  |  >>> STATUS NODE <<<       |  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  |  pico-w sensor reporter    |  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  +----------------------------+  " ++ ?R ++ "~n~n"),
    case UseSsl of
        true -> ssl:start();
        false -> ok
    end,
    BootTime = erlang:monotonic_time(second),
    loop(BootTime, UseSsl).

wait_for_wifi() ->
    case network:wait_for_sta(?WIFI_CONFIG, 15000) of
        {ok, {_Address, _Netmask, _Gateway}} ->
           ok;
        {error, {already_started, _}} ->
            ok;
        {error, Reason} ->
            io:format(?ERR ++ "~p, retrying..." ++ ?R ++ "~n", [Reason]),
            timer:sleep(3000),
            wait_for_wifi()
    end.

loop(BootTime, UseSsl) ->
    io:format(?INFO ++ ?C ++ "- Starting Wifi" ++ ?R ++ "~n"),
    wait_for_wifi(),
    process_sensors(UseSsl),
    timer:sleep(20000),
    loop(BootTime, UseSsl).

process_sensors(UseSsl) ->
    DummyData = dummy_sensor:get_sensor(),
    networking:post_sensor_data(DummyData, UseSsl).
