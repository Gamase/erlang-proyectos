# Prompts para Google Stitch — #40 Camas de hospital

Usa **Mobile** en Stitch. Pega el prompt 1 para crear el estilo y el dashboard; despues
pide cada pantalla extra con su prompt para que conserven el mismo estilo.
Al terminar: Export -> descarga el zip (HTML/CSS + capturas + `DESIGN.md`) y
descomprimelo en esta carpeta (`design/`).

Los nombres de servicios, IDs de camas y estados son los mismos que usa el backend
(`p40_cama`, `p40_admisiones`, `p40_eventos`), para que la UI se conecte sin traducir nada.

---

## Prompt 1 — Estilo general + Dashboard

```
Diseña una app web móvil en español para el control de camas de un hospital público
en México. La usa el personal de admisión y enfermería en el celular durante el turno,
así que debe leerse de un vistazo: tipografía clara, tarjetas grandes, buen contraste,
tema claro con fondo gris muy suave.

Colores de estado (úsalos igual en todas las pantallas):
- Cama libre: verde
- Cama ocupada: azul
- Cama por limpiar: ámbar
- Cama bloqueada: gris
- Ocupación de un servicio: verde si es menor a 75 %, ámbar entre 75 y 84 %, rojo si es 85 % o más (alerta crítica)

Pantalla "Dashboard":
- Encabezado: "Camas de hospital", reloj de la simulación ("Día 2 · 14:35") y un punto verde "En vivo".
- Tarjeta grande de ocupación general: 96 de 120 camas ocupadas (80 %), con barra de progreso, y debajo: 12 libres, 9 por limpiar, 3 bloqueadas.
- Banner rojo de alerta cuando hay servicios al 85 % o más: "Ocupación crítica en Cirugía (96 %) y Terapia intensiva (100 %)".
- Lista de 6 tarjetas, una por servicio, cada una con nombre, barra de ocupación con su color, "ocupadas / total", pacientes en espera y "libres en 4 h":
  Medicina interna 24/30 (80 %), 0 en espera, 5 libres en 4 h
  Cirugía 24/25 (96 %), 3 en espera, 2 libres en 4 h
  Gineco-obstetricia 15/20 (75 %), 0 en espera, 4 libres en 4 h
  Pediatría 10/15 (67 %), 0 en espera, 3 libres en 4 h
  Aislamiento 13/20 (65 %), 0 en espera, 6 libres en 4 h
  Terapia intensiva 10/10 (100 %), 2 en espera, 1 libre en 4 h
- Botón flotante "+ Admitir paciente".
- Barra de navegación inferior con 4 pestañas: Inicio, Camas, Admitir, Bitácora.
```

## Prompt 2 — Camas de un servicio + detalle de cama

```
Con el mismo estilo, crea la pantalla "Camas" de un servicio:
- Selector de servicio arriba (Cirugía seleccionado) y filtros en chips: Todas, Libres, Ocupadas, Por limpiar, Bloqueadas.
- Cuadrícula de 25 camas (CIR-01 a CIR-25) como cuadros con el ID y un ícono, coloreadas por estado. Una ocupada muestra el ID del paciente (P-0142); una por limpiar muestra el tiempo restante ("18 min").

Y una hoja inferior (bottom sheet) de detalle al tocar una cama, por ejemplo CIR-07:
- Estado actual en grande con su color: "Ocupada".
- Paciente: P-0142. En este estado desde: 13:05. Alta estimada: hoy 16:30.
- Botones de acción según el estado: "Dar de alta", "Programar alta", "Trasladar a otro servicio".
  Para una cama por limpiar: barra de progreso de limpieza y botón "Limpieza terminada".
  Para una cama libre: botón "Bloquear (mantenimiento)".
```

## Prompt 3 — Admitir paciente

```
Con el mismo estilo, crea la pantalla "Admitir paciente":
- Campo "ID del paciente" (ejemplo P-0231).
- Selector de servicio con los 6 servicios, mostrando junto a cada uno cuántas camas libres tiene.
- Botón principal "Asignar cama".
- Dos estados de resultado:
  1) Éxito (verde): "Cama asignada: MI-14 · Medicina interna".
  2) Sin cama (ámbar): "No hay camas libres en Terapia intensiva. El paciente quedó en lista de espera, posición 3. Se le asignará la primera cama que se libere." Debajo, la lista de espera del servicio.
- Nota pequeña: "Un paciente solo recibe cama de su servicio."
```

## Prompt 4 — Bitácora de eventos y alertas

```
Con el mismo estilo, crea la pantalla "Bitácora": una línea de tiempo de eventos en
vivo, el más reciente arriba, con ícono y color por tipo y chips para filtrar
(Todos, Alertas, Admisiones, Altas, Fallas):
- 14:35 · Alerta crítica: Cirugía al 96 % (rojo)
- 14:32 · Admisión: P-0231 → MI-14 (azul)
- 14:20 · Cama CIR-03: por limpiar → libre (verde)
- 14:05 · Falla inyectada: proceso de PED-04 terminado; se reinició y recuperó su estado "ocupada" (rojo con ícono de rayo)
- 13:50 · Sin cama: P-0228 en espera para Terapia intensiva, posición 2 (ámbar)
- 13:40 · Traslado: P-0190 de MI-08 a UCI-03 (morado)
- 13:15 · Alerta resuelta: Aislamiento bajó a 80 % (verde)
- 12:50 · Brote: 25 pacientes enviados a Aislamiento (rojo)
```
