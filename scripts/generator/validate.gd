# agent: composer-2.5 | 2026-07-07 | setup mismatch validation | c4d5e6
extends RefCounted

const GenTmx := preload("res://scripts/generator/tmx.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")


static func validate_setup(
	manifest: Dictionary,
	rules: Dictionary = {},
	constraints: Dictionary = {},
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	_collect_manifest_errors(manifest, errors)
	_collect_atlas_errors(manifest, errors, warnings)
	_collect_tsx_errors(manifest, errors, warnings)
	_collect_map_errors(manifest, errors, warnings)

	if not rules.is_empty():
		_collect_rules_errors(manifest, rules, errors, warnings)
		if not constraints.is_empty():
			_collect_constraint_warnings(rules, constraints, warnings)

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}


static func first_error(report: Dictionary) -> String:
	var errors: Variant = report.get("errors", [])
	if errors is Array and not errors.is_empty():
		return str(errors[0])
	return ""


static func format_report(report: Dictionary) -> String:
	var lines: PackedStringArray = []
	for err in report.get("errors", []):
		lines.append("ERROR: %s" % err)
	for warn in report.get("warnings", []):
		lines.append("WARN: %s" % warn)
	if lines.is_empty():
		return "OK: no mismatches"
	return "\n".join(lines)


static func tsx_path(manifest: Dictionary) -> String:
	var src: String = str(manifest.get("tileset_src", ""))
	if src.is_empty():
		return ""
	var maps: Array = manifest.get("maps", [])
	if not maps.is_empty():
		return str(maps[0]).get_base_dir().path_join(src)
	var atlas: String = str(manifest.get("atlas", ""))
	if not atlas.is_empty():
		return atlas.get_base_dir().path_join(src)
	return src


static func read_tsx_meta(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var image_rx := RegEx.new()
	image_rx.compile("<image[^>]*width=\"(\\d+)\"[^>]*height=\"(\\d+)\"")
	var m := image_rx.search(text)
	var image_w := m.get_string(1).to_int() if m else 0
	var image_h := m.get_string(2).to_int() if m else 0
	return {
		"columns": _tsx_attr(text, "columns"),
		"tilecount": _tsx_attr(text, "tilecount"),
		"tilewidth": _tsx_attr(text, "tilewidth"),
		"tileheight": _tsx_attr(text, "tileheight"),
		"image_width": image_w,
		"image_height": image_h,
	}


static func atlas_image_size(manifest: Dictionary) -> Vector2i:
	var path: String = str(manifest.get("atlas", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return Vector2i.ZERO
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return Vector2i.ZERO
	return Vector2i(img.get_width(), img.get_height())


static func _collect_manifest_errors(manifest: Dictionary, errors: Array[String]) -> void:
	if manifest.is_empty():
		errors.append("manifest is empty")
		return
	if int(manifest.get("columns", 0)) <= 0 or int(manifest.get("rows", 0)) <= 0:
		errors.append("manifest missing columns/rows")
	if int(manifest.get("map_width", 0)) <= 0 or int(manifest.get("map_height", 0)) <= 0:
		errors.append("manifest missing map_width/map_height")
	var tc: int = int(manifest.get("tile_count", 0))
	var cols: int = int(manifest.get("columns", 0))
	var row_count: int = int(manifest.get("rows", 0))
	if tc > 0 and cols > 0 and row_count > 0 and tc != cols * row_count:
		errors.append("manifest tile_count %d != columns*rows %d" % [tc, cols * row_count])


static func _collect_atlas_errors(manifest: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var tile_size: Array = manifest.get("tile_size", [8, 8])
	var tw: int = int(tile_size[0]) if tile_size.size() > 0 else 8
	var th: int = int(tile_size[1]) if tile_size.size() > 1 else 8
	var cols: int = int(manifest.get("columns", 0))
	var row_count: int = int(manifest.get("rows", 0))
	var img_size := atlas_image_size(manifest)
	if img_size == Vector2i.ZERO:
		errors.append("atlas image missing or unreadable: %s" % manifest.get("atlas", ""))
		return
	var img_cols: int = img_size.x / tw
	var img_rows: int = img_size.y / th
	if img_cols != cols or img_rows != row_count:
		errors.append(
			"atlas image %dx%d px → %dx%d tiles but manifest says %dx%d"
			% [img_size.x, img_size.y, img_cols, img_rows, cols, row_count]
		)
	var tileset_path: String = str(manifest.get("tileset", ""))
	if tileset_path.is_empty() or not ResourceLoader.exists(tileset_path):
		warnings.append("Godot tileset resource missing: %s" % tileset_path)


static func _collect_tsx_errors(manifest: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var path := tsx_path(manifest)
	if path.is_empty():
		warnings.append("no tileset_src / maps path to locate .tsx")
		return
	if not FileAccess.file_exists(path):
		warnings.append("tsx missing: %s" % path)
		return
	var tsx := read_tsx_meta(path)
	if tsx.is_empty():
		warnings.append("tsx unreadable: %s" % path)
		return
	var cols: int = int(manifest.get("columns", 0))
	var row_count: int = int(manifest.get("rows", 0))
	var tc: int = int(manifest.get("tile_count", 0))
	if tsx.columns > 0 and tsx.columns != cols:
		errors.append("tsx columns=%d manifest columns=%d" % [tsx.columns, cols])
	if tsx.tilecount > 0 and tc > 0 and tsx.tilecount != tc:
		errors.append("tsx tilecount=%d manifest tile_count=%d" % [tsx.tilecount, tc])
	var tile_size: Array = manifest.get("tile_size", [8, 8])
	var tw: int = int(tile_size[0]) if tile_size.size() > 0 else 8
	var th: int = int(tile_size[1]) if tile_size.size() > 1 else 8
	if tsx.image_width > 0 and tsx.image_height > 0:
		if tsx.image_width / tw != cols or tsx.image_height / th != row_count:
			errors.append(
				"tsx image %dx%d does not match manifest grid %dx%d @ %dx%d px"
				% [tsx.image_width, tsx.image_height, cols, row_count, tw, th]
			)


static func _collect_map_errors(manifest: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var maps: Array = manifest.get("maps", [])
	if maps.is_empty():
		warnings.append("manifest has no reference maps")
		return
	var map := GenTmx.read_map(str(maps[0]))
	if map.is_empty():
		errors.append("reference map unreadable: %s" % maps[0])
		return
	var mw: int = int(manifest.get("map_width", 0))
	var mh: int = int(manifest.get("map_height", 0))
	if map.width != mw or map.height != mh:
		errors.append(
			"map.tmx size %dx%d != manifest map %dx%d"
			% [map.width, map.height, mw, mh]
		)
	var first_gid: int = int(manifest.get("first_gid", 1))
	var max_gid := 0
	for gid in map.gids:
		var g: int = gid & 0x1FFFFFFF
		if g >= first_gid and g > max_gid:
			max_gid = g
	var tc: int = int(manifest.get("tile_count", 0))
	if tc > 0 and max_gid >= first_gid + tc:
		errors.append("map uses GID %d but tile_count is %d" % [max_gid, tc])


static func _collect_rules_errors(
	manifest: Dictionary,
	rules: Dictionary,
	errors: Array[String],
	warnings: Array[String],
) -> void:
	if int(rules.get("version", 0)) < 3:
		warnings.append("rules version %s is stale (expected v3+ with grid)" % rules.get("version", 0))
	var grid: Variant = rules.get("grid", {})
	if grid is Dictionary and grid.has("columns"):
		var cols: int = int(manifest.get("columns", 0))
		if int(grid.get("columns", 0)) != cols:
			errors.append("rules grid.columns mismatch manifest (re-analyze)")
		if int(grid.get("rows", 0)) != int(manifest.get("rows", 0)):
			errors.append("rules grid.rows mismatch manifest (re-analyze)")
		if int(grid.get("map_width", 0)) != int(manifest.get("map_width", 0)):
			errors.append("rules map_width mismatch manifest (re-analyze)")
		if int(grid.get("map_height", 0)) != int(manifest.get("map_height", 0)):
			errors.append("rules map_height mismatch manifest (re-analyze)")
	else:
		warnings.append("rules missing grid metadata (re-analyze)")

	var first_gid: int = int(manifest.get("first_gid", 1))
	var tc: int = int(manifest.get("tile_count", 0))
	for k in rules.get("tile_weights", {}):
		var gid := int(k)
		if gid < first_gid or (tc > 0 and gid >= first_gid + tc):
			warnings.append("rules references out-of-range GID %d" % gid)
			break

	var analyze: Dictionary = manifest.get("analyze", {})
	if analyze.get("tileset_edges", false) and not rules.get("sources", {}).get("tileset_edges", false):
		warnings.append("manifest analyze.tileset_edges=true but rules lack tileset_edges source (re-analyze)")


static func _collect_constraint_warnings(
	rules: Dictionary,
	constraints: Dictionary,
	warnings: Array[String],
) -> void:
	var sig_adj: Dictionary = rules.get("sig_adjacency", {})
	var gid_to_sig: Dictionary = rules.get("gid_to_sig", {})
	for i in constraints.modes.size():
		if constraints.modes[i] != GenConstraints.Mode.FIXED:
			continue
		var gid: int = constraints.fixed_gids[i]
		if gid <= 0:
			continue
		if not sig_adj.is_empty():
			var sig: String = str(gid_to_sig.get(str(gid), ""))
			if sig.is_empty():
				warnings.append("fixed tile GID %d has no signature in rules" % gid)
				continue
			if not sig_adj.has(sig):
				warnings.append("fixed tile GID %d signature missing from sig_adjacency" % gid)
			continue
		var key := str(gid)
		var adjacency: Dictionary = rules.get("adjacency", {})
		if not adjacency.has(key):
			warnings.append(
				"fixed tile GID %d not in rules adjacency (unknown to reference map)" % gid
			)
			continue
		var node: Variant = adjacency[key]
		if node is Dictionary:
			var empty_dirs: Array[String] = []
			for d in GenTmx.DIRS:
				var bucket: Variant = node.get(d, {})
				if bucket is Dictionary and bucket.is_empty():
					empty_dirs.append(d)
			if empty_dirs.size() == 4:
				warnings.append("fixed tile GID %d has no adjacency data in rules" % gid)


static func _tsx_attr(text: String, name: String) -> int:
	var rx := RegEx.new()
	rx.compile("%s=\"(\\d+)\"" % name)
	var m := rx.search(text)
	return m.get_string(1).to_int() if m else 0
