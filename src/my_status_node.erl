-module(my_status_node).
-export([start/0]).

-define(YB,   "\e[103;30m").
-define(C,    "\e[1;36m").
-define(R,    "\e[0m").

-define(OK,   "\e[1;36m[x]\e[0m").
-define(INFO, "\e[1;36m[*]\e[0m").
-define(WARN, "\e[1;33m[~]\e[0m").
-define(ERR,  "\e[1;35m[!]\e[0m \e[105;30m FAIL \e[0m \e[1;35m::\e[0m \e[1;91m").

-define(QUEUE_MAX,  100).
-define(CONFIG_TTL, 86400).

start() ->
    io:format("~n"),
    io:format(?YB ++ "  +----------------------------+  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  |  >>> STATUS NODE <<<       |  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  |  generic unix sensor node  |  " ++ ?R ++ "~n"),
    io:format(?YB ++ "  +----------------------------+  " ++ ?R ++ "~n~n"),
    Queue  = load_queue(),
    Config = fetch_config(3),
    report_loop(Config, erlang:monotonic_time(second), Queue).

%% Config fetch — up to Retries attempts, falls back to defaults on exhaustion.
fetch_config(0) ->
    io:format(?WARN ++ " Config fetch failed, using defaults" ++ ?R ++ "~n"),
    config:defaults();

fetch_config(Retries) ->
    Url = maps:get(config_url, config:defaults()),
    io:format(?INFO ++ ?C ++ " Fetching config from ~s" ++ ?R ++ "~n", [Url]),
    case networking:get_config(Url) of
        {ok, Body} ->
            Config = config:parse(Body),
            io:format(?OK ++ ?C ++ " Config: interval=~ps server=~s" ++ ?R ++ "~n",
                [maps:get(update_interval, Config), maps:get(update_server, Config)]),
            Config;
        {error, Reason} ->
            io:format(?ERR ++ "Config error: ~p, retrying..." ++ ?R ++ "~n", [Reason]),
            timer:sleep(5000),
            fetch_config(Retries - 1)
    end.

%% Main loop — drain old queue, post current reading, sleep, re-fetch config daily.
report_loop(Config, LastConfigTime, Queue) ->
    Payload = add_timestamp(dummy_sensor:get_sensor()),
    Queue2  = drain_queue(Config, Queue),
    Queue3  = case post_with_retry(Payload, maps:get(update_server, Config), 3) of
        ok    -> Queue2;
        error ->
            Q = enqueue(Queue2, Payload),
            save_queue(Q),
            Q
    end,
    timer:sleep(maps:get(update_interval, Config) * 1000),
    Now = erlang:monotonic_time(second),
    case (Now - LastConfigTime) >= ?CONFIG_TTL of
        true  -> report_loop(fetch_config(3), Now, Queue3);
        false -> report_loop(Config, LastConfigTime, Queue3)
    end.

%% POST with up to Retries attempts; returns ok | error.
post_with_retry(_, _, 0) ->
    io:format(?ERR ++ "Post failed after 3 retries, queuing payload" ++ ?R ++ "~n"),
    error;
post_with_retry(Payload, Url, Retries) ->
    case networking:post_sensor_data(Payload, Url) of
        {200, _} ->
            io:format(?OK ++ ?C ++ " Payload posted" ++ ?R ++ "~n"),
            ok;
        {202, _} ->
            io:format(?OK ++ ?C ++ " Payload posted" ++ ?R ++ "~n"),
	    ok; 
        {error, Reason} ->
            io:format(?ERR ++ "Post error: ~p, retrying..." ++ ?R ++ "~n", [Reason]),
            timer:sleep(3000),
            post_with_retry(Payload, Url, Retries - 1);
        {Status, _} ->
            io:format(?ERR ++ "HTTP ~p, retrying..." ++ ?R ++ "~n", [Status]),
            timer:sleep(3000),
            post_with_retry(Payload, Url, Retries - 1)
    end.

%% Drain queued payloads FIFO; stops on first failure; saves after full drain.
drain_queue(_Config, []) -> [];
drain_queue(Config, [Item | Rest] = Queue) ->
    case networking:post_sensor_data(Item, maps:get(update_server, Config)) of
        {200, _} ->
            io:format(?OK ++ ?C ++ " Drained queued item" ++ ?R ++ "~n"),
            drain_queue(Config, Rest);
        _ ->
            io:format(?WARN ++ " Queue drain stalled, ~p item(s) remain" ++ ?R ++ "~n",
                [length(Queue)]),
            Queue
    end.

%% Append payload to queue, dropping oldest if at cap.
enqueue(Queue, Item) when length(Queue) >= ?QUEUE_MAX ->
    io:format(?WARN ++ " Queue full, dropping oldest item" ++ ?R ++ "~n"),
    [_ | Rest] = Queue,
    Rest ++ [Item];
enqueue(Queue, Item) ->
    Queue ++ [Item].

%% Inject "captured_at" epoch into a JSON object binary.
add_timestamp(JsonBin) ->
    Ts   = integer_to_binary(os:system_time(second)),
    Size = byte_size(JsonBin) - 1,
    <<Base:Size/binary, _>> = JsonBin,
    <<Base/binary, ",\"captured_at\":", Ts/binary, "}">>.

%% File I/O is not available in AtomVM Unix; queue is in-memory only.
save_queue(_Queue) -> ok.

load_queue() -> [].
