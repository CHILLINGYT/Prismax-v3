# P10-B2 — Opciones compartidas entre menús + corrección del panel de ajustes

> Dos cambios: (1) la opción "Optimización agresiva del mundo" ya existe en AMBOS
> menús (principal y de pausa) con una sola preferencia; (2) se corrigió la
> maquetación del panel negro de ajustes. **Sigue desactivada por defecto.**

## A. Ajustes compartidos
La preferencia vive SOLO en el autoload `AjustesGraficos` (P10-B). Ambos menús leen y
escriben ahí; no hay gestores ni preferencias duplicadas.
- Menú principal → AJUSTES → GRÁFICOS: filas OPTIMIZACIÓN / CARGA / PRECARGA / DIAGNÓSTICO.
- En partida → ESC → CONFIGURACIÓN → GRÁFICOS: mismas opciones (con barras).
- Al abrir cualquiera de los dos, refleja el valor guardado. Cambiar en uno se ve en
  el otro y se guarda en `user://ajustes_graficos.cfg`.
- Con la opción OFF, los controles dependientes se ocultan y el mundo no se descarga.

## B. Corrección visual del panel
- **Causa:** en el menú de pausa, las filas del panel GRÁFICOS sumaban un ancho mínimo
  (hasta 498 px) MAYOR que el ancho útil del panel (386 px), así que el contenedor
  `ConfigContent` se salía ~21 px por cada lado del panel negro.
- **Correcciones:** etiquetas con ajuste de línea (`autowrap_mode = 2`), anchos de
  valores y barras reducidos, y el contenido del menú de pausa dentro de un
  `ScrollContainer` (para que, al activar la optimización, el contenido adicional
  haga scroll en vez de desbordar).
- Resultado: el contenido queda dentro del panel (591..977, panel 556..1012), con
  márgenes de 35 px, alineado y sin solaparse con el título.

## Archivos
**Nuevos (solo pruebas, en `pruebas/`):** `captura_pausa.gd/.tscn`,
`captura_menu.gd/.tscn`, `medir_layout.gd/.tscn` (más sus `.uid`).

**Modificados:**
- `ui/scripts/menu_option.gd` (enum Action: +OPTIMIZACION, +DIST_CARGA, +DIST_PRECARGA, +DIAGNOSTICO).
- `ui/scripts/main_menu.gd` (filas nuevas, navegación por filas visibles, flechas).
- `ui/scenes/MainMenu.tscn` (filas nuevas en la sección GRÁFICOS).
- `ui/scripts/pause_menu.gd` (ya tenía P10-B; sin cambios nuevos en P10-B2).
- `ui/scenes/PauseMenu.tscn` (autowrap de etiquetas, anchos reducidos, ScrollContainer).

> ⚠️ Ninguno de estos archivos estaba limpio en Git antes de P10-B2: `menu_option.gd`,
> `main_menu.gd`, `MainMenu.tscn` forman parte de los 8 modificados PREEXISTENTES, y
> `pause_menu.gd`/`PauseMenu.tscn` ya los tocó P10-B. **No los revviertas con `git
> checkout`** (perderías trabajo previo): retíralos a mano.

## Retirada MANUAL (solo P10-B2)
1. `ui/scripts/menu_option.gd`: en el enum `Action`, quita `OPTIMIZACION, DIST_CARGA,
   DIST_PRECARGA, DIAGNOSTICO`.
2. `ui/scenes/MainMenu.tscn`: borra los nodos `OptimizacionOption`, `CargaOption`,
   `PrecargaOption`, `DiagnosticoOption` (y sus `Label`) de `SeccionGraficos`.
3. `ui/scripts/main_menu.gd`: borra los casos nuevos de `_activate`, la sección
   "P10-B2: opciones de streaming" completa (`_actualizar_optimizacion`,
   `_poner_texto_fila`, `_indices_navegables`, `_primer_navegable`, `_ajustar_valor`),
   la llamada a `_actualizar_optimizacion()`, las ramas `ui_left`/`ui_right` de
   `_unhandled_input`, y vuelve a `_selected = 0` en `_toggle_categoria`.
4. `ui/scenes/PauseMenu.tscn`: borra `autowrap_mode = 2` de las etiquetas (o déjalas,
   no hace daño), repón los `custom_minimum_size` de las barras (130→200) y valores
   (90→150), y deshaz el `ScrollContainer` (vuelve a poner `ConfigContent` como hijo
   directo de `ConfigPanel` con sus anclas originales; renombra de nuevo las rutas de
   padre de sus descendientes).

## Nota de seguridad
`AjustesGraficos` es ahora quien GOBIERNA `GestorStreamingMundo` (P10-B): al arrancar,
aplica la preferencia guardada al nodo del mundo. Por eso, para activar el streaming
hay que usar el MENÚ (o dejar la preferencia guardada); activar el nodo a mano en el
editor no basta: el autoload lo pondrá al valor de la preferencia.