extends Node3D

## Escena de VERIFICACIÓN EN VIVO del combate de la partida (no forma parte del
## juego). Monta el jugador real, el gestor del encuentro y dos enemigos de
## prueba sobre suelo plano, y transforma al jugador por la secuencia
## Combate -> Agua -> Velocista para capturar cada sistema con clics reales.
##
## Secuencia: t=0.5 s forma Combate | t=4.5 s forma Agua | t=7.0 s Velocista |
## t=9.5 s forma Tanque (fuerza). La vida del personaje se sube para que las
## capturas largas no terminen en derrota (los enemigos atacan de verdad).

@onready var jugador: CharacterBody3D = $Jugador


func _ready() -> void:
	jugador.estadisticas.vida = 100000.0
	await get_tree().create_timer(0.5).timeout
	jugador._on_transformacion_elegida(&"combate")
	await get_tree().create_timer(4.0).timeout
	jugador._on_transformacion_elegida(&"pes")
	await get_tree().create_timer(2.5).timeout
	jugador._on_transformacion_elegida(&"velocista")
	await get_tree().create_timer(2.5).timeout
	jugador._on_transformacion_elegida(&"tanque")