# YuLi - Segundo Cerebro

![Flutter](https://img.shields.io/badge/Flutter-3.29-blue?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.7-0175C2?logo=dart)
![Plataforma](https://img.shields.io/badge/Plataforma-Android%20%7C%20iOS-lightgrey)
![Licencia](https://img.shields.io/badge/Licencia-MIT-green)
![Estado](https://img.shields.io/badge/Estado-En%20desarrollo-yellow)
![Offline First](https://img.shields.io/badge/Offline--First-Si-2ea44f)
![SQLite](https://img.shields.io/badge/Base%20de%20datos-SQLite-003b57)

YuLi es una aplicacion de organizacion personal que funciona como un segundo cerebro. Esta disenada para capturar ideas, administrar tareas, tomar notas y gestionar proyectos, todo sin necesidad de conexion a internet ni registro de usuario. Tus datos siempre estan contigo, almacenados localmente en tu dispositivo.

## Fight - Captura rapida

Fight es tu bandeja de entrada para tareas. Escribe al vuelo con un limite de 280 caracteres y asigna categorias usando menciones con @. Las tareas se organizan en tres secciones: **Pendientes**, **De Ayer** y **Completadas Hoy**.

- **Ciclo de vida**: Las tareas nuevas aparecen en Pendientes. Al dia siguiente pasan a De Ayer. Un dia despues se archivan y van a la papelera. Se borran definitivamente a los 7 dias.
- **Fecha limite**: Toca el reloj en una tarea para asignarle fecha y hora. Si tiene fecha limite, su ciclo de vida depende de esa fecha en vez de la fecha de creacion.
- **Gestos**: Desliza a la derecha para completar, a la izquierda para mandar a la papelera. Manten presionado para enviar la tarea a un tablero Kanban en Lab (con su fecha limite incluida).
- **Notificaciones**: Cuando una tarea se archiva automaticamente, aparece una notificacion en la campanita azul del encabezado.

## Flight - Notas con Markdown

Flight es tu cuaderno digital. Crea notas con formato enriquecido usando Markdown, con soporte para bloques de texto, dibujos, tablas, codigo y citas. La vista previa renderiza todo en vivo. Puedes exportar tus notas a PDF y compartirlas.

- Las notas se organizan en **carpetas** con color distintivo.
- Cada nota puede tener su **propio color** individual, independiente de la carpeta.
- Manten presionada una carpeta o nota para cambiar su nombre, color o eliminarla.

## Lab - Proyectos con Kanban

Lab te permite administrar proyectos usando tableros Kanban con arrastrar y soltar entre columnas.

- **Columnas por defecto**: Backlog, En Proceso, Entregado y **Vencido**.
- **Fecha limite**: Asigna fecha a una tarjeta y se movera automaticamente a la columna Vencido cuando expire.
- Manten presionado un espacio para cambiar su nombre, color o eliminarlo.

## Integracion entre modos

Todo esta conectado. Una tarea de Fight puede convertirse en tarjeta de Lab (con su fecha limite). Una nota de Flight puede vincularse a un tablero Kanban. Las carpetas de notas pueden asociarse a proyectos completos.

## Diseno neobrutalista

Sin bordes redondeados, con bordes negros marcados, sombras solidas y colores de acento por seccion: rojo para Fight, azul para Flight, verde para Lab y ocre para el tablero. Incluye modo oscuro que se adapta a la preferencia de tu sistema.

## Stack tecnologico

Construida con Flutter y Dart, utilizando Riverpod para el manejo de estado, Drift como ORM para SQLite. Arquitectura limpia con separacion clara de capas, preparada para una futura migracion a servidor. 100% offline-first.

## Licencia

Este proyecto esta bajo la licencia MIT.
