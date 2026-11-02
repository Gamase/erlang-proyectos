# #40 — Camas de hospital

**Dominio:** Salud

ocupacion, altas y limpieza.

## Equipo

Proyecto individual: Sebastián Martínez García (@Gamase) — backend, frontend y ops/QA.

## Arranque

```bash
rebar3 compile
rebar3 eunit
rebar3 shell
```

## Pendiente

- [ ] Disenar pantallas en Stitch (`design/PROMPT_STITCH.md`)
- [x] Modelar el dominio: que es un proceso, que es un supervisor
- [ ] Endpoints `/api/...` y WebSocket con cowboy
- [ ] Metricas `/metrics` y diagnostico con recon
- [ ] Release + systemd
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
