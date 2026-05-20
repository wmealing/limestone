-module(networking).
-export([post_sensor_data/2]).

-define(PATH, "/api/collect/").
-define(HOST_SSL,  "cobalt-mellowed-blossom-1379.fly.dev").
-define(PORT_SSL,  443).
-define(HOST_TCP,  "cobalt-mellowed-blossom-1379.fly.dev").
-define(PORT_TCP,  80).

-define(RECV_TIMEOUT, 10000).

transport_connect(true, Host, Port) ->
    Options = [{verify, verify_none}, {server_name_indication, Host}, {active, false}],
    ssl:connect(Host, Port, Options);
transport_connect(false, Host, Port) ->
    gen_tcp:connect(Host, Port, [binary, {active, false}, {inet_backend, socket}]).

transport_send(true, Socket, Data)  -> ssl:send(Socket, Data);
transport_send(false, Socket, Data) -> gen_tcp:send(Socket, Data).

transport_recv(true, Socket)  -> ssl:recv(Socket, 0, ?RECV_TIMEOUT);
transport_recv(false, Socket) -> gen_tcp:recv(Socket, 0, ?RECV_TIMEOUT).

transport_close(true, Socket)  -> ssl:close(Socket);
transport_close(false, Socket) -> gen_tcp:close(Socket).

do_request(UseSsl, HostName, Port, Request) ->
    case transport_connect(UseSsl, HostName, Port) of
        {ok, Socket} ->
            io:format("Connected, sending request~n"),
            case transport_send(UseSsl, Socket, Request) of
                ok ->
                    io:format("Msg sent..~n"),
                    case recv_all(UseSsl, Socket) of
                        {ok, Response} ->
                            transport_close(UseSsl, Socket),
                            handle_response(Response);
                        {error, Reason} ->
                            transport_close(UseSsl, Socket),
                            {error, Reason}
                    end;
                {error, Reason} ->
                    transport_close(UseSsl, Socket),
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

post_sensor_data(Body, UseSsl) ->
    {HostName, Port} = case UseSsl of
        true  -> {?HOST_SSL, ?PORT_SSL};
        false -> {?HOST_TCP, ?PORT_TCP}
    end,

    ContentLength = integer_to_list(byte_size(Body)),

    io:format("PATH: ~p~n", [?PATH]),

    Request = iolist_to_binary([
        "POST ", ?PATH, " HTTP/1.0\r\n",
        "Host: ", HostName, "\r\n",
        "Content-Type: application/json\r\n",
        "Content-Length: ", ContentLength, "\r\n",
        "\r\n",
        Body
    ]),

    io:format("Connecting to ~p (ssl=~p)~n", [HostName, UseSsl]),

    try
        do_request(UseSsl, HostName, Port, Request)
    catch
        _:Reason ->
            io:format("Request failed: ~p~n", [Reason]),
            {error, Reason}
    end.


recv_all(UseSsl, Socket) ->
    recv_all(UseSsl, Socket, []).

recv_all(UseSsl, Socket, Acc) ->
    case transport_recv(UseSsl, Socket) of
        {ok, Data} ->
            recv_all(UseSsl, Socket, [Acc, Data]);
        {error, -30848} ->
            {ok, iolist_to_binary(Acc)};
        {error, closed} ->
            {ok, iolist_to_binary(Acc)};
        {error, Reason} ->
            io:format("RCV_ALL ERROR: ~p~n", [Reason]),
            {error, Reason}
    end.

handle_response(Response) ->
    case binary:split(Response, <<"\r\n\r\n">>) of
        [Headers, Body] ->
            [StatusLine | _] = binary:split(Headers, <<"\r\n">>),
            Code = parse_status_code(StatusLine),
            io:format("HTTP ~p~n", [Code]),
            io:format("Body: ~s~n", [Body]),
            {Code, Body};
        _ ->
            io:format("Unexpected response format~n"),
            {error, bad_response}
    end.

parse_status_code(StatusLine) ->
    case binary:split(StatusLine, <<" ">>, [global]) of
        [_, CodeBin | _] -> binary_to_integer(CodeBin);
        _ -> 0
    end.
