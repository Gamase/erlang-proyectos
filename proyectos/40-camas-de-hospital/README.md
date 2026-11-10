# #40 — Camas de hospital

**Dominio:** Salud

**Manual de uso:** [`docs/MANUAL.md`](docs/MANUAL.md) (tambien publicado como Gist).

ocupacion, altas y limpieza.

## Equipo

Proyecto individual: Sebastián Martínez García (@Gamase) — backend, frontend y ops/QA.

## Arranque

Requiere Erlang/OTP 27 (usa el modulo `json`) y rebar3.

```bash
rebar3 compile
rebar3 eunit          # 20 tests: dominio, caos, simulacion, API y SSE
rebar3 shell          # abre http://localhost:8080 en el navegador o el celular
```

## Pendiente

- [x] Disenar pantallas en Stitch (`design/PROMPT_STITCH.md`)
- [x] Modelar el dominio: que es un proceso, que es un supervisor
- [x] Endpoints `/api/...` y SSE con cowboy
- [x] Metricas `/metrics`
- [x] Diagnostico con recon (`remote_console`, ver manual)
- [x] Release + systemd (`bash deploy/instalar-servicio.sh`)
- [x] Prueba de caos (matar procesos y verificar recuperacion) — ver tests `caos_*`
- [x] Simulacion del escenario (120 camas, 40 ingresos/40 altas al dia, brote, fallas inyectadas)

## Diseno OTP sugerido

- **Procesos:** un gen_statem por cama (libre, ocupada, por_limpiar, bloqueada); gen_server de admisiones que asigna camas por servicio
- **Supervision:** supervisor por piso/servicio
- **API / tiempo real:** GET /api/camas, POST /api/admisiones, POST /api/camas/:id/alta, SSE de ocupacion
- **Metricas:** ocupacion por servicio, rotacion de camas, tiempo de limpieza
- **Prueba de caos:** dos admisiones piden la ultima cama libre: solo una la obtiene

## Diseno OTP implementado

```
p40_camas_de_hospital_sup (rest_for_one)
|- p40_store        ETS con el estado de cada cama y la lista de espera
|- p40_eventos      bitacora + alertas al cruzar el 85 % por servicio
|- p40_camas_sup    (one_for_one)
|   `- p40_servicio_sup x6 (one_for_one) -> p40_cama (gen_statem) x N
`- p40_admisiones   asigna camas, lista de espera, traslados
```

| Modulo | Que hace |
|---|---|
| `p40_cama` | Estados `libre`, `ocupada`, `por_limpiar`, `bloqueada`. Rechaza transiciones ilegales con `{error, {estado, E}}`. La limpieza termina sola con un `state_timeout`. |
| `p40_admisiones` | Un solo proceso, asi que dos peticiones por la ultima cama se atienden en orden: solo una la obtiene. Si no hay cama del tipo requerido, el paciente entra a la lista de espera (nunca se asigna cama de otro servicio). |
| `p40_store` | Guarda el ultimo estado de cada cama y la fila de espera; al reiniciarse tras un crash, cama y admisiones recuperan lo que tenian. |
| `p40_eventos` | Bitacora de los ultimos 500 eventos, alertas de ocupacion y suscriptores (para el SSE). |
| `p40_ocupacion` | Funciones puras: resumen de ocupacion y prediccion de camas libres. |
| `p40_simulador` | Reloj simulado, ingresos (mas de noche), altas (por la tarde, 30 % se retrasan), limpiezas de 2 h, traslados a UCI, brote y fallas inyectadas. |
| `p40_config` | Servicios, tiempo de limpieza, umbral y escala de tiempo (`minuto_ms`). |

### Casos dificiles

- **Dos servicios piden la misma cama:** admisiones serializa las peticiones y la cama rechaza una segunda ocupacion (doble candado). Test: `caos_dos_piden_la_ultima_cama` (20 procesos, 1 cama).
- **Traslado interno:** primero se reserva la cama destino y despues se da de alta la de origen; si no hay destino, el paciente se queda donde esta.
- **Prediccion con altas inciertas:** libres + limpiezas que terminan en el horizonte + altas programadas que alcanzan a salir y limpiarse, multiplicadas por `prob_alta` (0.7).

### Pruebas de caos

| Que se mata | Que se espera | Que pasa |
|---|---|---|
| 20 admisiones simultaneas por 1 cama de UCI | Solo una gana | 1 `{ok, _}` y 19 `{en_espera, _}` |
| Proceso de una cama ocupada (`exit(Pid, kill)`) | Se reinicia sin perder al paciente | Vuelve en `ocupada` con el mismo paciente |
| `p40_admisiones` con un paciente en espera | Recupera la fila | La fila se restaura y el paciente recibe la cama al liberarse |

## Interfaz (Google Stitch -> cowboy)

El diseno se hizo en Stitch con los prompts de `design/PROMPT_STITCH.md`. El export
esta en `design/stitch/` (HTML y captura de cada pantalla) y `design/DESIGN.md` es
la fuente de colores y tipografia. La app real vive en `priv/www/index.html`: una
sola pagina con HTML/CSS/JS plano que reutiliza la configuracion de Tailwind del
export y se conecta a la API. Capturas de la app funcionando: `design/app/` (celular)
y `design/app/escritorio/` (computadora).

La pagina es responsiva: en el celular se ve como app (barra de navegacion abajo, una
columna) y en pantallas de 1024 px o mas se acomoda como dashboard web (menu lateral,
servicios en cuadricula, matriz de 10 columnas, detalle de cama en panel lateral). Es el
mismo HTML con clases responsivas de Tailwind; los colores, tipografia y componentes son
los de `design/DESIGN.md`.

| Pantalla | Stitch | App |
|---|---|---|
| Inicio (ocupacion en vivo) | `design/stitch/01-dashboard/` | `design/app/01-inicio.png` |
| Matriz de camas + detalle | `design/stitch/02-camas-servicio/` | `02-camas.png`, `03-detalle-cama.png` |
| Admitir paciente | `design/stitch/03-admitir/` | `04-admitir.png` |
| Bitacora | `design/stitch/04-bitacora/` | `05-bitacora.png` |

Cambios respecto al export de Stitch (documentados como pide `AGENTS.md`):

- Se quitaron los datos que Stitch invento y el sistema no maneja: nombre del
  paciente, NSS, nivel de triage, medico tratante y el boton de brazalete. El
  backend solo usa un ID de paciente (`P-0142`); no hay datos personales en el demo.
- Se agrego el panel "Simulacion del escenario" en Inicio (contadores y boton de
  brote) usando los mismos estilos de tarjeta y boton destructivo de `DESIGN.md`.
- La bitacora agrega el filtro "Camas" (cambios de estado) y muestra los eventos
  `falla_inyectada` y `restaurada` para ver la recuperacion de OTP en vivo.
- Las barras de ocupacion usan los niveles de `DESIGN.md` (verde < 75 %, ambar
  75-84 %, rojo >= 85 %).

### API

| Ruta | Metodo | Que hace |
|---|---|---|
| `/` | GET | La UI |
| `/api/resumen` | GET | Ocupacion general y por servicio, espera, prediccion a 4 h, alertas, reloj |
| `/api/camas?servicio=S` | GET | Camas (todas o de un servicio) |
| `/api/camas/:id` | GET | Una cama |
| `/api/camas/:id/:accion` | POST | `alta`, `limpieza`, `bloquear`, `desbloquear`, `programar_alta` |
| `/api/admisiones` | POST | `{"paciente":"P-0231","servicio":"cirugia"}` -> 200 asignada / 202 en espera |
| `/api/traslados` | POST | `{"cama":"MI-08","servicio":"terapia_intensiva"}` |
| `/api/eventos?n=50` | GET | Bitacora |
| `/api/simulador/brote` | POST | `{"n":25}` |
| `/sse` | GET | Server-Sent Events: cada evento de la bitacora en cuanto ocurre |
| `/metrics` | GET | Formato Prometheus: camas por estado, ocupacion, espera, altas, limpieza promedio |

Errores con su codigo: 400 entrada invalida, 404 cama o accion desconocida, 405
metodo no permitido, 409 transicion ilegal o sin cama, 503 cama reiniciandose.
El texto del navegador nunca se convierte en atom (`binary_to_atom`): servicios y
camas se buscan en la configuracion y el store, para que un cliente no pueda
agotar la tabla de atoms del nodo.

```bash
curl localhost:8080/api/resumen
curl -X POST localhost:8080/api/admisiones -d '{"paciente":"P-1","servicio":"cirugia"}'
curl -N localhost:8080/sse
curl localhost:8080/metrics
```

## Simulacion

Con `config/sys.config` tal cual, `rebar3 shell` arranca el hospital con el
simulador: 1 minuto del hospital = 100 ms, asi que 1 dia simulado dura 2.4 min.

```erlang
p40_simulador:reporte().     % reloj, contadores y tabla por servicio
p40_simulador:brote(25).     % 25 pacientes de golpe a aislamiento
p40_admisiones:en_espera().  % quien espera cama y en que servicio
p40_eventos:ultimos(20).     % bitacora: cambios, alertas, fallas inyectadas
p40_simulador:pausar().      % / reanudar()
```

`reporte()` muestra por servicio: camas ocupadas, libres, en limpieza, % de
ocupacion, pacientes en espera y las camas que se esperan libres en 4 horas.

Que se modela:

| Del problema | Como se simula |
|---|---|
| 120 camas en 6 servicios | MI 30, CIR 25, GO 20, PED 15, AIS 20, UCI 10 |
| 40 ingresos y 40 altas al dia | Ingresos Poisson (40/dia), x1.6 de 20:00 a 06:00; altas solo de 11:00 a 19:00 |
| Altas inciertas | 30 % de las altas vencidas se retrasan 2-6 h |
| Limpieza que tarda 2 h | 10 % de las altas usan `limpieza_min => 120` |
| Brote en aislamiento | `p40_simulador:brote(N)` |
| Traslado interno | 2 % de probabilidad por tick de mandar un paciente a UCI |
| Fallas inyectadas | Cada `falla_cada_min` (360) se mata una cama al azar con `exit(Pid, kill)` |

En corridas de 7 dias la ocupacion oscila entre ~67 % y ~92 %, con ~35-40
ingresos y altas diarias; las alertas de 85 % se activan y se resuelven solas.

### Lo que encontro la simulacion

Al inyectar fallas aparecio un bug real: si una cama moria justo mientras
admisiones la llamaba, `gen_statem:call` mataba tambien a admisiones. Se corrigio
atrapando ese exit y consultando el store para saber si la asignacion alcanzo a
ocurrir (la cama guarda su estado antes de responder), para no meter al mismo
paciente en dos camas. El test `simulacion_test_` corre ~2 dias con una falla
cada 2 horas y revisa invariantes: 120 camas vivas, ningun paciente en dos camas
y nadie en espera y en cama a la vez.

### Limitacion conocida

Si muere `p40_store` se pierde la tabla ETS y las camas reinician en `libre`. El siguiente paso es persistir en PostgreSQL (epgsql), como indica el stack.
