extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenTmx := preload("res://scripts/generator/tmx.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const OUT_PATH := "res://assets/tiles/adve/generated.tmx"


func _init() -> void:
	var args := _parse_args()
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	if manifest.is_empty():
		push_error("Missing manifest. Run tools/import_adve_tiles.gd first.")
		quit(1)
		return

	var rules := GenRules.load(manifest.get("rules", ""))
	if rules.is_empty():
		push_error("Missing rules. Run tools/analyze_maps.gd first.")
		quit(1)
		return

	var ref := GenTmx.read_map(manifest.maps[0])
	var width: int = args.get("width", ref.width)
	var height: int = args.get("height", ref.height)
	var seed: int = args.get("seed", 0)
	var out_path: String = args.get("out", OUT_PATH)

	var constraints := GenConstraints.empty(width, height)
	var result := GenService.generate(manifest, rules, constraints, seed)
	if not result.ok:
		push_error("Generate failed: %s (after %d attempts)" % [result.get("error", "?"), result.get("attempts", 0)])
		quit(1)
		return

	var meta := {
		"width": width,
		"height": height,
		"tile_size": Vector2i(manifest.tile_size[0], manifest.tile_size[1]),
		"first_gid": manifest.get("first_gid", 1),
		"tileset_src": manifest.get("tileset_src", "tiles.tsx"),
	}
	var err := GenTmx.write_map(out_path, meta, result.gids)
	if err != OK:
		push_error("Write failed: %s" % error_string(err))
		quit(1)
		return

	print("Generated %s (%dx%d) seed=%d attempts=%d" % [
		out_path, width, height, result.seed, result.attempts,
	])
	quit()


func _parse_args() -> Dictionary:
	var out := {"seed": 0}
	for i in OS.get_cmdline_user_args().size():
		var a: String = OS.get_cmdline_user_args()[i]
		if a == "--seed" and i + 1 < OS.get_cmdline_user_args().size():
			out.seed = OS.get_cmdline_user_args()[i + 1].to_int()
		elif a == "--width" and i + 1 < OS.get_cmdline_user_args().size():
			out.width = OS.get_cmdline_user_args()[i + 1].to_int()
		elif a == "--height" and i + 1 < OS.get_cmdline_user_args().size():
			out.height = OS.get_cmdline_user_args()[i + 1].to_int()
		elif a == "--out" and i + 1 < OS.get_cmdline_user_args().size():
			out.out = OS.get_cmdline_user_args()[i + 1]
	return out
