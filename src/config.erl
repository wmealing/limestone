-module(config).
-export([defaults/0, parse/1]).

defaults() ->
    #{
        update_interval => 1800,
        update_server   => "http://192.168.35.106:4000/api/v1/collect",
        config_url      => "http://192.168.35.106:8080/api/v1/config"
    }.

parse(Json) ->
    Defaults = defaults(),
    Interval = case extract_integer(<<"update-interval">>, Json) of
        {ok, Iv} ->
            io:format("[*] update_interval parsed: ~p~n", [Iv]),
            Iv;
        nomatch ->
            io:format("[*] update_interval not found, using default: ~p~n",
                [maps:get(update_interval, Defaults)]),
            maps:get(update_interval, Defaults)
    end,
    Server = case extract_string(<<"update-server">>, Json) of
        {ok, Sv} -> binary_to_list(Sv);
        nomatch   -> maps:get(update_server, Defaults)
    end,
    #{update_interval => Interval,
      update_server   => Server,
      config_url      => maps:get(config_url, Defaults)}.

extract_integer(Key, Json) ->
    Pattern = <<"\"", Key/binary, "\"">>,
    case binary:match(Json, Pattern) of
        nomatch -> nomatch;
        {Pos, Len} ->
            After = binary:part(Json, Pos + Len, byte_size(Json) - Pos - Len),
            scan_colon_int(After)
    end.

extract_string(Key, Json) ->
    Pattern = <<"\"", Key/binary, "\"">>,
    case binary:match(Json, Pattern) of
        nomatch -> nomatch;
        {Pos, Len} ->
            After = binary:part(Json, Pos + Len, byte_size(Json) - Pos - Len),
            scan_colon_string(After)
    end.

scan_colon_int(<<$:, Rest/binary>>) -> scan_int(ltrim(Rest));
scan_colon_int(<<_, Rest/binary>>)  -> scan_colon_int(Rest);
scan_colon_int(<<>>)                -> nomatch.

scan_colon_string(<<$:, Rest/binary>>) -> scan_string(ltrim(Rest));
scan_colon_string(<<_, Rest/binary>>)  -> scan_colon_string(Rest);
scan_colon_string(<<>>)                -> nomatch.

ltrim(<<$\s, Rest/binary>>) -> ltrim(Rest);
ltrim(<<$\t, Rest/binary>>) -> ltrim(Rest);
ltrim(<<$\n, Rest/binary>>) -> ltrim(Rest);
ltrim(<<$\r, Rest/binary>>) -> ltrim(Rest);
ltrim(Bin)                  -> Bin.

scan_int(Bin) -> scan_int(Bin, <<>>).
scan_int(<<D, Rest/binary>>, Acc) when D >= $0, D =< $9 ->
    scan_int(Rest, <<Acc/binary, D>>);
scan_int(_, <<>>) -> nomatch;
scan_int(_, Acc)  -> {ok, binary_to_integer(Acc)}.

scan_string(<<$", Rest/binary>>) -> scan_string_body(Rest, <<>>);
scan_string(<<_, Rest/binary>>)  -> scan_string(Rest);
scan_string(<<>>)                -> nomatch.

scan_string_body(<<$", _/binary>>, Acc)        -> {ok, Acc};
scan_string_body(<<$\\, $", Rest/binary>>, Acc) -> scan_string_body(Rest, <<Acc/binary, $">>);
scan_string_body(<<C, Rest/binary>>, Acc)       -> scan_string_body(Rest, <<Acc/binary, C>>);
scan_string_body(<<>>, _)                       -> nomatch.
