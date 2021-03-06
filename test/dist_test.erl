% ./detest test/dist_test.erl single
% ./detest test/dist_test.erl cluster

-module(dist_test).
-export([cfg/1,setup/1,cleanup/1,run/1]).
-export([killconns/0,call_start/1,call_receive/1]).
-define(INF(F,Param),io:format("~p ~p:~p ~s~n",[ltime(),?MODULE,?LINE,io_lib:fwrite(F,Param)])).
-define(INF(F),?INF(F,[])).
-define(NUMACTORS,100).
-include_lib("eunit/include/eunit.hrl").
-include("test_util.erl").
numactors() ->
	?NUMACTORS.
-define(ND1,[{name,node1},{rpcport,45551}]).
-define(ND2,[{name,node2},{rpcport,45552}]).
-define(ND3,[{name,node3},{rpcport,45553}]).
-define(ND4,[{name,node4},{rpcport,45554}]).
-define(ND5,[{name,node5},{rpcport,45555}]).
-define(ONEGRP(XX),[[{name,"grp1"},{nodes,[butil:ds_val(name,Nd) || Nd <- XX]}]]).
-define(TWOGRPS(X,Y),[[{name,"grp1"},{nodes,[butil:ds_val(name,Nd) || Nd <- X]}],
                      [{name,"grp2"},{nodes,[butil:ds_val(name,Nd) || Nd <- Y]}]]).

%{erlcmd,"../otp/bin/cerl -valgrind"},{erlenv,[{"VALGRIND_MISC_FLAGS","-v --leak-check=full --tool=memcheck --track-origins=no  "++
%                                       "--suppressions=../otp/erts/emulator/valgrind/suppress.standard --show-possibly-lost=no"}]}
cfg(Args) ->
	case Args of
		[TT|_] when TT == "single"; TT == "addsecond"; TT == "endless1"; TT == "addclusters"; TT == "mysql" ->
			Nodes = [?ND1],
			Groups = ?ONEGRP(Nodes);
		["multicluster"|_] ->
			Nodes = [?ND1,?ND2,?ND3,?ND4],
			Groups = ?TWOGRPS([?ND1,?ND2],[?ND3,?ND4]);
		[TT|_] when TT == "addthentake"; TT == "addcluster"; TT == "endless2" ->
			Nodes = [?ND1,?ND2],
			Groups = ?ONEGRP(Nodes);
		["repl"|_] ->
			Nodes = [?ND1,?ND2,?ND3,?ND4,?ND5],
			Groups = [[{name,"grp1"},{nodes,[node1]}],[{name,"grp2"},{nodes,[node2]}],[{name,"grp3"},{nodes,[node3]}],
			          [{name,"grp4"},{nodes,[node4]}],[{name,"grp5"},{nodes,[node5]}]];
		{Nodes,Groups} ->
			ok;
		_ ->
			Nodes = [?ND1,?ND2,?ND3],
			Groups = ?ONEGRP(Nodes)
	end,
	[
		% these dtl files get nodes value as a parameter and whatever you add here.
		{global_cfg,[{"test/etc/nodes.yaml",[{groups,Groups}]},
		             % schema does not need additional any parameters.
		             "test/etc/schema.yaml"]},
		% Config files per node. For every node, its property list is added when rendering.
		% if name contains app.config or vm.args it gets automatically added to run node command
		% do not set cookie or name of node in vm.args this is set by detest
		{per_node_cfg,["test/etc/app.config"]},
		% cmd is appended to erl execute command, it should execute your app.
		% It can be set for every node individually. Add it to that list if you need it, it will override this value.
		{cmd,"-s actordb_core +S 2 +A 2"},
		
		% optional command to start erlang with
		% {erlcmd,"../otp/bin/cerl -valgrind"},
		
		% optional environment variables for erlang
		%{erlenv,[{"VALGRIND_MISC_FLAGS","-v --leak-check=full --tool=memcheck --track-origins=no  "++
        %                               "--suppressions=../otp/erts/emulator/valgrind/suppress.standard --show-possibly-lost=no"}]},
        
        % in ms, how long to wait to connect to node. If running with valgrind it takes a while.
         {connect_timeout,60000},
        
        % in ms, how long to wait for application start once node is started
         {app_wait_timeout,60000*5},
		
		% which app to wait for to consider node started
		{wait_for_app,actordb_core},
		% What RPC to execute for stopping nodes (optional, def. is {init,stop,[]})
		{stop,{actordb_core,stop_complete,[]}},
		{nodes,Nodes}
	].

% Before starting nodes
setup(Param) ->
	filelib:ensure_dir([butil:ds_val(path,Param),"/log"]).

% Nodes have been closed
cleanup(_Param) ->
	os:cmd("iptables --flush"),
	ok.

run(Param) ->
	case butil:ds_val(args,Param) of
		[TestType|_] ->
			ok;
		_ ->
			lager:info("No test type provided. Running basic cluster test"),
			TestType = "cluster"
	end,
	run(Param,TestType),
	ok.


run(Param,TType) when TType == "single"; TType == "cluster"; TType == "multicluster" ->
	Nd1 = butil:ds_val(node1,Param),
	Nd2 = butil:ds_val(node2,Param),
	Nd3 = butil:ds_val(node3,Param),
	Nd4 = butil:ds_val(node4,Param),
	Ndl = [Nd1,Nd2,Nd3,Nd4],
	rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	basic_read(Ndl),
	basic_write(Ndl),
	basic_read(Ndl),
	multiupdate_write(Ndl),
	multiupdate_read(Ndl),
	kv_readwrite(Ndl),
	basic_write(Ndl),
	basic_read(Ndl),
	copyactor(Ndl);
run(Param,"mysql") ->
	true = code:add_path("test/mysql.ez"),
	Nd1 = butil:ds_val(node1,Param),
	rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	ok = wait_tree(Nd1,10000),
	
	[_,Host] = string:tokens(butil:tolist(Nd1),"@"),
	MyOpt = [{host,Host},{port,butil:ds_val(rpcport,?ND1)-10000},{user,"user"},{password,"password"},{database,"actordb"}],
	{ok,Pid} = mysql:start_link(MyOpt),
	ok = mysql:query(Pid, <<"actor type1(ac1) create;INSERT INTO tab VALUES (111,'aaaa',1);">>),
	ok = mysql:query(Pid, <<"PREPARE stmt1 () FOR type1 AS select * from tab;">>),
	{ok,_Cols,_Rows} = PrepRes = mysql:query(Pid,<<"actor type1(ac1);EXECUTE stmt1 ();">>),
	io:format("PrepRes ~p~n",[PrepRes]),
	ok;
run(Param,"addsecond") ->
	[Nd1,Path] = butil:ds_vals([node1,path],Param),
	Ndl = [Nd1],
	rpc:call(Nd1,actordb_cmd,cmd,[init,commit,Path++"/node1/etc"],3000),
	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	basic_read(Ndl),
	%test_add_second(Ndl),
	Nd2 = detest:add_node(?ND2,[{global_cfg,[{"test/nodes.yaml",[{groups,[[{name,"grp1"},{nodes,["node1","node2"]}]]}]},"test/schema.yaml"]}]),
	rpc:call(Nd1,actordb_cmd,cmd,[updatenodes,commit,Path++"/node1/etc"],3000),
	ok = wait_modified_tree(Nd2,[Nd1,Nd2],30000),
	basic_write(Ndl),
	kv_readwrite(Ndl),
	multiupdate_write(Ndl),
	multiupdate_read(Ndl),
	basic_write(Ndl),
	basic_read(Ndl);
run(Param,"missingnode") ->
	Nd1 = butil:ds_val(node1,Param),
	Nd2 = butil:ds_val(node2,Param),
	Nd3 = butil:ds_val(node3,Param),
	Ndl = [Nd1,Nd2,Nd3],
	rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	basic_read(Ndl),
	basic_write(Ndl),
	basic_read(Ndl),
	kv_readwrite(Ndl),
	multiupdate_write(Ndl),
	multiupdate_read(Ndl),
	copyactor(Ndl),
	detest:stop_node(Nd3),
	basic_write(Ndl);
run(Param,"addthentake") ->
	Path = butil:ds_val(path,Param),
	Nd1 = butil:ds_val(node1,Param),
	Nd2 = butil:ds_val(node2,Param),
	Ndl = [Nd1,Nd2],
	rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	basic_read(Ndl),
	Nd3 = detest:add_node(?ND3,[{global_cfg,[{"test/nodes.yaml",[{groups,[[{name,"grp1"},{nodes,["node1","node2","node3"]}]]}]},"test/schema.yaml"]}]),
	rpc:call(Nd1,actordb_cmd,cmd,[updatenodes,commit,Path++"/node1/etc"],3000),
	ok = wait_modified_tree(Nd3,[Nd1,Nd2,Nd3],30000),
	basic_read(Ndl),
	basic_write(Ndl),
	kv_readwrite(Ndl),
	multiupdate_write(Ndl),
	multiupdate_read(Ndl),
	detest:stop_node(Nd2),
	basic_write(Ndl),
	basic_read(Ndl),
	copyactor(Ndl);
run(Param,"addcluster") ->
	Nd1 = butil:ds_val(node1,Param),
	Nd2 = butil:ds_val(node2,Param),
	Ndl = [Nd1,Nd2],
	rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	basic_read(Ndl),
	kv_readwrite(Ndl),
	Nd3 = detest:add_node(?ND3,[{global_cfg,[{"test/nodes.yaml",[{groups,?TWOGRPS([?ND1,?ND2],[?ND3,?ND4])}]},"test/schema.yaml"]}]),
	Nd4 = detest:add_node(?ND4,[{global_cfg,[{"test/nodes.yaml",[{groups,?TWOGRPS([?ND1,?ND2],[?ND3,?ND4])}]},"test/schema.yaml"]}]),
	rpc:call(Nd1,actordb_cmd,cmd,[updatenodes,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	ok = wait_modified_tree(Nd3,[Nd1,Nd2,Nd3],60000),
	ok = wait_modified_tree(Nd4,[Nd1,Nd2,Nd3,Nd4],60000),
	basic_write(Ndl),
	basic_read(Ndl),
	multiupdate_write(Ndl),
	multiupdate_read(Ndl);
run(Param,"failednodes") ->
	Nd1 = butil:ds_val(node1,Param),
	Nd2 = butil:ds_val(node2,Param),
	Nd3 = butil:ds_val(node3,Param),
	Ndl = [Nd1,Nd2,Nd3],
	rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	basic_write(Ndl),
	basic_read(Ndl),
	kv_readwrite(Ndl),
	multiupdate_write(Ndl),
	multiupdate_read(Ndl),
	detest:stop_node(Nd2),
	basic_write(Ndl),
	detest:add_node(?ND2),
	basic_write(Ndl),
	detest:stop_node(Nd2),
	detest:stop_node(Nd3),
	detest:add_node(?ND2),
	detest:add_node(?ND3),
	basic_write(Ndl);
run(Param,"endless"++Num) ->
	Nd1 = butil:ds_val(node1,Param),
	case butil:toint(Num) of
		1 ->
			Ndl = [Nd1];
		2 ->
			Nd2 = butil:ds_val(node2,Param),
			Ndl = [Nd1,Nd2]
	end,
	rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	ok = wait_tree(Nd1,600000),
	Home = self(),
	ets:new(writecounter, [named_table,public,set,{write_concurrency,true}]),
	butil:ds_add(wnum,0,writecounter),
	butil:ds_add(wnum_sec,0,writecounter),
	Pids = [spawn_monitor(fun() -> rseed(N),writer(Home,Nd1,N,0) end) || N <- lists:seq(1,8000)],
	lager:info("Test will run until you stop it or something crashes."),
	wait_crash(Ndl);
run(Param,"addclusters") ->
	Nd1 = butil:ds_val(node1,Param),
	Ndl = [Nd1],
	"ok" = rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	ok = wait_tree(Nd1,60000),
	AdNodesProc = spawn_link(fun() -> addclusters(butil:ds_val(path,Param),Nd1,[?ND1]) end),
	make_actors(0),
	AdNodesProc ! done;
run(Param,"repl") ->
	[Nd1,Nd2,Nd3,Nd4,Nd5|_] = Ndl = butil:ds_vals([node1,node2,node3,node4,node5],Param),
	Nd1ip = dist_to_ip(Nd1),
	Nd2ip = dist_to_ip(Nd2),
	Nd3ip = dist_to_ip(Nd3),
	Nd4ip = dist_to_ip(Nd4),
	Nd5ip = dist_to_ip(Nd5),
	rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	ok = wait_tree(Nd1,10000),
	timer:sleep(1000),
	
	lager:info("Isolating node1,node2, me ~p",[node()]),
	isolate([Nd1ip,Nd2ip],[Nd3ip,Nd4ip,Nd5ip]),
	%rpc:call(Nd1,?MODULE,killconns,[]),
	%rpc:call(Nd2,?MODULE,killconns,[]),
	%rpc:call(Nd3,?MODULE,killconns,[]),
	%rpc:call(Nd4,?MODULE,killconns,[]),
	%rpc:call(Nd5,?MODULE,killconns,[]),
	
	%damocles:isolate_between_interfaces([Nd1ip, Nd2ip], [Nd3ip,Nd4ip,Nd5ip]),
	
	% nd1 should be leader but now it can only communicate with node2
	{badrpc,_} = rpc:call(Nd1,actordb_sharedstate,write_global,[key,123],5000),
	lager:info("Abandoned call, trying in ~p",[Nd3]),
	{ok,_} = rpc:call(Nd3,actordb_sharedstate,write_global,[key1,321],2000),
	lager:info("Write success. Restoring network. Do we have abandoned write?"),
	%damocles:restore_all_interfaces(),
	cleanup(1),
	123 = rpc:call(Nd1,actordb_sharedstate,read,[<<"global">>,key],15000),
	321 = rpc:call(Nd1,actordb_sharedstate,read,[<<"global">>,key1],15000),
	lager:info("REACHED END SUCCESSFULLY"),
	%{ok,_} = rpc:call(Nd1,?MODULE,call_start,[node2],10000),
	%{ok,_} = rpc:call(Nd1,?MODULE,call_start,[node3],10000),
	ok;
run(Param,Nm) ->
	lager:info("Unknown test type ~p",[Nm]).


isolate([],_) ->
	ok;
isolate([[_|_]|_] = ToIsolate, [[_|_]|_] = IsolateFrom) ->
	[begin
		Cmd1 = "iptables -A INPUT  -m conntrack --ctstate NEW,ESTABLISHED,RELATED --ctorigsrc "++F++" --ctorigdst "++hd(ToIsolate)++"  -j DROP",
		Cmd2 = "iptables -A INPUT  -m conntrack --ctstate NEW,ESTABLISHED,RELATED --ctorigsrc "++hd(ToIsolate)++" --ctorigdst "++F++"  -j DROP",
		lager:info("~s: ~s",[Cmd1,os:cmd(Cmd1)]),
		lager:info("~s: ~s",[Cmd2,os:cmd(Cmd2)])
		%Cmd3 = "iptables -A OUTPUT  -m conntrack --ctstate NEW,ESTABLISHED,RELATED -s "++F++" -d "++hd(ToIsolate)++"  -j DROP",
		%Cmd4 = "iptables -A OUTPUT  -m conntrack --ctstate NEW,ESTABLISHED,RELATED -s "++hd(ToIsolate)++" -d "++F++"  -j DROP",
		%lager:info("~s: ~s",[Cmd3,os:cmd(Cmd3)]),
		%lager:info("~s: ~s",[Cmd4,os:cmd(Cmd4)])
	end || F <- IsolateFrom],
	isolate(tl(ToIsolate),IsolateFrom);
isolate([_|_] = ToIsolate, IsolateFrom) when is_integer(hd(ToIsolate)) ->
	isolate([ToIsolate],IsolateFrom);
isolate(ToIsolate, [_|_] = IsolateFrom) when is_integer(hd(IsolateFrom)) ->
	isolate(ToIsolate,[IsolateFrom]).

% Called on nodes
killconns() ->
	L = supervisor:which_children(ranch_server:get_connections_sup(bkdcore_in)),
	[exit(Pid,stop) || {bkdcore_rpc,Pid,worker,[bkdcore_rpc]} <- L].



% This module is loaded inside every executed node. So we can rpc to these functions on every node.
call_start(Nd) ->
	lager:info("Calling from=~p to=~p, at=~p, connected=~p~n",[node(), Nd, time(),nodes(connected)]),
	%{ok,_} = rpc:call(Nd,?MODULE,call_receive,[node()],1000).
	{ok,_} = bkdcore_rpc:call(butil:tobin(Nd),{?MODULE,call_receive,[bkdcore:node_name()]}).

call_receive(From) ->
	lager:info("Received call on=~p from=~p, at=~p~n",[node(), From, time()]),
	{ok,node()}.
