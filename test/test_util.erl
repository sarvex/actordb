
basic_write(Ndl) ->
	basic_write(Ndl,<<"SOME TEXT">>).
basic_write(Ndl,Txt) ->
	?INF("Basic write",[]),
	[begin
		?INF("Write ac~p",[N]),
		{ok,_} = _R = exec(Ndl,<<"actor type1(ac",(integer_to_binary(N))/binary,") create; insert into tab values (",
									(integer_to_binary(flatnow()))/binary,",'",Txt/binary,"',1);">>)
		% ?INF("~p",[R])
	end
	 || N <- lists:seq(1,?NUMACTORS)].

basic_read(Ndl) ->
	?INF("Basic read",[]),
	[begin
		?INF("Read ac~p",[N]),
		{ok,[{columns,_},{rows,[{_,<<_/binary>>,_}|_]}]} =
			exec(Ndl,<<"actor type1(ac",(integer_to_binary(N))/binary,") create; select * from tab;">>)
	 end
	 || N <- lists:seq(1,?NUMACTORS)].

copyactor(Ndl) ->
	?INF("Copy actor",[]),
	{ok,_} = exec(Ndl,["actor type1(newcopy);PRAGMA copy=ac1;"]),
	{ok,[{columns,_},{rows,[{_,<<_/binary>>,_}|_]}]} = exec(Ndl,<<"actor type1(newcopy) create; select * from tab;">>),
	[begin
		{ok,_} = exec(Ndl,["actor type1(newcopy",integer_to_list(N),");PRAGMA copy=ac",integer_to_list(N),";"]),
		{ok,[{columns,_},{rows,[{_,<<_/binary>>,_}|_]}]} = exec(Ndl,<<"actor type1(newcopy) create; select * from tab;">>)
	 end
	 || N <- lists:seq(1,10)].


multiupdate_write(Ndl) ->
	?debugFmt("multiupdates",[]),
	% Insert names of 2 actors in table tab2 of actor "all"
	?assertMatch({ok,_},exec(Ndl,["actor type1(all) create;",
							  "insert into tab2 values (1,'a1');",
							  "insert into tab2 values (2,'a2');"])),
	
	?debugFmt("multiupdate fail insert",[]),
	% Fail test
	?assertMatch(ok,exec(Ndl,["actor thread(first) create;",
							  "insert into thread values (1,'a1',10);",
							  "actor thread(second) create;",
							  "insert into thread values (1,'a1',10);"])),
	?debugFmt("multiupdates fail",[]),
	?assertMatch(abandoned,exec(Ndl,["actor thread(first) create;",
							  "update thread set msg='a3' where id=1;",
							  "actor thread(second) create;",
							  "update thread set msg='a3' where i=2;"])),
	?debugFmt("multiupdates still old data",[]),
	?assertMatch({ok,[{columns,{<<"id">>,<<"msg">>,<<"user">>}},
                      {rows,[{1,<<"a1">>,10}]}]},
                 exec(Ndl,["actor thread(first);select * from thread;"])),
	?assertMatch({ok,[{columns,{<<"id">>,<<"msg">>,<<"user">>}},
                      {rows,[{1,<<"a1">>,10}]}]},
                 exec(Ndl,["actor thread(second);select * from thread;"])),
	
	?debugFmt("multiupdates foreach insert",[]),
	% Select everything from tab2 for actor "all".
	% Actorname is in .txt column, for every row take that actor and insert value with same unique integer id.
	Res = exec(Ndl,["actor type1(all);",
				"{{ACTORS}}SELECT * FROM tab2;",
				"actor type1(foreach X.txt in ACTORS) create;",
				"insert into tab2 values ({{uniqid.s}},'{{X.txt}}');"]),
	% ?debugFmt("Res ~p~n",[Res]),
	?assertMatch(ok,Res),

	?debugFmt("multiupdates delete actors",[]),
	?assertMatch(ok,exec(Ndl,["actor type1(ac100,ac99,ac98,ac97,ac96);PRAGMA delete;"])),
	?debugFmt("Deleting individual actor",[]),
	?assertMatch(ok,exec(Ndl,["actor type1(ac95);PRAGMA delete;"])),

	?debugFmt("multiupdates creating thread",[]),
	?assertMatch(ok,exec(Ndl,["actor thread(1) create;",
					"INSERT INTO thread VALUES (100,'message',10);",
					"INSERT INTO thread VALUES (101,'secondmsg',20);",
					"actor user(10) create;",
					"INSERT INTO userinfo VALUES (1,'user1');",
					"actor user(20) create;",
					"INSERT INTO userinfo VALUES (1,'user2');"])),
	ok.

multiupdate_read(Ndl) ->
	?INF("multiupdate read all type1",[]),
	Res = exec(Ndl,["actor type1(*);",
				"{{RESULT}}SELECT * FROM tab;"]),
	?assertMatch({ok,[_,_]},Res),
	{ok,[{columns,Cols},{rows,Rows}]} = Res,
	?INF("Result all actors ~p",[{Cols,lists:keysort(4,Rows)}]),
	?assertEqual({<<"id">>,<<"txt">>,<<"i">>,<<"actor">>},Cols),
	% 6 actors were deleted, 2 were added
	?assertEqual((numactors()-6)*2,length(Rows)),

	?INF("multiupdate read thread and user",[]),
	% Add username column to result
	{ok,ResForum} = exec(Ndl,["actor thread(1);",
				"{{RESULT}}SELECT * FROM thread;"
				"actor user(for X.user in RESULT);",
				"{{A}}SELECT * FROM userinfo WHERE id=1;",
				"{{X.username=A.name}}"
				]),
	?assertMatch([{columns,{<<"id">>,<<"msg">>,<<"user">>,<<"username">>}},
			       {rows,[{101,<<"secondmsg">>,20,<<"user2">>},
		  			      {100,<<"message">>,10,<<"user1">>}]}],
        ResForum),
	{ok,[{columns,_},{rows,Rows1}]} = exec(Ndl,["actor type1(*);pragma list;"]),
	Num = numactors()-6+3,
	%?INF("Num=~p",[Num]),
	?assertEqual(Num,length(Rows1)),
	%?INF("Rows ~p",[lists:sort(Rows1)]),
	?assertMatch({ok,[{columns,_},{rows,[{Num}]}]},exec(Ndl,["actor type1(*);pragma count;"])),
	ok.



kv_readwrite(Ndl) ->
	?debugFmt("~p",[[iolist_to_binary(["actor counters(id",butil:tolist(N),");",
		 "insert into actors values ('id",butil:tolist(N),"',{{hash(id",butil:tolist(N),")}},",
		 	butil:tolist(N),");"])|| N <- lists:seq(1,1)]]),
	[?assertMatch({ok,_},exec(Ndl,["actor counters(id",butil:tolist(N),");",
		 "insert into actors values ('id",butil:tolist(N),"',{{hash(id",butil:tolist(N),")}},",butil:tolist(N),");"])) 
				|| N <- lists:seq(1,numactors())],
	[?assertMatch({ok,[{columns,_},{rows,[{_,_,N}]}]},
					exec(Ndl,["actor counters(id",butil:tolist(N),");",
					 "select * from actors where id='id",butil:tolist(N),"';"])) || N <- lists:seq(1,numactors())],
	ReadAll = ["actor counters(*);",
	"{{RESULT}}SELECT * FROM actors;"],
	All = exec(Ndl,ReadAll),
	?debugFmt("All counters ~p",[All]),
	?debugFmt("Select first 5",[]),
	ReadSome = ["actor counters(id1,id2,id3,id4,id5);",
	"{{RESULT}}SELECT * FROM actors where id='{{curactor}}';"],
	?assertMatch({ok,[{columns,_},
					  {rows,[{<<"id5">>,_,5,<<"id5">>},
					  		  {<<"id4">>,_,4,<<"id4">>},
					  		  {<<"id3">>,_,3,<<"id3">>},
					  		  {<<"id2">>,_,2,<<"id2">>},
					  		  {<<"id1">>,_,1,<<"id1">>}]}]},
			exec(Ndl,ReadSome)),
	?debugFmt("Increment first 5",[]),
	?assertMatch(ok,exec(Ndl,["actor counters(id1,id2,id3,id4,id5);",
					"UPDATE actors SET val = val+1 WHERE id='{{curactor}}';"])),
	?debugFmt("Select first 5 again ~p",[exec(Ndl,ReadSome)]),
	?assertMatch({ok,[{columns,_},
						{rows,[{<<"id5">>,_,6,<<"id5">>},
						  {<<"id4">>,_,5,<<"id4">>},
						  {<<"id3">>,_,4,<<"id3">>},
						  {<<"id2">>,_,3,<<"id2">>},
						  {<<"id1">>,_,2,<<"id1">>}]}]},
			 exec(Ndl,ReadSome)),
	?debugFmt("delete 5 and 4",[]),
	% Not the right way to delete but it works (not transactional)
	?assertMatch(ok,exec(Ndl,["actor counters(id5,id4);PRAGMA delete;"])),
	?assertMatch({ok,[{columns,_},
					  {rows,[{<<"id3">>,_,4,<<"id3">>},
						  {<<"id2">>,_,3,<<"id2">>},
						  {<<"id1">>,_,2,<<"id1">>}]}]},
			 exec(Ndl,ReadSome)),
	% the right way
	?assertMatch(ok,exec(Ndl,["actor counters(id3,id2);DELETE FROM actors WHERE id='{{curactor}}';"])),
	?assertMatch({ok,[{columns,_},
					  {rows,[{<<"id1">>,_,2,<<"id1">>}]}]},
			 exec(Ndl,ReadSome)),
	?assertMatch({ok,[{columns,_},{rows,_}]},All),


	% Multiple tables test
	[?assertMatch({ok,_},exec(Ndl,["actor filesystem(id",butil:tolist(N),");",
		 "insert into actors values ('id",butil:tolist(N),"',{{hash(id",butil:tolist(N),")}},",butil:tolist(N),");",
		 "insert into users (fileid,uid) values ('id",butil:tolist(N),"',",butil:tolist(N),");"])) 
				|| N <- lists:seq(1,numactors())],

	ok.

make_actors(N) when N > 10000 ->
	ok;
make_actors(N) ->
	case exec(nodes(connected),<<"actor type1(ac",(integer_to_binary(N))/binary,") create; insert into tab values (",
			(integer_to_binary(flatnow()))/binary,",'",(base64:encode(crypto:rand_bytes(128)))/binary,"',1);">>) of
		{ok,_} ->
			ok;
		Err ->
			exit(Err)
	end,
	timer:sleep(100),
	make_actors(N+1).

writer(Home,Nd,N,RC) ->
	checkhome(Home),
	% Sleep a random amount from 0 to ..
	SleepFor = random:uniform(10000),
	timer:sleep(butil:ceiling(SleepFor)),
	checkhome(Home),
	Start = os:timestamp(),
	case exec([Nd],<<"actor type1(ac",(integer_to_binary(N))/binary,") create; insert into tab values (",
			(integer_to_binary(flatnow()))/binary,",'",(base64:encode(crypto:rand_bytes(128)))/binary,"',1);">>) of
		{ok,_} ->
			ok;
		Err ->
			exit(Err)
	end,
	Stop = os:timestamp(),
	Diff = timer:now_diff(Stop,Start) div 1000,
	% when quitting ets table may be gone so die quitely
	case catch ets:update_counter(writecounter,wnum,1) of
		X when is_integer(X) ->
			ok;
		_ ->
			exit(normal)
	end,
	case catch ets:update_counter(writecounter,wnum_sec,1) of
		X1 when is_integer(X1) ->
			ok;
		_ ->
			exit(normal)
	end,
	%lager:info("Write complete for ~p, runcount=~p, slept_for=~p, exec_time=~ps  ~pms",[N,RC,SleepFor,Diff div 1000, Diff rem 1000]),
	writer(Home,Nd,N,RC+1).

% We will keep adding single node clusters to the network. Cluster name is same as node name
addclusters(Path,Nd1,Nodes) ->
	receive
		done ->
			exit(normal)
	after 0 ->
		ok
	end,
	timer:sleep(1000),
	Port = 50000 + length(Nodes),
	NI = [{name,butil:toatom("node"++butil:tolist(Port))},{rpcport,Port}],
	Nodes1 = [NI|Nodes],
	Grps = [[{name,butil:ds_val(name,Ndi)},{nodes,[butil:ds_val(name,Ndi)]}] || Ndi <- Nodes1],
	DistName = detest:add_node(NI,cfg({Nodes1,Grps})),
	rpc:call(Nd1,actordb_cmd,cmd,[updatenodes,commit,Path++"/node1/etc"],3000),
	ok = wait_modified_tree(DistName,nodes(connected),30000),
	addclusters(Path,Nd1,Nodes1).

wait_crash(L) ->
	wait_crash(L,element(2,os:timestamp()),0).
wait_crash(L,Sec,N) ->
	case L -- nodes(connected) of
		[] ->
			receive
				{'DOWN',_Ref,_,_Pid,Reason} when Reason /= normal ->
					lager:error("Crash with reason ~p",[Reason])
			after 30 ->
				Sec1 = element(2,os:timestamp()),
				case Sec of
					Sec1 ->
						ok;
					_ ->
						lager:info("Writes so far: ~p, insec ~p",[butil:ds_val(wnum,writecounter),butil:ds_val(wnum_sec,writecounter)]),
						butil:ds_add(wnum_sec,0,writecounter)
				end,
				wait_crash(L,Sec1,N+1)
			end;
		L1 ->
			lager:error("Stopping. Nodes gone: ~p",[L1])
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
% 
% 	UTILITY FUNCTIONS
% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
checkhome(Home) ->
	case erlang:is_process_alive(Home) of
		true ->
			ok;
		false ->
			exit(normal)
	end.
rseed(N) ->
	{A,B,C} = now(),
	random:seed(A*erlang:phash2(["writer",now(),self()]),B+erlang:phash2([1,2,3,N]),C*N).
flatnow() ->
	{MS,S,MiS} = now(),
	MS*1000000000000 + S*1000000 + MiS.
ltime() ->
	element(2,lager_util:localtime_ms()).
exec(Nodes,Bin) ->
	rpc:call(findnd(Nodes),actordb,exec,[iolist_to_binary(Bin)]).

findnd([H|T]) ->
	case lists:member(H,nodes(connected)) of
		true ->
			H;
		_ ->
			findnd(T)
	end.

wait_tree(Nd,X) when X < 0 ->
	?INF("Timeout waiting for shard for ~p",[Nd]),
	exit(timeout);
wait_tree(Nd,N) ->
	case rpc:call(Nd,actordb_shardtree,all,[]) of
		{badrpc,_Err} ->
			?INF("waiting for shard from ~p",[Nd]),
			timer:sleep(1000),
			wait_tree(Nd,N-1000);
		Tree ->
			?INF("Have shard tree ~p~n ~p",[Nd,Tree]),
			timer:sleep(1000),
			ok
	end.

wait_modified_tree(Nd,All,Milis) when is_integer(Milis) ->
	{A,B,C} = os:timestamp(),
	wait_modified_tree(Nd,All,{A,B+(Milis div 1000),C+(Milis rem 1000)*1000});
wait_modified_tree(Nd,All,StopAt) ->
	TDiff = timer:now_diff(os:timestamp(),StopAt),
	Remain = erlang:abs(TDiff) div 1000,
	case TDiff > 0 of
		true ->
			exit(timeout);
		false ->
			?INF("Nodes connected on=~p are=~p",[Nd,rpc:call(Nd,erlang,nodes,[connected])]),
			case rpc:call(Nd,gen_server,call,[actordb_shardmngr,get_all_shards]) of
				{[_|_] = AllShards1,_Local} ->
					AllShards2 = lists:keysort(1,AllShards1),
					AllShards = [{From,To,To-From,Ndx} || {From,To,Ndx} <- AllShards2],
					?INF("~p allshards ~p",[time(),AllShards]),
					[?INF("~p For nd ~p, beingtaken ~p",[time(),Ndx,
							rpc:call(Ndx,gen_server,call,[actordb_shardmngr,being_taken])]) || Ndx <- All],
					[?INF("~p For nd ~p, moves ~p",[time(),Ndx,
							rpc:call(Ndx,gen_server,call,[actordb_shardmvr,get_moves])]) || Ndx <- All],
					case lists:keymember(butil:tobin(dist_to_bkdnm(Nd)),4,AllShards) of
						false ->
							?INF("not member of shard tree, timeleft=~p",[Remain]),
							timer:sleep(1000),
							wait_modified_tree(Nd,All,StopAt);
						true ->
							case rpc:call(Nd,gen_server,call,[actordb_shardmvr,get_moves]) of
								{[],[]} ->
									case lists:filter(fun({_,_,_,SNode}) -> SNode == butil:tobin(dist_to_bkdnm(Nd)) end,AllShards) of
										[_,_,_|_] ->
											ok;
										_X ->
											?INF("get_moves empty, should have 3 shards ~p ~p",[Nd,_X]),
											% ?debugFmt("get_moves wrong num shards ~p~n ~p",[Nd,X]),
											timer:sleep(1000),
											wait_modified_tree(Nd,All,StopAt)
									end;
								_L ->
									?INF("Still moving processes ~p, timeleft ~p",[Nd,Remain]),
									timer:sleep(1000),
									wait_modified_tree(Nd,All,StopAt)
							end
					end;
				{_,_Err} ->
					?INF("Waiting for shard data from ~p, time left=~p",[Nd,Remain]),
					timer:sleep(1000),
					wait_modified_tree(Nd,All,StopAt)
			end
	end.

dist_to_bkdnm(Nm) ->
	[BN|_] = string:tokens(atom_to_list(Nm),"@"),
	butil:tobin(BN).
dist_to_ip(Nm) ->
	[_,IP] = string:tokens(atom_to_list(Nm),"@"),
	IP.