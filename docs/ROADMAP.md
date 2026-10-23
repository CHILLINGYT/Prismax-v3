# Roadmap Prismax

## Fase 1 - Limpieza (Hecho - arena/cleanup)
- [x] .gitignore completo
- [x] Remover backups del tracking
- [x] README decente

## Fase 2 - Performance
- [ ] Separar generador_ciudad.gd en:
  - CityScanner (escanea Exports/glTF)
  - CityTracer (traza manzanas/calles)
  - BuildingBuilder (edificios modulares)
  - VegetationPlacer
- [ ] Pooling + LOD para peatones
- [ ] Optimizar ControladorLeo (demasiadas constantes)

## Fase 3 - Gameplay
- [ ] Vuelo: turbo con Q, aterrizaje suave
- [ ] Acuatico: combo 2 golpes + Marea Quebradefensas
- [ ] Fuerza: roca + slam + embestida
- [ ] Misiones: UI PanelMision conectado a gestor_misiones

## Fase 4 - DevOps
- [ ] Git LFS: git lfs track "*.fbx" "*.png" "*.glb"
- [ ] BFG Repo-Cleaner para bajar .git de 1.5GB a <300MB
- [ ] GitHub Actions: export Windows/Linux/Web
