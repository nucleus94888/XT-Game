extends Node3D
## 警鈴繩（第十二次議會）：兩根木樁之間一條發亮的粗繩、中間掛鈴鐺。
## 玩家踩過去 → 鈴響，20 公尺內的守衛全部過來搜索（故意踩響也可以拿來引開人）。
## 走到旁邊按情境鍵「割斷」→ 繩子落地、不再響。敵人自己走過不會響。

var a := Vector3.ZERO
var b := Vector3.ZERO
var cut := false
var rung := false
var _rope: MeshInstance3D
var _bell: MeshInstance3D
var _rope_mat: StandardMaterial3D
var _area: Area3D
var _t := 0.0


func _ready() -> void:
	add_to_group("interactable")
	var mid := (a + b) / 2.0
	global_position = mid
	var d := b - a
	d.y = 0.0
	var length := d.length()
	var yaw := atan2(-d.x, -d.z)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.25, 0.15)
	for end in [a, b]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.9, 0.14)
		post.mesh = bm
		post.material_override = wood
		add_child(post)
		post.global_position = Vector3(end.x, mid.y + 0.45, end.z)
	_rope = MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.09, 0.09, length)
	_rope.mesh = rm
	_rope_mat = StandardMaterial3D.new()
	_rope_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rope_mat.albedo_color = Color(1.0, 0.85, 0.3)
	_rope.material_override = _rope_mat
	_rope.position = Vector3(0, 0.45, 0)
	_rope.rotation.y = yaw
	add_child(_rope)
	_bell = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.14
	cm.height = 0.2
	_bell.mesh = cm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.85, 0.7, 0.25)
	bmat.metallic = 0.8
	_bell.material_override = bmat
	_bell.position = Vector3(0, 0.3, 0)
	add_child(_bell)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 1.2, length)
	cs.shape = bs
	cs.position = Vector3(0, 0.6, 0)
	cs.rotation.y = yaw
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	if not cut:
		_rope_mat.albedo_color = Color(1.0, 0.85, 0.3).lerp(Color(1.0, 1.0, 0.7), 0.5 + 0.5 * sin(_t * 5.0))
	if rung:
		_bell.rotation.z = sin(_t * 30.0) * 0.5 * maxf(0.0, 1.0 - (_t - _ring_t) / 2.0)


var _ring_t := 0.0


func _on_body(body: Node3D) -> void:
	if cut or not body.is_in_group("player"):
		return
	ring()


func ring() -> void:
	rung = true
	_ring_t = _t
	var sp := AudioStreamPlayer.new()
	add_child(sp)
	Sfx.bind(sp, "block", 1.05, 1.6)
	Sfx.play(sp)
	Feel.haptic(40)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and (e as Node3D).global_position.distance_to(global_position) < 20.0 and e.has_method("hear_noise"):
			e.hear_noise(global_position, 20.0)


func interact_radius() -> float:
	return 1.6


func interact_label() -> String:
	return "割斷"


func can_interact(_p: Node) -> bool:
	return not cut


func interact(_p: Node) -> void:
	if cut:
		return
	cut = true
	remove_from_group("interactable")
	_area.monitoring = false
	_rope_mat.albedo_color = Color(0.45, 0.4, 0.3)
	var tw := create_tween()
	tw.tween_property(_rope, "position:y", 0.05, 0.25)
	tw.parallel().tween_property(_bell, "position:y", 0.05, 0.25)
