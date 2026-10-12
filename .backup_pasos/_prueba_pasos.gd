extends Node

## PRUEBA EN VIVO del sistema de pisadas (carpeta temporal, no forma parte del juego).
##
## Instancia la escena REAL del jugador (res://personaje/base/escenas/leo_jugador.tscn)
## sobre un suelo plano, maneja la entrada por código siguiendo un guion y, por cada
## pisada emitida, mide:
##   - que el clip sea de locomoción de la tabla (nunca uno de salto/ataque/dash);
##   - que el jugador esté en el suelo;
##   - la fase de contacto emitida contra la de la tabla;
##   - la ALTURA REAL del tobillo en ese instante contra el mínimo de ese clip
##     (si el sonido coincide con el apoyo, la diferencia es ~0);
##   - que el mismo pie no repita antes de 0.25 s (sin duplicados en fundidos);
##   - la cadencia real de pasos contra la esperada (ciclo del clip / 2 / speed_scale).
## Y en la forma Combate cuenta los impactos reales contra los arranques del sonido
## de golpe (debe ser 1:1).

const ALTURA_SUELO := 220.0
const TOL_ALTURA := 0.02     # 2 cm: misma ventana de "pie apoyado" del relevamiento
const TOL_DUP := 0.25        # s mínimos entre dos pisadas del MISMO pie

# forma -> {ap: ruta del AnimationPlayer, clips: [...], esperado: {clip: s por paso}}
const CONFIG := {
	"humano": {
		"ap": "Humano/Animador",
		"clips": ["walk", "fast_run", "crouch_walk"],
		"esperado": {"walk": 0.5333, "fast_run": 0.2667, "crouch_walk": 0.5167},
	},
	"combate": {
		"ap": "Ataque/AnimadorAtaque",
		"clips": ["walk"],
		"esperado": {"walk": 0.1905},
	},
	"fuerza": {
		"ap": "Fuerza/AnimadorFuerza",
		"clips": ["Walk", "Run", "CrouchWalk", "RockCarryWalk"],
		"esperado": {"Walk": 0.7167, "Run": 0.3889, "CrouchWalk": 0.8333, "RockCarryWalk": 0.7167},
	},
	"velocista": {
		"ap": "Visual/Pose/Volteo/Modelo/AnimadorVelocista",
		"clips": ["caminar_hacia_adelante", "caminar_hacia_atras"],
		"esperado": {"caminar_hacia_adelante": 0.3333, "caminar_hacia_atras": 0.3167},
	},
}

var _jug: CharacterBody3D = null
var _pasos: PasosJugador = null
var _t := 0.0
var _minimos := {}            # "forma|clip|pie" -> altura mínima del tobillo del clip
var _apoyos := {}             # "forma" -> {ap: AnimationPlayer, sk: Skeleton3D, izq: int, der: int}
var _guanion_marcas := {}     # acciones puntuales ya disparadas
var _sueltas := []            # [accion, t_de_soltado]
var _pisadas_forma := {}      # forma -> Array de segundos (para cadencia)
var _pisadas_clip := {}       # "forma|clip" -> cantidad
var _pisadas_cadena := {}     # "forma|clip" -> Array de segundos
var _fallos := {
	"clip": 0, "suelo": 0, "dup": 0, "fase": 0, "altura": 0, "golpe": 0,
}
var _peor_fase := 0.0
var _peor_altura := 0.0
var _ultimo_pie := {}
var _impactos := 0
var _arranques := 0
var _arranques_pos := 0
var _arranques_playing := 0
var _pos_golpe_ant := -1.0
var _golpe_hecho_ant := false
var _golpe_son_ant := false
var _forma_actual := "humano"
var _fase_actual := ""

func _ready() -> void:
	# Suelo grande para que el personaje camine sin caerse.
	var piso := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(ALTURA_SUELO, 1.0, ALTURA_SUELO)
	col.shape = caja
	piso.add_child(col)
	piso.position = Vector3(0.0, -0.5, 0.0)
	add_child(piso)
	var esc: PackedScene = load("res://personaje/base/escenas/leo_jugador.tscn")
	_jug = esc.instantiate() as CharacterBody3D
	add_child(_jug)
	_jug.global_position = Vector3(0.0, 0.6, 0.0)
	_pasos = _jug.get_node_or_null("Pasos") as PasosJugador
	if _pasos == null:
		print("[prueba] FALLO: no existe el nodo Pasos")
		get_tree().quit()
		return
	_pasos.pisada.connect(_on_pisada)
	_pasos.golpe.connect(func() -> void: _arranques += 1)
	_medir_minimos()
	print("[prueba] mínimos medidos: %d pares (forma, clip, pie)" % _minimos.size())

# --- Medición de la altura mínima del tobillo de cada clip (igual método que el
# --- relevamiento: tobillo más bajo del ciclo, muestreado a 240 Hz). -------------
func _medir_minimos() -> void:
	for forma in CONFIG:
		var d: Dictionary = CONFIG[forma]
		var ap := _jug.get_node_or_null(String(d["ap"])) as AnimationPlayer
		if ap == null:
			print("[prueba] falta el AnimationPlayer de %s" % forma)
			continue
		var sk := _esqueleto_de(ap)
		if sk == null:
			continue
		var izq := _hueso(sk, "LeftFoot")
		var der := _hueso(sk, "RightFoot")
		_apoyos[forma] = {"ap": ap, "sk": sk, "izq": izq, "der": der}
		for buscado in d["clips"]:
			var nombre := _nombre_clip(ap, String(buscado))
			if nombre.is_empty():
				print("[prueba] %s: no existe el clip %s" % [forma, buscado])
				continue
			ap.play(nombre)
			ap.speed_scale = 1.0
			var largo := ap.get_animation(nombre).length
			var n := int(ceil(largo * 240.0))
			var mi := 1e9
			var md := 1e9
			for k in n:
				ap.seek(float(k) / 240.0, true)
				mi = minf(mi, sk.get_bone_global_pose(izq).origin.y)
				md = minf(md, sk.get_bone_global_pose(der).origin.y)
			var clave := "%s|%s" % [forma, buscado]
			_minimos[clave + "|izq"] = mi
			_minimos[clave + "|der"] = md
			print("   %-9s %-24s dura %.4f | izq min %.4f | der min %.4f" % [forma, buscado, largo, mi, md])

# --- Guion ---------------------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	_aplicar_sueltas()
	var entradas: Array = []
	_fase_actual = ""
	if _t < 1.0:
		_fase_actual = "quieto inicial"
	elif _t < 4.0:
		_fase_actual = "humano caminar"
		entradas = ["mover_adelante"]
	elif _t < 6.0:
		_fase_actual = "humano correr"
		entradas = ["mover_adelante", "correr"]
	elif _t < 7.5:
		_fase_actual = "humano quieto"
	elif _t < 9.5:
		_fase_actual = "humano salto"
		_puntual("salto", 7.6, "saltar", 0.08)
		if _t > 8.8:
			entradas = ["mover_adelante"]
	elif _t < 11.5:
		_fase_actual = "humano agachado"
		entradas = ["mover_adelante", "agacharse"]
	elif _t < 14.5:
		_fase_actual = "combate caminar + golpes"
		_cambiar("combate", "_entrar_combate")
		entradas = ["mover_adelante"]
		_puntual("g1", 12.2, "atacar", 0.08)
		_puntual("g2", 12.9, "atacar", 0.08)
		_puntual("g3", 13.6, "atacar", 0.08)
	elif _t < 17.5:
		_fase_actual = "fuerza caminar/correr"
		_cambiar("fuerza", "_entrar_fuerza")
		entradas = ["mover_adelante"]
		if _t > 16.0:
			entradas.append("correr")
	elif _t < 20.5:
		_fase_actual = "velocista caminar"
		_cambiar("velocista", "_entrar_velocista")
		entradas = ["mover_adelante"]
	elif _t < 21.5:
		_fase_actual = "velocista quieto"
	else:
		_resumen()
		get_tree().quit()
		return
	_fijar_entradas(entradas)
	_contar_golpe()

func _cambiar(forma: String, metodo: String) -> void:
	if _forma_actual == forma:
		return
	_forma_actual = forma
	_jug.call(metodo)

func _puntual(id: String, t: float, accion: String, dur: float) -> void:
	if _t < t or _guanion_marcas.has(id):
		return
	_guanion_marcas[id] = true
	Input.action_press(accion)
	_sueltas.append([accion, _t + dur])

func _aplicar_sueltas() -> void:
	var quedan: Array = []
	for s: Array in _sueltas:
		if _t >= float(s[1]):
			Input.action_release(String(s[0]))
		else:
			quedan.append(s)
	_sueltas = quedan

func _fijar_entradas(lista: Array) -> void:
	for a in ["mover_adelante", "mover_atras", "mover_izquierda", "mover_derecha", "correr", "agacharse"]:
		if lista.has(a):
			Input.action_press(a)
		else:
			Input.action_release(a)

# --- Medición de cada pisada ---------------------------------------------------
func _on_pisada(forma: String, clip: String, pie: String, u: float, _variante: int) -> void:
	var cfg: Dictionary = CONFIG.get(forma, {})
	if not (cfg.get("clips", []) as Array).has(clip):
		_fallos["clip"] += 1
	if not _jug.is_on_floor():
		_fallos["suelo"] += 1
	var esperado := float(PasosJugador.TABLA[forma][clip][pie])
	var df := absf(u - esperado)
	if df > 0.0001:
		_fallos["fase"] += 1
	_peor_fase = maxf(_peor_fase, df)
	var y := _altura_tobillo(forma, pie)
	var miny := float(_minimos.get("%s|%s|%s" % [forma, clip, pie], NAN))
	var dy := y - miny
	if is_nan(dy) or absf(dy) > TOL_ALTURA:
		_fallos["altura"] += 1
	if not is_nan(dy):
		_peor_altura = maxf(_peor_altura, absf(dy))
	var clave_pie := "%s|%s" % [forma, pie]
	if _ultimo_pie.has(clave_pie) and _t - float(_ultimo_pie[clave_pie]) < TOL_DUP:
		_fallos["dup"] += 1
	_ultimo_pie[clave_pie] = _t
	if not _pisadas_forma.has(forma):
		_pisadas_forma[forma] = []
	_pisadas_forma[forma].append(_t)
	var kc := "%s|%s" % [forma, clip]
	_pisadas_clip[kc] = int(_pisadas_clip.get(kc, 0)) + 1
	if not _pisadas_cadena.has(kc):
		_pisadas_cadena[kc] = []
	(_pisadas_cadena[kc] as Array).append(_t)
	print("[pisada] t=%6.3f  fase=%-24s  forma=%-9s clip=%-24s pie=%s  u=%.4f  tobillo=%.4f (min %.4f, dif %+.4f m)" % [
			_t, _fase_actual, forma, clip, pie, u, y, miny, dy])

func _altura_tobillo(forma: String, pie: String) -> float:
	if not _apoyos.has(forma):
		return NAN
	var a: Dictionary = _apoyos[forma]
	var sk := a["sk"] as Skeleton3D
	var idx := int(a["izq"]) if pie == "izq" else int(a["der"])
	if sk == null or idx < 0:
		return NAN
	return sk.get_bone_global_pose(idx).origin.y

# --- Sonido de golpe de combate: 1 arranque por impacto real -------------------
func _contar_golpe() -> void:
	var hecho := bool(_jug.get("c_golpe_hecho"))
	if hecho and not _golpe_hecho_ant:
		_impactos += 1
	_golpe_hecho_ant = hecho
	if _pasos == null:
		return
	var g := _pasos.get_node_or_null("GolpeCombate") as AudioStreamPlayer
	if g == null:
		return
	# Arranque REAL del sonido: la posición de reproducción vuelve al offset de
	# cabecera. Este conteo es informativo (depende del bloque de mezcla del audio);
	# el conteo exacto lo da la señal `golpe`, que se emite junto al play().
	var pos := g.get_playback_position()
	if g.playing and pos < _pos_golpe_ant - 0.005:
		_arranques_pos += 1
	_pos_golpe_ant = pos if g.playing else -1.0
	if g.playing and not _golpe_son_ant:
		_arranques_playing += 1
	_golpe_son_ant = g.playing

func _resumen() -> void:
	print("\n================ RESUMEN DE LA PRUEBA DE PISADAS ================")
	_fijar_entradas([])
	var total := 0
	for f in _pisadas_forma:
		total += (_pisadas_forma[f] as Array).size()
	print("pisadas emitidas: %d" % total)
	print("por forma/clip (cadencia medida contra la esperada del clip):")
	for k in _pisadas_clip:
		var partes := String(k).split("|")
		var forma_k := String(partes[0])
		var clip_k := String(partes[1])
		var esperado := float((CONFIG[forma_k]["esperado"] as Dictionary).get(clip_k, 0.0))
		var cad := _cadencia(k)
		var linea := "   %-42s %3d pisadas | cadencia media %.3f s | esperada %.3f s | forma/clip en la tabla: %s" % [
				String(k), int(_pisadas_clip[k]), cad, esperado,
				str((CONFIG[forma_k]["clips"] as Array).has(clip_k))]
		print(linea)
	print("fallos -> clip fuera de tabla: " + str(_fallos["clip"])
			+ " | pisada en el aire: " + str(_fallos["suelo"])
			+ " | duplicado <" + str(TOL_DUP) + " s: " + str(_fallos["dup"])
			+ " | fase distinta a la tabla: " + str(_fallos["fase"])
			+ " | tobillo lejos de su minimo: " + str(_fallos["altura"]))
	print("peor desvio de fase: %.5f | peor desvio de altura del tobillo: %+.4f m (tolerancia %.2f m)" % [
			_peor_fase, _peor_altura, TOL_ALTURA])
	print("combate: impactos reales %d | arranques del sonido de golpe %d %s" % [
			_impactos, _arranques, "OK" if _impactos == _arranques else "!! DESCUADRE"])
	print("combate: arranques contados por 'playing' %d y por salto de posicion %d (informativos: el mp3 tiene cola silenciosa y el audio se mezcla por bloques)" % [
			_arranques_playing, _arranques_pos])

func _cadencia(clave: String) -> float:
	var lista: Array = _pisadas_cadena.get(clave, [])
	if lista.size() < 3:
		return -1.0
	var deltas: Array = []
	for k in range(1, lista.size()):
		var d := float(lista[k]) - float(lista[k - 1])
		if d > 0.01:
			deltas.append(d)
	deltas.sort()
	return float(deltas[deltas.size() / 2])

# --- utilidades de esqueleto ---------------------------------------------------
func _esqueleto_de(ap: AnimationPlayer) -> Skeleton3D:
	var raiz := ap.get_node_or_null(ap.root_node)
	if raiz == null:
		raiz = ap.get_parent()
	var cola: Array = [raiz]
	while not cola.is_empty():
		var n: Node = cola.pop_front()
		if n is Skeleton3D:
			return n as Skeleton3D
		for h in n.get_children():
			cola.append(h)
	return null

func _hueso(sk: Skeleton3D, sufijo: String) -> int:
	for i in sk.get_bone_count():
		if String(sk.get_bone_name(i)).ends_with(sufijo):
			return i
	return -1

func _nombre_clip(ap: AnimationPlayer, buscado: String) -> String:
	for n in ap.get_animation_list():
		var s := String(n)
		if s == buscado or s.begins_with(buscado + "/"):
			return s
	return ""