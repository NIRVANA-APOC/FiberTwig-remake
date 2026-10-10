extends Node
## AssetLib - loads textures and sounds from the raw game files.
## Names are resolved case insensitively because the .zxc archive mixes
## .png/.PNG/.pNg spellings.

var _textures := {}
var _sounds := {}
var _index := {}
var _flash := {}

func _build_index(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		_index[dir_path.path_join(f).to_lower()] = dir_path.path_join(f)

## Extra directories searched by file name: the shipped art is split between
## Game/ and levels/ archives (hero portraits live in the level archive).
const SEARCH_DIRS := ["res://assets/game", "res://assets/squares", "res://assets/lng"]

func resolve(path: String) -> String:
	if FileAccess.file_exists(path):
		return path
	var dir := path.get_base_dir()
	if not _index.has(dir):
		_build_index(dir)
	var hit: String = _index.get(path.to_lower(), "")
	if hit != "":
		return hit
	var base := path.get_file().to_lower()
	for d in SEARCH_DIRS:
		if not _index.has(d):
			_build_index(d)
		hit = _index.get(d.path_join(base), "")
		if hit != "":
			return hit
	return path

func texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var real := resolve(path)
	var tex: Texture2D = null
	if FileAccess.file_exists(real):
		var img := Image.load_from_file(ProjectSettings.globalize_path(real))
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_textures[path] = tex
	return tex

## Rotated variant of a texture (quarter turns clockwise); used for light streaks.
func texture_rot(path: String, quarters: int) -> Texture2D:
	if quarters == 0:
		return texture(path)
	var key := "%s|rot%d" % [path, quarters]
	if _textures.has(key):
		return _textures[key]
	var tex := texture(path)
	var out: Texture2D = null
	if tex != null:
		var img := tex.get_image()
		for i in quarters % 4:
			img.rotate_90(CLOCKWISE)
		out = ImageTexture.create_from_image(img)
	_textures[key] = out
	return out

## Brightened yellow variant used for the lucky-twig flash. Drawing it over
## the base texture with alpha k yields base + k*(flash-base), i.e. the
## additive yellow pulse the original applies (FUN_00490abc).
func flash_texture(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var id := tex.get_instance_id()
	if _flash.has(id):
		return _flash[id]
	var out: Texture2D = null
	var img := tex.get_image()
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(minf(1.0, c.r + 0.62), minf(1.0, c.g + 0.70), c.b, c.a))
		out = ImageTexture.create_from_image(img)
	_flash[id] = out
	return out

func music(path: String) -> AudioStream:
	if _sounds.has(path):
		return _sounds[path]
	var s: AudioStream = null
	var real := resolve(path)
	if FileAccess.file_exists(real):
		s = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(real))
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
	_sounds[path] = s
	return s

func sound(path: String) -> AudioStream:
	if _sounds.has(path):
		return _sounds[path]
	var s: AudioStream = null
	var real := resolve(path)
	if FileAccess.file_exists(real):
		var bytes := FileAccess.get_file_as_bytes(real)
		if bytes.size() > 0:
			s = AudioStreamWAV.load_from_buffer(bytes)
	_sounds[path] = s
	return s
