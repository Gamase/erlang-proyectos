-module(p40_camas_de_hospital_sup).
-behaviour(supervisor).

%% Arbol de supervision:
%%
%%   p40_camas_de_hospital_sup (rest_for_one)
%%   |- p40_store        tabla ETS con el estado de camas y lista de espera
%%   |- p40_eventos      bitacora + alertas de ocupacion
%%   |- p40_camas_sup    (one_for_one)
%%   |   `- p40_servicio_sup x6 (one_for_one) -> p40_cama x N
%%   `- p40_admisiones   asigna camas, lista de espera, traslados
%%
%% rest_for_one porque el orden importa: las camas leen/escriben el store y
%% reportan a eventos; admisiones consulta a las camas. Si cae un proceso, se
%% reinician el y todos los que arrancaron DESPUES (los que dependen de el), pero
%% nunca los de antes.

-export([start_link/0]).
-export([init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  Hijos = [
    worker(p40_store),
    worker(p40_eventos),
    #{id => p40_camas_sup,
      start => {p40_camas_sup, start_link, []},
      restart => permanent,
      shutdown => infinity,
      type => supervisor},
    worker(p40_admisiones)
  ],
  {ok, {#{strategy => rest_for_one, intensity => 10, period => 60}, Hijos}}.

worker(Modulo) ->
  #{id => Modulo,
    start => {Modulo, start_link, []},
    restart => permanent,
    shutdown => 5000,
    type => worker}.
