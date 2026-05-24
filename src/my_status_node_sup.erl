-module(my_status_node_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    ChildSpec = {my_status_node_worker,
                 {my_status_node_worker, start_link, []},
                 permanent, 5000, worker, [my_status_node_worker]},
    {ok, {{one_for_one, 5, 60}, [ChildSpec]}}.
