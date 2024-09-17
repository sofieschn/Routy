-module(routy).
-export([start/2, stop/1, init/1, status/1]).


start(Reg, Name) ->
    Pid = spawn(fun() -> init(Name) end),
    case register(Reg, Pid) of
        true -> {ok, Pid};
        _ -> {error, registration_failed}
    end.
    
stop(Node) ->
    Node ! stop,
    unregister(Node).


init(Name) ->
    Intf = interface:new(),
    Map = map:new(),
    Table = dijkstra:table(Intf, Map),
    Hist = hist:new(Name),
    router(Name, 0, Hist, Intf, Table, Map).


    router(Name, Counter, Hist, Intf, Table, Map) ->
        % based on the structure of incoming message, recieve handles is as add, remove, 'DOWN' 
        % If a message does not match any pattern, it remains in the mailbox until a matching pattern is provided or the message is skipped or discarded.
        receive

            % add a new interface/connection to another router or node.
            {add, Node, Pid} ->
                %  monitors the process associated with Pid. If the process dies, 'DOWN' message will be sent to router.
                Ref = erlang:monitor(process, Pid),
                Intf1 = interface:add(Node, Ref, Pid, Intf),
                % Call the update function here to recalculate the routing table
                % UpdatedTable = dijkstra:table(interface:list(Intf1), Map),
                router(Name, Counter, Hist, Intf1, Table, Map);

            % remove an existing connection/interface.
            {remove, Node} ->
                {ok, Ref} = interface:ref(Node, Intf),
                erlang:demonitor(Ref),
                Intf1 = interface:remove(Node, Intf),
                % UpdatedTable = dijkstra:table(interface:list(Intf1), Map),
                router(Name, Counter, Hist, Intf1, Table, Map);

            % React to the crash or termination of a connected node's process.
            {'DOWN', Ref, process, _, _} ->
                {ok, Down} = interface:name(Ref, Intf),
                io:format("~w: exit received from ~w~n", [Name, Down]),
                Intf1 = interface:remove(Down, Intf),
                % UpdatedTable = dijkstra:table(interface:list(Intf1), Map),
                router(Name, Counter, Hist, Intf1, Table, Map);

            %% Handling link-state updates
            {links, Node, MessageNr, Links} ->
                case hist:update(Node, MessageNr, Hist) of
                    {new, UpdatedHist} ->
                        io:format("~p: Received new link-state from ~p. Links: ~p~n", [Name, Node, Links]),
                        UpdatedMap = map:update(Node, Links, Map),
                        io:format("~p: Updated map: ~p~n", [Name, UpdatedMap]),
                        interface:broadcast({links, Node, MessageNr, Links}, Intf),
                        % UpdatedTable = dijkstra:table(interface:list(Intf), UpdatedMap),
                        router(Name, Counter, UpdatedHist, Intf, Table, UpdatedMap);
                    old ->
                        io:format("~p: Received old link-state from ~p. Ignoring...~n", [Name, Node]),
                        router(Name, Counter, Hist, Intf, Table, Map)
                end;
            
                
            % Respond to a request for the current state of the router.
            {status, From} ->
                % Sends the current state of the router back to the requester.
                From ! {status, {Name, Counter, Hist, Intf, Table, Map}},
                router(Name, Counter, Hist, Intf, Table, Map);

            %updates the routing table based on any updates
            update ->
                UpdatedTable = dijkstra:table(interface:list(Intf), Map),
                io:format("~p: Updated routing table: ~p~n", [Name, UpdatedTable]),
                router(Name, Counter, Hist, Intf, UpdatedTable, Map);
        
            %%
            broadcast ->
                Message = {links, Name, Counter, interface:list(Intf)},
                interface:broadcast(Message, Intf),
                router(Name, Counter + 1, Hist, Intf, Table, Map);
            stop -> ok

        end.
    
    
    %% Sends a status request to the router and prints the response.
    status(RouterPid) ->
        %% Send the status request to the router.
        RouterPid ! {status, self()},

        %% Wait for the response.
        receive
            {status, {Name, Counter, Hist, Intf, Table, Map}} ->
                %% Pretty-print the state information.
                io:format("Router Status:~n"),
                io:format("  Name: ~p~n", [Name]),
                io:format("  Counter: ~p~n", [Counter]),
                io:format("  History: ~p~n", [Hist]),
                io:format("  Interfaces: ~p~n", [Intf]),
                io:format("  Routing Table: ~p~n", [Table]),
                io:format("  Network Map: ~p~n", [Map])
        after
            5000 -> % Timeout after 5000 milliseconds
                io:format("Failed to receive status response from router.~n")
        end.
    
