-module(p40_ocupacion).

%% Funciones puras (sin procesos ni efectos): reciben la lista de camas y regresan
%% numeros. Asi se prueban facil con eunit y las reusan la bitacora, la API y la
%% simulacion.

-export([resumen/1, prediccion/5]).

-define(ESTADOS, [libre, ocupada, por_limpiar, bloqueada]).

%% #{Servicio => #{total, libre, ocupada, por_limpiar, bloqueada, ocupacion}}
resumen(Camas) ->
  PorServicio = lists:foldl(fun agregar/2, #{}, Camas),
  maps:map(fun(_Servicio, Conteo) -> con_ocupacion(Conteo) end, PorServicio).

agregar(#{servicio := Servicio, estado := Estado}, Acc) ->
  Conteo0 = maps:get(Servicio, Acc, vacio()),
  Conteo = Conteo0#{total := maps:get(total, Conteo0) + 1,
                    Estado := maps:get(Estado, Conteo0) + 1},
  Acc#{Servicio => Conteo}.

vacio() ->
  maps:from_list([{total, 0} | [{E, 0} || E <- ?ESTADOS]]).

con_ocupacion(#{total := 0} = Conteo) ->
  Conteo#{ocupacion => 0.0};
con_ocupacion(#{total := Total, ocupada := Ocupadas} = Conteo) ->
  Conteo#{ocupacion => Ocupadas / Total}.

%% Cuantas camas esperamos libres por servicio dentro de HorizonteMs:
%%  - las libres ahora,
%%  - las que estan en limpieza y terminan antes del horizonte,
%%  - las altas programadas que alcanzan a salir Y limpiarse, multiplicadas por la
%%    probabilidad de que el alta si ocurra (las altas se retrasan seguido).
prediccion(Camas, Ahora, HorizonteMs, LimpiezaMs, ProbAlta) ->
  Limite = Ahora + HorizonteMs,
  PorServicio = lists:foldl(
    fun(Cama, Acc) ->
      Servicio = maps:get(servicio, Cama),
      P0 = maps:get(Servicio, Acc, #{libres_ahora => 0, por_terminar_limpieza => 0,
                                    altas_programadas => 0}),
      Acc#{Servicio => contar(Cama, Limite, LimpiezaMs, P0)}
    end, #{}, Camas),
  maps:map(
    fun(_S, #{libres_ahora := L, por_terminar_limpieza := T, altas_programadas := A} = P) ->
      P#{esperadas => L + T + round(A * ProbAlta)}
    end, PorServicio).

contar(#{estado := libre}, _Limite, _LimpiezaMs, P) ->
  incrementar(libres_ahora, P);
contar(#{estado := por_limpiar, limpieza_hasta := Hasta}, Limite, _LimpiezaMs, P)
    when Hasta =< Limite ->
  incrementar(por_terminar_limpieza, P);
contar(#{estado := ocupada, alta_estimada := Alta}, Limite, LimpiezaMs, P)
    when is_integer(Alta), Alta + LimpiezaMs =< Limite ->
  incrementar(altas_programadas, P);
contar(#{estado := Estado}, _Limite, _LimpiezaMs, P)
    when Estado =:= ocupada; Estado =:= por_limpiar; Estado =:= bloqueada ->
  P.

incrementar(Clave, Mapa) ->
  Mapa#{Clave := maps:get(Clave, Mapa) + 1}.
