-module(p40_config).

%% Lectura centralizada de la configuracion (sys.config) con valores por defecto.
%% Todo lo que dependa del tiempo pasa por minuto_ms/0 para poder acelerar la
%% simulacion y los tests sin tocar la logica.

-export([servicios/0, servicio/1, limpieza_min/0, minuto_ms/0,
         umbral_alerta/0, prob_alta/0, ids/2]).

-define(APP, p40_camas_de_hospital).

%% 120 camas en 6 servicios, como pide el escenario del problema.
-define(SERVICIOS_DEFAULT, [
  {medicina_interna,   <<"MI">>,  30},
  {cirugia,            <<"CIR">>, 25},
  {gineco_obstetricia, <<"GO">>,  20},
  {pediatria,          <<"PED">>, 15},
  {aislamiento,        <<"AIS">>, 20},
  {terapia_intensiva,  <<"UCI">>, 10}
]).

servicios() ->
  application:get_env(?APP, servicios, ?SERVICIOS_DEFAULT).

servicio(Nombre) ->
  case lists:keyfind(Nombre, 1, servicios()) of
    {Nombre, Prefijo, Camas} -> {ok, Prefijo, Camas};
    false -> error
  end.

%% Duracion tipica de limpieza/desinfeccion (30-60 min segun el problema).
limpieza_min() -> application:get_env(?APP, limpieza_min, 45).

%% Cuantos milisegundos reales dura un "minuto" del hospital.
minuto_ms() -> application:get_env(?APP, minuto_ms, 60000).

%% A partir de ~85 % de ocupacion empieza la saturacion.
umbral_alerta() -> application:get_env(?APP, umbral_alerta, 0.85).

%% Probabilidad de que un alta programada si ocurra a tiempo (altas inciertas).
prob_alta() -> application:get_env(?APP, prob_alta, 0.7).

%% <<"UCI">>, 3 -> [<<"UCI-01">>, <<"UCI-02">>, <<"UCI-03">>]
ids(Prefijo, N) ->
  [iolist_to_binary([Prefijo, "-", io_lib:format("~2..0B", [I])])
   || I <- lists:seq(1, N)].
