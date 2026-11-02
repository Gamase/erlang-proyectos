-module(p40_store).
-behaviour(gen_server).

%% Dueno de una tabla ETS donde cada cama guarda su ultimo estado y admisiones
%% guarda su lista de espera. Existe para que, si una cama o admisiones se caen y
%% el supervisor las reinicia, recuperen lo que tenian (un paciente no "desaparece"
%% de su cama por un crash). Limitacion conocida: si este proceso muere se pierde
%% la tabla; el siguiente paso seria PostgreSQL (epgsql), como pide el stack.

-export([start_link/0, guardar/2, leer/1, camas/0, camas/1]).
-export([init/1, handle_call/3, handle_cast/2]).

-define(TABLA, p40_store).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Escritura directa (tabla public): cada cama solo escribe su propia clave, asi
%% que no hay carreras y no hacemos cuello de botella en este proceso.
guardar(Clave, Valor) ->
  true = ets:insert(?TABLA, {Clave, Valor}),
  ok.

leer(Clave) ->
  case ets:lookup(?TABLA, Clave) of
    [{Clave, Valor}] -> {ok, Valor};
    [] -> none
  end.

camas() ->
  [Cama || {{cama, _}, Cama} <- ets:match_object(?TABLA, {{cama, '_'}, '_'})].

camas(Servicio) ->
  [Cama || #{servicio := S} = Cama <- camas(), S =:= Servicio].

init([]) ->
  ?TABLA = ets:new(?TABLA, [named_table, set, public, {read_concurrency, true}]),
  {ok, #{}}.

handle_call(_Peticion, _From, State) ->
  {reply, {error, no_soportado}, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.
