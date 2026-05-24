# YuLi - Segundo Cerebro

![Flutter](https://img.shields.io/badge/Flutter-3.29-blue?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.7-0175C2?logo=dart)
![Plataforma](https://img.shields.io/badge/Plataforma-Android%20%7C%20iOS-lightgrey)
![Licencia](https://img.shields.io/badge/Licencia-MIT-green)
![Estado](https://img.shields.io/badge/Estado-En%20desarrollo-yellow)
![Offline First](https://img.shields.io/badge/Offline--First-Si-2ea44f)
![SQLite](https://img.shields.io/badge/Base%20de%20datos-SQLite-003b57)

YuLi es una aplicacion de organizacion personal que funciona como un segundo cerebro. Esta diseñada para capturar ideas, administrar tareas, tomar notas y gestionar proyectos, todo sin necesidad de conexion a internet ni registro de usuario. Tus datos siempre estan contigo, almacenados localmente en tu dispositivo.

## Tablero de control

La pantalla principal te da una vista general de tu productividad. Muestra la hora y fecha actual, estadisticas de tus tareas y proyectos, un campo para escribir tareas al instante, y accesos directos a cada seccion de la aplicacion.

## Fight - Captura rapida

Fight es tu bandeja de entrada para tareas. Escribe al vuelo con un limite de 280 caracteres, asigna categorias usando menciones con @, y organiza tu dia. Las tareas pendientes aparecen primero, las de ayer tienen un tratamiento especial, y las completadas se muestran con un tachado. Puedes deslizar a la derecha para completar una tarea o a la izquierda para rescatar las del dia anterior. Un toque prolongado envia una tarea directamente a tu tablero de proyectos.

## Flight - Notas con Markdown y LaTeX

Flight es tu cuaderno digital. Crea notas con formato enriquecido usando Markdown y ecuaciones matematicas con LaTeX. Agrega bloques de texto, dibujos, tablas, codigo y citas. La vista previa renderiza todo en vivo. Puedes exportar tus notas a PDF y compartirlas con quien quieras. Cada nota se guarda automaticamente y se organiza en carpetas con un color distintivo.

## Lab - Proyectos con Kanban

Lab te permite administrar proyectos usando tableros Kanban. Crea espacios de trabajo, agrega columnas y tarjetas, y mueve las tareas entre etapas con solo arrastrarlas. Cada tarjeta puede tener descripcion, prioridad, fecha limite y enlaces a notas de Flight. Los proyectos se conectan entre si para que nunca pierdas el hilo.

## Integracion entre modos

Lo que hace especial a YuLi es que todo esta conectado. Una tarea de Fight puede convertirse en tarjeta de Lab. Una nota de Flight puede vincularse a un tablero Kanban. Las carpetas de notas pueden asociarse a proyectos completos. Todo funciona como un ecosistema donde la informacion fluye sin esfuerzo.

## Diseno neobrutalista

La interfaz tiene un estilo distintivo sin bordes redondeados, con bordes negros marcados, sombras solidas y colores de acento por seccion: rojo para Fight, azul para Flight, verde para Lab y ocre para el tablero. Incluye modo oscuro que se adapta a la preferencia de tu sistema.

## Stack tecnologico

Construida con Flutter y Dart, utilizando Riverpod para el manejo de estado, Drift como ORM para SQLite, y con soporte nativo para Markdown y LaTeX. La aplicacion sigue una arquitectura limpia con separacion clara de capas, preparada para una futura migracion a servidor.

## Licencia

Este proyecto esta bajo la licencia MIT.
