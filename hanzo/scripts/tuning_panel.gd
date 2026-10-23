extends PanelContainer
## 手感調校面板：依 Feel.PARAMS 自動產生滑桿；五組盲選預設；重設 / 儲存 / 複製 / 關閉。
## 面板開著遊戲照跑，拖一下滑桿立刻去砍，感覺對了按「儲存」。

var _sliders := {}
var _values := {}
var _syncing := false
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.93)
	sb.set_content_margin_all(14.0)
	add_theme_stylebox_override("panel", sb)
	_build()
	Feel.params_changed.connect(_sync)
	_sync()


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "手感調校（即時生效）"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	var presets := HFlowContainer.new()
	root.add_child(presets)
	for preset_name in Feel.PRESETS:
		var b := Button.new()
		b.text = preset_name
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

	for key in Feel.PARAMS:
		var spec: Array = Feel.PARAMS[key]
		var row := HBoxContainer.new()
		list.add_child(row)
		var name_l := Label.new()
		name_l.text = spec[0]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var val_l := Label.new()
		val_l.custom_minimum_size.x = 72.0
		val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_l)
		var s := HSlider.new()
		s.min_value = spec[1]
		s.max_value = spec[2]
		s.step = spec[3]
		s.custom_minimum_size = Vector2(0.0, 34.0)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(func(v: float) -> void:
			if not _syncing:
				Feel.set_p(key, v))
		list.add_child(s)
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
	_btn(actions, "關閉", func() -> void:
		visible = false)

	_status = Label.new()
	_status.text = "拖滑桿後直接去砍稻草人；先用上面五組預設盲選，別先看數字。"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func _btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
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
