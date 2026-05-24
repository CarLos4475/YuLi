# CONTEXT — YuLi (Segundo Cerebro)

## Resumen ejecutivo

YuLi es una app de organización personal **100% offline-first**. Sin servidores, sin login. Todo vive en el dispositivo. El esquema SQLite está diseñado para ser compatible con PostgreSQL (Supabase en v2).

---

## Stack

| Capa | Tecnología |
|---|---|
| UI | Flutter (iOS, Android, tablet) |
| Estado | flutter_riverpod ^2.x |
| Persistencia | Drift (ORM) + SQLite via drift_flutter |
| Markdown+LaTeX | markdown_widget + flutter_math_fork |
| Fuentes | Space Grotesk (display), Inter (cuerpo) — assets locales |

---

## Arquitectura

```
UI (Flutter Widgets)
        ↓
   Riverpod Providers  (lib/presentation/providers/)
        ↓
   Repository Interface  (lib/domain/repositories/)
        ↓
   LocalRepository (Drift)  (lib/data/repositories/local/)
        ↓
   DAO + AppDatabase  (lib/data/local/)
```

**Regla:** Riverpod NUNCA importa Drift directamente. Solo conoce las interfaces de repositorio del dominio.

---

## Estructura de carpetas

```
lib/
  data/
    local/
      tables/       ← definiciones de tablas Drift
      daos/         ← Data Access Objects
      database.dart ← AppDatabase + expiry queries
    repositories/
      local/        ← implementaciones LocalXxxRepository
  domain/
    models/         ← entidades de dominio puras (Task, Note, etc.)
    repositories/   ← interfaces abstractas (TaskRepository, etc.)
  presentation/
    theme/          ← app_tokens.dart
    widgets/        ← componentes reutilizables
    providers/      ← Riverpod providers
    screens/
      fight/
      flight/
      lab/
assets/
  fonts/            ← Space Grotesk + Inter (TTF locales)
```

---

## Design Tokens (resumen)

- **borderRadius:** 0.0 en todo — sin excepciones
- **Fondo light:** `#F5F2EC` (papel), dark: `#0D0D0D`
- **Texto:** `#111111` (ink), `#888888` (gris metadata)
- **Acentos:** Fight=`#E02B2B`, Flight=`#2D4B8E`, Lab=`#3D6B4F`, Journal=`#C17F3A`
- **Bordes:** `borderWidth=2.0`, `borderWidthHeavy=4.0`
- **Sombra:** offset(3,3), blur=0 (sólida, sin difuminar)

---

## Tablas SQLite

`tasks`, `folders`, `notes`, `note_images`, `note_versions`, `note_task_links`, `lab_spaces`, `kanban_columns`, `kanban_cards`, `space_folder_links`, `onboarding_flags`

Drift usa `@DataClassName('XxxRow')` para que los data classes generados no colisionen con los modelos de dominio.

---

## Ciclo de vida de tareas (expiry)

Al abrir la app se ejecutan 6 queries en secuencia:
1. `pending` → `yesterday` (si `created_at` es de ayer)
2. `yesterday` → `archived_failed` (si `created_at` es de hace 2+ días)
3. `archived_failed` → `trash` (inmediato; retorna count para AppBanner)
4. `trash` → DELETE permanente (si `trashed_at` tiene 7+ días)
5. `folders` → DELETE si `deleted_at` tiene 7+ días
6. `lab_spaces` → DELETE si `deleted_at` tiene 7+ días

---

## Decisiones técnicas tomadas

- `expires_at` se calcula en Dart al insertar (`DateTime.now().add(Duration(hours: 48))`), no con modificadores SQLite (inconsistencias entre plataformas).
- Imágenes de notas: `uuid.jpg` en `/app_documents/images/{note_id}/`.
- Versiones de notas: máximo 10 (FIFO). Al agregar la 11ª se elimina la más antigua.
- Anchors de Kanban en notas: `<!-- kanban:{card_id} -->` (invisibles al renderizar).
- Organizadores visuales (mindmap, flowchart): `CustomPainter` nativo. Prohibido WebView.
- Paleta de colores para carpetas: lista curada de 10 colores, sin color picker libre.
- Persistencia de etiquetas de carpeta: la base de datos conserva la etiqueta original (ej. `@matematicas`) en las tareas. Las vistas (`TaskCard`, `PanelTaskTile` y `_MarkdownPreview`) se encargan de removerla dinámicamente de la interfaz de usuario y colorear el texto con el color del folder asociado.
- Renderizado de LaTeX: Para evitar falsos positivos con precios de divisas (como `$10 y $20`), se implementaron lookarounds negativos (`(?!\s)` y `(?<!\s)`) en la expresión regular de LaTeX inline/single-line block. Además, para soportar correctamente ecuaciones de bloque multilinea con saltos y líneas vacías, se introdujo un parser personalizado `LatexBlockSyntax` (subclase de `BlockSyntax` de `markdown`) que consume las líneas completas entre bloques `$$` impidiendo su segmentación en múltiples párrafos.
- Guardado asíncrono en `dispose()`: Para evitar el error `StateError: Cannot use "ref" after the widget was disposed` al cerrar pantallas de edición, todas las llamadas a `_save()` invocadas durante `dispose()` deben almacenar las referencias de sus repositorios en variables locales sincrónicas (`final repository = ref.read(...)`) antes de cualquier instrucción `await`. Esto previene accesos tardíos a `ref` una vez que la instancia del WidgetState ha completado su ciclo de vida y se ha desmontado de la jerarquía de elementos.
- Conexiones Flight ➔ Lab (Fase 8):
  - La vinculación de notas se realiza mediante `note_editor_screen.dart` creando una tarjeta con `sourceNoteId` y concatenando de forma automática la firma invisible `<!-- kanban:{card_id} -->` en el texto de la nota, la cual es guardada al instante.
  - La vinculación de carpetas a proyectos se expone en `LabSpaceDetailScreen` permitiendo asociar carpetas Flight a través de `space_folder_links`. Las carpetas asociadas son renderizadas reactivamente en la barra superior del Kanban como mini-etiquetas de colores (basadas en la paleta de la carpeta) para mantener visibilidad cruzada.
- Eliminación de Carpetas y Spaces por Gesto: Para simplificar la administración offline-first y evitar menús redundantes, se habilitó el gesto `onLongPress` sobre las carpetas de Flight y los recuadros de proyectos de Lab. Ambos despliegan un modal `AlertDialog` con restricciones visuales neobrutalistas (`borderRadius: 0.0`) y delegan la persistencia mediante un `softDelete` hacia sus correspondientes repositorios locales.





