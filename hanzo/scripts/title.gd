extends Control
## 標題畫面：第一關 / 道場。

const LEVEL1 := "res://scenes/level1.tscn"
const DOJO := "res://scenes/main.tscn"


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.075, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 朱紅日輪 + 標題
	var sun := ColorRect.new()
	sun.color = Color(0.72, 0.2, 0.16)
	sun.size = Vector2(260, 260)
	sun.position = Vector2(60, 60)
	sun.rotation = 0.0
	add_child(sun)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.5
	vb.anchor_bottom = 0.5
	vb.offset_left = -260
	vb.offset_right = 260
	vb.offset_top = -200
	vb.offset_bottom = 200
	vb.add_theme_constant_override("separation", 18)
	add_child(vb)

	var title := Label.new()
	title.text = "半藏 HANZO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "影之刃，伊賀夜襲"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.8, 0.8, 0.85)
	sub.add_theme_font_size_override("font_size", 24)
	vb.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vb.add_child(spacer)

	_btn(vb, "第一關：伊賀夜襲", func() -> void:
		get_tree().change_scene_to_file(LEVEL1))
	_btn(vb, "第二關：湖畔屋敷（追擊）", func() -> void:
		get_tree().change_scene_to_file("res://scenes/level2.tscn"))
	_btn(vb, "道場（練手感）", func() -> void:
		get_tree().change_scene_to_file(DOJO))

	var hint := Label.new()
	hint.text = "手機請橫放。潛行從背後攻擊可暗殺；格擋可彈反；體幹崩壞後一刀忍殺。"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.7, 0.7, 0.75)
	hint.add_theme_font_size_override("font_size", 18)
	vb.add_child(hint)

	var ver := Label.new()
	ver.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0")
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.anchor_left = 1.0
	ver.anchor_top = 1.0
	ver.offset_left = -120
	ver.offset_top = -40
	ver.modulate = Color(1, 1, 1, 0.4)
	add_child(ver)


func _btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(440, 76)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(cb)
	parent.add_child(b)
