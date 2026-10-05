# YuLi Fast Typing y edición de notas

Fast Typing es una acción manual sobre el bloque de texto completo creado desde
**+ Texto**. Abre **•••** en el bloque y pulsa **YuLi Fast Typing**; la acción no
aparece permanentemente dentro del contenido. Los párrafos internos no se
convierten en bloques independientes ni muestran tiradores adicionales.

La interfaz de Fast Typing reutiliza las superficies y controles del panel de
YuLi AI. Abre un diálogo del bloque elegido que compara original y corregido.
**Aceptar cambios** aplica la propuesta y cierra el diálogo; **Rechazar cambios**
la descarta y también lo cierra. El texto no se modifica antes de aceptar.

## Corrección

- Una solicitud Flash por bloque de texto, hasta 10 000 caracteres y 80 fragmentos
  internos. Cada celda puede aportar texto. Usa la clave y la cuota locales de
  YuLi AI; la reserva de cuota se serializa para solicitudes simultáneas.
- Se envía únicamente la selección, sin historial del chat ni contexto de otras
  notas. Imágenes, bloques de código y LaTeX quedan fuera. Los segmentos de código,
  fórmulas, URLs y enlaces reconocidos dentro del texto se ocultan en la petición.
- La respuesta contiene sustituciones puntuales y señala la aparición de cada
  error, sin pedirle al modelo que calcule índices de caracteres. Se comprueban
  identidad, límites de palabra, solapamientos y distancia de edición. No se
  interpreta la respuesta como Markdown, HTML ni instrucciones.
- Se descartan respuestas truncadas, incompletas o inválidas. Los errores no
  reemplazan el texto. Cancelar impide aplicar la respuesta; una solicitud ya
  enviada puede consumir cuota y terminar en el proveedor.
- Si un bloque cambia o desaparece durante la petición, su respuesta no se aplica.
  Las correcciones aceptadas se agrupan en una transacción y conservan el formato.

El filtro es deliberadamente conservador: puede dejar errores sin corregir,
incluidas palabras repetidas o abreviaturas ambiguas. Ni el prompt ni la distancia
de edición garantizan que el modelo identifique siempre la palabra pretendida;
por eso se revisa la propuesta antes de aplicarla. Después se puede deshacer desde
el editor.

## Tablas, imágenes y código

- Las celdas se editan al tocarlas. Sólo mientras la tabla está activa aparece el
  botón **•••** sobre ella; al abrirlo, las acciones se despliegan en ese mismo
  lugar. Se conserva al menos una fila y columna.
- El menú avanzado permite duplicar y mover filas o columnas, además de ajustar el
  ancho de la columna activa. Las tablas anchas se desplazan dentro de la nota.
  Tab/Shift+Tab siguen disponibles con teclado.
- **Pegar celdas** admite texto tabulado, incluido el formato de celdas entre
  comillas con saltos de línea. Límites del pegado: 100 filas, 40 columnas y 2000
  celdas. Amplía la tabla cuando hace falta y conserva las celdas no afectadas.
- Imágenes y código usan el mismo flujo: tocar selecciona o edita el elemento y
  muestra **•••** arriba; ese botón abre reemplazo, alineación, lenguaje, selección
  o borrado en una capa flotante que no altera la altura de la nota. Al perder el
  foco, los controles se ocultan. Permanecen dentro del área de la nota, fuera del
  encabezado, las pestañas y las herramientas; si el elemento sale de la vista,
  su menú se oculta. El código conserva saltos de línea con
  indentación y Tab para espacios.
- Una imagen o fórmula tocada queda seleccionada completa. En tablas y código se
  usa **Seleccionar**; después, Retroceso o Supr elimina el elemento. Retroceso
  dentro de una celda o del código sólo elimina texto. Si era el único elemento,
  queda un párrafo vacío para seguir escribiendo.
- Al insertar una tabla, imagen, bloque de código o fórmula, se selecciona el
  elemento completo sin crear una línea vacía artificial. **Continuar escribiendo**
  aparece al final sólo mientras el bloque de texto tiene foco y, al pulsarlo,
  crea un párrafo real. Las acciones contextuales no reservan espacio permanente.

## Persistencia y compatibilidad

Referencias de interacción: [Obsidian 1.5](https://obsidian.md/changelog/2023-12-26-desktop-v1.5.3/)
para edición, selección y movimiento de filas/columnas, y
[Goodnotes Text Document](https://support.goodnotes.com/hc/en-us/articles/13692184123279-Text-Document)
para acciones contextuales sobre la selección. Esta implementación no incluye
combinación de celdas ni todos los controles de esos productos.

El payload de `TextBlock` conserva `md` y añade `document`, la representación
estructurada del editor. El guardado escribe ambos campos completos. No hay
migración de SQLite. El documento conserva anchos y atributos que Markdown no
representa; las exportaciones y consumidores existentes siguen leyendo `md`.

Solo se restaura `document` cuando su Markdown coincide con `md`. Un payload
antiguo, incompatible o editado por otro flujo conserva su texto mediante el
fallback Markdown. Los escritores externos que guardan únicamente `md` no
conservan los tamaños exclusivos de `document`.

## Verificación

Las pruebas cubren validación de respuestas, aceptación y rechazo, cancelación, edición concurrente,
formato, deshacer, selección múltiple, teclado, movimiento, pegado de tablas,
redimensionado, altura de imágenes decodificadas, menús durante el desplazamiento,
compatibilidad de payloads y guardado al salir.

Pendiente en Android/tablet: ergonomía con dedo y stylus, teclado del dispositivo,
tablas anchas, cambio de orientación y una solicitud real al proveedor. Las
pruebas de IA usan respuestas simuladas y no consumen la clave del usuario.
