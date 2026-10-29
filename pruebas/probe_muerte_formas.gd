extends Node3D
## SONDA de la MUERTE en TODAS las formas (una instancia del jugador por forma).
## Mide, por forma, la altura REAL de la cadera durante el clip de muerte y en qué
## instante suenan el 4 (rodillas) y el 3 (golpe contra el suelo), para ver por qué
## el 4 se pierde en algunas transformaciones. No cambia nada: sólo mide.

const FORMAS: Array = [
	{"nodo": "P1", "id": &"", "nombre": "humano"},
	{"nodo": "P2", "id": &"velocista", "nombre": "velocista"},
	{"nodo": "P3", "id": &"pes", "nombre": "acuatico"},
	{"nodo": "P4", "id": &"tanque", "nombre": "fuerza"},
	{"nodo": "P5", "id": &"combate", "nombre": "combate"},
	{"nodo": "P6", "id": &"aguila", "nombre": "vuelo"},
]

var _t := 0.0
var _paso := 0
var _info: Dictionary = {}
var _t_muerte := -1.0
var _t_print := 0.0

func _ready() -> void:
	for f in FORMAS:
		var r := get_node_or_null(String(f["nodo"]))
		if r == null:
			print("[FORMAS] FALTA el nodo ", f["nodo"])
			continue
		var p: Array[AudioStreamPlayer] = []
		for n in ["AudioMuerte1", "AudioMuerte2", "AudioMuerte3", "AudioMuerte4"]:
			p.append(r.get_node_or_null(n) as AudioStreamPlayer)
		_info[String(f["nombre"])] = {
			"r": r, "id": f["id"], "p": p,
			"sonaba": [false, false, false, false],
			"veces": [0, 0, 0, 0],
			"alt_ini": -1.0, "alt_max": -99.0, "alt_4": -1.0, "alt_3": -1.0,
			"t_4": -1.0, "t_3": -1.0, "forma": -1,
		}
	print("[FORMAS] instancias listas: ", _info.keys())

func _physics_process(delta: float) -> void:
	_t += delta
	match _paso:
		0:
			if _t >= 0.3:
				_paso = 1
				for nombre in _info:
					var d: Dictionary = _info[nombre]
					if String(d["id"]) != "":
						(d["r"] as Node).call("_on_transformacion_elegida", d["id"])
		1:
			if _t >= 2.6:
				_paso = 2
				_t_muerte = _t
				var linea := PackedStringArray()
				for nombre in _info:
					var d: Dictionary = _info[nombre]
					d["forma"] = int((d["r"] as Node).get("forma"))
					d["alt_ini"] = _altura(d)
					(d["r"] as Node).get_node("Estadisticas").call("recibir_danio", 9999.0)
					linea.append("%s(forma=%d alt_ini=%.2f)" % [nombre, d["forma"], d["alt_ini"]])
				print("[FORMAS] mueren todas → ", " | ".join(linea))
		2:
			_muestrear()
			if _t - _t_print >= 0.4:
				_t_print = _t
				var linea := PackedStringArray()
				for nombre in _info:
					var d: Dictionary = _info[nombre]
					linea.append("%s %.2f" % [nombre, _altura(d)])
				print("[FORMAS t=%5.2f] alturas: %s" % [_t - _t_muerte, " | ".join(linea)])
			if _t - _t_muerte >= 7.0:
				_paso = 3
				_final()

func _muestrear() -> void:
	for nombre in _info:
		var d: Dictionary = _info[nombre]
		var p: Array = d["p"]
		var sonaba: Array = d["sonaba"]
		var veces: Array = d["veces"]
		var alt := _altura(d)
		if alt > float(d["alt_max"]):
			d["alt_max"] = alt
		for i in 4:
			var jugador := p[i] as AudioStreamPlayer
			if jugador == null:
				continue
			var suena := jugador.playing
			if suena and not bool(sonaba[i]):
				veces[i] = int(veces[i]) + 1
				if i == 3 and float(d["alt_4"]) < 0.0:
					d["alt_4"] = alt
					d["t_4"] = _t - _t_muerte
				if i == 2 and float(d["alt_3"]) < 0.0:
					d["alt_3"] = alt
					d["t_3"] = _t - _t_muerte
			sonaba[i] = suena

func _altura(d: Dictionary) -> float:
	return float((d["r"] as Node).call("_altura_cadera_muerte"))

func _final() -> void:
	print("[FORMAS] ===== RESUMEN (t desde la muerte) =====")
	for nombre in _info:
		var d: Dictionary = _info[nombre]
		print("[FORMAS] %-10s forma=%d hemi %s alt_ini=%5.2f alt_max=%5.2f | 1:%d 2:%d 3:%d(t=%.2f alt=%.2f) 4:%d(t=%.2f alt=%.2f)" % [
			nombre, int(d["forma"]), str((d["r"] as Node).get("_muerte_estado")),
			float(d["alt_ini"]), float(d["alt_max"]),
			int((d["veces"] as Array)[0]), int((d["veces"] as Array)[1]),
			int((d["veces"] as Array)[2]), float(d["t_3"]), float(d["alt_3"]),
			int((d["veces"] as Array)[3]), float(d["t_4"]), float(d["alt_4"]),
		])
	print("[FORMAS] FIN")