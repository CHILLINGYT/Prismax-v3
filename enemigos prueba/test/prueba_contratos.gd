extends SceneTree

## Pruebas headless del PUENTE DE DAÑO de los enemigos de prueba: además de su
## interfaz propia (take_hit / take_damage(cantidad)), cumplen los contratos que
## ya usan las habilidades del proyecto:
##   - grupo "damageable" + take_damage(cantidad, desde, empuje)   (fuerza)
##   - apply_damage(cantidad, desde, tipo) + trap()                (agua)
## y un proyectil de agua REAL hace daño al impactar (una sola vez).
##
## Ejecutar: godot --headless -s "res://enemigos prueba/test/prueba_contratos.gd"

const ENEMY_SCENE := "res://enemigos prueba/scenes/enemy.tscn"
const AGUA_PROYECTIL := "res://personaje/transformaciones/acuatica/abilities/water_projectile.gd"

var _fallos: int = 0


func _initialize() -> void:
	await _run()
	if _fallos == 0:
		print("=== RESULTADO: TODAS LAS PRUEBAS PASAN ===")
		quit(0)
	else:
		print("=== RESULTADO: ", _fallos, " FALLOS ===")
		quit(1)


func _check(condicion: bool, mensaje: String) -> void:
	if condicion:
		print("  PASA:  ", mensaje)
	else:
		_fallos += 1
		print("  FALLA: ", mensaje)


func _run() -> void:
	print("--- 0) Mundo y enemigo")
	var raiz := Node3D.new()
	get_root().add_child(raiz)
	var suelo := StaticBody3D.new()
	var forma := BoxShape3D.new()
	forma.size = Vector3(40, 1, 40)
	var cs := CollisionShape3D.new()
	cs.shape = forma
	suelo.add_child(cs)
	suelo.position = Vector3(0, -0.5, 0)
	raiz.add_child(suelo)

	var enemigo: CharacterBody3D = (load(ENEMY_SCENE) as PackedScene).instantiate()
	raiz.add_child(enemigo)
	enemigo.global_position = Vector3(0, 0.1, 0)
	await _esperar_frames(10)
	_check(enemigo.is_on_floor(), "el enemigo está sobre el suelo")

	print("--- 1) Contrato de fuerza: damageable + take_damage(cantidad, desde, empuje)")
	_check(enemigo.is_in_group("damageable"), "el enemigo está en el grupo damageable")
	var v0: float = enemigo.health
	enemigo.take_damage(10.0)
	_check(absf(enemigo.health - (v0 - 10.0)) < 0.01,
			"take_damage(10) de 1 argumento sigue funcionando (%.0f)" % enemigo.health)
	var desde: Vector3 = enemigo.global_position
	enemigo.take_damage(10.0, desde, Vector3(0, 0, 4.0))
	_check(absf(enemigo.health - (v0 - 20.0)) < 0.01,
			"take_damage(10, desde, empuje) aplica daño (%.0f)" % enemigo.health)
	_check(enemigo.velocity.z > 2.0, "y el empuje desplaza al enemigo (velocidad z=%.1f)" % enemigo.velocity.z)

	print("--- 2) Contrato de agua: apply_damage + trap + helpers")
	var antes_a: float = enemigo.health
	enemigo.apply_damage(12.0, desde + Vector3(0, 0, 2.0), &"light")
	_check(absf(enemigo.health - (antes_a - 12.0)) < 0.01,
			"apply_damage(...light) hace daño (%.0f)" % enemigo.health)
	enemigo.apply_damage(12.0, desde + Vector3(0, 0, 2.0), &"heavy")
	_check(absf(enemigo.health - (antes_a - 24.0)) < 0.01,
			"apply_damage(...heavy) hace daño (%.0f)" % enemigo.health)
	enemigo.trap(0.6)
	_check(enemigo.is_stunned(), "trap() deja atrapado/aturdido al enemigo")
	await _esperar_frames(50)
	_check(not enemigo.is_stunned(), "el aturdimiento de trap() expira solo")
	_check(absf(enemigo.get_hit_radius() - 0.5) < 0.01, "get_hit_radius() = 0.5")
	var centro: Vector3 = enemigo.get_hit_center()
	_check(absf(centro.y - (enemigo.global_position.y + 1.0)) < 0.05,
			"get_hit_center() es el centro del pecho")
	_check(not enemigo.is_defeated(), "is_defeated() es falso con vida")

	print("--- 3) FuerzaCombat (puñetazo/pisotón) alcanza al enemigo")
	var espacio := raiz.get_world_3d().direct_space_state
	var antes_f: float = enemigo.health
	# El puñetazo empuja DESDE el centro de la esfera: si el enemigo quedara
	# clavado en el centro, la dirección saldría vertical y el contrato anula el
	# empuje vertical (como en el juego real, donde nunca coinciden exactos).
	var centro_golpe: Vector3 = enemigo.global_position + Vector3(0.3, 0.05, 0.0)
	var alcanzados: Array = FuerzaCombat.golpear_esfera(espacio, centro_golpe, 0.7, 8.0, 6.0, [], 0.4, 0.3)
	_check(alcanzados.has(enemigo), "golpear_esfera encuentra al enemigo")
	_check(enemigo.health < antes_f and enemigo.health > antes_f - 8.1,
			"el puñetazo le quita 6-8 de vida (%.1f -> %.1f)" % [antes_f, enemigo.health])
	_check(enemigo.velocity.length() > 3.0, "y le aplica empuje (velocidad %.1f)" % enemigo.velocity.length())

	print("--- 4) Proyectil de agua REAL contra un enemigo")
	var enemigo2: CharacterBody3D = (load(ENEMY_SCENE) as PackedScene).instantiate()
	raiz.add_child(enemigo2)
	enemigo2.global_position = Vector3(14, 0.1, 11)
	await _esperar_frames(6)
	enemigo2.stun(4.0)
	var caster := Node3D.new()
	raiz.add_child(caster)
	caster.global_position = Vector3(14, 1.2, 14)
	var proyectil = (load(AGUA_PROYECTIL) as GDScript).new()
	proyectil.damage = 12.0
	proyectil.hit_radius = 0.55
	proyectil.speed = 18.0
	proyectil.lifetime = 2.5
	proyectil.knockback = 3.0
	proyectil.damage_kind = &"light"
	raiz.add_child(proyectil)
	proyectil.setup(caster, Vector3(14, 1.2, 14), Vector3(0, 0, -1))
	var impacto := false
	for i in 150:
		await physics_frame
		if enemigo2.health < 100.0:
			impacto = true
			break
	_check(impacto, "el proyectil de agua impacta y hace daño (%.0f de vida)" % enemigo2.health)
	_check(absf(enemigo2.health - 88.0) < 0.01,
			"el daño es exactamente el del proyectil (12; quedó en %.1f)" % enemigo2.health)
	await _esperar_frames(30)
	_check(absf(enemigo2.health - 88.0) < 0.01,
			"y no se aplica una segunda vez (quedó en %.1f)" % enemigo2.health)

	print("--- 5) Muerte: sale de los grupos y no recibe más daño")
	enemigo.take_hit(9999.0, Vector3.FORWARD, 0.0, 0.0)
	_check(enemigo.is_defeated(), "el enemigo con daño letal queda derrotado")
	_check(not enemigo.is_in_group("damageable"), "y sale del grupo damageable")
	_check(not enemigo.is_in_group("enemies"), "y del grupo enemies")
	var salud_final: float = enemigo.health
	enemigo.take_damage(50.0)
	_check(absf(enemigo.health - salud_final) < 0.01, "un enemigo muerto no vuelve a recibir daño")

	# Deja terminar el desvanecido de la muerte antes de desmontar el mundo.
	await _esperar_frames(45)
	raiz.queue_free()
	await _esperar_frames(2)


func _esperar_frames(n: int) -> void:
	for i in n:
		await physics_frame