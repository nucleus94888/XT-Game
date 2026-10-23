extends Node3D
## 卷軸：每關藏一卷在潛行路線深處。撿到立刻生效（Progress.pickup_scroll），走到檢查點才寫進存檔。

var id := ""
var _taken := false
var _t := 0.0


func _ready() -> void:
	var roll := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.85, 0.65)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.5)
	mat.emission_energy_multiplier = 0.5
	roll.mesh = cm
	roll.material_override = mat
	roll.rotation.z = PI / 2.0
	roll.position = Vector3(0, 0.5, 0)
	add_child(roll)
	for side in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.15
		cc.bottom_radius = 0.15
		cc.height = 0.06
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.5, 0.12, 0.1)
		cap.mesh = cc
		cap.material_override = cmat
		cap.rotation.z = PI / 2.0
		cap.position = Vector3(side * 0.37, 0.5, 0)
		add_child(cap)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.9, 0.6)
	light.light_energy = 0.7
	light.omni_range = 2.5
	light.position = Vector3(0, 0.8, 0)
	add_child(light)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.0
	cs.shape = sh
	cs.position = Vector3(0, 0.5, 0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	rotation.y += delta * 1.2
	position.y = 0.1 + sin(_t * 2.5) * 0.08


func _on_body(b: Node3D) -> void:
	if _taken or not b.is_in_group("player"):
		return
	_taken = true
	Progress.pickup_scroll(id)
	var name_text: String = Progress.SCROLLS.get(id, "卷軸")
	Fx.damage_number(global_position + Vector3(0, 1.6, 0), 1, true, Color(1.0, 0.9, 0.6), "卷軸：%s" % name_text)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("say"):
		hud.say("卷軸：%s" % name_text, Color(1.0, 0.9, 0.6))
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.2)
	tw.tween_callback(queue_free)
