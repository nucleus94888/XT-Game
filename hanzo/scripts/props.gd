extends Node3D
## 可互動的關卡道具（第十二次議會）。全部走「靠近才出現的情境鍵」：玩家走到旁邊，按鍵變成對應的字。
##   kind = "oil"    油壺：放火（大火 3 公尺，燒 12 秒）
##   kind = "straw"  稻草堆：擋路；點燃後燒掉、路就開了（火 2.2 公尺，燒 9 秒）
##   kind = "bomb"   焙烙玉：撿起來（一次性，丟出去範圍爆炸、兼火源）
## 每種都會被附近的火、爆炸點著（group "flammable"）。

const FireScript := preload("res://scripts/fire.gd")

var kind := "oil"
var used := false
## kind = "latch"（門閂）：拉開時呼叫（第十三次議會的捷徑門）
var on_use: Callable
var _body: StaticBody3D
var _mesh_root: Node3D
var _t := 0.0


func _ready() -> void:
	add_to_group("interactable")
	if kind != "bomb" and kind != "latch":
		add_to_group("flammable")
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	match kind:
		"oil":
			_cyl(0.32, 0.8, Color(0.45, 0.3, 0.18), Vector3(0, 0.4, 0))
			_cyl(0.18, 0.15, Color(0.25, 0.15, 0.1), Vector3(0, 0.88, 0))
			_box(Vector3(0.66, 0.06, 0.66), Color(0.15, 0.12, 0.08, 0.6), Vector3(0, 0.02, 0))  # 地上的油漬
			_solid(Vector3(0.6, 0.9, 0.6), Vector3(0, 0.45, 0))
		"straw":
			for i in range(3):
				_box(Vector3(1.6, 0.6, 1.0), Color(0.62, 0.52, 0.25), Vector3(0, 0.3 + i * 0.6, 0), Vector3(0, i * 12.0, 0))
			_solid(Vector3(1.8, 1.8, 1.2), Vector3(0, 0.9, 0))
		"latch":
			_box(Vector3(1.6, 0.18, 0.18), Color(0.4, 0.28, 0.16), Vector3(0, 1.1, 0))
			_box(Vector3(0.12, 0.5, 0.3), Color(0.25, 0.25, 0.27), Vector3(-0.6, 1.1, 0))
			_box(Vector3(0.12, 0.5, 0.3), Color(0.25, 0.25, 0.27), Vector3(0.6, 1.1, 0))
		"bomb":
			_sphere(0.22, Color(0.15, 0.13, 0.12), Vector3(0, 0.3, 0))
			_box(Vector3(0.05, 0.18, 0.05), Color(0.9, 0.7, 0.3), Vector3(0, 0.55, 0))  # 引信
	# 發光描邊：一圈淡淡的光環，告訴玩家「這個可以互動」
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.7 if kind != "straw" else 1.2
	tm.outer_radius = tm.inner_radius + 0.08
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(1.0, 0.85, 0.4, 0.6)
	ring.material_override = rm
	ring.position = Vector3(0, 0.08, 0)
	ring.name = "Ring"
	add_child(ring)


func _process(delta: float) -> void:
	_t += delta
	var ring := get_node_or_null("Ring") as MeshInstance3D
	if ring:
		(ring.material_override as StandardMaterial3D).albedo_color.a = 0.35 + 0.3 * sin(_t * 4.0)
	if kind == "bomb":
		_mesh_root.position.y = 0.05 * sin(_t * 3.0)


func interact_radius() -> float:
	return 1.9 if kind == "straw" else 1.4


func interact_label() -> String:
	match kind:
		"oil": return "放火"
		"straw": return "點燃"
		"bomb": return "撿起"
		"latch": return "拉開"
	return ""


func can_interact(_p: Node) -> bool:
	return not used and not _fusing


func interact(p: Node) -> void:
	if used:
		return
	match kind:
		"oil", "straw":
			_light_fuse()
		"latch":
			used = true
			remove_from_group("interactable")
			var ring0 := get_node_or_null("Ring")
			if ring0:
				ring0.queue_free()
			var tw := create_tween()
			tw.tween_property(_mesh_root, "position:y", 0.8, 0.3)
			tw.parallel().tween_property(_mesh_root, "rotation:z", 1.2, 0.3)
			if on_use.is_valid():
				on_use.call()
		"bomb":
			used = true
			if p.has_method("pickup_bomb"):
				p.pickup_bomb()
			queue_free()


## 玩家點火：引信 1.2 秒（火星往上冒、嘶嘶聲），讓人有時間退開，不會一點就站在火裡
const FUSE := 1.2
var _fusing := false


func _light_fuse() -> void:
	if _fusing or used:
		return
	_fusing = true
	remove_from_group("interactable")
	var ring := get_node_or_null("Ring")
	if ring:
		ring.queue_free()
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 0.5
	p.direction = Vector3.UP
	p.spread = 30.0
	p.gravity = Vector3(0, 1.0, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.albedo_color = Color(1.0, 0.8, 0.3)
	q.material = pm
	p.mesh = q
	p.position = Vector3(0, 1.0 if kind == "oil" else 1.9, 0)
	add_child(p)
	var sp := AudioStreamPlayer.new()
	add_child(sp)
	Sfx.bind(sp, "dash", 1.1, 0.6)
	Sfx.play(sp)
	get_tree().create_timer(FUSE).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
		ignite())


## 被點著（玩家放火、附近的火、爆炸）
func ignite() -> void:
	if used:
		return
	used = true
	remove_from_group("interactable")
	var f: Node3D = FireScript.new()
	f.radius = 3.0 if kind == "oil" else 2.2
	f.duration = 12.0 if kind == "oil" else 9.0
	get_parent().add_child(f)
	f.global_position = global_position
	if kind == "straw":
		# 稻草燒 1.5 秒後垮掉，擋路的碰撞跟著消失（路開了）
		var tw := create_tween()
		tw.tween_interval(1.5)
		tw.tween_property(_mesh_root, "scale", Vector3(1.0, 0.1, 1.0), 1.5)
		tw.tween_callback(func() -> void:
			if is_instance_valid(_body):
				_body.queue_free())
	else:
		var tw2 := create_tween()
		tw2.tween_property(_mesh_root, "scale", Vector3(1.3, 0.2, 1.3), 0.3)
		tw2.tween_callback(func() -> void:
			if is_instance_valid(_body):
				_body.queue_free())
	var ring := get_node_or_null("Ring")
	if ring:
		ring.queue_free()


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _box(size: Vector3, c: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation_degrees = rot
	_mesh_root.add_child(mi)


func _cyl(r: float, h: float, c: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.85
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = _mat(c)
	mi.position = pos
	_mesh_root.add_child(mi)


func _sphere(r: float, c: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = _mat(c)
	mi.position = pos
	_mesh_root.add_child(mi)


func _solid(size: Vector3, pos: Vector3) -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	_body.add_child(cs)
	add_child(_body)
