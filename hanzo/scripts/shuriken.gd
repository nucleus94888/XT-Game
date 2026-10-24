extends Node3D
class_name Shuriken
## 手裡劍：直線飛行並旋轉。命中敵人造成小傷害與體幹，打斷弓兵拉弓；
## 命中牆／地面製造聲響（引開守衛）並插在那裡，半藏走過去可以撿回；命中燈籠使其熄滅。

var dir := Vector3.FORWARD
var speed := 24.0
var dmg := 8
var src: Node = null
## 已插在牆／地上（可撿回）
var stuck := false

var _life := 1.6
var _done := false
var _spin: MeshInstance3D
var _area: Area3D
var _t := 0.0


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

	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1 | 4 | 16
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.25
	cs.shape = sh
	_area.add_child(cs)
	add_child(_area)
	_area.area_entered.connect(_on_area)
	_area.body_entered.connect(_on_body)


func _physics_process(delta: float) -> void:
	_t += delta
	if stuck:
		# 插著微微發亮，提示可撿
		_spin.scale = Vector3.ONE * (1.0 + 0.08 * sin(_t * 6.0))
		return
	# 每幀用射線掃過這一步的路徑（Area 對靜態世界不可靠，會直接穿過地面與牆）：
	# 打到敵人受擊區／燈籠（Area）→ 命中；打到世界（Body）→ 插在那裡
	var from := global_position
	var to := from + dir * speed * delta
	var space := get_world_3d().direct_space_state
	var ex: Array = [(src as CollisionObject3D).get_rid()] if src is CollisionObject3D else []
	var hit := {}
	for i in range(4):
		var q := PhysicsRayQueryParameters3D.create(from, to + dir * 0.25, 1 | 4 | 16)
		q.collide_with_areas = true
		q.collide_with_bodies = true
		q.exclude = ex
		hit = space.intersect_ray(q)
		# 被遮蔽層隱藏的屋頂／樓板對玩家來說不存在，直接穿過
		if not hit.is_empty() and hit.collider is Node3D and not (hit.collider as Node3D).is_visible_in_tree():
			ex.append(hit.rid)
			hit = {}
			continue
		break
	if not hit.is_empty():
		var c: Node = hit.collider
		if c is Area3D:
			global_position = hit.position
			_on_area(c)
			if _done:
				return
		elif not (c.is_in_group("enemies") or c.is_in_group("player")):
			global_position = hit.position
			_hit_world(hit.normal)
			return
	global_position = to
	_spin.rotation.z += delta * 30.0
	_life -= delta
	if _life <= 0.0:
		_drop_to_ground()


func _finish() -> void:
	_done = true
	queue_free()


## 飛到底沒打到東西：落到地上變成可撿的
func _drop_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(0.0, -12.0, 0.0), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_finish()
		return
	global_position = (hit.position as Vector3) + Vector3(0.0, 0.05, 0.0)
	_stick(Vector3.UP)


## 插在牆／地上：變成撿拾點（半藏走到旁邊就撿回）
func _stick(normal: Vector3) -> void:
	stuck = true
	_done = false
	if absf(normal.y) < 0.7:
		_spin.rotation = Vector3.ZERO
		look_at(global_position + normal, Vector3.UP)
	else:
		_spin.rotation.x = 0.0
		rotation = Vector3.ZERO
		_spin.rotation.x = PI / 2.0
	var m: StandardMaterial3D = _spin.material_override
	m.emission_enabled = true
	m.emission = Color(0.7, 0.85, 1.0)
	m.emission_energy_multiplier = 0.9
	# 撿拾範圍：只對玩家本體
	var pick := Area3D.new()
	pick.collision_layer = 0
	pick.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.1
	cs.shape = sh
	pick.add_child(cs)
	add_child(pick)
	pick.body_entered.connect(_on_pick)
	_area.queue_free()


func _on_pick(b: Node3D) -> void:
	if _done or not b.is_in_group("player") or not b.has_method("pickup_shuriken"):
		return
	_done = true
	b.pickup_shuriken()
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.12)
	tw.tween_callback(queue_free)


func _on_area(a: Area3D) -> void:
	if _done or stuck:
		return
	var t := a.get_parent()
	if t == null or t == src:
		return
	if t.is_in_group("lanterns") and t.has_method("extinguish"):
		t.extinguish()
		Feel.shake(0.15)
		_finish()
	elif t.is_in_group("enemies") and t.has_method("take_hit"):
		# 命中高度超過 1.45m = 頭部，傷害 2.5 倍
		var headshot: bool = global_position.y - (t as Node3D).global_position.y > 1.45
		t.take_hit({"dmg": int(dmg * 2.5) if headshot else dmg, "dir": dir, "kb": 1.0, "heavy": false, "pos": global_position, "src": src, "shuriken": true, "headshot": headshot})
		_finish()


func _on_body(b: Node3D) -> void:
	if _done or stuck or b == src or b.is_in_group("enemies") or b.is_in_group("player"):
		return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position - dir * 0.6, global_position + dir * 0.6, 1)
	var hit := space.intersect_ray(q)
	var n := -dir
	if not hit.is_empty():
		global_position = hit.position
		n = hit.normal
	_hit_world(n)


## 打到牆或地：製造聲響，附近守衛會過來查看；手裡劍插在那裡可撿回
func _hit_world(normal: Vector3) -> void:
	if _done or stuck:
		return
	global_position += normal * 0.04
	get_tree().call_group("enemies", "hear_noise", global_position, 8.0)
	_stick(normal)
