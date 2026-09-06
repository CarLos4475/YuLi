# Respaldos y Google Drive

## Uso

En Ajustes → Almacenamiento → Respaldos y Google Drive:

- Conectar Google Drive usa la cuenta del usuario y el permiso `drive.file`.
- Respaldar ahora crea una copia completa nueva en `YuLi — Respaldos`. Las copias anteriores no se sobrescriben ni eliminan automáticamente.
- El respaldo automático es opcional y se intenta desde Inicio con la app abierta y activa, una vez transcurridas 24 horas desde el último respaldo confirmado de esa cuenta. Puede usar datos móviles. No es un trabajo de Android en segundo plano con la app cerrada.
- Exportar archivo crea un `.yuli` y abre Compartir. Hay que guardarlo fuera del espacio privado de la aplicación para conservarlo tras desinstalar.
- Restaurar archivo o Verificar y restaurar descarga/prepara una copia, verifica su contenido y muestra fecha y cantidades antes de pedir confirmación. Se aplica al siguiente arranque. No desinstalar para probar una restauración sobre datos reales.
- Las opciones de exportación de notas, pizarras y cuadernos permiten elegir Guardar en Google Drive. Esos PDF/PNG van a `YuLi — Apuntes`. Son exportaciones elegidas por el usuario; no se regeneran continuamente al editar.

La edición sincronizada entre tablets queda para la fase 2.

## PDF automáticos

La casilla **Actualizar mis PDF en Drive automáticamente** publica todos los apuntes activos en `Respaldo / Nombre de carpeta / Apunte.pdf`. Nota, pizarra y cuaderno se leen desde una transacción consistente; el cuaderno conserva una página PDF por página y la pizarra una por lienzo. Los PDF sirven para estudiar: el archivo `.yuli` sigue siendo el respaldo que permite recuperar datos editables.

El trabajo se inicia con YuLi abierta y activa, sin editores abiertos y después de 10 segundos sin interacción. Al salir de un editor se retoma automáticamente. No se ejecuta con la app cerrada ni durante una sesión larga dentro de un editor: el renderizador necesita Flutter. Se procesan bloques/páginas y lotes de trazos con puntos de interrupción; al tocar o abrir un editor se pausa antes del siguiente paso. Una operación gráfica individual ya iniciada no se puede cancelar instantáneamente.

Los cambios de la base de datos invalidan la revisión terminada. Al reiniciar se vuelve a reconciliar la biblioteca con Drive. Se compara una huella del contenido, trazos, tareas e imágenes para no regenerar PDF sin cambios. La cola es una reconciliación de datos guardados, no una lista volátil de eventos. Los fallos se reintentan después de dos minutos; un apunte que no se puede renderizar no bloquea los demás.

La identidad de biblioteca se incluye en los nuevos respaldos `.yuli`; la cuenta habilitada y los IDs remotos locales se excluyen. Restaurar desactiva la publicación automática. Cada archivo/carpeta usa propiedades privadas de Drive e IDs reservados persistidos antes de crear, de modo que un cierre o timeout no crea otra copia. Renombrar/mover actualiza nombre/padre del mismo archivo; una edición reemplaza su contenido mediante subida reanudable y comprobación de checksum. Los PDF de apuntes eliminados se conservan en Drive; esta publicación no borra archivos remotos ni replica ediciones hechas en Drive. Las exportaciones manuales antiguas permanecen en `YuLi — Apuntes`.

Referencia de API: [IDs reservados y reintentos sin duplicados](https://developers.google.com/workspace/drive/api/guides/manage-uploads), [actualización de archivos](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/update).

Validación adicional: `study_sync_test.dart`, `study_pdf_renderer_test.dart` y actualización de PDF por HTTP en `drive_backup_test.dart`. Confirmar en TGR la primera publicación, renombrar/mover, editar/reabrir, interrupción por interacción y funcionamiento sin red. Entregar APK **release** para verificar fluidez.

## Formato y recuperación

`BackupBundle` usa un formato binario versionado: identificador, longitud de manifiesto, JSON y archivos concatenados. La lectura y escritura de archivos son por bloques, con SHA-256 por archivo; no usa extracción ZIP ni ejecuta contenido del archivo.

La copia contiene SQLite obtenida con `VACUUM INTO`, `note_images`, `floating_pins`, `notebook_cameras` y una selección explícita de preferencias (incluye memoria/contexto de IA y preferencias de edición). Excluye almacenamiento seguro, tokens, logs, archivos temporales y el estado de conexión/automatización de Drive. No está cifrada con una contraseña adicional.

Antes del respaldo se esperan los guardados pendientes de los editores. La interfaz queda bloqueada durante la operación. Se comprueba el inventario y la existencia de adjuntos antes de dar la copia por válida. Drive debe confirmar tamaño y checksum antes de que un objeto pase de pendiente a completo; solo se listan copias completas.

La restauración valida hashes, estructura, conteos de tablas, integridad SQLite, adjuntos y esquema. Actualmente acepta únicamente la misma versión de esquema; al modificar el esquema debe ampliarse y probarse la compatibilidad de restauración. Reescribe referencias a imágenes al directorio del dispositivo de destino. Límite de contenido: 16 GB; manifiesto: 8 MB; preferencias: 32 MB. Crear/verificar un respaldo requiere espacio temporal adicional.

`restore_pending.json` se aplica antes de abrir SQLite, cargar preferencias en memoria o ejecutar expiry/GC. Las operaciones de renombrado pueden reanudarse tras una interrupción. Los archivos previos y sus preferencias se conservan en `backups/previous_<uuid>/`; la recuperación de esa carpeta es técnica, no hay todavía un selector de estados anteriores en la UI. Los errores de arranque dejan una pantalla de recuperación y no abren datos parcialmente restaurados. La conexión automática se desactiva al restaurar.

## Configuración

Proyecto: `yuli-507723`. Cliente OAuth web público en `GoogleBackupAuth.serverClientId`. Android debe estar registrado con paquete `com.carlos.yuli.yuli` y la huella del certificado usado para firmar la instalación. El cliente web se pasa como `serverClientId`; no se usa ni distribuye un secreto de cliente. Al publicar con otra firma se debe registrar su huella en Google.

## Validación

Pruebas: `backup_test.dart`, `drive_backup_test.dart`, `backup_export_options_test.dart`, además de `audit_test.dart`, `drawing_strokes_test.dart` y `notebook_raster_test.dart`.

Antes de dar por validada la integración real, probar en tablet Android: conectar una cuenta de prueba, subir un respaldo, comprobar ambas carpetas en Drive, exportar un PDF/PNG, descargar/restaurar en una instalación de prueba y verificar notas, imágenes, trazos y Lab. Probar también cancelar el acceso y perder la conexión durante una subida. Las pruebas HTTP usan un cliente simulado y no acreditan la configuración del proyecto en Google.

Security check:
- Data touched: Base de datos completa, adjuntos y preferencias seleccionadas; son datos privados del usuario.
- Auth required: Google Sign-In y consentimiento para `drive.file`; OAuth real pendiente de validar en tablet.
- Authorization enforced at: Google Drive limita el token a archivos autorizados para YuLi. Publicación automática opt-in por cuenta; cada petición comprueba la cuenta activa y la opción. Biblioteca e identidad se verifican antes de reutilizar un ID local.
- Secrets: Tokens gestionados por el SDK, usados en cabeceras; claves y tokens excluidos del paquete; solo el ID público del cliente está en código.
- Input validation: Rutas permitidas, tamaños limitados, hashes, conteos, esquema y adjuntos; rechazo de copias incompletas y de objetos SQL adicionales incompatibles.
- Output rendering: Exportadores existentes de PDF/PNG, snapshots guardados, memoria liberada por bloque/página y pausas por interacción; la importación no ejecuta código del paquete.
- Logs/errors: No se registran tokens, cabeceras ni respuestas HTTP; mensajes de operación genéricos y código de error OAuth sin descripción privada.
- DB/storage rules: Restauración antes de abrir SQLite y antes de GC; copia previa conservada; archivos de Drive sin permisos públicos añadidos.
- Dependencies: Plugin oficial `google_sign_in`; `crypto` y `sqlite3` ya estaban instalados transitivamente y ahora se declaran directamente.
- Rate limiting / abuse controls: Un documento a la vez, huella para omitir contenido idéntico, reintentos limitados y espera de dos minutos tras fallos. El respaldo completo mantiene su automatización diaria y límite de descarga.
- Web risks: URL de subida limitada a HTTPS en `www.googleapis.com/upload/drive/`; credenciales en cabeceras, nunca en enlaces compartidos.
- Prototype/security debt: Integración inicial; validar OAuth y recuperación en Android antes de depender de ella para datos irremplazables. Sin sincronización entre tablets ni ejecución con la app cerrada.
