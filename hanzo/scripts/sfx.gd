extends Node
## Sfx：音效庫（低延遲版）。
## 重點：網頁版只有「直接播 WAV/OGG」能走瀏覽器原生取樣播放（低延遲）；
## AudioStreamRandomizer 之類的包裝串流會退回混音器路徑、延遲明顯。所以這裡不用包裝，
## 由程式自己隨機挑檔、隨機音高，並在網頁版把播放器設成 SAMPLE 模式。
##
## 來源：audio/mixkit/（Mixkit 免費授權，刀揮、砍中）、audio/kenney/（CC0，木樁、衣物、受傷）

const SETS := {
	"swing": ["mixkit/swing.wav"],
	"hit": ["mixkit/hit_1.wav", "mixkit/hit_2.wav"],
	"heavy": ["mixkit/heavy.wav"],
	"heavy_wood": ["kenney/impactWood_medium_000.ogg", "kenney/impactWood_medium_001.ogg", "kenney/impactWood_medium_002.ogg"],
	"dash": ["kenney/cloth1.ogg", "kenney/cloth2.ogg", "kenney/cloth3.ogg"],
	"hurt": ["kenney/impactSoft_heavy_000.ogg", "kenney/impactSoft_heavy_001.ogg", "kenney/impactSoft_heavy_002.ogg"],
	"deflect": ["kenney/impactMetal_medium_000.ogg", "kenney/impactMetal_medium_001.ogg", "kenney/impactMetal_medium_002.ogg"],
	"block": ["kenney/impactMetal_light_000.ogg", "kenney/impactMetal_light_001.ogg", "kenney/impactMetal_light_002.ogg"],
	"break": ["kenney/impactWood_heavy_000.ogg", "kenney/impactWood_heavy_001.ogg", "kenney/impactWood_heavy_002.ogg"],
}

var _cache := {}


func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load("res://audio/" + path)
	return _cache[path]


## 把一組音效綁到現有的 AudioStreamPlayer 上（之後用 Sfx.play(node) 播放）
func bind(p: AudioStreamPlayer, set_name: String, pitch_spread: float = 1.08, base_pitch: float = 1.0) -> void:
	var streams: Array = []
	for path in SETS[set_name]:
		var s := _load(path)
		if s:
			streams.append(s)
	p.set_meta("sfx_streams", streams)
	p.set_meta("sfx_spread", pitch_spread)
	p.set_meta("sfx_base", base_pitch)
	p.set_meta("sfx_last", -1)
	if streams.size() > 0:
		p.stream = streams[0]
	if OS.has_feature("web"):
		p.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE


## 建一個新的播放器、綁好、掛到 parent 下
func player(parent: Node, set_name: String, volume_db: float = 0.0, base_pitch: float = 1.0, pitch_spread: float = 1.08) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = volume_db
	parent.add_child(p)
	bind(p, set_name, pitch_spread, base_pitch)
	return p


## 隨機挑一個變化（不連續重複）、隨機音高，立刻播
func play(p: AudioStreamPlayer) -> void:
	var streams: Array = p.get_meta("sfx_streams", [])
	if streams.is_empty():
		return
	var i := randi() % streams.size()
	var last: int = p.get_meta("sfx_last", -1)
	if streams.size() > 1 and i == last:
		i = (i + 1) % streams.size()
	p.set_meta("sfx_last", i)
	p.stream = streams[i]
	var spread: float = p.get_meta("sfx_spread", 1.0)
	var base: float = p.get_meta("sfx_base", 1.0)
	p.pitch_scale = base * randf_range(1.0 / spread, spread)
	p.play()
