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
- [ ] Simulacion del escenario (120 camas, 40 ingresos/40 altas al dia, brote)

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

### Limitacion conocida

Si muere `p40_store` se pierde la tabla ETS y las camas reinician en `libre`. El siguiente paso es persistir en PostgreSQL (epgsql), como indica el stack.
