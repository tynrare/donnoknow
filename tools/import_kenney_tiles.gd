# agent: composer-2.5 | 2026-07-07 | kenney import merge | 1e197f
extends SceneTree

const SRC := "/home/x/Downloads/kenney_pixel-platformer"
const OUT := "res://assets/tiles/kenney/sources"
const TILESET_PATH := "res://resources/platformer.tileset.tres"
const MANIFEST_PATH := "res://assets/tiles/kenney/manifest.json"


func _init() -> void:
	_import()
	quit()


func _import() -> void:
	var sheets := _collect_sheets()
	if sheets.is_empty():
		push_error("No Kenney tilemaps in %s" % SRC)
		return

	_reimport_assets()

	var tileset := _load_tileset()
	var manifest := _load_manifest()
	var ids: Dictionary = manifest.get("ids", {})

	for sheet in sheets:
		var tex_path: String = sheet.path
		var sid := _resolve_source_id(tileset, ids, sheet)
		_sync_atlas(tileset, sid, tex_path, sheet.info)
		ids[tex_path] = sid

	manifest["ids"] = ids
	_save_manifest(manifest)

	var err := ResourceSaver.save(tileset, TILESET_PATH)
	if err != OK:
		push_error("save failed: %s" % error_string(err))
		return

	print("Saved %s | sources=%d kenney=%d tiles=%d" % [
		TILESET_PATH,
		tileset.get_source_count(),
		ids.size(),
		_count_tiles(tileset),
	])


func _collect_sheets() -> Array:
	var sheets: Array = []
	var root := DirAccess.open(SRC)
	if root == null:
		return sheets

	for pack in root.get_directories():
		var pack_dir := SRC.path_join(pack)
		var tile_dir := pack_dir.path_join("Tilemap")
		if not DirAccess.dir_exists_absolute(tile_dir):
			continue

		var info := _parse_tilesheet(pack_dir.path_join("Tilesheet.txt"))
		_copy_tilesheet(pack, pack_dir.path_join("Tilesheet.txt"))

		var dir := DirAccess.open(tile_dir)
		for file_name in dir.get_files():
			if not file_name.ends_with(".png") or file_name.ends_with("_packed.png"):
				continue
			var dst_rel := "%s/%s/%s" % [OUT, pack, file_name]
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join(pack)))
			DirAccess.copy_absolute(tile_dir.path_join(file_name), ProjectSettings.globalize_path(dst_rel))
			sheets.append({"pack": pack, "name": file_name, "path": dst_rel, "info": info})

	sheets.sort_custom(func(a, b): return a.path < b.path)
	return sheets


func _copy_tilesheet(pack: String, src: String) -> void:
	if not FileAccess.file_exists(src):
		return
	var dst := OUT.path_join(pack).path_join("Tilesheet.txt")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join(pack)))
	DirAccess.copy_absolute(src, ProjectSettings.globalize_path(dst))


func _parse_tilesheet(path: String) -> Dictionary:
	var info := {
		"tile_w": 18, "tile_h": 18,
		"sep_x": 1, "sep_y": 1,
		"cols": 0, "rows": 0,
	}
	if not FileAccess.file_exists(path):
		return info
	var text := FileAccess.get_file_as_string(path)
	var rx := RegEx.new()
	rx.compile("Tile size\\s+•\\s+(\\d+)px × (\\d+)px")
	var m := rx.search(text)
	if m:
		info.tile_w = m.get_string(1).to_int()
		info.tile_h = m.get_string(2).to_int()
	rx.compile("Space between tiles\\s+•\\s+(\\d+)px × (\\d+)px")
	m = rx.search(text)
	if m:
		info.sep_x = m.get_string(1).to_int()
		info.sep_y = m.get_string(2).to_int()
	rx.compile("Total tiles \\(horizontal\\)\\s+•\\s+(\\d+)")
	m = rx.search(text)
	if m:
		info.cols = m.get_string(1).to_int()
	rx.compile("Total tiles \\(vertical\\)\\s+•\\s+(\\d+)")
	m = rx.search(text)
	if m:
		info.rows = m.get_string(1).to_int()
	return info


func _load_tileset() -> TileSet:
	if ResourceLoader.exists(TILESET_PATH):
		return load(TILESET_PATH) as TileSet
	var ts := TileSet.new()
	ts.tile_size = Vector2i(18, 18)
	return ts


func _load_manifest() -> Dictionary:
	if not ResourceLoader.exists(MANIFEST_PATH):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	return data if data is Dictionary else {}


func _save_manifest(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/tiles/kenney"))
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))


func _resolve_source_id(ts: TileSet, ids: Dictionary, sheet: Dictionary) -> int:
	var tex_path: String = sheet.path
	if ids.has(tex_path):
		var mid: int = ids[tex_path]
		if ts.has_source(mid):
			return mid

	var found := _find_source_by_path(ts, tex_path)
	if found >= 0:
		return found

	var stem: String = sheet.name.get_basename()
	var legacy := [
		"res://assets/tiles/kenney/sources/%s_%s_packed.png" % [sheet.pack, stem],
		"res://assets/tiles/kenney/sources/%s_%s.png" % [sheet.pack, stem],
	]
	for path in legacy:
		found = _find_source_by_path(ts, path)
		if found >= 0:
			return found

	return _next_source_id(ts)


func _find_source_by_path(ts: TileSet, path: String) -> int:
	for i in ts.get_source_count():
		var src := ts.get_source(i) as TileSetAtlasSource
		if src and src.texture and src.texture.resource_path == path:
			return i
	return -1


func _next_source_id(ts: TileSet) -> int:
	var id := 0
	while ts.has_source(id):
		id += 1
	return id


func _sync_atlas(ts: TileSet, sid: int, tex_path: String, info: Dictionary) -> void:
	var tex := load(tex_path) as Texture2D
	if tex == null:
		push_error("missing texture: %s" % tex_path)
		return

	var src: TileSetAtlasSource
	if ts.has_source(sid):
		src = ts.get_source(sid) as TileSetAtlasSource
	else:
		src = TileSetAtlasSource.new()
		ts.add_source(src, sid)

	src.texture = tex
	src.texture_region_size = Vector2i(info.tile_w, info.tile_h)
	src.separation = Vector2i(info.sep_x, info.sep_y)

	var img := tex.get_image()
	var cols: int = info.cols if info.cols > 0 else _grid_axis(img.get_width(), info.tile_w, info.sep_x)
	var rows: int = info.rows if info.rows > 0 else _grid_axis(img.get_height(), info.tile_h, info.sep_y)

	for y in rows:
		for x in cols:
			var c := Vector2i(x, y)
			if not _cell_opaque(img, c, info):
				continue
			if not src.has_tile(c):
				src.create_tile(c)


func _grid_axis(size: int, tile: int, sep: int) -> int:
	if tile <= 0:
		return 0
	var step := tile + sep
	if size <= tile:
		return 1
	return maxi(1, (size + sep) / step)


func _cell_opaque(img: Image, coord: Vector2i, info: Dictionary) -> bool:
	var work := img
	if work.is_compressed():
		work = work.duplicate()
		work.decompress()
	var step := Vector2i(info.tile_w + info.sep_x, info.tile_h + info.sep_y)
	var pos := Vector2i(coord.x * step.x, coord.y * step.y)
	var r := Rect2i(pos, Vector2i(info.tile_w, info.tile_h))
	if r.position.x + r.size.x > work.get_width() or r.position.y + r.size.y > work.get_height():
		return false
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if work.get_pixel(x, y).a > 0.01:
				return true
	return false


func _reimport_assets() -> void:
	OS.execute("godot", ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"], [], true)


func _count_tiles(ts: TileSet) -> int:
	var n := 0
	for i in ts.get_source_count():
		var src := ts.get_source(i) as TileSetAtlasSource
		if src:
			n += src.get_tiles_count()
	return n
