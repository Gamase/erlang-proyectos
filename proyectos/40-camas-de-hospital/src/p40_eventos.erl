-module(p40_eventos).
-behaviour(gen_server).

%% Bitacora de eventos y alertas de ocupacion.
%%  - Guarda los ultimos ?MAX eventos (para la pantalla de historial).
%%  - Cada cambio de cama recalcula la ocupacion de ESE servicio y dispara una
%%    alerta cuando cruza el umbral (~85 %), y otra cuando baja (resuelta). Solo
%%    avisa al cruzar, no en cada evento, para no inundar la bitacora.
%%  - Reenvia cada evento a los suscriptores (lo usara el SSE de cowboy).

-export([start_link/0, cambio/3, registrar/1, ultimos/1, suscribir/0,
         alertas_activas/0, estadisticas/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(MAX, 500).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% cast: quien reporta (una cama) nunca debe quedarse esperando a la bitacora.
cambio(De, #{estado := A} = Cama, DuracionMs) ->
  gen_server:cast(?MODULE, {cambio, De, A, Cama, DuracionMs}).

registrar(Evento) when is_map(Evento) ->
  gen_server:cast(?MODULE, {registrar, Evento}).

ultimos(N) ->
  gen_server:call(?MODULE, {ultimos, N}).

suscribir() ->
  gen_server:call(?MODULE, suscribir).

alertas_activas() ->
  gen_server:call(?MODULE, alertas_activas).

%% Contadores para /metrics: eventos por tipo, altas (rotacion de camas) y
%% tiempo acumulado de limpieza.
estadisticas() ->
  gen_server:call(?MODULE, estadisticas).

init([]) ->
  {ok, #{eventos => [], total => 0, suscriptores => #{}, alertas => #{},
        por_tipo => #{}, altas => 0, limpiezas => 0, limpieza_ms => 0}}.

handle_call({ultimos, N}, _From, #{eventos := Eventos} = State) ->
  {reply, lists:sublist(Eventos, N), State};
handle_call(suscribir, {Pid, _Tag}, #{suscriptores := Subs} = State) ->
  Ref = erlang:monitor(process, Pid),
  {reply, ok, State#{suscriptores := Subs#{Pid => Ref}}};
handle_call(alertas_activas, _From, #{alertas := Alertas} = State) ->
  {reply, Alertas, State};
handle_call(estadisticas, _From, State) ->
  {reply, maps:with([total, por_tipo, altas, limpiezas, limpieza_ms], State), State}.

handle_cast({cambio, De, A, #{id := Id, servicio := Servicio} = Cama, DuracionMs},
            State00) ->
  State0 = contar_cambio(De, A, DuracionMs, State00),
  Paciente = case A of
    por_limpiar -> maps:get(ultimo_paciente, Cama);
    _ -> maps:get(paciente, Cama)
  end,
  State = agregar(#{tipo => cambio, cama => Id, servicio => Servicio,
                    de => De, a => A, paciente => Paciente}, State0),
  {noreply, revisar_umbral(Servicio, State)};
handle_cast({registrar, Evento}, State) ->
  {noreply, agregar(Evento, State)}.

handle_info({'DOWN', _Ref, process, Pid, _Razon}, #{suscriptores := Subs} = State) ->
  {noreply, State#{suscriptores := maps:remove(Pid, Subs)}};
handle_info(_Info, State) ->
  {noreply, State}.

%%% Internas ---------------------------------------------------------------------

contar_cambio(ocupada, por_limpiar, _Ms, #{altas := Altas} = State) ->
  State#{altas := Altas + 1};
contar_cambio(por_limpiar, libre, Ms, #{limpiezas := N, limpieza_ms := Total} = State) ->
  State#{limpiezas := N + 1, limpieza_ms := Total + Ms};
contar_cambio(_De, _A, _Ms, State) ->
  State.

agregar(#{tipo := Tipo} = Evento0,
        #{eventos := Eventos, total := Total, suscriptores := Subs, por_tipo := PorTipo} = State) ->
  Evento = Evento0#{n => Total + 1, ts => erlang:system_time(millisecond)},
  [Pid ! {p40_evento, Evento} || Pid <- maps:keys(Subs)],
  State#{eventos := lists:sublist([Evento | Eventos], ?MAX), total := Total + 1,
         por_tipo := PorTipo#{Tipo => maps:get(Tipo, PorTipo, 0) + 1}}.

revisar_umbral(Servicio, #{alertas := Alertas} = State) ->
  Resumen = p40_ocupacion:resumen(p40_store:camas(Servicio)),
  Ocupacion = case Resumen of
    #{Servicio := #{ocupacion := O}} -> O;
    #{} -> 0.0
  end,
  Umbral = p40_config:umbral_alerta(),
  Activa = maps:is_key(Servicio, Alertas),
  if
    Ocupacion >= Umbral, not Activa ->
      logger:warning("ocupacion critica en ~p: ~.1f %", [Servicio, Ocupacion * 100],
                     #{proyecto => p40_camas_de_hospital, servicio => Servicio}),
      agregar(#{tipo => alerta, servicio => Servicio, ocupacion => Ocupacion},
              State#{alertas := Alertas#{Servicio => Ocupacion}});
    Ocupacion < Umbral, Activa ->
      agregar(#{tipo => alerta_resuelta, servicio => Servicio, ocupacion => Ocupacion},
              State#{alertas := maps:remove(Servicio, Alertas)});
    true ->
      State
  end.
