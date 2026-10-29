# pruebas/

Pruebas automáticas del juego. Cada prueba es una ESCENA que imprime líneas
`OK` / `FALLO` y un resumen `N OK / M FALLO`. Se ejecutan sin ventana:

    godot --headless --path . res://pruebas/<prueba>.tscn

- Raíz: pruebas del jugador, combate, casa, mundo, audio, UI, etc.
- `enemigos/`: esqueletos, animaciones y arma de los enemigos.
- `ziba/`: carga del mundo, pausa y rayos.
- `capturas/`: imágenes que generan algunas pruebas (se regeneran al correrlas).
- `_linea_base_auditoria.txt`: resultado de referencia de la auditoría.

Importante: algunas pruebas escriben `user://ajustes_*.cfg`. Para no tocar tus
ajustes reales, ejecutalas con un `user://` aislado (variable APPDATA propia).
