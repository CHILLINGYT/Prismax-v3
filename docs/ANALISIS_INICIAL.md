# Análisis Prismax-v3 - Arena AI - 23/10/2026

## Resumen del proyecto
- **Engine:** Godot 4.7 (config_version=5)
- **Main Scene:** `res://ui/scenes/IntroVideo.tscn`
- **Tamaño repo:** 1.5GB / 2866 archivos (MUY grande para Godot)
- **Ramas:** main, Rama-Theo, rama-uri, rama-gian, backup/mi-trabajo
- **Ultimo commit:** 46c90f4 Merge PR #68 rama-uri

## Arquitectura detectada
### Jugador - ControladorLeo (personaje/base/scripts/controlador_leo.gd)
Sistema muy ambicioso: UN solo CharacterBody3D con 6 formas:
- `HUMANO` - caminar, correr, agachado, escalón 0.26m
- `VELOCISTA` - dash, caída-dash, carga, ejecución (reusa ziba/scripts/jugador.gd)
- `ACUATICO` - nado 4.6 m/s, nado rápido 9.2 m/s, flotabilidad, combate de 2 golpes
- `FUERZA` - (referenciado)
- `COMBATE`
- `VUELO` - águila con rig distinto, Death01

Tiene sistema de agua inteligente: usa `Relieve.profundidad_agua()` para calcular profundidad real del terreno, no valor fijo.
Profundidad vadeo 0.55m, nado 0.95m, superficie mar -2.05

### Mundo
- `generador_ciudad.gd` - 3925 líneas, 168KB. Generador procedural completo:
  - Escanea carpeta Exports/glTF (Godot)/
  - Clasifica modelos por firma geométrica
  - Trazado en cuadrícula: manzanas 24m + calles 12m + aceras 3m
  - Edificios modulares con familias de fachada coherentes
  - MultiMeshInstance3D para performance
  - Parques, vegetación, marcas viales
- `world/streaming/` - gestores de streaming para ciudad, bosque, mundo
- `world/terreno_isla.gd`, `relieve.gd`, `terreno3d.gd` - sistema de islas
- `Agua/Scenes/Ocean.tscn` - océano
- Addons: dialogue_manager, sky_3d, terrain_3d, Jolt Physics

### Misiones y UI
- `misiones/gestor_misiones.gd` - autoload Misiones
- `addons/dialogue_manager` - diálogos
- `ui/scenes/` - MainMenu, PauseMenu, DeathScreen, LoadingScreen, PanelMision, DialogueBalloon
- Autoloads de ajustes: gráficos, jugabilidad, controles, audio

### Transformaciones
- `personaje/transformaciones/acuatica/` - water_ability, water_prison, water_burst, water_surge, vfx
- `personaje/transformaciones/vuelo/` - flight controller, feather ability, talons, third_person_camera
- `personaje/transformaciones/velocidad/` - trazador, rayos
- `personaje/hud_transformacion/` - hud circular, minimapa, costos estamina

## PROBLEMAS CRÍTICOS DETECTADOS

1. **Repo gigante (1.5GB):** 
   - `.backup_*` carpetas (15 carpetas) commiteadas con FBX, PNG, capturas
   - `libterrain.windows.debug.x86_64.dll` (4.2MB) y `prismaxdemo.console.exe` (50KB) en root
   - `(2).gitattributes` duplicado
   - `.gitignore` solo ignora `.godot/`, `/android/`, `addons/ziva_agent/` - falta todo lo demás

2. **generador_ciudad.gd monolítico:** 3925 líneas en un solo archivo, difícil de mantener en equipo

3. **Falta estructura de equipo:** Ramas Rama-Theo, rama-uri, rama-gian sin PR template, sin CI

4. **No hay documentación técnica:** README.md solo dice "version jugable en modificacion"

## PLAN DE ACCIÓN PROPUESTO CON ARENA AI

### FASE 1 - Limpieza urgente (lo hago yo ahora)
- [ ] Crear rama `arena/cleanup`
- [ ] Nuevo .gitignore completo Godot 4
- [ ] Mover .backup_* a .gitignore y borrar del repo
- [ ] Mover DLL/EXE a Exports/ o ignorar
- [ ] Crear LFS para .fbx, .png grandes si hace falta

### FASE 2 - Refactor y performance
- [ ] Separar generador_ciudad.gd en módulos: CityScanner, CityTracer, BuildingBuilder, VegetationPlacer
- [ ] Optimizar ControladorLeo - está creciendo mucho (ya tiene constantes de agua, muerte, escalones, agachado)
- [ ] Implementar pooling para MultiMesh y streaming real

### FASE 3 - Desarrollo de gameplay (vos elegís)
Opciones:
A) Terminar forma VUELO (animaciones, colisiones)
B) Balancear VELOCISTA (dash, estamina)
C) Sistema de misiones completo con UI
D) Optimizar ciudad para que genere en <2s en runtime
E) Sistema de combate acuático vs enemigos

### FASE 4 - DevOps
- [ ] GitHub Actions: export automático Windows/Linux/Web
- [ ] Crear docs/ con GDD

## Cómo trabajar con Arena de ahora en más

1. **Yo trabajo en este workspace clonado:** Cada cambio que hagas acá lo pusheo a una rama nueva
2. **Vos me pedís features como si fuera un dev:** "Arena, hacé que el vuelo tenga turbo con Q" y yo edito los .gd y te muestro el diff
3. **Push directo:** Si me das un PAT (token) puedo pushear directo a tu repo. Si no, te paso un patch o ZIP

¿Con qué empezamos?
