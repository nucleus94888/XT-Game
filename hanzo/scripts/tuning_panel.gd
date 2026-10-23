extends PanelContainer
## 手感調校面板：依 Feel.PARAMS 自動產生滑桿；五組盲選預設；重設 / 儲存 / 複製 / 關閉。
## 面板開著遊戲照跑，拖一下滑桿立刻去砍，感覺對了按「儲存」。

var _sliders := {}
var _values := {}
var _syncing := false
var _status: Label


const FONT := 22
const FONT_TITLE := 30
const FONT_BTN := 22


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.95)
	sb.set_content_margin_all(16.0)
	add_theme_stylebox_override("panel", sb)
	# 手機：介面已放大，剩下的畫布較窄，面板改佔六成寬才放得下滑桿
	if Feel.is_mobile():
		anchor_left = 0.38
	_build()
	Feel.params_changed.connect(_sync)
	_sync()


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "手感調校（即時生效）"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	head.add_child(title)
	_btn(head, "✕ 關閉", func() -> void:
		visible = false)

	var presets := HFlowContainer.new()
	root.add_child(presets)
	for preset_name in Feel.PRESETS:
		var b := Button.new()
		b.text = preset_name
		b.add_theme_font_size_override("font_size", FONT_BTN)
		b.custom_minimum_size = Vector2(0.0, 48.0)
		b.pressed.connect(func() -> void:
			Feel.apply_preset(preset_name)
			_say("已套用「%s」，去砍看看。" % preset_name))
		presets.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	# 一列放完「名稱｜滑桿｜數值」，手機上一屏能看到六七個參數
	for key in Feel.PARAMS:
		var spec: Array = Feel.PARAMS[key]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		list.add_child(row)
		var name_l := Label.new()
		name_l.text = spec[0]
		name_l.custom_minimum_size.x = 170.0
		name_l.add_theme_font_size_override("font_size", FONT - 2)
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_l)
		var s := HSlider.new()
		s.min_value = spec[1]
		s.max_value = spec[2]
		s.step = spec[3]
		s.custom_minimum_size = Vector2(120.0, 44.0)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.scrollable = false
		s.value_changed.connect(func(v: float) -> void:
			if not _syncing:
				Feel.set_p(key, v))
		row.add_child(s)
		var val_l := Label.new()
		val_l.custom_minimum_size.x = 70.0
		val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val_l.add_theme_font_size_override("font_size", FONT)
		val_l.modulate = Color(1.0, 0.85, 0.5)
		row.add_child(val_l)
		_sliders[key] = s
		_values[key] = val_l

	var actions := HBoxContainer.new()
	root.add_child(actions)
	_btn(actions, "重設", func() -> void:
		Feel.reset_defaults()
		_say("已重設為預設值。"))
	_btn(actions, "儲存", func() -> void:
		Feel.save_cfg()
		_say("已儲存到這台裝置，下次開啟自動載入。"))
	_btn(actions, "複製數值", func() -> void:
		DisplayServer.clipboard_set(Feel.to_text())
		_say("已複製，貼給 AI 就能重現這組手感。"))

	_status = Label.new()
	_status.text = "先按五組預設盲選各砍一分鐘，再微調；對了就「儲存」。"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", FONT - 2)
	root.add_child(_status)


func _btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", FONT_BTN)
	b.custom_minimum_size = Vector2(0.0, 48.0)
	b.pressed.connect(cb)
	parent.add_child(b)


func _sync() -> void:
	_syncing = true
	for key in _sliders:
		var v := Feel.get_p(key)
		(_sliders[key] as HSlider).set_value_no_signal(v)
		var step: float = Feel.PARAMS[key][3]
		(_values[key] as Label).text = ("%.2f" % v) if step < 1.0 else str(int(round(v)))
	_syncing = false


func _say(t: String) -> void:
	if _status:
		_status.text = t
