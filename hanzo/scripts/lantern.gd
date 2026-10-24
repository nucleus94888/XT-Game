extends Node3D
class_name Lantern
## 燈籠：照亮一圈。被手裡劍打到會熄滅，附近變暗，敵人視野縮短。

var lit := true
var _light: OmniLight3D
var _lamp_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("lanterns")
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 2.2, 0.18)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.25, 0.2, 0.15)
	post.mesh = bm
	post.material_override = pmat
	post.position = Vector3(0, 1.1, 0)
	add_child(post)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_mat.albedo_color = Color(1.0, 0.8, 0.5)
	lamp.mesh = sm
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(0, 2.35, 0)
	add_child(lamp)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.78, 0.5)
	_light.light_energy = 2.4
	# 照射範圍收到和判定差不多（以前畫面亮 11 公尺、判定只算 7 公尺，玩家看到光但其實算暗）
	_light.omni_range = 8.0
	_light.omni_attenuation = 0.7
	_light.position = Vector3(0, 2.4, 0)
	add_child(_light)
	# 手裡劍判定區
	var area := Area3D.new()
	area.collision_layer = 16
	area.collision_mask = 0
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.5
	cs.shape = sh
	cs.position = Vector3(0, 2.35, 0)
	area.add_child(cs)
	add_child(area)


## 熄燈的代價（第十次議會）：附近 12 公尺的守衛會起疑、走過來查看；
## 有守衛站在燈旁 2.5 公尺內超過 2 秒就重新點亮。回報是一段暗路，以及「把守衛引過來」。
const LIGHT_RADIUS := 6.5
const RELIGHT_RANGE := 2.5
const RELIGHT_TIME := 2.0
var _relight_t := 0.0


func extinguish() -> void:
	if not lit:
		return
	lit = false
	_light.visible = false
	_lamp_mat.albedo_color = Color(0.25, 0.2, 0.15)
	get_tree().call_group("enemies", "hear_noise", global_position, 12.0)


func relight() -> void:
	if lit:
		return
	lit = true
	_light.visible = true
	_lamp_mat.albedo_color = Color(1.0, 0.8, 0.5)
	_relight_t = 0.0


func _physics_process(delta: float) -> void:
	if lit:
		return
	var near := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and e.get("state") != null and e.state != e.State.DEAD and e.state != e.State.ALERT and e.state != e.State.ATTACK:
			var d: Vector3 = (e as Node3D).global_position - global_position
			d.y = 0.0
			if d.length() < RELIGHT_RANGE:
				near = true
				break
	_relight_t = _relight_t + delta if near else 0.0
	if _relight_t >= RELIGHT_TIME:
		relight()


## 玩家是否在這盞燈的照明範圍內（和畫面上明顯被照亮的範圍一致）
func lights(pos: Vector3) -> bool:
	return lit and global_position.distance_to(pos) < LIGHT_RADIUS
