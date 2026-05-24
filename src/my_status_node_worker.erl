-module(my_status_node_worker).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(C,    "\e[1;36m").
-define(R,    "\e[0m").
-define(OK,   "\e[1;36m[x]\e[0m").
-define(INFO, "\e[1;36m[*]\e[0m").
-define(WARN, "\e[1;33m[~]\e[0m").
-define(ERR,  "\e[1;35m[!]\e[0m \e[105;30m FAIL \e[0m \e[1;35m::\e[0m \e[1;91m").

-define(QUEUE_MAX,  100).
-define(CONFIG_TTL, 86400).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% init returns immediately with defaults; config is fetched on first message.
init([]) ->
    Queue = load_queue(),
    StartJitter = erlang:phash2(erlang:monotonic_time(), 10001),
    erlang:send_after(StartJitter, self(), fetch_config),
    {ok, #{config          => config:defaults(),
           last_config_time => 0,
           queue            => Queue}}.

handle_info(fetch_config, State) ->
    Config = fetch_config(3),
    Now    = erlang:monotonic_time(second),
    self() ! tick,
    {noreply, State#{config => Config, last_config_time => Now}};

handle_info(tick, State) ->
    #{config := Config, last_config_time := LastConfigTime, queue := Queue} = State,
    Payload = add_timestamp(dummy_sensor:get_sensor()),
    io:format(?INFO ++ ?C ++ " Sending: ~s" ++ ?R ++ "~n", [Payload]),
    Queue2 = drain_queue(Config, Queue),
    Queue3 = case post_with_retry(Payload, maps:get(update_server, Config), 3) of
        ok    -> Queue2;
        error ->
            Q = enqueue(Queue2, Payload),
            save_queue(Q),
            Q
    end,
    erlang:send_after(maps:get(update_interval, Config) * 1000, self(), tick),
    Now = erlang:monotonic_time(second),
    {NewConfig, NewLastConfigTime} = case (Now - LastConfigTime) >= ?CONFIG_TTL of
        true  -> {fetch_config(3), Now};
        false -> {Config, LastConfigTime}
    end,
    {noreply, State#{config           => NewConfig,
                     last_config_time  => NewLastConfigTime,
                     queue             => Queue3}};

handle_info(_Msg, State) ->
    {noreply, State}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%% Config fetch — up to Retries attempts, falls back to defaults on exhaustion.
fetch_config(Retries) -> fetch_config(Retries, 5000).

fetch_config(0, _Delay) ->
    io:format(?WARN ++ " Config fetch failed, using defaults" ++ ?R ++ "~n"),
    config:defaults();
fetch_config(Retries, Delay) ->
    Url = maps:get(config_url, config:defaults()),
    io:format(?INFO ++ ?C ++ " Fetching config from ~s" ++ ?R ++ "~n", [Url]),
    case networking:get_config(Url) of
        {ok, Body} ->
            Config = config:parse(Body),
            io:format(?OK ++ ?C ++ " Config: interval=~ps server=~s" ++ ?R ++ "~n",
                [maps:get(update_interval, Config), maps:get(update_server, Config)]),
            Config;
        {error, Reason} ->
            io:format(?ERR ++ "Config error: ~p, retrying in ~pms..." ++ ?R ++ "~n",
                [Reason, Delay]),
            backoff_sleep(Delay),
            fetch_config(Retries - 1, Delay * 2)
    end.

%% POST with up to Retries attempts; returns ok | error.
post_with_retry(Payload, Url, Retries) -> post_with_retry(Payload, Url, Retries, 3000).

post_with_retry(_, _, 0, _Delay) ->
    io:format(?ERR ++ "Post failed after 3 retries, queuing payload" ++ ?R ++ "~n"),
    error;
post_with_retry(Payload, Url, Retries, Delay) ->
    case networking:post_sensor_data(Payload, Url) of
        {Status, _} when Status =:= 200; Status =:= 202 ->
            io:format(?OK ++ ?C ++ " Payload posted" ++ ?R ++ "~n"),
            ok;
        {error, Reason} ->
            io:format(?ERR ++ "Post error: ~p, retrying in ~pms..." ++ ?R ++ "~n",
                [Reason, Delay]),
            backoff_sleep(Delay),
            post_with_retry(Payload, Url, Retries - 1, Delay * 2);
        {Status, _} ->
            io:format(?ERR ++ "HTTP ~p, retrying in ~pms..." ++ ?R ++ "~n", [Status, Delay]),
            backoff_sleep(Delay),
            post_with_retry(Payload, Url, Retries - 1, Delay * 2)
    end.

%% Sleep for Delay ms plus a random jitter of up to half the delay.
backoff_sleep(Delay) ->
    Jitter = erlang:phash2(erlang:monotonic_time(), Delay div 2 + 1),
    timer:sleep(Delay + Jitter).

%% Drain queued payloads FIFO; stops on first failure.
drain_queue(_Config, []) -> [];
drain_queue(Config, [Item | Rest] = Queue) ->
    case networking:post_sensor_data(Item, maps:get(update_server, Config)) of
        {Status, _} when Status =:= 200; Status =:= 202 ->
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

%% Not yet implemented — AtomVM file I/O support is unconfirmed.
%% Intended to persist the queue across reboots once file support is available.
save_queue(_Queue) -> ok.

load_queue() -> [].
