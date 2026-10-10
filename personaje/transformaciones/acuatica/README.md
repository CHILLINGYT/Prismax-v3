# MÓDULO: TRANSFORMACIÓN ACUÁTICA DEL PERSONAJE

Este proyecto es **el módulo de la transformación acuática**: el personaje 3D con
su locomoción terrestre y acuática, su sistema de agua, sus cuatro habilidades
acuáticas, su apuntado y su cámara.

Es un proyecto Godot **4.7** (Forward+) que se puede abrir y ejecutar tal cual, y
que está pensado para **integrarse después en el proyecto general del videojuego**.

---

## Por dónde empezar

| Documento | Para qué sirve |
| --- | --- |
| `docs/INTEGRATION_GUIDE.md` | **Cómo integrar el módulo** en otro proyecto: qué copiar, qué no, y qué revisar. |
| `docs/FILE_MAP.md` | Mapa archivo a archivo: qué es cada cosa y de qué depende. |
| `docs/CLEANUP_LOG.md` | Qué se eliminó en la limpieza y por qué, y qué se conservó por seguridad. |
| `docs/guia_personaje_3d.md` | Guía técnica completa del sistema (movimiento, animación, agua, habilidades). |

---

## Estructura

```
res://
├── aquatic_transformation/     EL MÓDULO (todo lo que hace al personaje acuático)
│   ├── character/              escena del jugador + movimiento, cámara, modelo, animación
│   ├── abilities/              las cuatro habilidades acuáticas + gestor de enfriamientos
│   ├── water/                  detección de agua, zona de agua, lago de prueba, shader
│   ├── vfx/                    efectos de agua, carga, vista subacuática y shaders
│   ├── ui/                     retícula de apuntado
│   ├── models/                 modelo final del personaje: escena Godot + texturas
│   ├── animations/             AnimationLibrary + AnimationTree finales
│   ├── scenes/                 ESCENA DE PRUEBA/DESARROLLO + maniquí de entrenamiento
│   └── docs/                   documentación
├── source_assets/              FBX/GLB/OBJ de origen (NO hacen falta para ejecutar)
├── tools/                      herramientas de desarrollo (horneado, retargeting, revisión)
├── tests/                      pruebas automáticas del sistema del personaje
└── project.godot
```

## Ejecutar

1. Abrir el proyecto con Godot 4.7.
2. Ejecutar (F5): se abre `aquatic_transformation/scenes/player_test.tscn`, la
   **escena de prueba/desarrollo** (suelo, plataformas, lago y tres maniquíes).
3. Controles: WASD moverse, ratón cámara, Espacio saltar, Shift correr/esprintar,
   Ctrl/C agacharse, clic izquierdo atacar (combo), clic derecho golpe cruzado,
   Q esquivar, **1-4 habilidades de agua**, **F apuntar con el balón de agua**,
   **E caminar sobre la superficie del agua**, y H/G/J/U/K/L son pruebas de daño.

## Pruebas

`res://tests/test_player_system.gd` contiene la batería de pruebas del sistema
(estructura, huesos, animaciones, agua, habilidades y combo).

---

> **Nota:** `addons/ziva_agent/` es la herramienta del asistente usada durante el
> desarrollo. **No forma parte del módulo**: se puede excluir al empaquetar el
> proyecto para entregarlo.