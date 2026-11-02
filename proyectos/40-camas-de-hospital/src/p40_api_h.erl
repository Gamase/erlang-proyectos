-module(p40_api_h).
-behaviour(cowboy_handler).

%% Endpoints JSON. El estado del handler (tercer elemento de cada ruta en el
%% router) dice que recurso es; aqui solo se valida la entrada, se llama al
%% dominio y se traduce el resultado a un codigo HTTP.
%%
%%   GET  /api/resumen                  ocupacion general y por servicio
%%   GET  /api/camas[?servicio=S]       lista de camas
%%   GET  /api/camas/:id                una cama
%%   POST /api/camas/:id/:accion        alta | limpieza | bloquear | desbloquear | programar_alta
%%   POST /api/admisiones               {"paciente": "P-0231", "servicio": "cirugia"}
%%   POST /api/traslados                {"cama": "MI-08", "servicio": "terapia_intensiva"}
%%   GET  /api/eventos[?n=50]           bitacora, el mas reciente primero
%%   POST /api/simulador/brote          {"n": 25}

-export([init/2]).

-define(MAX_BODY, 4096).

init(Req0, Ruta) ->
  {Codigo, Cuerpo, Req1} =
    try
      atender(Ruta, cowboy_req:method(Req0), Req0)
    catch
      throw:{http, C, Mensaje} -> {C, #{error => Mensaje}, Req0};
      %% La cama a la que llamamos murio (o se reinicia) justo en este instante.
      exit:{_Razon, {gen_statem, call, _}} -> {503, #{error => <<"cama_reiniciando">>}, Req0}
    end,
  Req = cowboy_req:reply(Codigo, #{<<"content-type">> => <<"application/json">>,
                                   <<"cache-control">> => <<"no-store">>},
                         json:encode(Cuerpo), Req1),
  {ok, Req, Ruta}.

%%% Rutas ------------------------------------------------------------------------

atender(resumen, <<"GET">>, Req) ->
  {200, p40_api:resumen(), Req};

atender(camas, <<"GET">>, Req) ->
  Filtro = case cowboy_req:match_qs([{servicio, [], undefined}], Req) of
    #{servicio := undefined} -> todas;
    #{servicio := Texto} -> servicio(Texto)
  end,
  {200, p40_api:camas(Filtro), Req};

atender(cama, <<"GET">>, Req) ->
  case p40_api:cama(cowboy_req:binding(id, Req)) of
    {ok, Cama} -> {200, Cama, Req};
    none -> {404, #{error => <<"cama_desconocida">>}, Req}
  end;

atender(accion_cama, <<"POST">>, Req0) ->
  Id = cama_id(cowboy_req:binding(id, Req0)),
  {Body, Req} = leer_json(Req0),
  Resultado = case cowboy_req:binding(accion, Req0) of
    <<"alta">> -> p40_cama:dar_alta(Id, opciones_alta(Body));
    <<"limpieza">> -> p40_cama:terminar_limpieza(Id);
    <<"bloquear">> -> p40_cama:bloquear(Id, texto(<<"motivo">>, Body, <<"mantenimiento">>));
    <<"desbloquear">> -> p40_cama:desbloquear(Id);
    <<"programar_alta">> -> p40_cama:programar_alta(Id, entero(<<"minutos">>, Body, 0, 43200));
    _Otra -> throw({http, 404, <<"accion_desconocida">>})
  end,
  case Resultado of
    ok ->
      {ok, Cama} = p40_api:cama(Id),
      {200, #{ok => true, cama => Cama}, Req};
    {error, {estado, Estado}} ->
      {409, #{error => <<"transicion_invalida">>, estado => Estado}, Req}
  end;

atender(admisiones, <<"POST">>, Req0) ->
  {Body, Req} = leer_json(Req0),
  Paciente = paciente(Body),
  Servicio = servicio(maps:get(<<"servicio">>, Body, undefined)),
  case p40_admisiones:admitir(Paciente, Servicio) of
    {ok, Cama} -> {200, #{resultado => asignada, cama => Cama, paciente => Paciente}, Req};
    {en_espera, Pos} -> {202, #{resultado => en_espera, posicion => Pos, paciente => Paciente}, Req}
  end;

atender(traslados, <<"POST">>, Req0) ->
  {Body, Req} = leer_json(Req0),
  Origen = cama_id(maps:get(<<"cama">>, Body, undefined)),
  Destino = servicio(maps:get(<<"servicio">>, Body, undefined)),
  case p40_admisiones:trasladar(Origen, Destino) of
    {ok, Cama} -> {200, #{resultado => trasladado, cama => Cama}, Req};
    {error, sin_cama} -> {409, #{error => <<"sin_cama">>}, Req};
    {error, {origen, Estado}} -> {409, #{error => <<"origen_no_ocupada">>, estado => Estado}, Req};
    {error, cama_desconocida} -> {404, #{error => <<"cama_desconocida">>}, Req}
  end;

atender(eventos, <<"GET">>, Req) ->
  #{n := Texto} = cowboy_req:match_qs([{n, [], <<"50">>}], Req),
  N = try binary_to_integer(Texto) catch error:badarg -> 50 end,
  {200, p40_api:eventos(max(1, min(N, 500))), Req};

atender(brote, <<"POST">>, Req0) ->
  {Body, Req} = leer_json(Req0),
  N = entero(<<"n">>, Body, 1, 100),
  case whereis(p40_simulador) of
    undefined -> {409, #{error => <<"simulador_apagado">>}, Req};
    _Pid -> ok = p40_simulador:brote(N), {200, #{ok => true, pacientes => N}, Req}
  end;

atender(_Ruta, _Metodo, Req) ->
  {405, #{error => <<"metodo_no_permitido">>}, Req}.

%%% Validacion de entrada ----------------------------------------------------------

leer_json(Req0) ->
  case cowboy_req:read_body(Req0, #{length => ?MAX_BODY}) of
    {ok, <<>>, Req} ->
      {#{}, Req};
    {ok, Bin, Req} ->
      try json:decode(Bin) of
        Mapa when is_map(Mapa) -> {Mapa, Req};
        _Otro -> throw({http, 400, <<"se_esperaba_objeto_json">>})
      catch
        error:_ -> throw({http, 400, <<"json_invalido">>})
      end;
    {more, _, _Req} ->
      throw({http, 413, <<"cuerpo_muy_grande">>})
  end.

servicio(Texto) ->
  case p40_api:servicio_de(Texto) of
    {ok, Servicio} -> Servicio;
    error -> throw({http, 400, <<"servicio_desconocido">>})
  end.

cama_id(Id) ->
  case p40_api:cama_existe(Id) of
    true -> Id;
    false -> throw({http, 404, <<"cama_desconocida">>})
  end.

paciente(Body) ->
  case maps:get(<<"paciente">>, Body, undefined) of
    P when is_binary(P), byte_size(P) > 0, byte_size(P) =< 40 -> P;
    _ -> throw({http, 400, <<"paciente_invalido">>})
  end.

opciones_alta(Body) ->
  case maps:is_key(<<"limpieza_min">>, Body) of
    true -> #{limpieza_min => entero(<<"limpieza_min">>, Body, 1, 600)};
    false -> #{}
  end.

texto(Clave, Body, Default) ->
  case maps:get(Clave, Body, Default) of
    T when is_binary(T), byte_size(T) =< 80 -> T;
    _ -> throw({http, 400, <<"texto_invalido">>})
  end.

entero(Clave, Body, Min, Max) ->
  case maps:get(Clave, Body, undefined) of
    N when is_integer(N), N >= Min, N =< Max -> N;
    _ -> throw({http, 400, iolist_to_binary([Clave, <<"_invalido">>])})
  end.
