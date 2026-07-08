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
	var manifest := {
		"pack": "adve",
		"tile_size": [TILE_SIZE.x, TILE_SIZE.y],
		"columns": columns,
		"rows": rows,
		"first_gid": 1,
		"source_id": 0,
		"atlas": ATLAS_PATH,
		"tileset": TILESET_PATH,
		"tileset_src": "tiles.tsx",
		"maps": [MAP_PATH],
		"rules": "res://resources/generator/adve.rules.json",
		"tile_count": tile_count,
		"map_width": map_meta.width,
		"map_height": map_meta.height,
		"analyze": {
			"alias_auto": true,
			"alias_max_class_size": 4,
			"alias_max_col_distance": 1,
			"alias_max_row_distance": 1,
			"alias_threshold": 0.85,
			"color_quantize": 24,
			"edge_gap_max_neighbors": 8,
			"edge_match": "exact",
			"edge_quantize": 32,
			"maps": true,
			"min_adj_count": 1,
			"save_topology": false,
			"tileset_edges": true,
			"tileset_edges_weight": 1,
			"trim_self_adj": true,
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
