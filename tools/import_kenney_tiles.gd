# agent: composer-2.5 | 2026-07-06 | kenney tile import | 491da9
extends SceneTree

const SRC := "/home/x/Downloads/kenney_pixel-platformer"
const OUT := "res://assets/tiles/kenney"
const TILESET_PATH := "res://resources/platformer.tileset.tres"
const TILE := 18
const MERGE := false


func _init() -> void:
	_import()
	quit()


func _import() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/sources"))
	var sheets := _collect_sheets()
	if sheets.is_empty():
		push_error("No Kenney packed tilemaps found in %s" % SRC)
		return

	_reimport_assets()

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)

	if MERGE:
		var atlas_path := _merge(sheets)
		_reimport_assets()
		_add_atlas(tileset, 0, atlas_path)
	else:
		for i in sheets.size():
			_add_atlas(tileset, i, sheets[i].path)

	var err := ResourceSaver.save(tileset, TILESET_PATH)
	if err != OK:
		push_error("Failed to save tileset: %s" % error_string(err))
	else:
		print("Saved %s (%d sources, %d tiles)" % [TILESET_PATH, tileset.get_source_count(), _count_tiles(tileset)])


func _collect_sheets() -> Array:
	var sheets: Array = []
	var root := DirAccess.open(SRC)
	if root == null:
		return sheets
	for pack in root.get_directories():
		var tile_dir := SRC.path_join(pack).path_join("Tilemap")
		if not DirAccess.dir_exists_absolute(tile_dir):
			continue
		var dir := DirAccess.open(tile_dir)
		for file_name in dir.get_files():
			if not file_name.ends_with("_packed.png"):
				continue
			var src_path := tile_dir.path_join(file_name)
			var dst_rel := OUT + "/sources/" + pack + "_" + file_name
			DirAccess.copy_absolute(src_path, ProjectSettings.globalize_path(dst_rel))
			sheets.append({"path": dst_rel, "pack": pack, "name": file_name.get_basename()})
	sheets.sort_custom(func(a, b): return a.path < b.path)
	return sheets


func _merge(sheets: Array) -> String:
	var cols := 4
	var cell := Vector2i(TILE * 9, TILE * 9)
	var rows := ceili(float(sheets.size()) / float(cols))
	var out := Image.create(cols * cell.x, rows * cell.y, false, Image.FORMAT_RGBA8)
	var manifest: Array = []
	for i in sheets.size():
		var s: Dictionary = sheets[i]
		var img := Image.load_from_file(ProjectSettings.globalize_path(s.path))
		var ox := (i % cols) * cell.x
		var oy := (i / cols) * cell.y
		out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(ox, oy))
		manifest.append({"pack": s.pack, "name": s.name, "offset": [ox, oy]})
	var atlas_path := OUT + "/atlas_merged.png"
	out.save_png(ProjectSettings.globalize_path(atlas_path))
	var f := FileAccess.open(OUT + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	return atlas_path


func _reimport_assets() -> void:
	OS.execute("godot", ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"], [], true)


func _add_atlas(ts: TileSet, id: int, tex_path: String) -> void:
	var tex := load(tex_path) as Texture2D
	if tex == null:
		push_error("Missing texture: %s" % tex_path)
		return
	var img := tex.get_image()
	var src := TileSetAtlasSource.new()
	src.texture_region_size = Vector2i(TILE, TILE)
	src.separation = Vector2i.ZERO
	src.texture = tex
	ts.add_source(src, id)
	var grid := src.get_atlas_grid_size()
	for y in grid.y:
		for x in grid.x:
			var c := Vector2i(x, y)
			if _cell_opaque(img, c):
				src.create_tile(c)


func _cell_opaque(img: Image, c: Vector2i) -> bool:
	var work := img
	if work.is_compressed():
		work = work.duplicate()
		work.decompress()
	var r := Rect2i(c * TILE, Vector2i(TILE, TILE))
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if work.get_pixel(x, y).a > 0.01:
				return true
	return false


func _count_tiles(ts: TileSet) -> int:
	var n := 0
	for i in ts.get_source_count():
		var src := ts.get_source(i) as TileSetAtlasSource
		if src:
			n += src.get_tiles_count()
	return n
