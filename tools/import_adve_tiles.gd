extends SceneTree

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const TILESET_PATH := "res://resources/adve.tileset.tres"
const ATLAS_PATH := "res://assets/tiles/adve/tiles.png"
const MAP_PATH := "res://assets/tiles/adve/map.tmx"
const TILE_SIZE := Vector2i(8, 8)


func _init() -> void:
	_import()
	quit()


func _import() -> void:
	var tex := load(ATLAS_PATH) as Texture2D
	if tex == null:
		push_error("Missing atlas: %s" % ATLAS_PATH)
		return

	var columns: int = tex.get_width() / TILE_SIZE.x
	var rows: int = tex.get_height() / TILE_SIZE.y
	var tile_count: int = columns * rows

	var tileset := TileSet.new()
	tileset.tile_size = TILE_SIZE
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = TILE_SIZE
	tileset.add_source(src, 0)

	for y in rows:
		for x in columns:
			src.create_tile(Vector2i(x, y))

	var err := ResourceSaver.save(tileset, TILESET_PATH)
	if err != OK:
		push_error("Save failed: %s" % error_string(err))
		return

	var map_meta := _read_map_size(MAP_PATH)
	# agent: composer-2.5 | 2026-07-10 | slim import manifest | 86051f
	var manifest := {
		"atlas": ATLAS_PATH,
		"background_gid": 1,
		"tileset": TILESET_PATH,
		"tileset_src": "tiles.tsx",
		"maps": [MAP_PATH],
		"rules": "res://resources/generator/adve.rules.json",
		"analyze": {
			"tileset_edges": true,
			"min_adj_count": 2,
		},
	}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/tiles/adve"))
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))

	print(
		"Saved %s (%dx%d=%d tiles) map=%dx%d manifest=%s"
		% [TILESET_PATH, columns, rows, tile_count, map_meta.width, map_meta.height, MANIFEST_PATH]
	)


func _read_map_size(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var rx := RegEx.new()
	rx.compile("width=\"(\\d+)\"")
	var m := rx.search(text)
	var width: int = m.get_string(1).to_int() if m else 0
	rx.compile("height=\"(\\d+)\"")
	m = rx.search(text)
	var height: int = m.get_string(1).to_int() if m else 0
	return {"width": width, "height": height}
