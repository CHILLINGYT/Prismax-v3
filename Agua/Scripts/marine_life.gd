class_name MarineLife
extends Node3D

## Gentle life animation for everything in the water: boats and buoys bob on the
## surface, fish circle inside their school, kelp and shore algae sway with the
## current.
##
## Purely visual: every fish keeps the school node it was placed under as its
## orbit center, so the scene stays hand-editable -- move a school in the editor
## and its fish swim around the new spot. Per-fish variation comes from the node
## name, so the scene file needs no extra data.

const BOB_Y: float = 0.075
const BOB_TILT: float = 0.028
const KELP_SWAY: float = 0.085
const ALGAE_SWAY: float = 0.05
const FISH_BOB: float = 0.3

var _time: float = 0.0
var _boats: Array[Node3D] = []
var _boat_home: Array[Vector3] = []
var _fish: Array[Node3D] = []
var _plants: Array[Node3D] = []
var _plant_amp: Array[float] = []


func _ready() -> void:
	for n in get_tree().get_nodes_in_group("marine_boat"):
		var b: Node3D = n as Node3D
		if b != null:
			_boats.append(b)
			_boat_home.append(b.position)
	for n in get_tree().get_nodes_in_group("marine_fish"):
		var f: Node3D = n as Node3D
		if f != null:
			_fish.append(f)
	for n in get_tree().get_nodes_in_group("marine_kelp"):
		var k: Node3D = n as Node3D
		if k != null:
			_plants.append(k)
			_plant_amp.append(KELP_SWAY)
	for n in get_tree().get_nodes_in_group("marine_algae"):
		var a: Node3D = n as Node3D
		if a != null:
			_plants.append(a)
			_plant_amp.append(ALGAE_SWAY)


func _process(p_delta: float) -> void:
	_time += p_delta
	_boat_phase()
	_fish_phase()
	_plant_phase()


func _boat_phase() -> void:
	for i in _boats.size():
		var b: Node3D = _boats[i]
		var home: Vector3 = _boat_home[i]
		var ph: float = _seed(b.name) * TAU
		b.position = Vector3(home.x, home.y + sin(_time * 1.05 + ph) * BOB_Y, home.z)
		b.rotation.z = sin(_time * 0.85 + ph) * BOB_TILT
		b.rotation.x = cos(_time * 1.15 + ph) * BOB_TILT * 0.7


func _fish_phase() -> void:
	for f in _fish:
		var school: Node3D = f.get_parent() as Node3D
		if school == null:
			continue
		var count: int = max(1, school.get_child_count())
		var hs: float = _seed(f.name)
		var radius: float = 2.4 + hs * 1.8
		var speed: float = 0.30 + hs * 0.28
		var dir: float = 1.0 if hs > 0.5 else -1.0
		var ang: float = _time * speed * dir + float(f.get_index()) / float(count) * TAU + hs * 1.2
		var center: Vector3 = school.global_position
		f.global_position = Vector3(
			center.x + cos(ang) * radius,
			center.y + sin(ang * 2.0 + hs * 3.0) * FISH_BOB,
			center.z + sin(ang) * radius)
		var vx: float = -sin(ang) * dir
		var vz: float = cos(ang) * dir
		f.rotation.y = atan2(-vz, vx)


func _plant_phase() -> void:
	for i in _plants.size():
		var k: Node3D = _plants[i]
		var amp: float = _plant_amp[i]
		var ph: float = _seed(k.name) * TAU
		k.rotation.z = sin(_time * 0.75 + ph) * amp
		k.rotation.x = cos(_time * 0.60 + ph) * amp * 0.7


## Stable 0..1 value derived from a node name.
func _seed(p_name: StringName) -> float:
	return float(absi(String(p_name).hash()) % 997) / 997.0
