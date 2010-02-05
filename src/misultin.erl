% ==========================================================================================================
% MISULTIN - Main
%
% >-|-|-(°>
% 
% Copyright (C) 2010, Roberto Ostinelli <roberto@ostinelli.net>, Sean Hinde.
% All rights reserved.
%
% Code portions from Sean Hinde have been originally taken under BSD license from Trapexit at the address:
% <http://www.trapexit.org/A_fast_web_server_demonstrating_some_undocumented_Erlang_features>
%
% BSD License
% 
% Redistribution and use in source and binary forms, with or without modification, are permitted provided
% that the following conditions are met:
%
%  * Redistributions of source code must retain the above copyright notice, this list of conditions and the
%	 following disclaimer.
%  * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and
%	 the following disclaimer in the documentation and/or other materials provided with the distribution.
%  * Neither the name of the authors nor the names of its contributors may be used to endorse or promote
%	 products derived from this software without specific prior written permission.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
% WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
% PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
% ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
% TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
% HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
% NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.
% ==========================================================================================================
-module(misultin).
-behaviour(gen_server).
-vsn('0.4.0').

% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% API
-export([start_link/1, stop/0, create_acceptor/0, websocket_pid_add/1, websocket_pid_remove/1]).

% macros
-define(SERVER, ?MODULE).

% records
-record(state, {
	listen_socket,
	port,
	loop,
	acceptor,
	recv_timeout,
	stream_support,
	ws_loop,
	ws_references = []
}).

% includes
-include("../include/misultin.hrl").


% ============================ \/ API ======================================================================

% Function: {ok,Pid} | ignore | {error, Error}
% Description: Starts the server.
start_link(Options) when is_list(Options) -> 
    gen_server:start_link({local, ?SERVER}, ?MODULE, [Options], []).

start_link(Loop, ConfigPath) when is_function(Loop), is_list(ConfigPath) ->
    {ok, Config} = erlcfg:new(ConfigPath, true),
    Ip = Config:get(misultin.ip, "0.0.0.0"),
    Port = Config:get(misultin.port, 80),
    Backlog = Config:get(misultin.backlog, 30),
    start_link([{loop, Loop}, {ip, Ip}, {port, Port}, {backlog, Backlog}]).

% Function: -> ok
% Description: Manually stops the server.
stop() ->
	gen_server:cast(?SERVER, stop).

% Function: -> ok
% Description: Send message to cause a new acceptor to be created
create_acceptor() ->
	gen_server:cast(?SERVER, create_acceptor).

% Function -> ok
% Description: Adds a new websocket pid reference to status
websocket_pid_add(WsPid) ->
	gen_server:cast(?SERVER, {add_ws_pid, WsPid}).

% Function -> ok
% Description: Remove a websocket pid reference from status
websocket_pid_remove(WsPid) ->
	gen_server:cast(?SERVER, {remove_ws_pid, WsPid}).

% ============================ /\ API ======================================================================


% ============================ \/ GEN_SERVER CALLBACKS =====================================================

% ----------------------------------------------------------------------------------------------------------
% Function: -> {ok, State} | {ok, State, Timeout} | ignore | {stop, Reason}
% Description: Initiates the server.
% ----------------------------------------------------------------------------------------------------------
init([Options]) ->
	process_flag(trap_exit, true),
	?LOG_INFO("starting with Pid: ~p", [self()]),
	% test and get options
	OptionProps = [
		{ip, {0, 0, 0, 0}, fun check_and_convert_string_to_ip/1, invalid_ip},
		{port, 80, fun is_integer/1, port_not_integer},
		{loop, {error, undefined_loop}, fun is_function/1, loop_not_function},
		{backlog, 128, fun is_integer/1, backlog_not_integer},
		{recv_timeout, 30*1000, fun is_integer/1, recv_timeout_not_integer},
		{stream_support, true, fun is_boolean/1, invalid_stream_support_option},
		{ws_loop, none, fun is_function/1, ws_loop_not_function}
	],
	OptionsVerified = lists:foldl(fun(OptionName, Acc) -> [get_option(OptionName, Options)|Acc] end, [], OptionProps),
	case proplists:get_value(error, OptionsVerified) of
		undefined ->
			% get options
			Ip = proplists:get_value(ip, OptionsVerified),
			Port = proplists:get_value(port, OptionsVerified),
			Loop = proplists:get_value(loop, OptionsVerified),
			Backlog = proplists:get_value(backlog, OptionsVerified),
			RecvTimeout = proplists:get_value(recv_timeout, OptionsVerified),
			StreamSupport = proplists:get_value(stream_support, OptionsVerified),
			WsLoop = proplists:get_value(ws_loop, OptionsVerified),
			% ipv6 support
			?LOG_DEBUG("ip address is: ~p", [Ip]),
			InetOpt = case Ip of
				{_, _, _, _} ->
					% IPv4
					inet;
				{_, _, _, _, _, _, _, _} ->
					% IPv6
					inet6
			end,
			% ok, no error found in options -> create listening socket.
			case gen_tcp:listen(Port, [binary, {packet, http}, InetOpt, {ip, Ip}, {reuseaddr, true}, {active, false}, {backlog, Backlog}]) of
				{ok, ListenSocket} ->
					% start listening
					?LOG_DEBUG("starting listener loop", []),
					% create acceptor
					AcceptorPid = misultin_socket:start_link(ListenSocket, Port, Loop, RecvTimeout, StreamSupport, WsLoop),
					{ok, #state{listen_socket = ListenSocket, port = Port, loop = Loop, acceptor = AcceptorPid, recv_timeout = RecvTimeout, stream_support = StreamSupport, ws_loop = WsLoop}};
				{error, Reason} ->
					?LOG_ERROR("error starting: ~p", [Reason]),
					% error
					{stop, Reason}
			end;
		Reason ->
			% error found in options
			{stop, Reason}
	end.

% ----------------------------------------------------------------------------------------------------------
% Function: handle_call(Request, From, State) -> {reply, Reply, State} | {reply, Reply, State, Timeout} |
%									   {noreply, State} | {noreply, State, Timeout} |
%									   {stop, Reason, Reply, State} | {stop, Reason, State}
% Description: Handling call messages.
% ----------------------------------------------------------------------------------------------------------

% handle_call generic fallback
handle_call(_Request, _From, State) ->
	{reply, undefined, State}.

% ----------------------------------------------------------------------------------------------------------
% Function: handle_cast(Msg, State) -> {noreply, State} | {noreply, State, Timeout} | {stop, Reason, State}
% Description: Handling cast messages.
% ----------------------------------------------------------------------------------------------------------

% manual shutdown
handle_cast(stop, State) ->
	?LOG_INFO("manual shutdown..", []),
	{stop, normal, State};

% create
handle_cast(create_acceptor, #state{listen_socket = ListenSocket, port = Port, loop = Loop, recv_timeout = RecvTimeout, stream_support = StreamSupport, ws_loop = WsLoop} = State) ->
	?LOG_DEBUG("creating new acceptor process", []),
	AcceptorPid = misultin_socket:start_link(ListenSocket, Port, Loop, RecvTimeout, StreamSupport, WsLoop),
	{noreply, State#state{acceptor = AcceptorPid}};

% add websocket reference to server
handle_cast({add_ws_pid, WsPid}, #state{ws_references = WsReferences} = State) ->
	{noreply, State#state{ws_references = [WsPid|WsReferences]}};

% remove websocket reference from server
handle_cast({remove_ws_pid, WsPid}, #state{ws_references = WsReferences} = State) ->
	{noreply, State#state{ws_references = lists:delete(WsPid, WsReferences)}};
	
% handle_cast generic fallback (ignore)
handle_cast(_Msg, State) ->
	?LOG_WARNING("received unknown cast message: ~p", [_Msg]),
	{noreply, State}.

% ----------------------------------------------------------------------------------------------------------
% Function: handle_info(Info, State) -> {noreply, State} | {noreply, State, Timeout} | {stop, Reason, State}
% Description: Handling all non call/cast messages.
% ----------------------------------------------------------------------------------------------------------

% The current acceptor has died, respawn
handle_info({'EXIT', Pid, _Reason}, #state{listen_socket = ListenSocket, port = Port, loop = Loop, acceptor = Pid, recv_timeout = RecvTimeout, stream_support = StreamSupport, ws_loop = WsLoop} = State) ->
	?LOG_WARNING("acceptor has died with reason: ~p, respawning", [_Reason]),
	AcceptorPid = misultin_socket:start_link(ListenSocket, Port, Loop, RecvTimeout, StreamSupport, WsLoop),
	{noreply, State#state{acceptor = AcceptorPid}};

% handle_info generic fallback (ignore)
handle_info(_Info, State) ->
	?LOG_WARNING("received unknown info message: ~p", [_Info]),
	{noreply, State}.

% ----------------------------------------------------------------------------------------------------------
% Function: terminate(Reason, State) -> void()
% Description: This function is called by a gen_server when it is about to terminate. When it returns,
% the gen_server terminates with Reason. The return value is ignored.
% ----------------------------------------------------------------------------------------------------------
terminate(_Reason, #state{listen_socket = ListenSocket, acceptor = AcceptorPid, ws_references = WsReferences}) ->
	?LOG_INFO("shutting down server with Pid ~p", [self()]),
	% kill acceptor
	exit(AcceptorPid, kill),
	% send a shutdown message to all websockets, if any
	?LOG_DEBUG("sending shutdown message to websockets, if any", []),
	lists:foreach(fun(WsPid) -> catch WsPid ! shutdown end, WsReferences),
	% stop gen_tcp
	gen_tcp:close(ListenSocket),
	terminated.

% ----------------------------------------------------------------------------------------------------------
% Function: code_change(OldVsn, State, Extra) -> {ok, NewState}
% Description: Convert process state when code is changed.
% ----------------------------------------------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

% ============================ /\ GEN_SERVER CALLBACKS =====================================================


% ============================ \/ INTERNAL FUNCTIONS =======================================================

% Function: -> false | IpTuple
% Description: Checks and converts a string Ip to inet repr.
check_and_convert_string_to_ip(Ip) ->
	case inet_parse:address(Ip) of
		{error, _Reason} ->
			false;
		{ok, IpTuple} ->
			IpTuple
	end.

% Description: Validate and get misultin options.
get_option({OptionName, DefaultValue, CheckAndConvertFun, FailTypeError}, Options) ->
	case proplists:get_value(OptionName, Options) of
		undefined ->
			case DefaultValue of
				{error, Reason} ->
					{error, Reason};
				Value -> 
					{OptionName, Value}
			end;
		Value ->
			case CheckAndConvertFun(Value) of
				false ->
					{error, {FailTypeError, Value}};
				true -> 
					{OptionName, Value};
				OutValue ->
					{OptionName, OutValue}
			end
	end.
% ============================ /\ INTERNAL FUNCTIONS =======================================================
