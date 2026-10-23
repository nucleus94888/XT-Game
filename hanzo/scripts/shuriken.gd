extends Node3D
class_name Shuriken
## 手裡劍：直線飛行並旋轉。命中敵人造成小傷害與體幹，打斷弓兵拉弓；
## 命中牆／地面製造聲響（引開守衛）；命中燈籠使其熄滅。

var dir := Vector3.FORWARD
var speed := 24.0
var dmg := 8
var src: Node = null

var _life := 1.6
var _done := false
var _spin: MeshInstance3D


func launch(from: Vector3, to_dir: Vector3) -> void:
	global_position = from
	dir = to_dir.normalized()
	look_at(from + dir, Vector3.UP)


func _ready() -> void:
	_spin = MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 四芒星（平面）
	for i in range(4):
		var a0 := i * PI / 2.0
		var a1 := a0 + PI / 4.0
		var a2 := a0 + PI / 2.0
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0) * 0.22, 0.0, sin(a0) * 0.22))
		st.add_vertex(Vector3(cos(a1) * 0.08, 0.0, sin(a1) * 0.08))
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a1) * 0.08, 0.0, sin(a1) * 0.08))
		st.add_vertex(Vector3(cos(a2) * 0.22, 0.0, sin(a2) * 0.22))
	_spin.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.85, 0.95)
	mat.metallic = 0.9
	mat.roughness = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spin.material_override = mat
	_spin.rotation.x = PI / 2.0
	add_child(_spin)

	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1 | 4 | 16
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.25
	cs.shape = sh
	area.add_child(cs)
	add_child(area)
	area.area_entered.connect(_on_area)
	area.body_entered.connect(_on_body)


func _physics_process(delta: float) -> void:
	global_position += dir * speed * delta
	_spin.rotation.z += delta * 30.0
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _finish() -> void:
	_done = true
	queue_free()


func _on_area(a: Area3D) -> void:
	if _done:
		return
	var t := a.get_parent()
	if t == null or t == src:
		return
	if t.is_in_group("lanterns") and t.has_method("extinguish"):
		t.extinguish()
		Feel.shake(0.15)
		_finish()
	elif t.is_in_group("enemies") and t.has_method("take_hit"):
		t.take_hit({"dmg": dmg, "dir": dir, "kb": 1.0, "heavy": false, "pos": global_position, "src": src, "shuriken": true})
		_finish()


func _on_body(b: Node3D) -> void:
	if _done or b == src or b.is_in_group("enemies") or b.is_in_group("player"):
		return
	# 打到牆或地：製造聲響，附近守衛會過來查看
	get_tree().call_group("enemies", "hear_noise", global_position, 8.0)
	_finish()
