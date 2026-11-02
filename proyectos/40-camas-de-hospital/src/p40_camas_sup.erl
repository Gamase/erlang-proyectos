-module(p40_camas_sup).
-behaviour(supervisor).

%% Agrupa los supervisores de cada servicio. one_for_one: un servicio con
%% problemas (por ejemplo, camas que truenan una y otra vez hasta agotar su
%% intensidad) se reinicia solo, sin tumbar a los demas servicios.

-export([start_link/0]).
-export([init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  Hijos = [#{id => {servicio, Servicio},
             start => {p40_servicio_sup, start_link, [Servicio, Prefijo, Camas]},
             restart => permanent,
             shutdown => infinity,
             type => supervisor}
           || {Servicio, Prefijo, Camas} <- p40_config:servicios()],
  {ok, {#{strategy => one_for_one, intensity => 5, period => 60}, Hijos}}.
