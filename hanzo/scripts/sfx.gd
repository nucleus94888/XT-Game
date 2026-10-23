extends Node
## Sfx：音效庫。來源 Kenney（CC0，audio/kenney/LICENSE-kenney-CC0.txt）。
## 每組音效用 AudioStreamRandomizer 隨機挑變化、隨機微調音高，連按不會聽到同一聲。

const DIR := "res://audio/kenney/"

## 名稱 → 檔名清單（不含 .ogg）
const SETS := {
	"swing": ["knifeSlice", "knifeSlice2"],
	"hit": ["impactPunch_medium_000", "impactPunch_medium_001", "impactPunch_medium_002"],
	"heavy": ["impactPunch_heavy_000", "impactPunch_heavy_001", "impactPunch_heavy_002"],
	"heavy_wood": ["chop", "impactWood_medium_000", "impactWood_medium_001"],
	"dash": ["cloth1", "cloth2", "cloth3"],
	"hurt": ["impactSoft_heavy_000", "impactSoft_heavy_001", "impactSoft_heavy_002"],
	"break": ["impactWood_heavy_000", "impactWood_heavy_001", "impactWood_heavy_002"],
	"break_crack": ["impactPlank_medium_000", "impactPlank_medium_001", "impactPlank_medium_002"],
}

var _cache := {}


func make(set_name: String, pitch_spread: float = 1.08, vol_spread_db: float = 1.5) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	r.random_pitch = pitch_spread
	r.random_volume_offset_db = vol_spread_db
	var i := 0
	for name in SETS[set_name]:
		var s := _load(name)
		if s:
			r.add_stream(i, s)
			i += 1
	return r


func _load(name: String) -> AudioStream:
	if not _cache.has(name):
		_cache[name] = load(DIR + name + ".ogg")
	return _cache[name]


## 建一個已接好音效的播放器並掛到 parent 下
func player(parent: Node, set_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = make(set_name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	parent.add_child(p)
	return p
