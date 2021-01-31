-module(edgar).

-export([parse/1]).

-record(state, {
    stage = headers,
    headers = [],
    columns = [],
    body = [],
    fd = undefined
}).

parse(Path) when is_list(Path) ->
    {ok, FD} = file:open(Path, [raw, binary]),
    run(#state{fd = FD}).

run(#state{stage = finish} = State) ->
    {ok, #{
        headers => State#state.headers,
        columns => State#state.columns,
        body => State#state.body
    }};
run(#state{stage = Stage, fd = FD} = State) ->
    Data0 = file:read_line(FD),
    case parse(Stage, Data0) of
        {ok, []} ->
            run(State);
        {ok, Result} ->
            State1 =
                case Stage of
                    headers -> State#state{headers = [Result | State#state.headers]};
                    columns -> State#state{columns = State#state.columns ++ Result};
                    body -> State#state{body = [Result | State#state.body]}
                end,
            run(State1);
        nil ->
            State1 = next_stage(State),
            run(State1)
    end.

parse(headers, {ok, Bin}) -> parse_headers(Bin);
parse(columns, {ok, Bin}) -> parse_columns(Bin);
parse(body, {ok, Bin}) -> parse_body(Bin);
parse(_stage, eof) -> nil.

parse_headers(<<"Description:"/utf8, Value/binary>>) ->
    {ok, {description, string:trim(Value)}};
parse_headers(<<"Last Data Received:"/utf8, Value/binary>>) ->
    {ok, {last_data_received, string:trim(Value)}};
parse_headers(<<"Comments:"/utf8, Value/binary>>) ->
    {ok, {comments, string:trim(Value)}};
parse_headers(<<"Anonymous FTP:"/utf8, Value/binary>>) ->
    {ok, {anonymous_ftp, string:trim(Value)}};
parse_headers(<<" \n"/utf8, _/binary>>) ->
    nil.

parse_columns(<<"-----", _/binary>>) ->
    nil;
parse_columns(<<" \n">>) ->
    {ok, []};
parse_columns(Binary) ->
    Splitted = binary:split(Binary, <<"  ">>, [global, trim_all]),
    Filtered = lists:map(fun(Field) -> string:trim(Field) end, Splitted),
    {ok, Filtered}.

parse_body(Binary) ->
    Splitted = binary:split(Binary, <<"  ">>, [global, trim_all]),
    Filtered =
        lists:filtermap(
            fun(Field) ->
                case string:trim(Field) of
                    <<>> -> false;
                    Res -> {true, Res}
                end
            end,
            Splitted
        ),
    {ok, Filtered}.

next_stage(#state{stage = headers} = State) -> State#state{stage = columns};
next_stage(#state{stage = columns} = State) -> State#state{stage = body};
next_stage(#state{stage = body} = State) -> State#state{stage = finish}.
