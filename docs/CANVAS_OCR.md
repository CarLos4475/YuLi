# Escritura buscable

En Ajustes → Reconocimiento (OCR), «Reconocimiento automático» y «Revisión
ortográfica» son interruptores independientes, activos por defecto y persistidos
localmente. Apagarlos cancela colas/reintentos y descarta resultados en curso;
una llamada nativa ya iniciada puede terminar. No borra transcripciones ni afecta
al OCR manual del lazo. Con reconocimiento apagado, la revisión puede trabajar
sobre texto vigente ya reconocido; con revisión apagada no hay subrayados ni
sugerencias. Mientras se cargan los ajustes, no se inicia procesamiento automático.

Pizarra y cuaderno reconocen automáticamente la tinta tras 3 segundos de pausa,
con el modelo español de ML Kit descargado. La lupa del encabezado abre la búsqueda
dentro del documento: campo, contador, anterior/siguiente y cerrar, sin lista de
transcripciones. La coincidencia activa se resalta sobre la hoja; navegar conserva
la escala. Enter/Shift+Enter recorren coincidencias y Escape cierra. Si falta el
modelo, la barra ofrece descargar español una vez.
El reconocimiento y la revisión ortográfica no realizan peticiones a YuLi AI.

La revisión usa el corrector del sistema a través de Flutter. Depende de que el
dispositivo tenga un servicio de corrección e idioma español disponibles; no se
garantiza el comportamiento de red de un corrector instalado por terceros.
Los posibles errores se señalan con una línea fina bajo la palabra. Digital Ink
no aporta sus coordenadas: se asocian los tokens con grupos de trazos separados por
huecos espaciales. Solo se conservan asociaciones uno-a-uno; nunca se reparten
anchos según el número de letras. Es una heurística conservadora, no una garantía
de precisión para cursiva, palabras unidas, rotación o diagramas. Si la asociación
es ambigua, no se dibuja un subrayado de renglón como sustituto.

Con rechazo de palma activo y sin una selección o herramienta de inserción/borrado,
tocar la palabra con el dedo muestra una burbuja informativa con las alternativas.
El stylus no la abre. La burbuja no intercepta trazos, desaparece al volver a tocar
o mover la vista, y no modifica tinta ni transcripción. Las correcciones guardadas
por la versión anterior se conservan.

La revisión ortográfica tiene estado independiente del OCR. Una respuesta nula,
error o timeout de 5 segundos queda pendiente, no como «sin errores». Hay dos
reintentos automáticos espaciados (30/60 segundos más la pausa de escritura), con
un periodo de espera compartido si el servicio falla. Reabrir/editar permite otro
intento. La revisión de texto vigente no repite el OCR. Si no hay servicio de
corrección español, la búsqueda muestra el problema; no se inventan sugerencias.

La búsqueda global encuentra texto OCR sin distinguir mayúsculas ni tildes y abre
la página/lienzo y región correspondientes. El chat recibe la transcripción vigente
al enviar un mensaje, respetando el ajuste de contexto de la nota. Ese contenido
por turno no reinicia la conversación ni se guarda como un ancla adicional.

## Persistencia y límites

- Schema 28 agrega `canvas_ocr_pages`, sin modificar trazos existentes. Hacer respaldo
  antes de instalar una versión que migre la BD real.
- Los repositorios de trazos incrementan la revisión del bloque dentro de la misma
  transacción que cambia la tinta. Búsqueda y contexto solo leen revisiones vigentes;
  un resultado tardío no puede sobrescribir una revisión nueva ni revivir una nota borrada.
- La caché deriva de la tinta: el borrado de bloque/nota/carpeta la elimina mediante
  las cascadas de la app. Viaja en los respaldos completos de SQLite.
- Una cola procesa bloques con lecturas de 128 trazos, segmentación en isolate y
  reconocimiento por grupos de hasta 64 trazos. Los hashes reutilizan grupos sin cambios.
  Al volver a tocar el canvas o salir de primer plano, no comienza otro grupo;
  una llamada nativa que ya empezó puede terminar, pero su resultado se descarta si
  se interrumpió la tarea. Una edición puede requerir releer el bloque, aunque solo
  se vuelven a reconocer los grupos cuyo hash cambió.
- El máximo por bloque es 10 000 segmentos. La búsqueda devuelve hasta 200 coincidencias.
  La búsqueda dentro del documento cuenta ocurrencias individuales, hasta 1 000
  (muestra `+` al alcanzar ese límite), y reutiliza las páginas cargadas durante
  la búsqueda. Las búsquedas se agrupan con una pausa de 250 ms y se ejecutan en
  isolate; las respuestas de consultas anteriores se descartan.
  El contexto OCR por mensaje se limita a 12 000 caracteres y señala el truncamiento.
- Esta versión reconoce tinta vectorial; imágenes, PDFs, formas y resaltadores
  quedan fuera. El OCR matemático manual sigue siendo una ruta independiente.
- La agrupación espacial es heurística; columnas, diagramas, escritura rotada y
  fragmentos que cruzan lotes pueden requerir corrección o selección manual.
- Los subrayados pertenecen a una capa de pintura independiente, con geometría
  cacheada por página/revisión. Pan/zoom repintan esa capa sin recalcular OCR ni
  modificar la tinta. Al cambiar trazos se ocultan resultados desactualizados hasta
  completar la nueva revisión. Los avisos de una página no invalidan las demás.
- La cola vive mientras la app está abierta. Abrir un documento reanuda su indexación;
  no hay barrido de toda la biblioteca al arrancar ni servicio de fondo Android.

## Validación en dispositivo

Las pruebas headless cubren migración, revisiones, cascadas, caché, búsqueda,
historial de IA y panel en teléfono/tablet/horizontal con teclado. La precisión de
ML Kit, disponibilidad del corrector, latencia fría/caliente, memoria, batería y
fluidez con stylus necesitan medición en Android, especialmente con lienzos densos.

## Referencias de interacción

- [Goodnotes: subrayado y sugerencias al tocar con el dedo](https://support.goodnotes.com/hc/en-us/articles/14500614035471-Spellcheck-your-handwriting).
  YuLi toma el gesto informativo, no el reemplazo de escritura.
- [Chrome: búsqueda y resaltado dentro de una página](https://support.google.com/chrome/answer/95440?hl=EN).
- [Apple Notes: búsqueda dentro de una nota](https://support.apple.com/en-gb/guide/ipad/ipad64863a98/26/ipados/26).
