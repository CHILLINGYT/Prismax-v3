# CREDITS — assets externos de PRISMAX

Solo se usan recursos de licencia libre. Cada fila dice qué archivo del proyecto
viene de dónde, con qué licencia y para qué se usa.

## Audio

| Archivos del proyecto | Fuente | Autor | Licencia | Uso |
|---|---|---|---|---|
| `assets/sfx_combat/kenney_impact/impactPunch_medium_000..004.ogg` | [Kenney — Impact Sounds 1.0](https://kenney.nl/assets/impact-sounds) | Kenney (www.kenney.nl) | CC0 1.0 | Puñetazo del jab (JuiceCombate, capa "puñetazo") |
| `assets/sfx_combat/kenney_impact/impactPunch_heavy_000..004.ogg` | Kenney — Impact Sounds 1.0 | Kenney | CC0 1.0 | Puñetazo de cros/gancho y capa grave del remate |
| `assets/sfx_combat/kenney_impact/impactSoft_heavy_000..004.ogg` | Kenney — Impact Sounds 1.0 | Kenney | CC0 1.0 | Golpe sordo de cuerpo en golpes pesados |

El texto de licencia original está junto a los archivos
(`assets/sfx_combat/kenney_impact/License_Kenney_ImpactSounds.txt`).

El **whoosh** de los golpes NO es un asset: se sintetiza por código en
`personaje/base/efectos/juice_combate.gd` (`_sintetizar_whoosh`).

## Interfaz

| Archivos del proyecto | Fuente | Autor | Licencia | Uso |
|---|---|---|---|---|
| `assets/ui/fuentes/Barlow-Medium.ttf`, `Barlow-SemiBold.ttf` | [Google Fonts — Barlow](https://fonts.google.com/specimen/Barlow) (repo `google/fonts`, `ofl/barlow`) | Jeremy Tribby / The Barlow Project Authors | SIL Open Font License 1.1 | Texto del HUD (tema `ui/tema/tema_juego.tres`) |
| `assets/ui/fuentes/BarlowCondensed-Bold.ttf`, `BarlowCondensed-ExtraBold.ttf` | [Google Fonts — Barlow Condensed](https://fonts.google.com/specimen/Barlow+Condensed) (`ofl/barlowcondensed`) | Jeremy Tribby / The Barlow Project Authors | SIL Open Font License 1.1 | Títulos, objetivo, contador de combo, keycaps |
| `assets/ui/kenney_input_prompts/keyboard_*.png`, `mouse_*.png` (variante "Double", 128 px) | [Kenney — Input Prompts](https://kenney.nl/assets/input-prompts) | Kenney (www.kenney.nl) | CC0 1.0 | Keycap de la tecla en los avisos de interacción |

Licencias originales junto a los archivos: `assets/ui/fuentes/OFL_Barlow.txt` y
`assets/ui/kenney_input_prompts/License_Kenney_InputPrompts.txt`.

`assets/ui/generadas/velo_lateral.png` NO es un asset externo: es un degradado
generado por código para el fondo del panel de misión.
