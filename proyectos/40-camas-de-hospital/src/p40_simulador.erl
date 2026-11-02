-module(p40_simulador).
-behaviour(gen_server).

%% Simula el escenario del problema sobre las camas reales (los mismos procesos
%% que usaria el sistema en produccion):
%%  - ~40 ingresos al dia, cargados a la noche (urgencias) y ~40 altas al dia,
%%    concentradas por la tarde.
%%  - Altas inciertas: cuando a un paciente ya le toca salir, a veces se retrasa
%%    (receta, transporte, familiares) y se reprograma unas horas despues.
%%  - Algunas limpiezas tardan 2 horas en lugar de ~45 min.
%%  - De vez en cuando un paciente se agrava y se traslada a terapia intensiva.
%%  - Fallas inyectadas: cada cierto tiempo matamos el proceso de una cama al azar.
%%  - brote/1 mete muchos pacientes de golpe a aislamiento.
%%
%% El reloj simulado arranca el dia 1 a las 08:00 y avanza segun minuto_ms.
%% Va al final del arbol de supervision: si truena, solo se reinicia el.

-export([start_link/0, estado/0, brote/1, pausar/0, reanudar/0, reporte/0,
         reloj_de/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
%% Exportadas para probarlas solas.
-export([poisson/1, reloj/1]).

-define(TICK_MIN, 5).                 % cada cuantos minutos simulados avanza
-define(INGRESOS_DIA, 40).
-define(HORA_INICIO, 8).
-define(OCUPACION_INICIAL, 0.7).
-define(PROB_ALTA_A_TIEMPO, 0.7).     % igual que prob_alta de la prediccion
-define(PROB_LIMPIEZA_LENTA, 0.1).
-define(PROB_TRASLADO_TICK, 0.02).
-define(SERVICIO_GRAVE, terapia_intensiva).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

estado() -> gen_server:call(?MODULE, estado).
brote(N) -> gen_server:call(?MODULE, {brote, N}).
pausar() -> gen_server:call(?MODULE, pausar).

%% Hora simulada ("Dia 2 14:35") de una marca de tiempo real, para la bitacora.
%% Sin simulador corriendo regresa undefined y la UI usa la hora del reloj.
reloj_de(TsMs) ->
  case whereis(?MODULE) of
    undefined -> undefined;
    _Pid ->
      Inicio = gen_server:call(?MODULE, inicio),
      reloj(?HORA_INICIO * 60 + (TsMs - Inicio) div p40_config:minuto_ms())
  end.
reanudar() -> gen_server:call(?MODULE, reanudar).

%% Resumen legible para la consola (y para copiar al README).
reporte() ->
  #{reloj := Reloj} = Est = estado(),
  io:format("~n== ~s ==~n", [Reloj]),
  io:format("ingresos ~p  altas ~p  retrasadas ~p  traslados ~p  fallas ~p~n",
            [maps:get(K, Est) || K <- [ingresos, altas, altas_retrasadas, traslados,
                                       fallas]]),
  Resumen = p40_ocupacion:resumen(p40_store:camas()),
  Prediccion = p40_admisiones:prediccion(240),
  Espera = p40_admisiones:en_espera(),
  io:format("~-20s ~5s ~5s ~6s ~6s ~7s ~9s~n",
            ["servicio", "ocup", "libre", "limp.", "%", "espera", "libres4h"]),
  maps:foreach(
    fun(Servicio, #{ocupada := O, libre := L, por_limpiar := PL, ocupacion := Pct}) ->
      #{esperadas := E} = maps:get(Servicio, Prediccion),
      io:format("~-20s ~5b ~5b ~6b ~5.1f% ~7b ~9b~n",
                [Servicio, O, L, PL, Pct * 100, length(maps:get(Servicio, Espera, [])), E])
    end, Resumen),
  io:format("alertas activas: ~p~n", [maps:keys(p40_eventos:alertas_activas())]),
  ok.

%%% gen_server -----------------------------------------------------------------

init([]) ->
  rand:seed(exsss, semilla()),
  State0 = #{inicio => ahora(), pausado => false, siguiente => 1,
             ingresos => 0, altas => 0, altas_retrasadas => 0, traslados => 0,
             fallas => 0, ultima_falla => 0},
  %% Arrancamos con el hospital a ~75 %: un hospital vacio no es realista.
  State = llenado_inicial(State0),
  programar_tick(),
  {ok, State}.

handle_call(inicio, _From, #{inicio := Inicio} = State) ->
  {reply, Inicio, State};
handle_call(estado, _From, State) ->
  Publico = maps:with([ingresos, altas, altas_retrasadas, traslados, fallas, pausado],
                      State),
  {reply, Publico#{reloj => reloj(minuto_sim(State))}, State};
handle_call({brote, N}, _From, State0) ->
  p40_eventos:registrar(#{tipo => brote, servicio => aislamiento, pacientes => N}),
  State = lists:foldl(fun(_, S) -> ingresar(aislamiento, S) end, State0,
                      lists:seq(1, N)),
  {reply, ok, State};
handle_call(pausar, _From, State) ->
  {reply, ok, State#{pausado := true}};
handle_call(reanudar, _From, State) ->
  {reply, ok, State#{pausado := false}}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(tick, #{pausado := true} = State) ->
  programar_tick(),
  {noreply, State};
handle_info(tick, State0) ->
  Minuto = minuto_sim(State0),
  Hora = (Minuto rem 1440) div 60,
  State1 = ingresos_del_tick(Hora, State0),
  State2 = altas_del_tick(Hora, State1),
  State3 = traslado_eventual(State2),
  State = falla_eventual(Minuto, State3),
  programar_tick(),
  {noreply, State};
handle_info(_Info, State) ->
  {noreply, State}.

%%% Ingresos -----------------------------------------------------------------------

ingresos_del_tick(Hora, State) ->
  Lambda = ?INGRESOS_DIA / 1440 * ?TICK_MIN * peso_ingreso(Hora),
  lists:foldl(fun(_, S) -> ingresar(servicio_al_azar(), S) end, State,
              lists:seq(1, poisson(Lambda))).

%% Urgencias llega sobre todo de noche. Los pesos promedian ~1 en el dia.
peso_ingreso(Hora) when Hora >= 20; Hora < 6 -> 1.6;
peso_ingreso(_Hora) -> 0.6.

ingresar(Servicio, #{siguiente := N, ingresos := Ingresos} = State) ->
  Paciente = id_paciente(N),
  _ = p40_admisiones:admitir(Paciente, Servicio),
  State#{siguiente := N + 1, ingresos := Ingresos + 1}.

id_paciente(N) ->
  iolist_to_binary(io_lib:format("P-~4..0b", [N])).

%% Cada servicio recibe pacientes en proporcion a sus camas.
servicio_al_azar() ->
  Servicios = p40_config:servicios(),
  Total = lists:sum([C || {_, _, C} <- Servicios]),
  elegir(rand:uniform(Total), Servicios).

elegir(R, [{Servicio, _, C} | _]) when R =< C -> Servicio;
elegir(R, [{_, _, C} | Resto]) -> elegir(R - C, Resto).

llenado_inicial(State0) ->
  Camas = p40_store:camas(),
  case [C || #{estado := ocupada} = C <- Camas] of
    [] -> llenar(Camas, State0);
    %% Si el simulador se reinicio, el hospital ya tiene pacientes: no lo llenamos
    %% otra vez.
    _ -> State0
  end.

llenar(Camas, State0) ->
  lists:foldl(
    fun(#{servicio := Servicio}, #{siguiente := N} = S) ->
      case rand:uniform() < ?OCUPACION_INICIAL of
        true ->
          S1 = ingresar(Servicio, S),
          %% Estos pacientes ya llevaban dias internados: les queda solo una
          %% parte de su estancia (si no, nadie saldria el primer dia).
          Paciente = id_paciente(N),
          [seguro(fun() -> p40_cama:programar_alta(Id, rand:uniform(2 * 1440)) end)
           || #{id := Id, paciente := P} <- p40_store:camas(Servicio), P =:= Paciente],
          S1;
        false ->
          S
      end
    end, State0, Camas).

%%% Altas --------------------------------------------------------------------------

altas_del_tick(Hora, State0) ->
  Ahora = ahora(),
  Ocupadas = [C || #{estado := ocupada} = C <- p40_store:camas()],
  %% A quien todavia no tiene alta programada (recien ingresado o que salio de la
  %% lista de espera) le estimamos su estancia.
  [seguro(fun() -> p40_cama:programar_alta(Id, estancia_min()) end)
   || #{id := Id, alta_estimada := undefined} <- Ocupadas],
  Vencidas = [Id || #{id := Id, alta_estimada := A} <- Ocupadas,
                    is_integer(A), A =< Ahora],
  case horario_de_altas(Hora) of
    true -> lists:foldl(fun intentar_alta/2, State0, Vencidas);
    false -> State0
  end.

%% Las altas se firman por la tarde.
horario_de_altas(Hora) -> Hora >= 11 andalso Hora < 19.

intentar_alta(Id, #{altas := Altas, altas_retrasadas := Retrasadas} = State) ->
  case rand:uniform() < ?PROB_ALTA_A_TIEMPO of
    true ->
      Opts = case rand:uniform() < ?PROB_LIMPIEZA_LENTA of
        true -> #{limpieza_min => 120};
        false -> #{}
      end,
      case seguro(fun() -> p40_cama:dar_alta(Id, Opts) end) of
        ok -> State#{altas := Altas + 1};
        _ -> State
      end;
    false ->
      %% Se retrasa: falta la receta, el transporte o el familiar.
      seguro(fun() -> p40_cama:programar_alta(Id, 120 + rand:uniform(240)) end),
      State#{altas_retrasadas := Retrasadas + 1}
  end.

%% Estancia: minimo 12 h + exponencial con media ~1.1 dias. Sumando la espera a
%% que se firme el alta por la tarde y los retrasos, la estancia real ronda 2.3
%% dias: con 40 ingresos/dia eso deja ~90 de 120 camas ocupadas (~75-80 %).
estancia_min() ->
  720 + round(-math:log(1.0 - rand:uniform()) * 1.1 * 1440).

%%% Traslados y fallas ---------------------------------------------------------------

traslado_eventual(#{traslados := T} = State) ->
  Candidatas = [Id || #{id := Id, estado := ocupada, servicio := S} <- p40_store:camas(),
                      S =/= ?SERVICIO_GRAVE],
  case rand:uniform() < ?PROB_TRASLADO_TICK andalso Candidatas =/= [] of
    true ->
      Id = lists:nth(rand:uniform(length(Candidatas)), Candidatas),
      case p40_admisiones:trasladar(Id, ?SERVICIO_GRAVE) of
        {ok, _} -> State#{traslados := T + 1};
        {error, _} -> State
      end;
    false ->
      State
  end.

falla_eventual(Minuto, #{ultima_falla := Ultima, fallas := Fallas} = State) ->
  Cada = application:get_env(p40_camas_de_hospital, falla_cada_min, 360),
  case Cada > 0 andalso Minuto - Ultima >= Cada of
    true ->
      Camas = p40_store:camas(),
      #{id := Id, estado := Estado} = lists:nth(rand:uniform(length(Camas)), Camas),
      case whereis(p40_cama:nombre(Id)) of
        Pid when is_pid(Pid) ->
          p40_eventos:registrar(#{tipo => falla_inyectada, cama => Id, estado => Estado}),
          logger:warning("falla inyectada: matando cama ~s (~p)", [Id, Estado],
                         #{proyecto => p40_camas_de_hospital, cama => Id}),
          exit(Pid, kill),
          State#{ultima_falla := Minuto, fallas := Fallas + 1};
        undefined ->
          State#{ultima_falla := Minuto}
      end;
    false ->
      State
  end.

%%% Utilidades -----------------------------------------------------------------------

%% El simulador tambien habla con camas que pudo haber matado hace un instante;
%% si la cama se esta reiniciando lo intentamos en el siguiente tick.
seguro(Fun) ->
  try Fun()
  catch exit:{_Razon, {gen_statem, call, _}} -> {error, cama_caida}
  end.

%% Knuth: suficiente para lambdas chicas como las de un tick.
poisson(Lambda) ->
  knuth(math:exp(-Lambda), 0, rand:uniform()).

knuth(Limite, K, P) when P > Limite -> knuth(Limite, K + 1, P * rand:uniform());
knuth(_Limite, K, _P) -> K.

minuto_sim(#{inicio := Inicio}) ->
  ?HORA_INICIO * 60 + (ahora() - Inicio) div p40_config:minuto_ms().

%% 1950 -> "Dia 2 08:30"
reloj(Minuto) ->
  lists:flatten(io_lib:format("Dia ~b ~2..0b:~2..0b",
                              [Minuto div 1440 + 1, (Minuto rem 1440) div 60, Minuto rem 60])).

programar_tick() ->
  erlang:send_after(?TICK_MIN * p40_config:minuto_ms(), self(), tick).

%% Semilla fija configurable: la misma corrida se puede repetir en la exposicion.
semilla() ->
  application:get_env(p40_camas_de_hospital, semilla, {40, 27, 2026}).

ahora() -> erlang:system_time(millisecond).
