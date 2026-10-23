# Contribuir a Prismax

## Flujo de trabajo
1. Crear rama desde main: `git checkout -b rama-nombre-feature`
2. No commitear .backup_*, .godot/, *.dll, *.exe
3. Probar en Godot 4.7.2
4. PR a main

## Estructura de commits
- feat: nueva feature
- fix: bug
- cleanup: limpieza
- perf: performance

## Backups
Nunca commitear carpetas .backup_* o _backup_*. Usar .gitignore. Si necesitas guardar algo, usa branches.

## Archivos grandes
FBX >50MB deben ir por Git LFS:
```
git lfs install
git lfs track "*.fbx"
git lfs track "*.png"
```

## Test
Escenas en _tests/ para probar sistemas aislados.
