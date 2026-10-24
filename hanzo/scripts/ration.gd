extends Node3D
class_name Ration
## 忍者口糧：敵人倒下時機率掉落，半藏走過去撿起回血。

const HEAL := 35

var _t := 0.0
var _taken := false


func _ready() -> void:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 1.0, 0.8)
	mat.emission_energy_multiplier = 0.35
	ball.mesh = sm
	ball.material_override = mat
	ball.position = Vector3(0, 0.4, 0)
	add_child(ball)
	var band := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.1, 0.16)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.15, 0.35, 0.2)
	band.mesh = bm
	band.material_override = bmat
	band.position = Vector3(0, 0.34, 0.1)
	add_child(band)
	var light := OmniLight3D.new()
	light.light_color = Color(0.8, 1.0, 0.7)
	light.light_energy = 0.6
	light.omni_range = 2.5
	light.position = Vector3(0, 0.6, 0)
	add_child(light)

	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.9
	cs.shape = sh
	cs.position = Vector3(0, 0.5, 0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body)
	scale = Vector3(0.2, 0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	rotation.y += delta * 1.5
	position.y = 0.1 + sin(_t * 3.0) * 0.08


func _on_body(b: Node3D) -> void:
	if _taken or not b.is_in_group("player") or not b.has_method("heal"):
		return
	_taken = true
	# 不跳字：回血→血條閃綠；帶著→持有物欄位彈一下（player 那邊處理）
	b.heal(HEAL)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.15)
	tw.tween_callback(queue_free)
