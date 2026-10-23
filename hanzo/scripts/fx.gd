extends Node
## Fx：一次性視覺效果（傷害數字、殘影）。任何地方呼叫 Fx.xxx() 即可。

var ui_font: Font


func _ready() -> void:
	ui_font = load("res://fonts/ui.otf")


func damage_number(pos: Vector3, dmg: int, heavy: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var l := Label3D.new()
	l.text = str(dmg)
	if ui_font:
		l.font = ui_font
	l.font_size = 96 if heavy else 64
	l.pixel_size = 0.012 * Feel.get_p("dmg_scale")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 16
	l.outline_modulate = Color(0.05, 0.05, 0.06, 1.0)
	l.modulate = Color(1.0, 0.82, 0.35) if heavy else Color(1.0, 1.0, 1.0)
	l.render_priority = 10
	scene.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.25, 0.25), 0.2, 0.0)
	l.scale = Vector3.ONE * (1.8 if heavy else 1.5)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y + 1.3, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


## 開場預熱：數字字形（兩種字級）與殘影材質先各畫幾幀
func warmup(pos: Vector3, body: MeshInstance3D) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var labels: Array[Label3D] = []
	for size in [64, 96]:
		var l := Label3D.new()
		l.text = "0123456789！"
		if ui_font:
			l.font = ui_font
		l.font_size = size
		l.pixel_size = 0.012
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.outline_size = 16
		l.modulate = Color(1, 1, 1, 0.02)
		l.outline_modulate = Color(0, 0, 0, 0.02)
		scene.add_child(l)
		l.global_position = pos
		labels.append(l)
	afterimage(body, Color(0.6, 0.7, 1.0, 0.02), 0.2)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	for l in labels:
		l.queue_free()


func afterimage(src: MeshInstance3D, color: Color, dur: float = 0.25) -> void:
	var scene := get_tree().current_scene
	if scene == null or src == null or src.mesh == null:
		return
	var m := MeshInstance3D.new()
	m.mesh = src.mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	m.material_override = mat
	scene.add_child(m)
	m.global_transform = src.global_transform
	var tw := m.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.tween_callback(m.queue_free)
