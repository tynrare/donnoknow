extends SceneTree

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const TILESET_PATH := "res://resources/adve.tileset.tres"
const ATLAS_PATH := "res://assets/tiles/adve/tiles.png"
const TILE_SIZE := Vector2i(8, 8)
const COLUMNS := 16
const ROWS := 16


func _init() -> void:
	_import()
	quit()


func _import() -> void:
	var tex := load(ATLAS_PATH) as Texture2D
	if tex == null:
		push_error("Missing atlas: %s" % ATLAS_PATH)
		return

	var tileset := TileSet.new()
	tileset.tile_size = TILE_SIZE
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = TILE_SIZE
	tileset.add_source(src, 0)

	for y in ROWS:
		for x in COLUMNS:
			src.create_tile(Vector2i(x, y))

	var err := ResourceSaver.save(tileset, TILESET_PATH)
	if err != OK:
		push_error("Save failed: %s" % error_string(err))
		return

	var manifest := {
		"pack": "adve",
		"tile_size": [TILE_SIZE.x, TILE_SIZE.y],
		"columns": COLUMNS,
		"first_gid": 1,
		"source_id": 0,
		"atlas": ATLAS_PATH,
		"tileset": TILESET_PATH,
		"tileset_src": "tiles.tsx",
		"maps": ["res://assets/tiles/adve/map.tmx"],
		"rules": "res://resources/generator/adve.rules.json",
		"tile_count": COLUMNS * ROWS,
		"rows": ROWS,
	}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/tiles/adve"))
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))

	print("Saved %s (%d tiles) and %s" % [TILESET_PATH, COLUMNS * ROWS, MANIFEST_PATH])
