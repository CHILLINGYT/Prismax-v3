extends Node3D
## PRUEBAS de la integración del ARMAMENTO REAL (Tareas 1, 2 y 3):
##  T1  · el tirador lleva el AKM importado en el hueso de la mano derecha, con la
##        boca del cañón en el marcador que ya usaba (BocaArma) y apuntando al frente;
##      · la biblioteca de clips del enemigo NO ha cambiado (ninguna animación tocada);
##  T2  · el proyectil usa el cartucho real como malla, ESCALADO DE FORMA UNIFORME,
##        con su eje largo (+Y del modelo) sobre el -Z de vuelo del proyectil;
##      · el tamaño visible sigue el radio/escala_visual del proyectil;
##  T3  · el disparo real suena UNA vez por disparo, por el bus "Efectos", en un
##        AudioStreamPlayer3D pegado a la boca del arma, y sin duplicarse.
## Mide con el esqueleto REAL las alineaciones (no estima a ojo).

const TIRADOR := "res://enemigos/Scenes/enemigo_tirador.tscn"
const GERENTE := "res://enemigos/Scripts/gerente_enemigos_prueba.gd"
const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const LARGO_MODELO := 0.4482

var _ok := 0
var _fallos := 0
var _gerente: Node3D
var _jugador: Node3D

func _ready() -> void:
	_piso()
	var ps := load(JUGADOR) as PackedScene
	_jugador = ps.instantiate() as Node3D
	_jugador.position = Vector3(0, 0.1, 0)
	add_child(_jugador)
	await get_tree().create_timer(0.6).timeout

	# ---------- T1: arma real anclada a la mano derecha --------------------
	var e := (load(TIRADOR) as PackedScene).instantiate() as Node3D
	add_child(e)
	# Se deja ASENTAR la pose de reposo antes de medir: en los primeros fotogramas el
	# clip todavía está mezclándose desde la pose del FBX y el brazo apunta a otro lado.
	await get_tree().create_timer(0.8).timeout

	var anclaje := e.find_child("AnclajeArma", true, false) as BoneAttachment3D
	_check(anclaje != null, "T1 el tirador tiene el anclaje de arma por hueso")
	_check(anclaje != null and anclaje.bone_name == &"mixamorig_RightHand",
			"T1 el anclaje va al hueso de la mano derecha (%s)" % (anclaje.bone_name if anclaje != null else "—"))
	var arma := e.find_child("ArmaTirador", true, false) as Node3D
	_check(arma != null, "T1 hay arma anclada en la mano")
	_check(arma != null and arma.get_script() != null and arma.has_method("punto_de_boca"),
			"T1 el arma es la escena REAL (expone punto_de_boca)")
	var boca := (arma.get_node_or_null("BocaArma") as Node3D) if arma != null else null
	_check(boca != null, "T1 la boca del cañón conserva el nombre 'BocaArma' (lo que busca el tirador)")
	_check(arma != null and arma.find_child("Modelo", false, false) != null,
			"T1 el arma instancia el modelo importado (nodo Modelo)")
	var modelo := (arma.find_child("Modelo", false, false) as Node3D) if arma != null else null
	var mallas := 0
	if modelo != null:
		mallas = modelo.find_children("*", "MeshInstance3D", true, false).size()
	_check(mallas == 64, "T1 el modelo real trae sus 64 mallas (%d)" % mallas)

	# Medidas de alineación con el esqueleto real.
	var sk := e.find_child("Skeleton3D", true, false) as Skeleton3D
	var p_mano := _hueso(sk, "mixamorig_RightHand")
	var p_izq := _hueso(sk, "mixamorig_LeftHand")
	var p_agarre := arma.global_position if arma != null else Vector3.ZERO
	var p_boca := boca.global_position if boca != null else Vector3.ZERO
	var frente := -e.global_transform.basis.z
	_check(p_mano.distance_to(p_agarre) <= 0.14,
			"T1 la empuñadura cae EN la mano derecha (%.3f m de la muñeca)" % p_mano.distance_to(p_agarre))
	_check(absf(p_agarre.distance_to(p_boca) - 0.626) <= 0.03,
			"T1 de la empuñadura a la boca hay el largo real del arma (%.3f m)" % p_agarre.distance_to(p_boca))
	var dir_boca := (p_boca - p_agarre).normalized() if boca != null else Vector3.ZERO
	_check(dir_boca.dot(frente) >= 0.85,
			"T1 la boca apunta hacia el FRENTE del enemigo (dot %.2f)" % dir_boca.dot(frente))
	# Mano de apoyo: se MIDE y se informa; la animación existente decide si sujeta.
	var guarda := arma.to_global(Vector3(0.0, 0.093, -0.327)) if arma != null else Vector3.ZERO
	var d_apoyo := p_izq.distance_to(guarda)
	# La mano de apoyo es cosa de la ANIMACIÓN (no se toca), pero se MIDE: en el clip
	# de reposo el enemigo sujeta el arma con las dos manos, así que la izquierda debe
	# quedar cerca del guardamano.
	_check(d_apoyo <= 0.30, "T1 la mano de apoyo queda en el guardamano (%.3f m)" % d_apoyo)

	# Librería de clips intacta (no se tocó ninguna animación).
	var ap := e.get_node_or_null("Animador") as AnimationPlayer
	var claves := 0
	if ap != null:
		for n in ap.get_animation_list():
			if String(n) in ["idle_arma", "caminar_arma", "disparar", "recibir_arma"]:
				claves += 1
	_check(ap != null and ap.get_animation_list().size() == 14 and claves == 4,
			"T1 la librería de clips sigue con sus 14 clips y los 4 del arma (%d/%d)" % [
					ap.get_animation_list().size() if ap != null else -1, claves])

	# ---------- T2: cartucho real como malla del proyectil -----------------
	var proy := (load("res://enemigos/Scenes/proyectil_enemigo.tscn") as PackedScene).instantiate() as Node3D
	add_child(proy)
	await get_tree().physics_frame
	var municion := proy.get_node_or_null("Municion") as Node3D
	_check(municion != null, "T2 el proyectil lleva el cartucho real como malla")
	_check(municion != null and municion.get_parent() == proy,
			"T2 el cartucho cuelga de la raíz del proyectil (sin malla esférica de por medio)")
	var esc := municion.scale if municion != null else Vector3.ZERO
	_check(esc.x > 0.0 and absf(esc.x - esc.y) < 0.0001 and absf(esc.y - esc.z) < 0.0001,
			"T2 la escala del cartucho es UNIFORME (%.4f, %.4f, %.4f)" % [esc.x, esc.y, esc.z])
	var esperado := 0.14 * 2.0 * 1.0 / LARGO_MODELO
	_check(absf(esc.x - esperado) <= 0.001,
			"T2 conserva el tamaño visible de antes (largo %.3f m)" % (esc.x * LARGO_MODELO))
	var eje := (municion.global_transform.basis * Vector3.UP).normalized() if municion != null else Vector3.ZERO
	var avance := -proy.global_transform.basis.z
	# SIN valor absoluto: con abs() se aceptaba también el cartucho AL REVÉS (dot -1),
	# que es justo como volaba hasta la corrección de la orientación en el .tscn.
	_check(eje.dot(avance) >= 0.99,
			"T2 la punta del cartucho apunta en la dirección de vuelo (dot %.2f)" % eje.dot(avance))
	proy.set("escala_visual", 2.0)
	proy.call("_actualizar_malla")
	_check(absf(municion.scale.x - esperado * 2.0) <= 0.001,
			"T2 escala_visual sigue mandando en el tamaño (x2 = %.4f)" % municion.scale.x)
	proy.queue_free()

	# ---------- T3: sonido real del disparo --------------------------------
	var sonido := (arma.get_node_or_null("SonidoDisparo") as AudioStreamPlayer3D) if arma != null else null
	_check(sonido != null, "T3 el arma trae su AudioStreamPlayer3D")
	_check(sonido != null and sonido.stream != null and absf(sonido.stream.get_length() - 2.216) <= 0.02,
			"T3 el stream es el disparo real (%.3f s)" % (sonido.stream.get_length() if sonido != null and sonido.stream != null else -1.0))
	_check(sonido != null and sonido.bus == &"Efectos", "T3 suena por el bus 'Efectos'")
	_check(boca != null and sonido != null and sonido.global_position.distance_to(boca.global_position) < 0.02,
			"T3 el reproductor está EN la boca del arma (posicional, se oye venir de ahí)")
	var antes := int(arma.call("veces_disparado")) if arma != null else -1
	arma.call("disparar_efectos")
	arma.call("disparar_efectos")   # segundo intento inmediato: NO debe contar
	var despues := int(arma.call("veces_disparado"))
	_check(despues == antes + 1, "T3 dos peticiones seguidas = UNA reproducción (%d -> %d)" % [antes, despues])
	_check(sonido != null and sonido.playing, "T3 el sonido quedó sonando tras el disparo")

	# ---------- T3 (real): el disparo del tirador pide los efectos ---------
	_gerente = load(GERENTE).new() as Node3D
	_gerente.name = "EnemigosPrueba"
	add_child(_gerente)
	await get_tree().create_timer(0.2).timeout
	var centro := _jugador.global_position
	var t := _gerente.call("crear_enemigo_en", centro + Vector3(0.0, 0.0, -10.0), 2) as Node3D
	_check(t != null, "T3 se creó un tirador real a 10 m del jugador")
	# OJO: cada tirador lleva SU PROPIA arma; el contador que importa es el del arma
	# que lleva ESTE tirador en la mano (el de arriba es otro enemigo).
	var arma_t := (t.find_child("ArmaTirador", true, false) as Node3D) if t != null else null
	_check(arma_t != null and arma_t.has_method("veces_disparado"), "T3 el tirador de prueba lleva el arma real")
	var en_primera := int(arma.call("veces_disparado"))
	var disparos_antes := int(arma_t.call("veces_disparado")) if arma_t != null else -1
	var t0 := Time.get_ticks_msec()
	var disparo_visto := false
	var proyectil_visto := false
	while Time.get_ticks_msec() - t0 < 7000:
		await get_tree().process_frame
		if _proyectiles() > 0:
			proyectil_visto = true
		if t != null and not is_instance_valid(t):
			break
		if arma_t != null and is_instance_valid(arma_t) \
				and int(arma_t.call("veces_disparado")) > disparos_antes:
			disparo_visto = true
			break
	_check(disparo_visto, "T3 un disparo REAL del tirador produce exactamente un efecto de sonido")
	_check(proyectil_visto, "T3 ese mismo disparo lanzó su proyectil (cartucho real)")
	_check(int(arma.call("veces_disparado")) == en_primera,
			"T3 el arma del OTRO enemigo no sonó (cada disparo suena donde se dispara)")
	var son_t := (arma_t.get_node_or_null("SonidoDisparo") as AudioStreamPlayer3D) if arma_t != null else null
	_check(son_t != null and son_t.playing, "T3 en ese momento su audio estaba sonando (posicional, en la boca)")
	_check(son_t != null and son_t.pitch_scale >= 0.96 and son_t.pitch_scale <= 1.05,
			"T3 el tono queda dentro de la variación leve (%.3f)" % (son_t.pitch_scale if son_t != null else 1.0))

	print("==================== ARMAS AK: %d OK / %d FALLO ====================" % [_ok, _fallos])
	await get_tree().create_timer(0.5).timeout


## Proyectiles VIVOS en la escena, estén colgados de donde estén: el tirador los
## añade al PADRE del enemigo, que dentro del gerente es el propio gerente.
func _proyectiles() -> int:
	var n := 0
	for p in get_tree().root.find_children("*", "Node3D", true, false):
		if p is ProyectilEnemigo:
			n += 1
	return n


func _hueso(sk: Skeleton3D, nombre: String) -> Vector3:
	if sk == null:
		return Vector3.ZERO
	for b in sk.get_bone_count():
		if String(sk.get_bone_name(b)) == nombre:
			return sk.global_transform * sk.get_bone_global_pose(b).origin
	return Vector3.ZERO


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[armas-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[armas-suite] FALLO ", texto)


func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja_col := BoxShape3D.new()
	caja_col.size = Vector3(80, 0.5, 80)
	forma.shape = caja_col
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.25, 0)
	add_child(cuerpo)
	var malla := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = Vector3(80, 0.5, 80)
	malla.mesh = caja
	malla.position = Vector3(0, -0.25, 0)
	add_child(malla)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.0, 6.0)
	cam.current = true
	add_child(cam)