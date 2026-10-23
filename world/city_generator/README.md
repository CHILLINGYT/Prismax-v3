# City Generator - Módulos

Refactorización de `generador_ciudad.gd` (3925 líneas) en módulos para trabajo en equipo.

## Módulos Fase 1 (Hecho)

- `city_constants.gd` - Constantes métricas
- `city_utils.gd` - Funciones puras, aabb 2700ms->16ms
- `city_scanner.gd` - Escaneo .gltf con optimización estado 2-3s->70ms
- `city_tracer.gd` - Trazado manzanas y parques
- `city_multimesh_manager.gd` - MultiMesh por sectores
- `city_generator_modular.gd` - Orquestador nuevo

## Beneficios

- Theo puede trabajar en peatones sin tocar el archivo gigante
- Uri en edificios
- Gian en calles/playa
- Sin conflictos de merge

## Próximas fases

- city_street_builder.gd
- city_block_builder.gd
- city_vegetation.gd
- city_beach.gd
