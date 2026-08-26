# YuLi - Segundo Cerebro

![Flutter](https://img.shields.io/badge/Flutter-3.27+-blue?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.7-0175C2?logo=dart)
![Plataforma](https://img.shields.io/badge/Plataforma-Android%20%7C%20iOS-lightgrey)
![Licencia](https://img.shields.io/badge/Licencia-MIT-green)
![Estado](https://img.shields.io/badge/Estado-En%20desarrollo-yellow)
![Offline First](https://img.shields.io/badge/Offline--First-Si-2ea44f)
![SQLite](https://img.shields.io/badge/Base%20de%20datos-SQLite-003b57)

YuLi es una aplicacion de organizacion personal que funciona como un segundo cerebro. Disenada para capturar ideas, administrar tareas, tomar notas con dibujo, gestionar proyectos con Kanban y consultar a una IA — todo sin conexion a internet ni registro de usuario. Tus datos siempre estan contigo, almacenados localmente en SQLite.

---

## Requisitos previos

- **Flutter 3.27+** (Dart 3.7)
- **Android Studio** o **VS Code** con extension Flutter
- **Git**
- **(Opcional)** API key de DeepSeek para funciones de IA

## Inicio rapido

```bash
# Clonar el repositorio
git clone https://github.com/tuusuario/yuli.git
cd yuli

# Obtener dependencias
flutter pub get

# Generar codigo Drift (DAOs, tablas, database)
dart run build_runner build --delete-conflicting-outputs

# Ejecutar en modo debug
flutter run
```

> **Nota:** Las funciones de IA requieren una API key de DeepSeek. Se configura desde la app en Ajustes → YuLi AI. La key se almacena cifrada con `flutter_secure_storage`.

## Ejecutar tests

```bash
# Tests headless (no requiere emulador/dispositivo)
flutter test

# Test de regresión de la auditoría (Lab, cascadas, expiry)
flutter test test/audit_test.dart
```

---



## YuLi AI — Powered by DeepSeek

YuLi integra un asistente de inteligencia artificial basado en **DeepSeek V4** (modelos Flash y Pro), accesible desde cualquier nota, pizarra o cuaderno. El chat es contextual: toma el contenido de tu nota como punto de partida y mantiene el hilo de la conversacion por nota.

- **Modelo Flash**: rapido y economico para uso diario (resumir, limpiar, extraer tareas, traducir).
- **Modelo Pro**: razonamiento profundo para explicaciones complejas, codigo, matematicas.
- **Contexto persistente por nota**: el contenido que subes al chat sobrevive cierres y reinicios de la app.
- **Token-shielding**: el contexto se compacta automaticamente si es muy largo, con opcion a deshacer.
- **Limite diario configurable** (150 requests/dia) para evitar costos inesperados.
- **Acciones quick**: Resumir, Extraer tareas, Sugerir titulo, Traducir, Reescribir y Resumir chat — sin necesidad de escribir.
- **Renderizado en markdown** con LaTeX, tablas GFM, codigo, checklists.
- **Enviar respuesta al lienzo**: convierte la respuesta de la IA en una caja de texto dentro de tu pizarra o cuaderno.
- **Extraer tareas**: detecta tareas accionables en la respuesta y las crea directamente en FIGHT.
- **Sincronizacion nota ↔ canvas**: vincula una nota block como fuente de contexto para una pizarra o cuaderno; el OCR redirigido escribe en la nota fuente.
- **API key cifrada** en flutter_secure_storage — nunca sale del dispositivo.

---

## Home — Panel central

Home es el centro de comando con los tres pilares de YuLi.

- **Triptico Fight / Flight / Lab** con contadores de tareas pendientes, notas activas y espacios en curso.
- **Captura rapida** inline desde el panel Fight sin salir del home.
- **Barra de progreso** con relleno hatchado por espacio.
- **Widget "Proxima clase"** agrega el bloque de horario mas proximo.
- **Cubo animado de YuLi** como cabecera.
- **Saludo** segun la hora del dia y reloj en vivo.

---

## Fight — Captura rapida de tareas

Fight es tu bandeja de entrada para tareas. Escribe al vuelo con un limite de 280 caracteres y asigna categorias usando menciones con `@`.

- **Captura inline** con contador de caracteres y auto-completado de carpetas.
- **Tres buckets**: Hoy, Ayer y Vencidas — swipe a la derecha completa, a la izquierda descarta.
- **Fecha limite**: toca el reloj para asignar fecha con DatePicker + TimePicker.
- **Propagacion a Kanban**: long-press envia la tarea a un tablero Lab con su fecha limite.
- **Ciclo de vida**: pendiente → ayer → archivada → papelera → borrado definitivo a los 7 dias.
- **Vinculacion bidireccional**: completar una tarea mueve su tarjeta Kanban; mover la tarjeta completa la tarea.

### Recordatorios

Sistema completo de recordatorios con presets programables.

- **Presets**: al vencimiento, 30 min antes, 1 dia antes, o personalizado.
- **Resumen diario**: notificacion configurable con tareas del dia.
- **Notificaciones exactas**: con permiso y canal dedicado.
- **Sincronizacion automatica**: recordatorios se re-sincronizan al editar fechas.

---

## Flight — Notas, pizarras y cuadernos

Flight es un sistema de notas triple: block (markdown con bloques), pizarra (lienzo infinito) y cuaderno (multi-pagina A4). Todo se organiza en carpetas con color.

### Modo Nota (Block)

Notas enriquecidas con bloques tipo-dispatch:

- **TextBlock** — editor LIVE de Markdown persistido, con wrapping vertical, seleccion entre parrafos, autosave y flush al salir.
- **MathBlock** — LaTeX display.
- **BulletsBlock** — listas de items.
- **TareasBlock** — tareas FIGHT embebidas con check/uncheck y propagacion.
- **DrawingBlock** — canvas de dibujo inline con todas las herramientas.
- **Format toolbar**: H1/H2/H3, bold, italic, strikethrough, highlight, codigo, listas, tareas, divisor y alineaciones.
- **Insert menu**: tabla, codigo, cita, LaTeX, imagen y divisor mediante nodos/comandos documentales.
- **Tablas, imagenes, codigo y LaTeX display**: nodos atomicos seleccionables con acciones discretas y edicion inline/panel compacto.
- **Render LIVE**: los marcadores Markdown se suavizan o esconden fuera del dominio activo, sin perder el texto fuente.
- **Exportacion a PDF** con share; conserva la ruta actual usando el Markdown serializado.

### Modo Pizarra (Whiteboard)

Lienzo virtual de 10000x10000px con pan + zoom (0.3x–4x). Disenado para pensamiento visual.

**Herramientas de dibujo:**

- **Múltiples pizarras por nota** — panel lateral para crear, renombrar, cambiar y eliminar lienzos independientes; los nuevos heredan el fondo activo.
- **Pen** — trazo libre con presion.
- **Fountain Pen** — simulacion de tinta con variacion de grosor por velocidad.
- **Highlighter** — marcador semitransparente (BlendMode.multiply).
- **Eraser** — modo Stroke (borra entero) y modo Partial (corta trazos con precision).
- **Lasso** — seleccion por trazo libre o tap; move, resize, rotate, duplicate, delete.
- **Text** — cajas de texto markdown redimensionables con reflow.

**Shape recognition** (estilo Apple Notes): dibuja una forma y mantén 800ms para que se ajuste a linea recta, flecha, circulo, elipse, rectangulo o triangulo. Ajuste en vivo antes de soltar. Relleno semitransparente opcional.

**Imagenes:** insercion desde galeria o camara, recorte, rotacion, posicion. Cache por nota con limpieza de huerfanos al salir.

**Canvas Text Blocks:** cajas de texto markdown (mismo engine que las notas). Editor dockeado sobre el teclado. Redimension por esquina (escala uniforme) o lateral (reflow).

**Canvas Task Blocks:** tareas FIGHT embebidas en el canvas. Crear, check/uncheck, propagacion bidireccional. Long-press para linkear a Lab Space.

**Background:** patrones Blank, Lined, Grid, GridSmall, Dotted + color de papel (blanco, crema, gris, negro).

**Pines flotantes (PiN):** ventanas ancladas a la pantalla que se quedan fijas mientras navegas el lienzo (no se mueven con scroll/zoom). Arrastrables, redimensionables, colapsables (con animacion). Tipos: snapshot de una seleccion con lasso (volatil), imagen, PDF (con navegacion de paginas que persiste) y video de YouTube (con barra de estudio; requiere conexion). Imagen/PDF/video se persisten por nota. Estilo accent de la nota.

**Exportacion a PNG/PDF:** renderizado offline fiel del canvas completo o region seleccionada, con opcion de incluir bloques de tareas.

### Modo Cuaderno (Notebook)

Multi-pagina A4 con scroll vertical, transiciones animadas y page drawer con miniaturas.

- **Mismo drawing engine** que la pizarra: todas las herramientas, shape recognition, lasso, imagenes, texto, tareas.
- **Paginas infinitas**: pull-to-add, auto-creacion al dibujar fuera, drag-to-reorder.
- **Fondo por pagina**: patron + color independiente por pagina.
- **Paginas destacadas** (star) aparecen primero en el drawer.
- **Historial de versiones** por nota (snapshots automaticos).
- **Vinculacion nota ↔ tarea** many-to-many: las notas pueden referenciar tareas FIGHT.

### OCR (Google ML Kit Digital Ink)

Reconocimiento de escritura a mano on-device (descarga bajo demanda del modelo de idioma).

- OCR de trazos seleccionados con lasso → texto editable.
- Hoja de resultados con opciones: enviar a nota, enviar a YuLi como contexto, preguntar a YuLi.
- Deteccion heuristica de contenido no-textual (dibujos, matematicas).
- OCR matematico → LaTeX → chat AI.

---

## Lab — Proyectos con Kanban

Lab organiza proyectos en tableros Kanban con arrastrar y soltar, respaldados por cuatro vistas.

### Vista de espacios

La pantalla principal de Lab lista todos tus espacios con filtros y resumen visual.

- **Filtros por estado**: Todos, En Proceso, Pausados, Completados, Archivo.
- **Tarjetas de espacio** con barra de distribucion apilada por columna, etapa actual, dias restantes y accesos directos a vistas.
- **Hoja de opciones**: renombrar, cambiar color, pausar/reanudar, completar, archivar, reactivar o eliminar.
- **Columna de legendas** con indicador de color por columna Kanban.

### Kanban Board

- **Columnas configurables**: posicion, default, terminal, expiracion.
- **Cards** con titulo, descripcion markdown, prioridad (none/low/medium/high), deadline, color de carpeta origen, badges de origen (TAREA / NOTA / HECHO / VENCIDO) y chip de carpeta mencionada.
- **Multi-seleccion** para borrado batch.
- **Drag & drop** entre columnas.
- **Card detail**: editor de titulo, descripcion con preview en vivo y toggle edicion/vista, selector de columna, selector de prioridad, fecha de inicio (auto/fijo), fecha limite con hora, selector de recordatorio con flujo de permisos, boton "Ver nota de origen" y chips "Aparece en" (Kanban, Calendar, Timeline, FIGHT, FLIGHT).
- **Propagacion automatica**: tarjetas vencidas se mueven a columna de vencidos; completar desde FIGHT mueve a terminal.
- **Quick-add**: dialogo para crear tarjetas rapidamente.
- **Gestion de columnas**: renombrar, recolorar, reordenar, toggle de flags (isTerminal, isExpired, isInProgress) y eliminar desde popover.
- **Editor de fechas de proyecto**: rango inicio-fin del espacio con control granular.
- **Pestañas multiples**: Kanban, Calendario, Timeline, Horario y Grafo — pestañas persistidas y reordenables.

### Lab AI

YuLi LAB integra un asistente de IA especifico para el proyecto.

- **Generar tarjetas**: describe tareas en lenguaje natural y la IA las desglosa en tarjetas Kanban con prioridad y columna sugerida. Revision y aprobacion antes de crear.
- **Resumir/triar**: la IA analiza el estado del tablero, identifica bloqueos y sugiere acciones.
- **Chatear sobre el proyecto**: sesion de chat contextual con todo el tablero como fuente.
- **Contexto enriquecido**: el AI recibe la serializacion completa del board (columnas, tarjetas, prioridades, fechas).

### Fuentes de contexto

Cada espacio Lab puede alimentarse de contenido externo para enriquecer el AI y el grafo de conexiones.

- **Carpetas Flight**: vincula una carpeta entera — todas sus notas y tareas aparecen en el grafo.
- **Notas individuales**: selecciona notas especificas como fuente.
- **URLs externas**: ingresa un enlace y YuLi lo fetchea via Jina Reader para usarlo como contexto.
- **Habilitar/deshabilitar fuentes**: cada fuente tiene un toggle individual.
- **Cache de URLs**: el contenido fetcheado se persiste en disco por hash; refetch disponible.
- **Cache de contexto**: compactacion por hash de contenido para evitar re-procesar fuentes identicas.

### Schedule (Horario Semanal)

Grid hora × dia con bloques de horario por proyecto.

- Soporte para sabado/domingo configurable.
- Horas inicio/fin configurables por espacio.
- Bloques con titulo, ubicacion, color.
- Vinculacion de bloques con carpetas de Flight.
- Notas semanales por espacio.
- Asignacion automatica de lanes para resolucion de overlap.
- **Drag-to-create**: arrastre vertical en una columna de dia para crear bloques.
- **Bloque "EN VIVO"**: badge que identifica el bloque actualmente en curso.
- **Linea de hora actual** con marcador "HOY".
- **Detalle de bloque**: hoja con edicion de titulo, ubicacion, hora, dias, carpeta vinculada y color.

### Calendar

Vista semanal y mensual con tarjetas Kanban organizadas por deadline.

- Navegacion entre semanas/meses con toggle de vista.
- **Drag-and-drop de tarjetas** a diferentes dias: cambia la fecha limite automaticamente.
- **Dialogo de dia**: muestra todas las tarjetas con deadline en esa fecha.
- **Seccion "Sin fecha"**: scroll horizontal de tarjetas sin deadline asignado.

### Timeline

Linea de tiempo horizontal tipo Gantt con pan + zoom.

- Cards organizadas por deadline para vision general del proyecto.
- **Lane packing**: filas apiladas por columna con resolucion automatica de overlap.
- **Indicador "Hoy"**: linea vertical + etiqueta en la fecha actual.
- **Grid con cabeceras**: fecha y mes en el eje superior.
- **Seccion "Sin fecha"**: tarjetas sin deadline agrupadas al final.

### Grafo de conexiones

Grafo dirigido por fuerzas que visualiza las relaciones entre todos los elementos de YuLi.

- **5 tipos de nodo**: espacio (sol), tarjeta Kanban, carpeta, nota, tarea.
- **3 tipos de arista**: estructura (contiene), puente (cross-mode), IA (alimenta contexto).
- **Filtros**: activar/desactivar tipos de nodo y arista visibles.
- **Grafo global** vs **grafo por espacio**.
- **Simulacion fisica** tipo D3 con deteccion de colisiones y layout deterministico.
- **Pan, zoom, arrastre** de nodos con InteractiveViewer.
- **Inspector de nodo**: panel lateral con detalles segun el tipo (tarea: fecha, carpeta, enlaces; nota: tipo, bloques, conexiones; etc.).
- **Capa de pulso**: animacion para tarjetas urgentes.
- **Ajuste automatico** (fit-to-view) al estabilizarse la simulacion.

---

## Settings — Ajustes

- **Tema**: alternar modo claro/oscuro con bloques de previsualizacion en vivo.
- **YuLi AI**: configurar API key de DeepSeek, seleccionar modelo (Flash/Pro), limite diario de requests (150/dia por defecto).
- **Jina Reader**: configurar API key para fetching de URLs como contexto.
- **Recordatorio diario**: habilitar/deshabilitar resumen diario y configurar hora.
- **Almacenamiento de imagenes**: explorar imagenes almacenadas por nota con tamanos y opcion de limpieza.
- **Logs de crash**: visualizar, compartir y limpiar el registro de errores Dart en diagnostics/crash.log.

## Trash — Papelera

Tres columnas para gestion de elementos eliminados.

- **Flight**: carpetas y notas eliminadas con opciones de restaurar o borrado definitivo.
- **Lab**: espacios eliminados con restaurar o borrado definitivo.
- **Fight**: tareas eliminadas (sin restauracion, borrado definitivo tras 7 dias).
- **Cascadas**: al borrar una carpeta se eliminan sus notas; al borrar un espacio se eliminan sus tarjetas y bloques de horario.

## Coach Marks — Tutorial interactivo

Guias de una sola vez que aparecen en la primera interaccion con cada seccion principal, almacenadas en la tabla `onboarding_flags`.

## Diseno neobrutalista

Sin bordes redondeados, bordes negros marcados, sombras solidas. Colores de acento por seccion: rojo para Fight, azul para Flight, verde para Lab, ocre para el tablero. Tipografia: Space Grotesk (display) + Inter (body).

- **Modo oscuro** que se adapta a la preferencia del sistema.
- **Textura grain overlay** sobre fondos.
- **Animaciones sutiles** (avatar giratorio de la IA, indicador de sincronia, micro-interacciones).

---

## Stack tecnologico

| Capa | Tecnologia |
|------|-----------|
| UI | Flutter 3.27+ (Material 3) |
| Estado | Riverpod 2.x (manual, sin generacion `@riverpod`) |
| Base de datos | Drift ORM + SQLite (offline-first) |
| IA | DeepSeek API (OpenAI-compatible, streaming SSE) |
| OCR | Google ML Kit Digital Ink Recognition (on-device) |
| Markdown / LIVE editor | `appflowy_editor` + `markdown_widget` + `flutter_math_fork` |
| Imagenes | `image_picker`, `photo_manager`, `flutter_image_compress` |
| PDF | `pdf` + `share_plus` |
| Seguridad | `flutter_secure_storage` (API key cifrada) |
| Notificaciones | `flutter_local_notifications` + `timezone` |
| Web fetching | Jina Reader API |
| Fuentes | Space Grotesk, Inter (local TTF) |

19 tablas SQLite modeladas con Drift, repositorios con interfaces abstractas preparadas para futura migracion a servidor (PostgreSQL-compatible). 100% offline-first.

---

## Arquitectura

```
lib/
├── data/                # Implementaciones concretas (Drift, DeepSeek, ML Kit)
│   ├── local/
│   │   ├── daos/        # DAOs Drift (folders, notes, kanban, tasks, schedule…)
│   │   ├── tables/      # 19 tablas SQLite modeladas con Drift
│   │   ├── database.dart
│   │   └── repositories/  # Implementaciones locales de repositorios
│   └── services/        # DeepSeek Assistant, ML Kit recognizer, reminder coordinator,
│                        # web reader, context cache, crash logger, image storage
├── domain/              # Capa de dominio pura
│   ├── models/          # Task, Note, NoteBlock, LabSpace, KanbanCard, Graph,
│   │                    # ScheduleBlock, ReminderPreset, CanvasContextSource…
│   ├── repositories/    # Interfaces abstractas (nota, folder, task, kanban…)
│   └── services/        # Contratos (AiAssistant, InkRecognizer, ReminderScheduler)
└── presentation/        # UI con Riverpod
    ├── providers/       # Estado (database, theme, navigation, AI session, lab tabs…)
    ├── screens/         # Home (dashboard), Fight, Flight (editor/whiteboard/notebook),
    │                    # Lab (kanban/calendar/timeline/schedule/graph), Settings, Trash
    ├── theme/           # Tokens de diseno neobrutalista
    └── widgets/         # Sistema de diseno reutilizable (ModeHeader, YBadge, PillTab…)
```

---

## Licencia

Este proyecto esta bajo la licencia MIT.
