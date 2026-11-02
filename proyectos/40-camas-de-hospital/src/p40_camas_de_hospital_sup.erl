-module(p40_camas_de_hospital_sup).
-behaviour(supervisor).

%% Arbol de supervision:
%%
%%   p40_camas_de_hospital_sup (rest_for_one)
%%   |- p40_store        tabla ETS con el estado de camas y lista de espera
%%   |- p40_eventos      bitacora + alertas de ocupacion
%%   |- p40_camas_sup    (one_for_one)
%%   |   `- p40_servicio_sup x6 (one_for_one) -> p40_cama x N
%%   |- p40_admisiones   asigna camas, lista de espera, traslados
%%   |- p40_simulador    (opcional, {simulacion, true}) genera el escenario
%%   `- p40_http         (opcional, {puerto, N}) listener cowboy: UI, API, SSE
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
  ] ++ simulador() ++ http(),
  {ok, {#{strategy => rest_for_one, intensity => 10, period => 60}, Hijos}}.

%% El simulador es opcional para que los tests y un despliegue "real" no lo
%% arranquen. Va al final: depende de todo lo demas y nadie depende de el.
simulador() ->
  case application:get_env(p40_camas_de_hospital, simulacion, false) of
    true -> [worker(p40_simulador)];
    false -> []
  end.

%% El listener va al final: si se reinicia algo de lo anterior, las conexiones
%% SSE se cierran y el navegador se reconecta contra procesos nuevos. Cuelga del
%% arbol con ranch:child_spec, igual que en el demo de cowboy del curso.
http() ->
  case application:get_env(p40_camas_de_hospital, puerto) of
    {ok, Puerto} when is_integer(Puerto) -> [listener(Puerto)];
    undefined -> []
  end.

listener(Puerto) ->
  App = p40_camas_de_hospital,
  Dispatch = cowboy_router:compile([{'_', [
    {"/",                        cowboy_static, {priv_file, App, "www/index.html"}},
    {"/api/resumen",             p40_api_h, resumen},
    {"/api/camas",               p40_api_h, camas},
    {"/api/camas/:id",           p40_api_h, cama},
    {"/api/camas/:id/:accion",   p40_api_h, accion_cama},
    {"/api/admisiones",          p40_api_h, admisiones},
    {"/api/traslados",           p40_api_h, traslados},
    {"/api/eventos",             p40_api_h, eventos},
    {"/api/simulador/brote",     p40_api_h, brote},
    {"/sse",                     p40_sse_h, []},
    {"/metrics",                 p40_metrics_h, []}
  ]}]),
  ranch:child_spec(p40_http, ranch_tcp, #{socket_opts => [{port, Puerto}]},
                   cowboy_clear, #{env => #{dispatch => Dispatch}}).

worker(Modulo) ->
  #{id => Modulo,
    start => {Modulo, start_link, []},
    restart => permanent,
    shutdown => 5000,
    type => worker}.
