# UI Module

A self-contained main-menu UI. The whole `res://ui/` folder can be copied into
another Godot 4 project as-is: paste it, open `res://ui/scenes/MainMenu.tscn`
and the interface (layout, video, logo, navigation) is ready to use.

## Structure

| Path | Purpose |
| --- | --- |
| `scenes/MainMenu.tscn` | The main menu (entry point for this UI). |
| `scenes/VideoBackground.tscn` | Full-screen looping background video. Swap the `stream` property to change the video. |
| `scenes/GameLogo.tscn` | Logo composition (prism mark + wordmark). Replace this whole scene with your real logo. |
| `scripts/main_menu.gd` | Menu navigation / routing logic. |
| `scripts/menu_option.gd` | A single option row (label + action + description). |
| `shaders/prism_logo.gdshader` | Placeholder prism logo mark (replaceable). |
| `video/video-fondo.ogv` | Background video (Ogg Theora). |

## Required project settings (not carried inside the folder)

Godot keeps input actions in `project.godot`, so these must exist in the target
project (Project Settings > Input Map):

- `menu_up` — Up arrow, W
- `menu_down` — Down arrow, S
- `menu_accept` — Enter, Keypad Enter, Space

Recommended display settings for the intended composition:

- Display > Window > Size > Viewport Width/Height: `1280 x 720`
- Display > Window > Stretch > Mode: `canvas_items`, Aspect: `expand`
- Optionally set Application > Run > Main Scene to `res://ui/scenes/MainMenu.tscn`

## Wiring into a game

`MainMenu` emits two signals so the host game can react without changing the UI:

- `continue_requested` — resume an existing save
- `new_game_requested` — start a fresh game

`continue_requested` and `new_game_requested` are stubs for now (no save system
or game scene exists yet); `QUIT` calls `get_tree().quit()`.

## Dependencies

None outside `res://ui/`. The UI uses Godot's default theme font; if custom
fonts are added later, place them in `res://ui/fonts/`.