-module(networking).
-export([post_sensor_data/2]).

-define(PATH, "/api/collect/").
-define(HOST_SSL,  "cobalt-mellowed-blossom-1379.fly.dev").
-define(PORT_SSL,  443).
-define(HOST_TCP,  "cobalt-mellowed-blossom-1379.fly.dev").
-define(PORT_TCP,  80).

post_sensor_data(Body, UseSsl) ->
    {Protocol, Host, Port} = case UseSsl of
        true  -> {https, ?HOST_SSL, ?PORT_SSL};
        false -> {http,  ?HOST_TCP, ?PORT_TCP}
    end,
    io:format("Connecting to ~p (ssl=~p)~n", [Host, UseSsl]),
    case ahttp_client:connect(Protocol, Host, Port, [{active, false}, {inet_backend, socket}]) of
        {ok, Conn} ->
            Headers = [{<<"Content-Type">>, <<"application/json">>}],
            case ahttp_client:request(Conn, <<"POST">>, ?PATH, Headers, Body) of
                {ok, Conn2, Ref} ->
                    Result = collect_response(Conn2, Ref, undefined, []),
                    ahttp_client:close(Conn2),
                    Result;
                {error, Reason} ->
                    io:format("Request failed: ~p~n", [Reason]),
                    {error, Reason}
            end;
        {error, {gen_tcp, enoname} = Reason} ->
            io:format("DNS lookup failed, retrying in 3s~n"),
            timer:sleep(3000),
            post_sensor_data(Body, UseSsl);
        {error, Reason} ->
            io:format("Connect failed: ~p~n", [Reason]),
            {error, Reason}
    end.

collect_response(Conn, Ref, Status, BodyAcc) ->
    case ahttp_client:recv(Conn, 0) of
        {ok, Conn2, Responses} ->
            process_responses(Conn2, Ref, Status, BodyAcc, Responses);
        {error, {_, closed}} ->
            finalize(Status, BodyAcc);
        {error, Reason} ->
            io:format("Recv error: ~p~n", [Reason]),
            {error, Reason}
    end.

process_responses(Conn, Ref, Status, BodyAcc, []) ->
    collect_response(Conn, Ref, Status, BodyAcc);
process_responses(_Conn, _Ref, Status, BodyAcc, [{done, _} | _]) ->
    finalize(Status, BodyAcc);
process_responses(Conn, Ref, _Status, BodyAcc, [{status, Ref, Code} | Rest]) ->
    process_responses(Conn, Ref, Code, BodyAcc, Rest);
process_responses(Conn, Ref, Status, BodyAcc, [{data, _, Chunk} | Rest]) ->
    process_responses(Conn, Ref, Status, [BodyAcc, Chunk], Rest);
process_responses(Conn, Ref, Status, BodyAcc, [_ | Rest]) ->
    process_responses(Conn, Ref, Status, BodyAcc, Rest).

finalize(Status, BodyAcc) ->
    Body = iolist_to_binary(BodyAcc),
    io:format("HTTP ~p~n", [Status]),
    io:format("Body: ~s~n", [Body]),
    {Status, Body}.
