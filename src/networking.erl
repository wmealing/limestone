-module(networking).
-export([post_sensor_data/0]).

-define(HOST, {192, 168, 34, 102}).
-define(PORT, 4000).
-define(PATH, "/collect/").



post_sensor_data() ->
    Temp = 12, 
    Body = list_to_binary(io_lib:format("{\"sensor_id\": \"1234-1234\", \"value\": ~p}", [Temp])),
    ContentLength = integer_to_list(byte_size(Body)),
    Request = iolist_to_binary([
        "POST ", ?PATH, " HTTP/1.0\r\n",
        "Host: 192.168.34.102:4000\r\n",
        "Content-Type: application/json\r\n",
        "Content-Length: ", ContentLength, "\r\n",
        "\r\n",
        Body
    ]),
    io:format("Connecting to 192.168.34.102:4000~n"),
    case gen_tcp:connect(?HOST, ?PORT, [{inet_backend, socket}, {active, false}]) of
        {ok, Socket} ->
            io:format("Connected, sending request~n"),
            ok = gen_tcp:send(Socket, Request),
            case recv_all(Socket) of
                {ok, Response} ->
                    gen_tcp:close(Socket),
                    handle_response(Response);
                {error, Reason} ->
                    gen_tcp:close(Socket),
                    io:format("Recv error: ~p~n", [Reason]),
                    {error, Reason}
            end;
        {error, Reason} ->
            io:format("Connect failed: ~p~n", [Reason]),
            {error, Reason}
    end.

recv_all(Socket) ->
    recv_all(Socket, <<>>).

recv_all(Socket, Acc) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Data} ->
            recv_all(Socket, <<Acc/binary, Data/binary>>);
        {error, closed} ->
            {ok, Acc};
        {error, Reason} ->
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
