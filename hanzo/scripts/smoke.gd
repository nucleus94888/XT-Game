extends Node3D
## 煙玉的煙（第十二次議會）：灰色半透明圓柱，持續 7 秒。
## 敵人的視線穿過煙、或玩家站在煙裡 → 看不到（enemy._los 會查 group "smoke"）。
## 煙冒出來的瞬間，附近在追你的敵人改成「搜索」。

var radius := 2.6
var height := 3.2
var duration := 7.0
var _t := 0.0
var _mi: Node3D
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("smoke")
	# 一團團的煙球疊起來（不是一根圓柱）：底下大而密、上面小而淡，慢慢翻滾往上飄
	_mi = Node3D.new()
	add_child(_mi)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.72, 0.72, 0.76, 0.0)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	for i in range(11):
		var puff := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var lvl := float(i % 3)
		var r := radius * randf_range(0.5, 0.75) * (1.0 - lvl * 0.18)
		sm.radius = r
		sm.height = r * 1.6
		sm.radial_segments = 12
		sm.rings = 6
		puff.mesh = sm
		puff.material_override = _mat
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := randf() * TAU
		var d := radius * randf_range(0.0, 0.55)
		puff.position = Vector3(cos(a) * d, 0.6 + lvl * 1.0 + randf() * 0.4, sin(a) * d)
		puff.set_meta("base_y", puff.position.y)
		puff.set_meta("ph", randf() * TAU)
		_mi.add_child(puff)
	_mi.scale = Vector3(0.3, 0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(_mi, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and (e as Node3D).global_position.distance_to(global_position) < radius + 6.0 and e.has_method("smoke_lost"):
			e.smoke_lost(global_position)


func _process(delta: float) -> void:
	_t += delta
	var fade_in := clampf(_t / 0.3, 0.0, 1.0)
	var fade_out := clampf((duration - _t) / 1.2, 0.0, 1.0)
	_mat.albedo_color.a = 0.55 * fade_in * fade_out
	_mi.rotation.y += delta * 0.4
	for p in _mi.get_children():
		var ph: float = p.get_meta("ph")
		p.position.y = float(p.get_meta("base_y")) + sin(_t * 1.3 + ph) * 0.15 + _t * 0.04
		p.scale = Vector3.ONE * (1.0 + 0.08 * sin(_t * 2.0 + ph) + _t * 0.02)
	if _t >= duration:
		queue_free()


func active() -> bool:
	return _t < duration - 0.8


## 線段 a→b 有沒有穿過這團煙（水平面上點到線段距離 < 半徑，且高度在煙裡）
func blocks(a: Vector3, b: Vector3) -> bool:
	if not active():
		return false
	var c := global_position
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var c2 := Vector2(c.x, c.z)
	var ab := b2 - a2
	var t := clampf((c2 - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	var closest := a2 + ab * t
	if closest.distance_to(c2) > radius:
		return false
	var y := lerpf(a.y, b.y, t)
	return y > c.y - 0.5 and y < c.y + height


func contains(p: Vector3) -> bool:
	return active() and Vector2(p.x - global_position.x, p.z - global_position.z).length() < radius and p.y > global_position.y - 0.5 and p.y < global_position.y + height
