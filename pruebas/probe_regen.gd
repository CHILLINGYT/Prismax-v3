extends Node3D

# SONDA temporal: regeneración de estamina del HUMANO recién instanciado
# (el caso que falló en la suite C: 30.0 → 29.5 tras esperar espera+0.5 s).

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

func _ready() -> void:
	call_deferred("_go")

func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _go() -> void:
	var suelo := StaticBody3D.new()
	var forma_s := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(300.0, 1.0, 300.0)
	forma_s.shape = caja
	suelo.add_child(forma_s)
	suelo.position = Vector3(0.0, -0.5, 0.0)
	add_child(suelo)
	var jug := JUGADOR.instantiate() as ControladorLeo
	jug.position = Vector3(0.0, 0.1, 0.0)
	add_child(jug)
	await _esperar(30)
	var st := jug.get_node("Estadisticas") as EstadisticasJugador
	print("espera=%.2f vel_regen=%.2f factor_inactivo=%.2f" % [
			st.espera_regen_estamina, st.velocidad_regen_estamina, st.factor_inactivo])
	var e := st._estados[&"humano"] as Dictionary
	e["stamina"] = 40.0
	e["t_desde_gasto"] = 0.0
	st._sincronizar_activa()
	st.probar_gasto(10.0, &"prueba")
	print("tras probar_gasto: stamina=%.2f t_gasto=%.2f forma=%s" % [
			float(e["stamina"]), float(e["t_desde_gasto"]), st.forma_actual()])
	for i in 14:
		await _esperar(9)  # 0.15 s
		print("  t=%.2f stam=%.3f t_gasto=%.2f t_dano=%.2f v=%.2f forma=%d muerto=%s regen=%s" % [
				(i + 1) * 0.15, float(e["stamina"]), float(e["t_desde_gasto"]),
				float(e["t_desde_dano"]),
				Vector2(jug.velocity.x, jug.velocity.z).length(),
				int(jug.forma), bool(e["muerto"]), st._regenerando])
	print("FIN SONDA REGEN")