extends Node3D
class_name Arrow
## 弓兵的箭：直線飛行，碰到玩家受擊區就造成傷害（可格擋、不可彈反），碰到牆就消失。

var dir := Vector3.FORWARD
var speed := 15.0
var dmg := 10
var src: Node = null

var _life := 2.6
var _done := false
var _area: Area3D


func launch(from: Vector3, to_dir: Vector3) -> void:
	global_position = from
	dir = to_dir.normalized()
	look_at(from + dir, Vector3.UP)


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.25, 0.15)
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	var tip := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.08, 0.08, 0.15)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.85, 0.88, 0.95)
	tmat.metallic = 0.8
	tip.mesh = tm
	tip.material_override = tmat
	tip.position = Vector3(0, 0, -0.5)
	add_child(tip)

	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 9
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.22
	cs.shape = sh
	cs.position = Vector3(0, 0, -0.4)
	_area.add_child(cs)
	add_child(_area)
	_area.area_entered.connect(_on_area)
	_area.body_entered.connect(_on_body)


func _physics_process(delta: float) -> void:
	global_position += dir * speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _hit(t: Node) -> void:
	if _done:
		return
	_done = true
	t.take_hit({"dmg": dmg, "dir": dir, "kb": 2.0, "heavy": false, "pos": global_position, "src": src, "ranged": true})
	queue_free()


func _on_area(a: Area3D) -> void:
	var t := a.get_parent()
	if t and t != src and t.is_in_group("player") and t.has_method("take_hit"):
		_hit(t)


func _on_body(b: Node3D) -> void:
	if b == src:
		return
	if b.is_in_group("player") and b.has_method("take_hit"):
		_hit(b)
	elif not b.is_in_group("enemies"):
		queue_free()
