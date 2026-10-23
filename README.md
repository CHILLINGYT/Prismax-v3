# Prismax v3 - Godot 4.7.2

Juego de mundo abierto con sistema de transformaciones prismáticas. Un solo personaje (Leo) con 6 formas jugables.

## 🎮 Formas
- **HUMANO** - Exploración base, sigilo, agachado
- **VELOCISTA** - Dash, supervelocidad, trazadores
- **ACUATICO** - Nado 4.6m/s, nado rápido 9.2m/s, prisiones de agua
- **FUERZA** - Combate cuerpo a cuerpo, rocas, embestidas
- **COMBATE** - Forma de combate especializada
- **VUELO** - Águila, vuelo libre, garras, plumas

## 🌍 Mundo
- Generador procedural de ciudad (`generador_ciudad.gd`) - 6x6 manzanas, MultiMesh, parques
- Terreno isla 3D con `terrain_3d` addon
- Océano con sistema de profundidad real (`Relieve.profundidad_agua()`)
- Streaming de bosque/ciudad/mundo
- Sistema de farolas, bancos, vegetación, muelle

## 🧩 Sistemas
- **ControladorLeo** - Un solo CharacterBody3D para todas las formas
- **Misiones** - `misiones/gestor_misiones.gd` (autoload Misiones)
- **Diálogos** - `dialogue_manager` addon + DialogueBalloon
- **UI** - MainMenu, PauseMenu, DeathScreen, PanelMision, HUD circular
- **Ajustes** - Gráficos, Audio, Controles, Jugabilidad (autoloads)

## 🚀 Quick Start
1. Abrir con **Godot 4.7.2**
2. Main scene: `res://ui/scenes/IntroVideo.tscn`
3. Input: WASD mover, SPACE saltar, SHIFT dash/correr, F menú transformaciones, E interactuar, 1-4 habilidades agua

## 📁 Estructura
```
personaje/base/ - ControladorLeo + cámara + efectos
personaje/transformaciones/ - acuatica, vuelo, velocidad, fuerza
world/ - generador_ciudad, terreno_isla, streaming
ui/ - scenes + scripts
misiones/ - gestor_misiones
NPCs/ - peatones, obreros
Agua/ - Ocean
addons/ - dialogue_manager, terrain_3d, sky_3d
```

## 🔧 Ramas
- `main` - estable
- `Rama-Theo`, `rama-uri`, `rama-gian` - features de equipo
- `arena/cleanup` - limpieza de repo (Arena AI) - 800MB menos, nuevo .gitignore

## 🧹 Limpieza reciente (23/10/2026 - arena/cleanup)
- Eliminados .backup_* (15 carpetas, 900MB)
- Eliminados binarios .dll/.exe del root
- Nuevo .gitignore completo Godot 4
- Working tree: 2.6GB -> 1.8GB
- TODO: Git LFS para FBX >50MB + BFG para limpiar historia (1.5GB .git)

## 📝 TODO
- [ ] Migrar FBX grandes a Git LFS
- [ ] Separar generador_ciudad.gd (3925 líneas) en módulos
- [ ] Balanceo velocista + vuelo
- [ ] GitHub Actions export automático

## 👥 Equipo
CHILLINGYT / Prismax Team

## 📄 Licencia
License_Standard.txt
