# PENDIENTES — YuLi

Cosas implementadas que faltan **verificar en dispositivo físico** (no se pueden probar en remoto). Cuando confirmes que algo funciona, bórralo de aquí.

---

## Verificación pendiente — fixes del 2026-05-30 (rama `fountainPen`)

### 1. Pluma fuente — que ya NO arrastre (cuaderno + pizarra)

**Qué se cambió:** el trazo activo ahora se pinta en su propia capa (`_ActiveStrokePainter` + `RepaintBoundary`) y los movimientos del puntero actualizan solo esa capa vía un `ValueNotifier` (`_activeTick`), sin `setState` del editor completo. Antes cada punto repintaba todo el canvas → latencia → el trazo se quedaba atrás de la punta.

**Cómo probar:**
- Abre un **cuaderno**, selecciona la **pluma fuente**, escribe rápido (palabras enlazadas, no solo trazos sueltos).
  - ✅ Esperado: la punta del trazo sigue al stylus **igual de pegada que con la pluma normal**. No debe "quedarse atrás" ni sentirse como si el grosor llegara con retraso.
  - Comparar A/B: dibuja lo mismo con pluma normal y con fuente; el seguimiento de la punta debe sentirse idéntico (solo cambia el grosor variable).
- Repetir lo mismo en una **pizarra** (sobre todo si ya tiene muchos trazos / imágenes encima — ahí era donde más se notaba el lag).
- Probar con trazos **largos** (toda una línea de escritura) — antes el lag crecía con el largo del trazo.
- Confirmar que al **soltar**, el trazo horneado queda exactamente donde estaba el trazo "mojado" (sin saltos ni que aparezca/desaparezca un frame).
- Confirmar que NO se rompió la pluma normal, el resaltador, ni el borrado por garabato (scribble-erase) en ambos editores.

**Si todavía arrastra:** revisar si el reprocesamiento por frame de la fuente (downsample→widths→chaikin→tessellate sobre todo el trazo crudo) sigue siendo el cuello de botella; ahí sí tocaría un guard de distancia mínima en la captura en vivo o cachear el centerline ya procesado.

---

### 2. Caja de tareas — resize por esquina y lateral (cuaderno + pizarra)

**Qué se cambió:** el bloque ahora tiene un campo `scale`. El contenido se maqueta a ancho `w/scale` y se escala uniforme con `FittedBox(fit: fitWidth)`. Se eliminó el viejo `_heightLocked` + `FittedBox.fill` (deformaba y nunca se activaba porque el lasso muta el bloque in-place).

**Cómo probar (con el lasso, bloque seleccionado):**
- **Resize por ESQUINA:**
  - ✅ Esperado: crece/encoge **uniforme** — la caja Y el **texto** escalan juntos (la letra se hace más grande/chica). Cambia ancho **y alto** a la vez. NO debe deformarse (texto estirado/aplastado).
  - ✅ Al **soltar** debe quedar exactamente como se veía durante el arrastre — **sin** deformarse y **sin** tener que "moverla un poco" para que tome forma.
- **Resize LATERAL derecho:**
  - ✅ Esperado: solo cambia el **ancho**, el texto **refluye** (se reacomoda) al mismo tamaño de letra. (Esto ya funcionaba; confirmar que sigue igual.)
- **Resize en vivo:**
  - ✅ Durante el arrastre por esquina se debe ver el cambio en tiempo real (la caja sigue al lasso). Durante el lateral la caja se queda quieta y salta al reflujo al soltar (comportamiento aceptado).
- Probar **encoger** hasta el mínimo (no debe bajar de ~220×90 px renderizados ni dejar el texto ilegible/cortado).
- **Rotar** + luego redimensionar: que siga coherente.
- **Cerrar y reabrir** el cuaderno/pizarra: el bloque debe conservar su tamaño/escala (se serializa `scale`). Bloques **viejos** (creados antes de este cambio) deben verse igual que antes (scale por defecto 1.0).
- Que el **bounding box del lasso** quede bien ajustado al bloque después de redimensionar (sin franja vacía arriba/abajo).

---

### 4. NUEVO FEATURE — Insertar figuras al canvas (cuaderno + pizarra)

**Qué se agregó:** botón **FIGURAS** en el toolbar (ícono `category`) que abre un popup con rect / óvalo / triángulo / línea / flecha. Al tocar una, se inserta en el centro del viewport como `DrawingStroke` con `isShape: true`, ya **seleccionada con el lasso** (handles visibles) y con el tool cambiado a lazo. Las cerradas respetan el toggle **RELLENO**. Reusa la geometría de `shape_recognizer.dart` (`buildShape`).

**Cómo probar:**
- Toolbar → **FIGURAS** → tocar cada figura. Para cada una:
  - ✅ Aparece centrada en lo que estás viendo, con tamaño razonable (≈constante en pantalla aunque tengas zoom in/out).
  - ✅ Queda **seleccionada con el lasso** al instante (se ven los handles) y puedes **moverla/redimensionarla/rotarla** sin tocar nada más.
  - ✅ Usa el **color y grosor** actuales del toolbar.
- Toggle **RELLENO** ON y luego inserta rect/óvalo/triángulo: deben salir **rellenas**; con RELLENO OFF, solo contorno. Línea y flecha siempre contorno.
- **Undo/redo:** tras insertar una figura, **deshacer** debe quitarla (y soltar la selección); **rehacer** la regresa. Confirmar que entra al historial como un solo paso.
- **Cuaderno:** insertar con el viewport sobre distintas páginas — la figura debe caer en la página correcta y, al moverla entre páginas con el lasso, reasignarse bien (igual que trazos/imágenes).
- **Persistencia:** cerrar y reabrir — las figuras siguen ahí (se serializan como trazos `isShape`).
- Probar que insertar figura **no rompe** el dibujo normal, el lazo de selección manual, ni el reconocimiento de figuras a mano alzada (hold-to-snap).

---

### 5. Redesign del toolbar (cuaderno + pizarra)

**Qué se cambió:**
- Botones **solo iconos** (sin texto) en la fila principal; **long-press = tooltip** con el nombre.
- Toolbar **full-width** (padding lateral fijo de 8px en vez del 8%/4% que dejaba huecos).
- Controles secundarios movidos a un **popup "⋯ Más"** (icono `more_horiz`): pizarra = zoom-lock, estabilizador, relleno, palma, fondo, encuadrar, borrar; cuaderno = estabilizador, relleno, palma, fondo. La fila principal queda: herramientas · insertar (imagen/tareas/figuras) · color+favoritos+grosor · undo/redo · [PG x/y solo cuaderno] · ⋯.

**Cómo probar:**
- ✅ La barra llega de borde a borde, sin huecos laterales.
- ✅ En tablet la fila principal cabe **sin scroll** (en pantallas angostas puede scrollear como fallback — verificar que no truene/overflow).
- ✅ **Long-press** en cualquier botón sin texto muestra su nombre (Lápiz, Pluma fuente, Resaltador, Borrador, Lazo, Imagen, Tareas, Figuras, Deshacer, Rehacer, Más).
- ✅ Botón **⋯ Más** abre el popup con los ajustes; toca fuera para cerrar. Verificar que el popup se vea bien (no deformado / no ocupando raro todo el ancho) y que los toggles (estabilizador cicla OFF/BAJO/MEDIO/ALTO, relleno, palma, zoom-lock) funcionen desde ahí.
- ✅ FONDO / ENCUADRAR / BORRAR desde el popup cierran "Más" y hacen su acción.
- ✅ Estabilizador: su nivel ahora se ve en el popup (texto "ESTAB · BAJO" etc.), ya no en la barra.
- ✅ Que abrir un popup (figuras/más/color/etc.) cierre los otros (no se enciman).

### 6. Colores favoritos — reemplazar en su lugar

**Qué se cambió:** al estrellar un color nuevo, si al **abrir** el color picker había un favorito **seleccionado** (== color actual), el nuevo color **reemplaza ese favorito en su posición exacta** (no expulsa al más viejo, no cambia de lugar). Si no había favorito seleccionado, sigue igual (push al frente, expulsa el más viejo si está llena).

**Cómo probar:**
- Llena los 5 favoritos. Selecciona uno (tócalo en la tira). Abre el picker, ajústalo a otro tono y estréllalo → ✅ el favorito seleccionado se reemplaza **en su misma posición**; los otros 4 NO se mueven ni se pierden.
- Sin ningún favorito seleccionado (color actual no es favorito), estrella uno nuevo con la cola llena → ✅ entra al frente y se va el más viejo (comportamiento previo).
- Estrella un color que **ya** es favorito → ✅ lo quita (toggle off), como antes.

### 3. Pizarra — indicador "BLOQUEAR PARA DIBUJAR" eliminado

**Qué se cambió:** se quitó el texto guía del centro del canvas.

**Cómo probar:**
- Crear una **pizarra nueva** y abrir una existente.
  - ✅ Esperado: ya **no** aparece el texto "BLOQUEAR PARA DIBUJAR · PINCH PARA ZOOM" en el centro.
- Confirmar que el botón de **ZOOM ON/OFF (candado)** del toolbar sigue funcionando normal (esa función no se tocó).
