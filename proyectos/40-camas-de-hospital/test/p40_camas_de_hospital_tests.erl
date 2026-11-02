-module(p40_camas_de_hospital_tests).
-include_lib("eunit/include/eunit.hrl").

%% Hospital chiquito para probar rapido: 1 cama de UCI y 3 generales.
%% Un "minuto" dura 1 ms y la limpieza 20 minutos -> 20 ms reales.
-define(SERVICIOS, [{terapia_intensiva, <<"UCI">>, 1}, {general, <<"GEN">>, 3}]).

%%% Funciones puras ---------------------------------------------------------------

resumen_test() ->
  Camas = [#{servicio => a, estado => ocupada}, #{servicio => a, estado => libre},
           #{servicio => a, estado => ocupada}, #{servicio => a, estado => por_limpiar},
           #{servicio => b, estado => bloqueada}],
  #{a := A, b := B} = p40_ocupacion:resumen(Camas),
  ?assertMatch(#{total := 4, ocupada := 2, libre := 1, por_limpiar := 1}, A),
  ?assertEqual(0.5, maps:get(ocupacion, A)),
  ?assertEqual(0.0, maps:get(ocupacion, B)).

prediccion_test() ->
  Ahora = 1000,
  Camas = [#{servicio => s, estado => libre},
           %% termina limpieza dentro del horizonte (cuenta)
           #{servicio => s, estado => por_limpiar, limpieza_hasta => 1050},
           %% termina limpieza despues del horizonte (no cuenta)
           #{servicio => s, estado => por_limpiar, limpieza_hasta => 9999},
           %% alta a tiempo de salir y limpiarse: 1010 + 50 =< 1100
           #{servicio => s, estado => ocupada, alta_estimada => 1010},
           #{servicio => s, estado => ocupada, alta_estimada => 1020},
           %% alta sin tiempo para la limpieza: 1080 + 50 > 1100
           #{servicio => s, estado => ocupada, alta_estimada => 1080},
           #{servicio => s, estado => ocupada, alta_estimada => undefined}],
  #{s := P} = p40_ocupacion:prediccion(Camas, Ahora, 100, 50, 0.5),
  ?assertEqual(#{libres_ahora => 1, por_terminar_limpieza => 1,
                 altas_programadas => 2, esperadas => 3}, P).

%%% Sistema completo -------------------------------------------------------------

sistema_test_() ->
  {foreach, fun arrancar/0, fun detener/1,
   [fun ciclo_de_una_cama/1,
    fun transiciones_ilegales/1,
    fun sin_cama_va_a_espera_y_se_asigna_sola/1,
    fun limpieza_lenta/1,
    fun traslado_interno/1,
    fun alerta_de_ocupacion/1,
    fun caos_dos_piden_la_ultima_cama/1,
    fun caos_matar_una_cama_ocupada/1,
    fun caos_matar_admisiones_con_espera/1]}.

arrancar() ->
  logger:set_primary_config(level, error),
  application:set_env(p40_camas_de_hospital, servicios, ?SERVICIOS),
  application:set_env(p40_camas_de_hospital, minuto_ms, 1),
  application:set_env(p40_camas_de_hospital, limpieza_min, 20),
  {ok, Pid} = p40_camas_de_hospital_sup:start_link(),
  unlink(Pid),
  Pid.

detener(Pid) ->
  Ref = erlang:monitor(process, Pid),
  exit(Pid, shutdown),
  receive {'DOWN', Ref, process, Pid, _} -> ok after 5000 -> error(no_murio) end.

ciclo_de_una_cama(_) ->
  fun() ->
    ?assertEqual({ok, <<"GEN-01">>}, p40_admisiones:admitir(<<"P1">>, general)),
    ?assertMatch(#{estado := ocupada, paciente := <<"P1">>}, p40_cama:info(<<"GEN-01">>)),
    ?assertEqual(ok, p40_cama:dar_alta(<<"GEN-01">>)),
    ?assertMatch(#{estado := por_limpiar, ultimo_paciente := <<"P1">>},
                 p40_cama:info(<<"GEN-01">>)),
    esperar_estado(<<"GEN-01">>, libre),
    Tipos = [{T, maps:get(a, E, none)} || #{tipo := T} = E <- p40_eventos:ultimos(10)],
    ?assertEqual([{cambio, libre}, {cambio, por_limpiar}, {admision, none},
                  {cambio, ocupada}], Tipos)
  end.

transiciones_ilegales(_) ->
  fun() ->
    ?assertEqual({error, {estado, libre}}, p40_cama:dar_alta(<<"GEN-01">>)),
    ?assertEqual({error, {estado, libre}}, p40_cama:terminar_limpieza(<<"GEN-01">>)),
    ok = p40_cama:ocupar(<<"GEN-01">>, <<"P1">>),
    ?assertEqual({error, {estado, ocupada}}, p40_cama:ocupar(<<"GEN-01">>, <<"P2">>)),
    ?assertEqual({error, {estado, ocupada}}, p40_cama:bloquear(<<"GEN-01">>, x)),
    ok = p40_cama:bloquear(<<"GEN-02">>, mantenimiento),
    ?assertEqual({error, {estado, bloqueada}}, p40_cama:ocupar(<<"GEN-02">>, <<"P3">>)),
    ?assertEqual({error, servicio_desconocido}, p40_admisiones:admitir(<<"P4">>, marte))
  end.

sin_cama_va_a_espera_y_se_asigna_sola(_) ->
  fun() ->
    ?assertEqual({ok, <<"UCI-01">>}, p40_admisiones:admitir(<<"P1">>, terapia_intensiva)),
    %% No hay otra cama de UCI: NO se le da una general, se forma.
    ?assertEqual({en_espera, 1}, p40_admisiones:admitir(<<"P2">>, terapia_intensiva)),
    ?assertMatch(#{estado := libre}, p40_cama:info(<<"GEN-01">>)),
    ok = p40_cama:dar_alta(<<"UCI-01">>),
    esperar(fun() -> maps:get(paciente, p40_cama:info(<<"UCI-01">>)) =:= <<"P2">> end),
    ?assertEqual(#{terapia_intensiva => []}, p40_admisiones:en_espera())
  end.

limpieza_lenta(_) ->
  fun() ->
    ok = p40_cama:ocupar(<<"GEN-01">>, <<"P1">>),
    %% La limpieza tarda 2 horas (120 ms aqui) en lugar de 20.
    ok = p40_cama:dar_alta(<<"GEN-01">>, #{limpieza_min => 120}),
    timer:sleep(50),
    ?assertMatch(#{estado := por_limpiar}, p40_cama:info(<<"GEN-01">>)),
    esperar_estado(<<"GEN-01">>, libre)
  end.

traslado_interno(_) ->
  fun() ->
    {ok, Origen} = p40_admisiones:admitir(<<"P1">>, general),
    ?assertEqual({ok, <<"UCI-01">>}, p40_admisiones:trasladar(Origen, terapia_intensiva)),
    ?assertMatch(#{estado := ocupada, paciente := <<"P1">>}, p40_cama:info(<<"UCI-01">>)),
    ?assertMatch(#{estado := por_limpiar}, p40_cama:info(Origen)),
    %% Sin cama destino el paciente se queda donde esta.
    {ok, Otro} = p40_admisiones:admitir(<<"P2">>, general),
    ?assertEqual({error, sin_cama}, p40_admisiones:trasladar(Otro, terapia_intensiva)),
    ?assertMatch(#{estado := ocupada, paciente := <<"P2">>}, p40_cama:info(Otro))
  end.

alerta_de_ocupacion(_) ->
  fun() ->
    [{ok, _} = p40_admisiones:admitir(P, general) || P <- [<<"A">>, <<"B">>]],
    %% 2/3 = 67 %: todavia no
    ?assertEqual(#{}, esperar_alertas(fun(A) -> A =:= #{} end)),
    {ok, _} = p40_admisiones:admitir(<<"C">>, general),
    %% 3/3 = 100 % >= 85 %: alerta
    esperar_alertas(fun(A) -> maps:is_key(general, A) end),
    ok = p40_cama:dar_alta(<<"GEN-01">>),
    esperar_alertas(fun(A) -> not maps:is_key(general, A) end),
    Tipos = [T || #{tipo := T} <- p40_eventos:ultimos(50)],
    ?assert(lists:member(alerta, Tipos)),
    ?assert(lists:member(alerta_resuelta, Tipos))
  end.

%%% Pruebas de caos ---------------------------------------------------------------

%% 20 procesos piden la unica cama de UCI al mismo tiempo: solo uno la obtiene.
caos_dos_piden_la_ultima_cama(_) ->
  fun() ->
    Yo = self(),
    Pacientes = [integer_to_binary(N) || N <- lists:seq(1, 20)],
    [spawn(fun() -> Yo ! {resp, p40_admisiones:admitir(P, terapia_intensiva)} end)
     || P <- Pacientes],
    Respuestas = [receive {resp, R} -> R after 2000 -> timeout end || _ <- Pacientes],
    Ganadores = [R || {ok, _} = R <- Respuestas],
    ?assertEqual([{ok, <<"UCI-01">>}], Ganadores),
    ?assertEqual(19, length([R || {en_espera, _} = R <- Respuestas])),
    #{paciente := Dueno} = p40_cama:info(<<"UCI-01">>),
    ?assert(lists:member(Dueno, Pacientes))
  end.

%% Matamos el proceso de una cama ocupada: el supervisor la reinicia y la cama
%% recuerda a su paciente (no lo "pierde").
caos_matar_una_cama_ocupada(_) ->
  fun() ->
    {ok, Id} = p40_admisiones:admitir(<<"P1">>, general),
    Antes = whereis(p40_cama:nombre(Id)),
    exit(Antes, kill),
    esperar(fun() -> is_pid(whereis(p40_cama:nombre(Id)))
                     andalso whereis(p40_cama:nombre(Id)) =/= Antes end),
    ?assertMatch(#{estado := ocupada, paciente := <<"P1">>}, p40_cama:info(Id)),
    %% Y sigue funcionando normal despues del reinicio.
    ?assertEqual(ok, p40_cama:dar_alta(Id)),
    esperar_estado(Id, libre)
  end.

%% Matamos admisiones con un paciente formado: al reiniciar recupera la fila y lo
%% asigna cuando se libera la cama.
caos_matar_admisiones_con_espera(_) ->
  fun() ->
    {ok, _} = p40_admisiones:admitir(<<"P1">>, terapia_intensiva),
    {en_espera, 1} = p40_admisiones:admitir(<<"P2">>, terapia_intensiva),
    Antes = whereis(p40_admisiones),
    exit(Antes, kill),
    esperar(fun() -> is_pid(whereis(p40_admisiones))
                     andalso whereis(p40_admisiones) =/= Antes end),
    ?assertEqual(#{terapia_intensiva => [<<"P2">>]}, p40_admisiones:en_espera()),
    ok = p40_cama:dar_alta(<<"UCI-01">>),
    esperar(fun() -> maps:get(paciente, p40_cama:info(<<"UCI-01">>)) =:= <<"P2">> end)
  end.

%%% Utilidades --------------------------------------------------------------------

esperar_estado(Id, Estado) ->
  esperar(fun() -> maps:get(estado, p40_cama:info(Id)) =:= Estado end).

esperar_alertas(Condicion) ->
  esperar(fun() -> Condicion(p40_eventos:alertas_activas()) end),
  p40_eventos:alertas_activas().

esperar(Condicion) -> esperar(Condicion, 200).

esperar(_Condicion, 0) ->
  error(condicion_no_cumplida);
esperar(Condicion, Intentos) ->
  case catch Condicion() of
    true -> ok;
    _ -> timer:sleep(10), esperar(Condicion, Intentos - 1)
  end.
