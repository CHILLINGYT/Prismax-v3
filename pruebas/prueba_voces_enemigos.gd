extends Node3D
## PRUEBAS de las VOCES DE APARICIÓN de los enemigos (Tarea 4 de esta tanda:
## UNA SOLA VOZ POR APARICIÓN GRUPAL):
##  1. los archivos reales de res://Audio/enemigos se cargan;
##  2. un grupo de N enemigos creado de golpe suena UNA vez, no N: sólo el PRIMER
##     enemigo del grupo recibe el nodo de voz y los demás no reciben nada;
##  3. la voz es audio 3D pegado a un enemigo real del grupo (bus "Efectos");
##  4. pasada la ventana de grupo, una aparición nueva vuelve a sonar (grupo nuevo);
##  5. los enemigos creados seguidos por la API del panel/evento también son UN grupo;
##  6. una aparición FALLIDA no crea voz;
##  7. la tecla G (5 enemigos de dos tipos) suena UNA vez;
##  8. la rueda de grabaciones sigue sin repetir la misma dos veces seguidas.

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const GERENTE := "res://Enemigos Prueba/Scripts/gerente_enemigos_prueba.gd"
## Separación (s) entre grupos de prueba: mayor que VocesAparicion.VENTANA_GRUPO.
const SEPARACION_GRUPOS := 0.45

var _ok := 0
var _fallos := 0
var _gerente: Node3D

func _ready() -> void:
	_piso()
	# El gerente necesita un ControladorLeo en la escena (lo busca por tipo).
	var ps := load(JUGADOR) as PackedScene
	var jug := ps.instantiate() as Node3D
	jug.position = Vector3(0, 0.1, 0)
	add_child(jug)
	await get_tree().create_timer(0.6).timeout

	# --- 1. Archivos reales ------------------------------------------------
	var rutas := VocesAparicion.rutas_disponibles()
	_check(rutas.size() == 4, "se cargan las %d grabaciones reales de %s" % [rutas.size(), VocesAparicion.CARPETA])
	var todas_ok := true
	for r in rutas:
		var st := load(r) as AudioStream
		if st == null or st.get_length() <= 0.05:
			todas_ok = false
	_check(todas_ok, "todas las grabaciones cargan y duran > 0,05 s")
	_check(VocesAparicion.VENTANA_GRUPO > 0.0 and VocesAparicion.VENTANA_GRUPO < 1.0,
			"la ventana de grupo es un margen razonable (%.2f s)" % VocesAparicion.VENTANA_GRUPO)

	_gerente = load(GERENTE).new() as Node3D
	_gerente.name = "EnemigosPrueba"
	add_child(_gerente)
	await get_tree().create_timer(0.2).timeout

	# --- 2 y 3. Grupo de 3 cuerpo a cuerpo (mismo fotograma) = 1 voz --------
	VocesAparicion.reiniciar_rueda()
	_gerente.call("generar_tipo", 1)  # Tipo.MELEE
	await get_tree().physics_frame
	var creados: Array = _gerente.call("enemigos_vivos")
	_check(creados.size() == 3, "el grupo de prueba creó 3 enemigos (%d)" % creados.size())
	var con_voz := _voces_de(creados)
	_check(con_voz.size() == 1, "de los 3 enemigos del grupo, SÓLO 1 recibió voz (%d)" % con_voz.size())
	_check(VocesAparicion.grupos_anunciados() == 1,
			"se anunció 1 grupo de aparición (%d)" % VocesAparicion.grupos_anunciados())
	var primera := con_voz[0] if con_voz.size() == 1 else null
	var primero := creados[0] as Node3D
	_check(primera != null and primera.get_parent() == primero,
			"la voz la lleva el PRIMER enemigo del grupo (el que anuncia)")
	_check(primera != null and primera is AudioStreamPlayer3D, "la voz es AUDIO 3D (se oye venir del enemigo)")
	_check(primera != null and primera.bus == &"Efectos", "suena por el bus 'Efectos' (los ajustes mandan)")
	_check(primera != null and primera.volume_db <= -3.0 and primera.volume_db >= -12.0,
			"volumen moderado (%.1f dB)" % (primera.volume_db if primera != null else 0.0))
	_check(primera != null and primera.ya_sono(), "la voz del grupo quedó disparada UNA vez")
	await get_tree().create_timer(0.2).timeout
	var siguen_en_uno := true
	for v in con_voz:
		if v.veces_sonado() != 1:
			siguen_en_uno = false
	_check(siguen_en_uno, "la voz no se repite después (ni por _process ni por el retardo)")

	# --- 4. Pasada la ventana, aparición nueva = grupo nuevo ---------------
	var antes := VocesAparicion.grupos_anunciados()
	await get_tree().create_timer(SEPARACION_GRUPOS).timeout
	var e2 := _gerente.call("crear_enemigo_en", _jugador_pos() + Vector3(7.0, 0.0, 5.0), 1) as Node3D
	await get_tree().physics_frame
	_check(e2 != null, "una aparición suelta posterior sí se crea")
	_check(VocesAparicion.grupos_anunciados() == antes + 1,
			"la aparición posterior abre grupo NUEVO (%d -> %d)" % [antes, VocesAparicion.grupos_anunciados()])
	var v2 := (e2.get_node_or_null("VozAparicion") as VocesAparicion) if e2 != null else null
	_check(v2 != null and v2.ya_sono(), "y esa aparición sí suelta su voz")
	_retirar(e2)
	_gerente.call("retirar_grupo")
	await get_tree().create_timer(0.3).timeout

	# --- 5. El panel/evento que crea VARIOS de golpe = 1 voz ---------------
	VocesAparicion.reiniciar_rueda()
	var base := _jugador_pos()
	var lote: Array[Node3D] = []
	var recientes: Array[Node3D] = []
	# Tres llamadas seguidas SIN esperar entre ellas: así aparece un grupo de panel.
	for i in 3:
		var e := _gerente.call("crear_enemigo_en", base + Vector3(8.0 + float(i) * 2.5, 0.0, -6.0), 1) as Node3D
		if e != null:
			lote.append(e)
			recientes.append(e)
	await get_tree().physics_frame
	_check(lote.size() == 3, "el panel/evento creó 3 enemigos seguidos (%d)" % lote.size())
	_check(_voces_de(lote).size() == 1, "el lote del panel suena UNA vez (%d voces)" % _voces_de(lote).size())

	# --- 5b. Y con separación de ventana, cada aparición del panel suena ---
	await get_tree().create_timer(SEPARACION_GRUPOS).timeout
	var e4 := _gerente.call("crear_enemigo_en", base + Vector3(9.0, 0.0, -10.0), 1) as Node3D
	if e4 != null:
		recientes.append(e4)
	await get_tree().physics_frame
	_check(e4 != null and (e4.get_node_or_null("VozAparicion") as VocesAparicion) != null,
			"pasada la ventana, el panel vuelve a sonar")
	for e in recientes:
		if e != null and is_instance_valid(e):
			e.call("retirar")
	await get_tree().create_timer(0.4).timeout

	# --- 6. Aparición FALLIDA → sin voz ------------------------------------
	var voces_antes := _contar_voces()
	var malo: Variant = _gerente.call("crear_enemigo_en", Vector3(0.0, 900.0, 0.0), 1)
	await get_tree().physics_frame
	_check(malo == null, "una posición inválida NO crea enemigo (devuelve null)")
	_check(_contar_voces() == voces_antes, "una aparición fallida NO crea ninguna voz (%d voces)" % _contar_voces())

	# --- 7. La tecla G (5 enemigos, dos tipos) suena UNA vez ---------------
	VocesAparicion.reiniciar_rueda()
	await _pulsar_tecla(KEY_G)
	await get_tree().create_timer(0.3).timeout
	var con_g: Array = _gerente.call("enemigos_vivos")
	_check(con_g.size() == 5, "la tecla G creó sus 5 enemigos (%d)" % con_g.size())
	var voces_g := _voces_de(con_g)
	_check(voces_g.size() == 1, "los 5 enemigos de G suenan UNA vez (%d voces)" % voces_g.size())
	_check(VocesAparicion.grupos_anunciados() == 1,
			"G se contó como UN grupo (%d)" % VocesAparicion.grupos_anunciados())
	_check(voces_g.size() == 1 and voces_g[0].ya_sono(), "esa voz quedó disparada")

	# --- 8. La rueda sigue variando sin repetir la última ------------------
	var elegidas := PackedStringArray()
	if voces_g.size() == 1:
		elegidas.append(voces_g[0].archivo_actual())
	_gerente.call("retirar_grupo")
	await get_tree().create_timer(0.4).timeout
	for i in 3:
		var e := _gerente.call("crear_enemigo_en", base + Vector3(-8.0 - float(i) * 3.0, 0.0, 4.0), 1) as Node3D
		await get_tree().physics_frame
		var v := (e.get_node_or_null("VozAparicion") as VocesAparicion) if e != null else null
		if v != null:
			elegidas.append(v.archivo_actual())
		await get_tree().create_timer(SEPARACION_GRUPOS).timeout
	_check(elegidas.size() == 4, "4 grupos distintos eligieron grabación (%d/4)" % elegidas.size())
	var consecutivas := 0
	for i in range(1, elegidas.size()):
		if elegidas[i] == elegidas[i - 1]:
			consecutivas += 1
	_check(consecutivas == 0, "nunca sale la MISMA grabación dos veces seguidas (%d repetidas)" % consecutivas)
	var distintas := {}
	for r in elegidas:
		distintas[r.get_file()] = true
	_check(distintas.size() >= 2, "la rueda usa variedad de grabaciones (%d distintas)" % distintas.size())

	print("==================== VOCES: %d OK / %d FALLO ====================" % [_ok, _fallos])
	await get_tree().create_timer(0.6).timeout


# ------------------------------------------------------------------ auxiliares
## Nodos de voz REALES (instalados) de una lista de enemigos.
func _voces_de(enemigos: Array) -> Array[VocesAparicion]:
	var out: Array[VocesAparicion] = []
	for e in enemigos:
		if e == null or not is_instance_valid(e):
			continue
		for c in (e as Node).get_children():
			if c is VocesAparicion:
				out.append(c)
	return out


func _retirar(e: Node3D) -> void:
	if e != null and is_instance_valid(e) and e.has_method("retirar"):
		e.call("retirar")


func _jugador_pos() -> Vector3:
	var j: Node = get_tree().get_first_node_in_group(&"player")
	if j == null:
		for n in get_tree().root.find_children("*", "CharacterBody3D", true, false):
			if n is ControladorLeo:
				j = n
				break
	return (j as Node3D).global_position if j != null else Vector3.ZERO


func _contar_voces() -> int:
	var n := 0
	for nodo in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		if nodo is VocesAparicion:
			n += 1
	return n


func _pulsar_tecla(codigo: Key) -> void:
	var abajo := InputEventKey.new()
	abajo.physical_keycode = codigo
	abajo.pressed = true
	Input.parse_input_event(abajo)
	await get_tree().create_timer(0.09).timeout
	var arriba := InputEventKey.new()
	arriba.physical_keycode = codigo
	arriba.pressed = false
	Input.parse_input_event(arriba)
	await get_tree().create_timer(0.05).timeout


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[voces-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[voces-suite] FALLO ", texto)


func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Piso"
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(120, 1, 120)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.5, 0)
	add_child(cuerpo)
	var malla := MeshInstance3D.new()
	var caja_malla := BoxMesh.new()
	caja_malla.size = Vector3(120, 1, 120)
	malla.mesh = caja_malla
	cuerpo.add_child(malla)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 4.0, 14.0)
	cam.rotation = Vector3(-0.2, 0.0, 0.0)
	cam.current = true
	add_child(cam)