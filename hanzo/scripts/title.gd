extends Control
## 標題畫面（第八次議會：只做「不丟臉＋告訴新手走哪條路」）。
## 一顆「開始」接續進度；關卡選擇降為次要列（未到的關卡變淡但仍可點，方便測試）；按鍵有縮放與聲音；日輪慢呼吸。

const LEVELS := [
	{"id": "level1", "scene": "res://scenes/level1.tscn", "num": "一", "name": "伊賀夜襲"},
	{"id": "level2", "scene": "res://scenes/level2.tscn", "num": "二", "name": "湖畔屋敷"},
	{"id": "level3", "scene": "res://scenes/level3.tscn", "num": "三", "name": "夜之城下町"},
]
const DOJO := "res://scenes/main.tscn"

var _sfx: AudioStreamPlayer


func _ready() -> void:
	# 網頁版測試：網址 ?level=2 直接進第二關
	if OS.has_feature("web"):
		var qs = JavaScriptBridge.eval("window.location.search", true)
		if typeof(qs) == TYPE_STRING:
			for part in String(qs).trim_prefix("?").split("&"):
				if part.begins_with("level="):
					var n := int(part.substr(6))
					if n >= 1 and n <= LEVELS.size():
						get_tree().change_scene_to_file.call_deferred(LEVELS[n - 1].scene)
						return
	_sfx = Sfx.player(self, "dash", -6.0, 0.9)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.075, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 朱紅日輪：圓形，壓在標題後面，慢呼吸
	var sun := Sun.new()
	sun.anchor_left = 0.5
	sun.anchor_right = 0.5
	sun.anchor_top = 0.0
	sun.anchor_bottom = 0.0
	sun.offset_left = -120
	sun.offset_right = 120
	sun.offset_top = -40
	sun.offset_bottom = 200
	sun.pivot_offset = Vector2(120, 120)
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sun)
	var breath := sun.create_tween().set_loops()
	breath.tween_property(sun, "scale", Vector2(1.05, 1.05), 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath.tween_property(sun, "scale", Vector2(1.0, 1.0), 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.5
	vb.anchor_bottom = 0.5
	vb.offset_left = -300
	vb.offset_right = 300
	vb.offset_top = -180
	vb.offset_bottom = 180
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	add_child(vb)

	var title := Label.new()
	title.text = "半藏 HANZO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_outline_color", Color(0.07, 0.075, 0.1))
	title.add_theme_constant_override("outline_size", 6)
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "影之刃"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.8, 0.8, 0.85)
	sub.add_theme_font_size_override("font_size", 24)
	vb.add_child(sub)
	vb.add_child(_spacer(14))

	# 主鍵：接續進度（第一個沒通關的關卡；全通就回第一關）
	var next: Dictionary = LEVELS[0]
	for lv in LEVELS:
		if not Progress.cleared.has(lv.id):
			next = lv
			break
	var start := _btn("開始", 34, Vector2(320, 72), func() -> void:
		_go(next.scene))
	start.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	vb.add_child(start)
	var dest := Label.new()
	dest.text = "第%s關　%s" % [next.num, next.name]
	dest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dest.modulate = Color(1.0, 0.85, 0.6)
	dest.add_theme_font_size_override("font_size", 20)
	vb.add_child(dest)
	vb.add_child(_spacer(10))

	# 次要列：關卡選擇＋道場。通關的標記最佳評價；還沒到的變淡（仍可點）
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var reached := true
	for lv in LEVELS:
		var cleared: bool = Progress.cleared.has(lv.id)
		var text: String = lv.num
		if cleared:
			text += "　" + String(Progress.best_rank.get(lv.id, "✓"))
		var b := _btn(text, 22, Vector2(96, 54), func() -> void:
			_go(lv.scene))
		b.tooltip_text = lv.name
		if not reached:
			b.modulate = Color(1, 1, 1, 0.45)
		row.add_child(b)
		reached = reached and cleared
	var dojo := _btn("道場", 20, Vector2(110, 54), func() -> void:
		_go(DOJO))
	dojo.modulate = Color(1, 1, 1, 0.75)
	row.add_child(dojo)

	# 持有物（有才顯示）
	if Progress.beads > 0 or Progress.scroll_count() > 0:
		var prog := Label.new()
		var names: Array = []
		for id in Progress.scrolls:
			names.append(Progress.SCROLLS[id])
		prog.text = "念珠 %d/%d　卷軸 %d/%d%s" % [Progress.beads, Progress.MAX_BEADS, Progress.scroll_count(), Progress.SCROLLS.size(), ("：" + "、".join(names)) if names.size() > 0 else ""]
		prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prog.modulate = Color(1.0, 0.9, 0.7, 0.8)
		prog.add_theme_font_size_override("font_size", 16)
		vb.add_child(prog)

	var ver := Label.new()
	ver.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0")
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.anchor_left = 1.0
	ver.anchor_top = 1.0
	ver.offset_left = -260
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.offset_right = -14
	ver.offset_top = -40
	ver.modulate = Color(1, 1, 1, 0.4)
	add_child(ver)

	# 自動截圖（AI 看畫面用）：++ --shot=<目錄>
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var dir := a.substr(7)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
			get_tree().create_timer(0.8).timeout.connect(func() -> void:
				var img := get_viewport().get_texture().get_image()
				img.save_png(dir.path_join("title.png"))
				print("shot: ", dir.path_join("title.png"))
				get_tree().quit())


## 日輪：一個會畫圓的 Control
class Sun extends Control:
	func _draw() -> void:
		draw_circle(size / 2.0, size.x / 2.0, Color(0.72, 0.2, 0.16))


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## 按下：縮一下＋一聲布響，放開再切場景（讓回饋看得到）
func _btn(text: String, font_size: int, min_size: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.resized.connect(func() -> void:
		b.pivot_offset = b.size / 2.0)
	b.button_down.connect(func() -> void:
		Sfx.play(_sfx)
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(0.94, 0.94), 0.06))
	b.button_up.connect(func() -> void:
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	b.pressed.connect(cb)
	return b


func _go(scene: String) -> void:
	get_tree().create_timer(0.1).timeout.connect(func() -> void:
		get_tree().change_scene_to_file(scene))
