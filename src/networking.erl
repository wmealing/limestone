-module(networking).
-export([post_sensor_data/1]).

-define(HOST, {192, 168, 34, 102}).
-define(PORT, 4000).
-define(PATH, "/api/collect/").

do_request(HostName, Port, Options, Request) ->
    case ssl:connect(HostName, Port, Options) of
        {ok, Socket} ->
            io:format("Connected, sending request~n"),
            case ssl:send(Socket, Request) of
                ok ->
                    io:format("Msg sent..~n"),
                    case recv_all(Socket) of
                        {ok, Response} ->
                            ssl:close(Socket),
                            handle_response(Response);
                        {error, Reason} ->
                            ssl:close(Socket),
                            {error, Reason}
                    end;
                {error, Reason} ->
                    ssl:close(Socket),
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

post_sensor_data(Body) ->

    HostName = "cobalt-mellowed-blossom-1379.fly.dev",
    Port = 443,

    Options = [
        {verify, verify_none},
        {server_name_indication, HostName},
        {active, false}
    ],

    ContentLength = integer_to_list(byte_size(Body)),

    io:format("PATH: ~p~n", [?PATH]),

    Request = iolist_to_binary([
        "POST ", ?PATH, " HTTP/1.0\r\n",
        "Host:", HostName, "\r\n",
        "Content-Type: application/json\r\n",
        "Content-Length: ", ContentLength, "\r\n",
        "\r\n",
        Body
    ]),

    io:format("Connecting to ~p~n", [HostName]),

    Parent = self(),
    Ref = make_ref(),

    spawn(fun() -> Parent ! {Ref, do_request(HostName, Port, Options, Request)} end),

    receive
        {Ref, {error, Reason}} ->
            io:format("Request failed: ~p~n", [Reason]),
            {error, Reason};
        {Ref, Result} ->
            Result
    after 30000 ->
        io:format("Request timed out~n"),
        {error, timeout}
    end.


recv_all(Socket) ->
    recv_all(Socket, <<>>).

recv_all(Socket, Acc) ->
    case ssl:recv(Socket, 0) of
        {ok, Data} ->
	    io:format("RCV_ALL DATA: ~p~n", [Data]),
            recv_all(Socket, <<Acc/binary, Data/binary>>);
        {error, -30848} ->
	    io:format("RCV_ALL CLOSED~n"),
            {ok, Acc};
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
