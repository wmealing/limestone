-module(networking).
-export([get_config/1, post_sensor_data/2]).

get_config(Url) ->
    {Host, Port, Path} = parse_url(Url),
    case ahttp_client:connect(http, Host, Port, [{active, false}, {inet_backend, socket}, {timeout, 10000}]) of
        {ok, Conn} ->
            case ahttp_client:request(Conn, <<"GET">>, list_to_binary(Path), [], <<>>) of
                {ok, Conn2, Ref} ->
                    Result = collect_response(Conn2, Ref, undefined, []),
                    ahttp_client:close(Conn2),
                    case Result of
                        {200, Body} -> {ok, Body};
                        {Status, _} -> {error, {http_status, Status}}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

post_sensor_data(Body, Url) ->
    {Host, Port, Path} = parse_url(Url),
    io:format("Connecting to ~s:~p~n", [Host, Port]),
    case ahttp_client:connect(http, Host, Port, [{active, false}, {inet_backend, socket}, {timeout, 10000}]) of
        {ok, Conn} ->
            Headers = [{<<"Content-Type">>, <<"application/json">>}],
            case ahttp_client:request(Conn, <<"POST">>, list_to_binary(Path), Headers, Body) of
                {ok, Conn2, Ref} ->
                    Result = collect_response(Conn2, Ref, undefined, []),
                    ahttp_client:close(Conn2),
                    Result;
                {error, Reason} ->
                    io:format("Request failed: ~p~n", [Reason]),
                    {error, Reason}
            end;
        {error, Reason} ->
            io:format("Connect failed: ~p~n", [Reason]),
            {error, Reason}
    end.

parse_url("http://"  ++ Rest) -> parse_host_port_path(Rest, 80);
parse_url("https://" ++ Rest) -> parse_host_port_path(Rest, 443).

parse_host_port_path(Rest, DefaultPort) ->
    {HostPort, Path} = split_at_slash(Rest),
    {Host, Port} = split_host_port(HostPort, DefaultPort),
    {Host, Port, "/" ++ Path}.

split_at_slash(Str) -> split_at_slash(Str, []).
split_at_slash([$/ | Rest], Acc) -> {lists:reverse(Acc), Rest};
split_at_slash([C   | Rest], Acc) -> split_at_slash(Rest, [C | Acc]);
split_at_slash([],           Acc) -> {lists:reverse(Acc), ""}.

split_host_port(HostPort, Default) ->
    case split_at_colon(HostPort) of
        {Host, ""}      -> {Host, Default};
        {Host, PortStr} -> {Host, list_to_integer(PortStr)}
    end.

split_at_colon(Str) -> split_at_colon(Str, []).
split_at_colon([$: | Rest], Acc) -> {lists:reverse(Acc), Rest};
split_at_colon([C  | Rest], Acc) -> split_at_colon(Rest, [C | Acc]);
split_at_colon([],          Acc) -> {lists:reverse(Acc), ""}.

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
