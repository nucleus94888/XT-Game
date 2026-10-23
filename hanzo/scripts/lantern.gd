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
	_light.light_energy = 2.2
	_light.omni_range = 11.0
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


func extinguish() -> void:
	if not lit:
		return
	lit = false
	_light.visible = false
	_lamp_mat.albedo_color = Color(0.25, 0.2, 0.15)
	Fx.damage_number(global_position + Vector3(0, 2.8, 0), 0, false, Color(0.6, 0.6, 0.7), "熄")


## 玩家是否在這盞燈的照明範圍內
func lights(pos: Vector3) -> bool:
	return lit and global_position.distance_to(pos) < 7.0
