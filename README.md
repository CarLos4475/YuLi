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

## Fight — Captura rapida de tareas

Fight es tu bandeja de entrada para tareas. Escribe al vuelo con un limite de 280 caracteres y asigna categorias usando menciones con `@`.

- **Captura inline** con contador de caracteres y auto-completado de carpetas.
- **Tres buckets**: Hoy, Ayer y Vencidas — swipe a la derecha completa, a la izquierda descarta.
- **Fecha limite**: toca el reloj para asignar fecha con DatePicker + TimePicker.
- **Propagacion a Kanban**: long-press envia la tarea a un tablero Lab con su fecha limite.
- **Ciclo de vida**: pendiente → ayer → archivada → papelera → borrado definitivo a los 7 dias.
- **Vinculacion bidireccional**: completar una tarea mueve su tarjeta Kanban; mover la tarjeta completa la tarea.

---

## Flight — Notas, pizarras y cuadernos

Flight es un sistema de notas triple: block (markdown con bloques), pizarra (lienzo infinito) y cuaderno (multi-pagina A4). Todo se organiza en carpetas con color.

### Modo Nota (Block)

Notas enriquecidas con bloques tipo-dispatch:

- **TextBlock** — markdown con LaTeX inline y en vivo.
- **MathBlock** — LaTeX display.
- **BulletsBlock** — listas de items.
- **TareasBlock** — tareas FIGHT embebidas con check/uncheck y propagacion.
- **DrawingBlock** — canvas de dibujo inline con todas las herramientas.
- **Format toolbar**: heading levels, bold, italic, Strikethrough, codigo, LaTeX, alineaciones.
- **Insert menu**: Tabla, Codigo, Cita, LaTeX, Imagen, Divisor.
- **Markdown preview** en vivo con el mismo renderer del chat AI.
- **Exportacion a PDF** con share.

### Modo Pizarra (Whiteboard)

Lienzo virtual de 10000x10000px con pan + zoom (0.3x–4x). Disenado para pensamiento visual.

**Herramientas de dibujo:**

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

### Modo Cuaderno (Notebook)

Multi-pagina A4 con scroll vertical, transiciones animadas y page drawer con miniaturas.

- **Mismo drawing engine** que la pizarra: todas las herramientas, shape recognition, lasso, imagenes, texto, tareas.
- **Paginas infinitas**: pull-to-add, auto-creacion al dibujar fuera, drag-to-reorder.
- **Fondo por pagina**: patron + color independiente por pagina.
- **Paginas destacadas** (star) aparecen primero en el drawer.

### OCR (Google ML Kit Digital Ink)

Reconocimiento de escritura a mano on-device (descarga bajo demanda del modelo de idioma).

- OCR de trazos seleccionados con lasso → texto editable.
- Hoja de resultados con opciones: enviar a nota, enviar a YuLi como contexto, preguntar a YuLi.
- Deteccion heuristica de contenido no-textual (dibujos, matematicas).
- OCR matematico → LaTeX → chat AI.

---

## Lab — Proyectos con Kanban

Lab organiza proyectos en tableros Kanban con arrastrar y soltar, respaldados por cuatro vistas.

### Kanban Board

- **Columnas configurables**: posicion, default, terminal, expiracion.
- **Cards** con titulo, descripcion markdown, prioridad (none/low/medium/high), deadline, color de carpeta origen.
- **Multi-seleccion** para borrado batch.
- **Drag & drop** entre columnas.
- **Card detail**: editor de titulo, descripcion con preview, prioridad, deadline, links a nota fuente y tarea FIGHT.
- **Propagacion automatica**: tarjetas vencidas se mueven a columna de vencidos; completar desde FIGHT mueve a terminal.

### Schedule (Horario Semanal)

Grid hora × dia con bloques de horario por proyecto.

- Soporte para sabado/domingo configurable.
- Horas inicio/fin configurables por espacio.
- Bloques con titulo, ubicacion, color.
- Vinculacion de bloques con carpetas de Flight.
- Notas semanales por espacio.
- Asignacion automatica de lanes para resolucion de overlap.

### Calendar

Vista semanal y mensual con tarjetas Kanban organizadas por deadline. Navegacion entre semanas/meses.

### Timeline

Linea de tiempo horizontal con pan + zoom. Cards organizadas por deadline para vision general del proyecto.

---

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
| Markdown | `markdown_widget` + `flutter_math_fork` |
| Imagenes | `image_picker`, `photo_manager`, `flutter_image_compress` |
| PDF | `pdf` + `share_plus` |
| Seguridad | `flutter_secure_storage` (API key cifrada) |
| Fuentes | Space Grotesk, Inter (local TTF) |

17 tablas SQLite modeladas con Drift, repositorios con interfaces abstractas preparadas para futura migracion a servidor (PostgreSQL-compatible). 100% offline-first.

---

## Arquitectura

```
lib/
├── data/           # Implementaciones concretas (Drift, DeepSeek, ML Kit)
│   ├── local/      # DAOs, tablas, repositorios locales
│   └── services/   # DeepSeek Assistant, ML Kit recognizer, key store
├── domain/         # Capa de dominio pura
│   ├── models/     # 12 modelos (Task, Note, NoteBlock, LabSpace, KanbanCard…)
│   ├── repositories/  # Interfaces abstractas
│   └── services/   # Contratos de servicio (AiAssistant, InkRecognizer)
└── presentation/   # UI con Riverpod
    ├── providers/  # Estado (database, theme, navigation, AI session…)
    ├── screens/    # Fight, Flight, Lab, Settings, Trash, Home
    ├── theme/      # Tokens de diseno, colores, tipografia
    └── widgets/    # Componentes reutilizables (brutalist design system)
```

---

## Licencia

Este proyecto esta bajo la licencia MIT.
