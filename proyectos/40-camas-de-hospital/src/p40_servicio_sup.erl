-module(p40_servicio_sup).
-behaviour(supervisor).

%% Un supervisor por servicio (piso). one_for_one porque las camas son
%% independientes: si truena una cama de pediatria, solo esa se reinicia y
%% recupera su estado desde p40_store; las demas ni se enteran.

-export([start_link/3]).
-export([init/1]).

start_link(Servicio, Prefijo, Camas) ->
  supervisor:start_link(?MODULE, {Servicio, Prefijo, Camas}).

init({Servicio, Prefijo, Camas}) ->
  Hijos = [#{id => Id,
             start => {p40_cama, start_link, [Id, Servicio]},
             restart => permanent,
             shutdown => 2000,
             type => worker}
           || Id <- p40_config:ids(Prefijo, Camas)],
  {ok, {#{strategy => one_for_one, intensity => 10, period => 60}, Hijos}}.
