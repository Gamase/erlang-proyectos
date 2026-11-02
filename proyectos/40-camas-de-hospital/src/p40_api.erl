-module(p40_api).

%% Arma los datos que regresa la API ya listos para json:encode/1. Separado de los
%% handlers de cowboy para poder probarlo sin HTTP.
%%
%% Seguridad: nunca convertimos texto que llega del navegador a atom con
%% binary_to_atom (cada atom nuevo es memoria que no se libera; un cliente podria
%% tumbar el nodo). Los servicios se buscan en la configuracion y las camas en el
%% store; solo lo que ya existe se acepta.

-export([resumen/0, camas/1, cama/1, eventos/1, evento_json/1, servicio_de/1,
         cama_existe/1]).

-define(ESTADOS, [libre, ocupada, por_limpiar, bloqueada]).

resumen() ->
  Camas = p40_store:camas(),
  PorServicio = p40_ocupacion:resumen(Camas),
  Prediccion = p40_admisiones:prediccion(240),
  Espera = p40_admisiones:en_espera(),
  Servicios =
    [(maps:get(S, PorServicio))#{id => S, prefijo => Prefijo,
                                 espera => length(maps:get(S, Espera, [])),
                                 pacientes_espera => maps:get(S, Espera, []),
                                 libres_4h => esperadas(S, Prediccion)}
     || {S, Prefijo, _} <- p40_config:servicios()],
  Simulacion = simulacion(),
  Reloj = case Simulacion of
    #{reloj := R} -> R;
    undefined -> undefined
  end,
  #{reloj => nulo(Reloj),
    simulacion => nulo(Simulacion),
    umbral => p40_config:umbral_alerta(),
    total => totales(Servicios),
    servicios => Servicios,
    alertas => maps:keys(p40_eventos:alertas_activas())}.

%% todas | Servicio (atom ya validado)
camas(Filtro) ->
  Ahora = erlang:system_time(millisecond),
  Camas = case Filtro of
    todas -> p40_store:camas();
    Servicio -> p40_store:camas(Servicio)
  end,
  [cama_json(C, Ahora) || C <- lists:sort(fun(#{id := A}, #{id := B}) -> A =< B end, Camas)].

cama(Id) ->
  case p40_store:leer({cama, Id}) of
    {ok, Cama} -> {ok, cama_json(Cama, erlang:system_time(millisecond))};
    none -> none
  end.

eventos(N) ->
  [evento_json(E) || E <- p40_eventos:ultimos(N)].

%% <<"cirugia">> -> {ok, cirugia} | error
servicio_de(Texto) when is_binary(Texto) ->
  case [S || {S, _, _} <- p40_config:servicios(), atom_to_binary(S) =:= Texto] of
    [S] -> {ok, S};
    [] -> error
  end;
servicio_de(_Otro) ->
  error.

cama_existe(Id) when is_binary(Id) ->
  p40_store:leer({cama, Id}) =/= none;
cama_existe(_Otro) ->
  false.

%%% Internas -------------------------------------------------------------------

totales(Servicios) ->
  Claves = [total | ?ESTADOS],
  Sumas = maps:from_list([{K, lists:sum([maps:get(K, S) || S <- Servicios])} || K <- Claves]),
  Sumas#{ocupacion => case Sumas of
                        #{total := 0} -> 0.0;
                        #{total := T, ocupada := O} -> O / T
                      end}.

esperadas(Servicio, Prediccion) ->
  case Prediccion of
    #{Servicio := #{esperadas := E}} -> E;
    #{} -> 0
  end.

%% Los tiempos se mandan en minutos del hospital (no ms reales), asi la UI muestra
%% "18 min" igual con la simulacion acelerada que en tiempo real.
cama_json(Cama, Ahora) ->
  MinutoMs = p40_config:minuto_ms(),
  Base = maps:with([id, servicio, estado, paciente, ultimo_paciente, motivo], Cama),
  Extra = #{minutos_en_estado => (Ahora - maps:get(desde, Cama)) div MinutoMs,
            limpieza_restante_min => minutos_hasta(maps:get(limpieza_hasta, Cama), Ahora, MinutoMs),
            alta_en_min => minutos_hasta(maps:get(alta_estimada, Cama), Ahora, MinutoMs)},
  maps:map(fun(_K, V) -> nulo(V) end, maps:merge(Base, Extra)).

minutos_hasta(undefined, _Ahora, _MinutoMs) -> undefined;
minutos_hasta(Ts, Ahora, MinutoMs) -> max(0, (Ts - Ahora) div MinutoMs).

evento_json(#{ts := Ts} = Evento) ->
  Hora = case p40_simulador:reloj_de(Ts) of
    undefined -> hora_local(Ts);
    Reloj -> list_to_binary(Reloj)
  end,
  maps:map(fun(_K, V) -> nulo(V) end, Evento#{hora => Hora}).

hora_local(Ts) ->
  {_, {H, M, _}} = calendar:system_time_to_local_time(Ts, millisecond),
  iolist_to_binary(io_lib:format("~2..0b:~2..0b", [H, M])).

simulacion() ->
  case whereis(p40_simulador) of
    undefined -> undefined;
    _Pid ->
      #{reloj := Reloj} = Estado = p40_simulador:estado(),
      Estado#{reloj := list_to_binary(Reloj)}
  end.

%% json:encode convierte cualquier atom a texto; undefined debe ser null.
nulo(undefined) -> null;
nulo(Valor) -> Valor.
