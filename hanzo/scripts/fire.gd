extends Node3D
## 火（第十二次議會「油與火」）：燒一段時間就熄。
## - 是光源：玩家站在火光裡＝在光裡（敵人看得遠、發現得快）→ 光暗系統反過來用
## - 點起來的瞬間發出聲響，附近守衛過來查看（視野錐被拉到火那邊，你的路就空出來）
## - 站在火裡會被燙（玩家、敵人都會），敵人被燙會退開
## - 燒到稻草堆、油壺會一起點著（範圍固定，不做無限蔓延）
## 畫面只用發光方塊＋一盞燈＋少量粒子（iOS 網頁版效能）

var radius := 2.2
var duration := 10.0
var light_radius := 7.0
var _t := 0.0
## 第一次燙人在 0.6 秒後（剛冒出來那一下不算）
var _tick := 0.6
var _flames: Array = []
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("fires")
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.15)
	var mat2 := mat.duplicate() as StandardMaterial3D
	mat2.albedo_color = Color(1.0, 0.85, 0.3)
	# 火焰：幾根歪斜的細長方塊，隨機抖動高度
	var n := int(clampf(radius * 3.0, 4.0, 9.0))
	for i in range(n):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 1.0, 0.35)
		mi.mesh = bm
		mi.material_override = mat if i % 2 == 0 else mat2
		var a := TAU * float(i) / n + randf() * 0.5
		var r := radius * randf_range(0.15, 0.8)
		mi.position = Vector3(cos(a) * r, 0.5, sin(a) * r)
		mi.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_flames.append(mi)
	# 地上焦黑一圈（看得出燒到哪裡）
	var scorch := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.02
	scorch.mesh = cm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(1.0, 0.35, 0.1, 0.35)
	scorch.material_override = sm
	scorch.position = Vector3(0, 0.25, 0)
	add_child(scorch)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.light_energy = 3.0
	_light.omni_range = light_radius + 1.0
	_light.position = Vector3(0, 1.5, 0)
	add_child(_light)
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.6
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, 2.5, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	var q := QuadMesh.new()
	q.size = Vector2(0.15, 0.15)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.albedo_color = Color(1.0, 0.7, 0.2)
	q.material = pm
	p.mesh = q
	p.position = Vector3(0, 0.3, 0)
	add_child(p)
	# 點火的動靜：附近守衛過來查看
	get_tree().call_group("enemies", "hear_noise", global_position, 14.0)
	Feel.shake(0.3)
	_ignite_neighbors()


func lights(pos: Vector3) -> bool:
	return global_position.distance_to(pos) < light_radius * _strength()


func _strength() -> float:
	# 最後 2 秒漸弱
	return clampf((duration - _t) / 2.0, 0.0, 1.0)


func _ignite_neighbors() -> void:
	for n in get_tree().get_nodes_in_group("flammable"):
		if n is Node3D and (n as Node3D).global_position.distance_to(global_position) < radius + 1.2 and n.has_method("ignite"):
			n.ignite.call_deferred()


func _physics_process(delta: float) -> void:
	_t += delta
	var k := _strength()
	for f in _flames:
		var mi := f as MeshInstance3D
		mi.scale = Vector3(1.0, (0.6 + 0.8 * absf(sin(_t * 9.0 + mi.position.x * 3.0))) * maxf(k, 0.05), 1.0)
	_light.light_energy = 3.0 * k * (0.85 + 0.15 * sin(_t * 17.0))
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.6
		_burn_inside()
	if _t >= duration:
		queue_free()


## 站在火裡會被燙：玩家每 0.6 秒 6 點；敵人 8 點並被推開
func _burn_inside() -> void:
	for b in get_tree().get_nodes_in_group("player"):
		var pb := b as Node3D
		if _inside(pb.global_position) and b.has_method("take_hit"):
			var d := pb.global_position - global_position
			d.y = 0.0
			b.take_hit({"dmg": 6, "dir": d.normalized() if d.length() > 0.01 else Vector3.FORWARD, "kb": 3.0, "heavy": false, "pos": pb.global_position + Vector3(0, 1, 0), "src": self, "unblockable": true, "fire": true})
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Node3D
		if en and _inside(en.global_position) and e.has_method("burn"):
			e.burn(global_position)


func _inside(p: Vector3) -> bool:
	var d := p - global_position
	return absf(d.y) < 1.6 and Vector2(d.x, d.z).length() < radius
