## leo_enums.gd - Fase 3 - Enums extraídos de controlador_leo.gd
## Parte de la modularización para reducir 6066 líneas

class_name LeoEnums

enum Forma { HUMANO, VELOCISTA, ACUATICO, FUERZA, COMBATE, VUELO }
enum Estado { NORMAL, DASH, CAIDA_DASH, CARGA, PREPARADO, EJECUCION }
enum Muerte { VIVO, CAYENDO, MUERTO, RESPAWN }

## Estados de combate FreeFlow (forma COMBATE)
enum C_Estado { LIBRE, ACERCAR, VIENTO, ACTIVO, RECUPERACION, CONTRA, ESQUIVA, GOLPEADO, MUERTO }
