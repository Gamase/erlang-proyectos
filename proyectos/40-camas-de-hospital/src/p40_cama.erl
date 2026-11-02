-module(p40_cama).
-behaviour(gen_statem).

%% Una cama = un proceso gen_statem. Estados legales y quien dispara cada cambio:
%%
%%   libre --ocupar (admisiones)--> ocupada
%%   ocupada --dar_alta (medico/enfermeria)--> por_limpiar
%%   por_limpiar --timeout de limpieza o terminar_limpieza (intendencia)--> libre
%%   libre --bloquear (mantenimiento)--> bloqueada --desbloquear--> libre
%%
%% Cualquier otra peticion se rechaza con {error, {estado, EstadoActual}}: por
%% ejemplo, ocupar una cama ocupada. Esa regla es la que evita que dos servicios
%% se queden con la misma cama aunque alguien se salte a admisiones.

-export([start_link/2, nombre/1, info/1, ocupar/2, dar_alta/1, dar_alta/2,
         terminar_limpieza/1, bloquear/2, desbloquear/1, programar_alta/2]).
-export([init/1, callback_mode/0, libre/3, ocupada/3, por_limpiar/3, bloqueada/3]).

%%% API ----------------------------------------------------------------------

start_link(Id, Servicio) ->
  gen_statem:start_link({local, nombre(Id)}, ?MODULE, {Id, Servicio}, []).

%% Registro local por nombre: el conjunto de camas viene de la configuracion, asi
%% que los atoms son acotados (120), y al morir el proceso el nombre se libera de
%% inmediato, lo que permite que el supervisor lo reinicie sin conflictos.
nombre(Id) ->
  binary_to_atom(<<"p40_cama_", Id/binary>>, utf8).

info(Id) -> gen_statem:call(nombre(Id), info).
ocupar(Id, Paciente) -> gen_statem:call(nombre(Id), {ocupar, Paciente}).
dar_alta(Id) -> dar_alta(Id, #{}).
%% Opts: #{limpieza_min => N} para simular una limpieza mas lenta de lo normal.
dar_alta(Id, Opts) -> gen_statem:call(nombre(Id), {alta, Opts}).
terminar_limpieza(Id) -> gen_statem:call(nombre(Id), terminar_limpieza).
bloquear(Id, Motivo) -> gen_statem:call(nombre(Id), {bloquear, Motivo}).
desbloquear(Id) -> gen_statem:call(nombre(Id), desbloquear).
%% El medico estima que el paciente sale en N minutos (alimenta la prediccion).
programar_alta(Id, EnMinutos) -> gen_statem:call(nombre(Id), {programar_alta, EnMinutos}).

%%% gen_statem -----------------------------------------------------------------

callback_mode() -> state_functions.

init({Id, Servicio}) ->
  Base = #{id => Id, servicio => Servicio, paciente => undefined,
           ultimo_paciente => undefined, desde => ahora(),
           alta_estimada => undefined, limpieza_hasta => undefined,
           motivo => undefined},
  case p40_store:leer({cama, Id}) of
    {ok, #{estado := Estado} = Guardada} ->
      %% Venimos de un crash: retomamos el estado guardado en lugar de
      %% arrancar en libre (eso dejaria a un paciente "sin cama").
      Data = maps:merge(Base, maps:remove(estado, Guardada)),
      logger:warning("cama ~s restaurada en estado ~p", [Id, Estado],
                     #{proyecto => p40_camas_de_hospital, cama => Id}),
      p40_eventos:registrar(#{tipo => restaurada, cama => Id, servicio => Servicio,
                              estado => Estado}),
      avisar_si_libre(Estado, Data),
      {ok, Estado, Data, timeout_de(Estado, Data)};
    none ->
      publicar(libre, Base),
      {ok, libre, Base}
  end.

libre({call, From}, {ocupar, Paciente}, Data) ->
  ir(ocupada, libre, Data#{paciente := Paciente}, From);
libre({call, From}, {bloquear, Motivo}, Data) ->
  ir(bloqueada, libre, Data#{motivo := Motivo}, From);
libre(Tipo, Evento, Data) ->
  comun(Tipo, Evento, libre, Data).

ocupada({call, From}, {alta, Opts}, #{paciente := Paciente} = Data) ->
  Minutos = maps:get(limpieza_min, Opts, p40_config:limpieza_min()),
  Hasta = ahora() + Minutos * p40_config:minuto_ms(),
  ir(por_limpiar, ocupada,
     Data#{paciente := undefined, ultimo_paciente := Paciente,
           alta_estimada := undefined, limpieza_hasta := Hasta}, From);
ocupada({call, From}, {programar_alta, EnMinutos}, Data0)
    when is_integer(EnMinutos), EnMinutos >= 0 ->
  Data = Data0#{alta_estimada := ahora() + EnMinutos * p40_config:minuto_ms()},
  publicar(ocupada, Data),
  {keep_state, Data, [{reply, From, ok}]};
ocupada(Tipo, Evento, Data) ->
  comun(Tipo, Evento, ocupada, Data).

por_limpiar(state_timeout, limpieza_terminada, Data) ->
  ir(libre, por_limpiar, Data#{limpieza_hasta := undefined}, sin_respuesta);
por_limpiar({call, From}, terminar_limpieza, Data) ->
  ir(libre, por_limpiar, Data#{limpieza_hasta := undefined}, From);
por_limpiar(Tipo, Evento, Data) ->
  comun(Tipo, Evento, por_limpiar, Data).

bloqueada({call, From}, desbloquear, Data) ->
  ir(libre, bloqueada, Data#{motivo := undefined}, From);
bloqueada(Tipo, Evento, Data) ->
  comun(Tipo, Evento, bloqueada, Data).

%% Peticiones validas en cualquier estado, y rechazo explicito de transiciones
%% ilegales. Una peticion que no conocemos no se atrapa: es un bug y debe tronar.
comun({call, From}, info, Estado, Data) ->
  {keep_state_and_data, [{reply, From, snapshot(Estado, Data)}]};
comun({call, From}, Peticion, Estado, _Data) ->
  true = peticion_conocida(Peticion),
  {keep_state_and_data, [{reply, From, {error, {estado, Estado}}}]}.

peticion_conocida({ocupar, _}) -> true;
peticion_conocida({alta, _}) -> true;
peticion_conocida(terminar_limpieza) -> true;
peticion_conocida({bloquear, _}) -> true;
peticion_conocida(desbloquear) -> true;
peticion_conocida({programar_alta, _}) -> true.

%%% Internas -------------------------------------------------------------------

%% Toda transicion pasa por aqui: guarda el estado ANTES de responder (asi quien
%% lea el store justo despues ya ve el cambio), avisa a la bitacora y, si la cama
%% quedo libre, avisa a admisiones por si hay pacientes en espera.
ir(Nuevo, Viejo, #{desde := Desde} = Data0, From) ->
  Ahora = ahora(),
  Data = Data0#{desde := Ahora},
  publicar(Nuevo, Data),
  %% La duracion del estado que termina alimenta metricas como el tiempo real de
  %% limpieza (por_limpiar -> libre).
  p40_eventos:cambio(Viejo, snapshot(Nuevo, Data), Ahora - Desde),
  avisar_si_libre(Nuevo, Data),
  Respuesta = case From of
    sin_respuesta -> [];
    _ -> [{reply, From, ok}]
  end,
  {next_state, Nuevo, Data, Respuesta ++ timeout_de(Nuevo, Data)}.

publicar(Estado, #{id := Id} = Data) ->
  p40_store:guardar({cama, Id}, snapshot(Estado, Data)).

snapshot(Estado, Data) ->
  Data#{estado => Estado}.

avisar_si_libre(libre, #{id := Id, servicio := Servicio}) ->
  p40_admisiones:cama_libre(Id, Servicio);
avisar_si_libre(_Estado, _Data) ->
  ok.

%% El timer de limpieza se calcula contra limpieza_hasta (hora absoluta), asi que
%% sobrevive a un reinicio: la cama restaurada solo espera lo que le faltaba.
timeout_de(por_limpiar, #{limpieza_hasta := Hasta}) ->
  [{state_timeout, max(0, Hasta - ahora()), limpieza_terminada}];
timeout_de(_Estado, _Data) ->
  [].

ahora() -> erlang:system_time(millisecond).
