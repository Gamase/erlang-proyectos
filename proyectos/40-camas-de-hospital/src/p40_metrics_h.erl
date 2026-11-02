-module(p40_metrics_h).
-behaviour(cowboy_handler).

%% /metrics en el formato de texto de Prometheus. Se escribe a mano porque la
%% libreria prometheus.erl no esta en las dependencias del proyecto (solo cowboy y
%% recon) y el formato es sencillo. Metricas del dominio que pide el README:
%% ocupacion por servicio, rotacion de camas (altas) y tiempo de limpieza.

-export([init/2, texto/0]).

init(Req0, State) ->
  Req = case cowboy_req:method(Req0) of
    <<"GET">> ->
      cowboy_req:reply(200, #{<<"content-type">> => <<"text/plain; version=0.0.4">>},
                       texto(), Req0);
    _Otro ->
      cowboy_req:reply(405, #{<<"allow">> => <<"GET">>}, Req0)
  end,
  {ok, Req, State}.

texto() ->
  Resumen = p40_ocupacion:resumen(p40_store:camas()),
  Espera = p40_admisiones:en_espera(),
  Alertas = p40_eventos:alertas_activas(),
  #{total := Total, por_tipo := PorTipo, altas := Altas,
    limpiezas := Limpiezas, limpieza_ms := LimpiezaMs} = p40_eventos:estadisticas(),
  Servicios = [S || {S, _, _} <- p40_config:servicios()],
  PromedioLimpieza = case Limpiezas of
    0 -> 0.0;
    _ -> LimpiezaMs / Limpiezas / p40_config:minuto_ms()
  end,
  [metrica(<<"p40_camas">>, gauge, <<"Camas por servicio y estado">>,
           [{[{servicio, S}, {estado, E}], maps:get(E, maps:get(S, Resumen))}
            || S <- Servicios, E <- [libre, ocupada, por_limpiar, bloqueada]]),
   metrica(<<"p40_ocupacion_ratio">>, gauge, <<"Camas ocupadas / total por servicio">>,
           [{[{servicio, S}], maps:get(ocupacion, maps:get(S, Resumen))} || S <- Servicios]),
   metrica(<<"p40_espera_pacientes">>, gauge, <<"Pacientes esperando cama por servicio">>,
           [{[{servicio, S}], length(maps:get(S, Espera, []))} || S <- Servicios]),
   metrica(<<"p40_alerta_activa">>, gauge, <<"1 si el servicio esta sobre el umbral">>,
           [{[{servicio, S}], bool(maps:is_key(S, Alertas))} || S <- Servicios]),
   metrica(<<"p40_altas_total">>, counter, <<"Altas dadas (rotacion de camas)">>,
           [{[], Altas}]),
   metrica(<<"p40_limpieza_minutos_promedio">>, gauge,
           <<"Duracion promedio de limpieza en minutos del hospital">>,
           [{[], PromedioLimpieza}]),
   metrica(<<"p40_eventos_total">>, counter, <<"Eventos de la bitacora por tipo">>,
           [{[{tipo, T}], N} || {T, N} <- lists:sort(maps:to_list(PorTipo))]
           ++ [{[{tipo, todos}], Total}]),
   metrica(<<"p40_procesos">>, gauge, <<"Procesos vivos en la VM">>,
           [{[], erlang:system_info(process_count)}])].

metrica(Nombre, Tipo, Ayuda, Muestras) ->
  [<<"# HELP ">>, Nombre, $\s, Ayuda, $\n,
   <<"# TYPE ">>, Nombre, $\s, atom_to_binary(Tipo), $\n,
   [[Nombre, etiquetas(Etiquetas), $\s, numero(Valor), $\n] || {Etiquetas, Valor} <- Muestras]].

etiquetas([]) -> <<>>;
etiquetas(Pares) ->
  [${, lists:join($,, [[atom_to_binary(K), <<"=\"">>, atom_to_binary(V), $"]
                       || {K, V} <- Pares]), $}].

numero(N) when is_integer(N) -> integer_to_binary(N);
numero(F) when is_float(F) -> float_to_binary(F, [{decimals, 4}, compact]).

bool(true) -> 1;
bool(false) -> 0.
