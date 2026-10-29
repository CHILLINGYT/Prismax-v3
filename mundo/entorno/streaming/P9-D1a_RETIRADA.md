# P9-D1a — Streaming visual de sectores de ciudad · GUÍA DE PRUEBA Y RETIRADA

> Prototipo **aislado** y **desactivado por defecto**. NO está integrado en la escena
> principal (`ziba_prototipo.tscn`) ni en ningún autoload. No modifica ningún archivo
> preexistente: son **solo archivos nuevos**.

## Qué es

Un gestor (`GestorStreamingCiudad`) que descarga y reconstruye **exactamente** los
nodos visuales `S_x_y` de `Ciudad/CiudadGenerada/Sectores` (MultiMesh de "piezas"
agrupadas por sector de 42 m) según la distancia al jugador. Estrategia de datos:
**captura-al-descargar** (no toca la generación ni el RNG).

Alcance deliberadamente acotado: **SOLO** sectores visuales. NO toca colisiones,
Terrain3D, peatones, minimapa ni los MultiMesh globales (vegetación, macetas,
ventanas, marcas).

## Archivos creados por esta fase (5)

| # | Ruta | md5 |
|---|------|-----|
| 1 | `world/streaming/gestor_streaming_ciudad.gd` | `026e1f0a5c5ea4ab0d37a13f55064180` |
| 2 | `world/streaming/gestor_streaming_ciudad.gd.uid` | `b81ff2d9476ff9f8029f408816bc076a` |
| 3 | `pruebas/streaming_ciudad_test.gd` | `55bee6ec22734cf0992aa871e56e8805` |
| 4 | `pruebas/streaming_ciudad_test.gd.uid` | `5aa57299dd80b36a73a890a675db840b` |
| 5 | `pruebas/streaming_ciudad_test.tscn` | `f39fb0437bc4ecf1ae2fa3724fec2db9` |

> `world/streaming/` TAMBIÉN contiene los archivos del prototipo previo P9-B del
> bosque (`gestor_streaming_bosque.gd` + `.uid`). **No borres toda la carpeta**:
> borra solo `gestor_streaming_ciudad.gd` y su `.uid`.

## Cómo probarlo SIN activarlo en el juego habitual

En una terminal, desde la carpeta del proyecto:

```bash
XDG_DATA_HOME=/tmp/prismax_p9d1/xdg \
  /home/micro/Descargas/Godot_v4.7.2-stable_linux.x86_64 --headless --path . \
  res://pruebas/streaming_ciudad_test.tscn
```

- Usa un directorio de usuario aislado (`XDG_DATA_HOME`) → **no toca tus preferencias**.
- Semilla fija 20250901 → ciudad determinista (64 sectores / 16642 instancias).
- Resultado esperado: `===== RESULTADO STREAMING CIUDAD: 26 OK, 0 FALLOS =====`, salida 0.
- Aviso esperado y **ajeno a este prototipo**: "8 ObjectDB instances were leaked at
  exit" proviene del generador de ciudad (confirmado con una corrida solo-ciudad).

## Cómo desactivarlo (sin borrar nada)

- El gestor tiene `activo = false` por defecto → no hace nada.
- Para detenerlo en caliente (si estuviera activo): poner `activo = false` en el nodo
  `Gestor`, o llamar a `restaurar_todo()` para reconstruir todos los sectores.

---

## A. RETIRADA MANUAL (sin Git, con Explorador de archivos)

1. **Cierra Godot** (para que no reimporte mientras borras).
2. Abre la carpeta del proyecto.
3. Borra **exactamente** estos 5 archivos:
   - `world/streaming/gestor_streaming_ciudad.gd`
   - `world/streaming/gestor_streaming_ciudad.gd.uid`
   - `pruebas/streaming_ciudad_test.gd`
   - `pruebas/streaming_ciudad_test.gd.uid`
   - `pruebas/streaming_ciudad_test.tscn`
   - (este mismo archivo, `world/streaming/P9-D1a_RETIRADA.md`, si ya no lo quieres)
4. **NO borres** `world/streaming/gestor_streaming_bosque.gd` ni su `.uid` (son de P9-B),
   ni ningún otro archivo.
5. Comprueba que no queda nada:
   - Busca en el proyecto el texto `GestorStreamingCiudad` y `streaming_ciudad`:
     no debe aparecer en ningún archivo.
   - Abre el juego normal: debe funcionar exactamente igual que antes.
6. Si Godot avisa de un `.uid` huérfano en la reimportación, es inofensivo; el
   proyecto sigue válido. (Opcional: Godot > Proyecto > Herramientas > Reimportar.)
7. Conservas intactos tus 8 archivos modificados, el resto de archivos sin seguimiento
   y todas tus preferencias: esta fase no los tocó.

## B. RETIRADA MEDIANTE GIT (segura, solo los archivos nuevos)

Estos 5 archivos son **sin seguimiento** (`??`), **exclusivos** de este prototipo y
**nadie más los referencia**. Se pueden borrar con confianza.

Antes de borrar, **confirma** que cada ruta es realmente de este prototipo:

```bash
cd /home/micro/hola/Prismax-v3
git status --porcelain --untracked-files=all | grep -E 'gestor_streaming_ciudad|streaming_ciudad_test'
```

Debe listar exactamente los 5 archivos de la tabla de arriba. Si aparece cualquier otra
cosa, **detente** y revísalo a mano.

Borrado (excluye explícitamente el bosque de P9-B):

```bash
rm -f world/streaming/gestor_streaming_ciudad.gd
rm -f world/streaming/gestor_streaming_ciudad.gd.uid
rm -f pruebas/streaming_ciudad_test.gd
rm -f pruebas/streaming_ciudad_test.gd.uid
rm -f pruebas/streaming_ciudad_test.tscn
rm -f world/streaming/P9-D1a_RETIRADA.md   # opcional
```

> **NO** uses `git clean -f`, `git reset --hard` ni borrados globales: eliminarían
> también los otros archivos sin seguimiento (P7/P8, P9-B, capturas, etc.).

Comprobación final:

```bash
git status --porcelain --untracked-files=all | grep -E 'streaming_ciudad|gestor_streaming_ciudad' \
  && echo "QUEDA ALGO" || echo "P9-D1a retirado limpiamente"
```

---

## Estado de Git registrado (para comparar)

- Rama: `backup/mi-trabajo` · HEAD: `104c798037b1b5884c1320e875766a953ac47c86`
- 8 archivos modificados preexistentes (NO tocados por esta fase):
  `enemigos/Scripts/proyectil_enemigo.gd`, `npcs/Scripts/director_peatones.gd`,
  `pruebas/auditoria_rendimiento/arnes_auditoria.gd`, `generador_ciudad.gd`,
  `ui/scenes/MainMenu.tscn`, `ui/scripts/ajustes_graficos.gd`,
  `ui/scripts/main_menu.gd`, `ui/scripts/menu_option.gd`.
- Preferencias reales (NO tocadas): `ajustes_graficos.cfg` md5
  `3f2ad3952e188d1cded3bcb0e3765ceb`.
- Sin `commit`, `push`, `reset`, `clean` ni operaciones destructivas.