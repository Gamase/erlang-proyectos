-module(p40_admisiones).
-behaviour(gen_server).

%% Asigna camas a pacientes. Es UN solo proceso a proposito: las peticiones se
%% atienden una por una, asi que si dos servicios piden la ultima cama libre al
%% mismo tiempo, solo la primera la obtiene. Ademas la cama misma rechaza que la
%% ocupen dos veces (doble candado).
%%
%% Decision cuando no hay cama del tipo requerido: NO se asigna una cama de otro
%% servicio (un paciente de terapia intensiva no va a cama general). El paciente
%% entra a una lista de espera por servicio, se registra un evento sin_cama, y en
%% cuanto una cama de ese servicio queda libre se le asigna automaticamente.

-export([start_link/0, admitir/2, trasladar/2, en_espera/0, cama_libre/2,
         prediccion/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% -> {ok, CamaId} | {en_espera, Posicion} | {error, servicio_desconocido}
admitir(Paciente, Servicio) ->
  gen_server:call(?MODULE, {admitir, Paciente, Servicio}).

%% Traslado interno: primero se reserva la cama destino y luego se da de alta la
%% de origen, para que el paciente nunca se quede sin cama. Durante ese instante
%% ocupa ambas, pero como todo pasa dentro de este proceso nadie mas lo ve a medias.
%% -> {ok, CamaDestino} | {error, sin_cama} | {error, {origen, Estado}}
trasladar(CamaOrigen, ServicioDestino) ->
  gen_server:call(?MODULE, {trasladar, CamaOrigen, ServicioDestino}).

en_espera() ->
  gen_server:call(?MODULE, en_espera).

%% La cama avisa por cast: una cama nunca debe bloquearse esperando a admisiones
%% (admisiones si llama a las camas, asi evitamos un deadlock).
cama_libre(CamaId, Servicio) ->
  gen_server:cast(?MODULE, {cama_libre, CamaId, Servicio}).

%% Camas que esperamos libres en las proximas HorizonteMin minutos, por servicio.
prediccion(HorizonteMin) ->
  MinutoMs = p40_config:minuto_ms(),
  p40_ocupacion:prediccion(p40_store:camas(), erlang:system_time(millisecond),
                           HorizonteMin * MinutoMs,
                           p40_config:limpieza_min() * MinutoMs,
                           p40_config:prob_alta()).

%%% gen_server -----------------------------------------------------------------

init([]) ->
  %% La lista de espera vive tambien en el store para sobrevivir a un crash.
  Espera = case p40_store:leer(espera) of
    {ok, E} -> E;
    none -> #{}
  end,
  %% Puede que se liberaran camas mientras estabamos caidos.
  self() ! revisar_espera,
  {ok, #{espera => Espera}}.

handle_call({admitir, Paciente, Servicio}, _From, State) ->
  case p40_config:servicio(Servicio) of
    error ->
      {reply, {error, servicio_desconocido}, State};
    {ok, _Prefijo, _Camas} ->
      case asignar(Servicio, Paciente) of
        {ok, CamaId} ->
          p40_eventos:registrar(#{tipo => admision, paciente => Paciente,
                                  servicio => Servicio, cama => CamaId}),
          {reply, {ok, CamaId}, State};
        sin_cama ->
          {Posicion, State1} = encolar(Servicio, Paciente, State),
          p40_eventos:registrar(#{tipo => sin_cama, paciente => Paciente,
                                  servicio => Servicio, posicion => Posicion}),
          {reply, {en_espera, Posicion}, State1}
      end
  end;
handle_call({trasladar, Origen, Destino}, _From, State) ->
  %% Leemos el store en vez de llamar a la cama: si la cama origen se esta
  %% reiniciando en este instante, admisiones no se cae por eso.
  case p40_store:leer({cama, Origen}) of
    {ok, #{estado := ocupada, paciente := Paciente, servicio := ServicioOrigen}} ->
      case asignar(Destino, Paciente) of
        {ok, CamaDestino} ->
          ok = alta_con_reintento(Origen, 50),
          p40_eventos:registrar(#{tipo => traslado, paciente => Paciente,
                                  de => Origen, a => CamaDestino,
                                  servicio_origen => ServicioOrigen,
                                  servicio => Destino}),
          {reply, {ok, CamaDestino}, State};
        sin_cama ->
          {reply, {error, sin_cama}, State}
      end;
    {ok, #{estado := Estado}} ->
      {reply, {error, {origen, Estado}}, State};
    none ->
      {reply, {error, cama_desconocida}, State}
  end;
handle_call(en_espera, _From, #{espera := Espera} = State) ->
  {reply, Espera, State}.

handle_cast({cama_libre, CamaId, Servicio}, #{espera := Espera} = State) ->
  case maps:get(Servicio, Espera, []) of
    [] ->
      {noreply, State};
    [Paciente | Resto] ->
      case ocupar_seguro(CamaId, Paciente) of
        ok ->
          p40_eventos:registrar(#{tipo => admision_desde_espera, paciente => Paciente,
                                  servicio => Servicio, cama => CamaId}),
          {noreply, guardar_espera(Espera#{Servicio => Resto}, State)};
        {error, _} ->
          %% Alguien la tomo antes o la cama se cayo; el paciente sigue
          %% primero en la fila.
          {noreply, State}
      end
  end.

handle_info(revisar_espera, #{espera := Espera} = State) ->
  Nueva = maps:map(fun atender_fila/2, Espera),
  {noreply, guardar_espera(Nueva, State)};
handle_info(_Info, State) ->
  {noreply, State}.

%%% Internas -------------------------------------------------------------------

%% Recorre las camas libres del servicio (en orden) y se queda con la primera que
%% acepte. Si el store estaba un instante atrasado y la cama ya no estaba libre,
%% la cama lo rechaza y probamos con la siguiente.
asignar(Servicio, Paciente) ->
  Libres = lists:sort([Id || #{id := Id, estado := libre} <- p40_store:camas(Servicio)]),
  intentar(Libres, Paciente).

intentar([], _Paciente) ->
  sin_cama;
intentar([Id | Resto], Paciente) ->
  case ocupar_seguro(Id, Paciente) of
    ok -> {ok, Id};
    {error, _} -> intentar(Resto, Paciente)
  end.

%% Encontrado con la simulacion de fallas: si la cama muere a media llamada,
%% gen_statem:call le avienta un exit a admisiones y la tumbaria. Lo atrapamos y
%% preguntamos al store que alcanzo a pasar: la cama guarda su estado ANTES de
%% responder, asi que si el store dice "ocupada por este paciente", la asignacion
%% si ocurrio (no la repetimos en otra cama, el paciente quedaria en dos).
ocupar_seguro(Id, Paciente) ->
  try
    p40_cama:ocupar(Id, Paciente)
  catch
    exit:{_Razon, {gen_statem, call, _}} ->
      case p40_store:leer({cama, Id}) of
        {ok, #{estado := ocupada, paciente := Paciente}} -> ok;
        _ -> {error, cama_caida}
      end
  end.

%% En un traslado el alta de origen TIENE que ocurrir (si no, el paciente queda en
%% dos camas). Si la cama se esta reiniciando, esperamos un poco y reintentamos.
alta_con_reintento(Origen, 0) ->
  error({alta_imposible, Origen});
alta_con_reintento(Origen, Intentos) ->
  try p40_cama:dar_alta(Origen) of
    ok -> ok;
    {error, {estado, por_limpiar}} -> ok
  catch
    exit:{_Razon, {gen_statem, call, _}} ->
      timer:sleep(10),
      alta_con_reintento(Origen, Intentos - 1)
  end.

atender_fila(_Servicio, []) ->
  [];
atender_fila(Servicio, [Paciente | Resto] = Fila) ->
  case asignar(Servicio, Paciente) of
    {ok, CamaId} ->
      p40_eventos:registrar(#{tipo => admision_desde_espera, paciente => Paciente,
                              servicio => Servicio, cama => CamaId}),
      atender_fila(Servicio, Resto);
    sin_cama ->
      Fila
  end.

encolar(Servicio, Paciente, #{espera := Espera} = State) ->
  Fila = maps:get(Servicio, Espera, []) ++ [Paciente],
  {length(Fila), guardar_espera(Espera#{Servicio => Fila}, State)}.

guardar_espera(Espera, State) ->
  ok = p40_store:guardar(espera, Espera),
  State#{espera := Espera}.
