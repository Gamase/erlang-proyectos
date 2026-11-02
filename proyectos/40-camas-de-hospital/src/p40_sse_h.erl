-module(p40_sse_h).
-behaviour(cowboy_loop).

%% Server-Sent Events: cada evento de la bitacora se empuja al navegador en
%% cuanto ocurre. Cada conexion es su propio proceso, suscrito a p40_eventos; si
%% el navegador se va, el proceso muere y p40_eventos lo saca (lo monitorea).

-export([init/2, info/3]).

-define(PING_MS, 15000).

init(Req0, State) ->
  Req = cowboy_req:stream_reply(200, #{
    <<"content-type">> => <<"text/event-stream">>,
    <<"cache-control">> => <<"no-cache">>
  }, Req0),
  ok = p40_eventos:suscribir(),
  %% Si la bitacora se reinicia perdemos la suscripcion: cerramos el stream y el
  %% EventSource del navegador se reconecta solo (y se vuelve a suscribir).
  erlang:monitor(process, p40_eventos),
  cowboy_req:stream_body(<<": conectado\n\n">>, nofin, Req),
  erlang:send_after(?PING_MS, self(), ping),
  {cowboy_loop, Req, State}.

info({p40_evento, Evento}, Req, State) ->
  Json = json:encode(p40_api:evento_json(Evento)),
  cowboy_req:stream_body(["data: ", Json, "\n\n"], nofin, Req),
  {ok, Req, State};
%% Comentario periodico para que proxies y el idle_timeout no corten el stream.
info(ping, Req, State) ->
  cowboy_req:stream_body(<<": ping\n\n">>, nofin, Req),
  erlang:send_after(?PING_MS, self(), ping),
  {ok, Req, State};
info({'DOWN', _Ref, process, _Pid, _Razon}, Req, State) ->
  {stop, Req, State}.
