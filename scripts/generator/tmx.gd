extends RefCounted

const DIRS := ["north", "east", "south", "west"]


static func read_map(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var width := _attr_int(text, "width")
	var height := _attr_int(text, "height")
	var tile_w := _attr_int(text, "tilewidth")
	var tile_h := _attr_int(text, "tileheight")
	var first_gid := 1
	var ts := RegEx.new()
	ts.compile("<tileset[^>]*firstgid=\"(\\d+)\"")
	var m := ts.search(text)
	if m:
		first_gid = m.get_string(1).to_int()

	var data_rx := RegEx.new()
	data_rx.compile("<data[^>]*>([\\s\\S]*?)</data>")
	m = data_rx.search(text)
	if m == null:
		push_error("TMX has no layer data: %s" % path)
		return {}

	var nums: PackedInt32Array = []
	for part in m.get_string(1).split(","):
		var s := part.strip_edges()
		if s.is_empty():
			continue
		nums.append(s.to_int())

	if nums.size() != width * height:
		push_error("TMX size mismatch %s: got %d expected %d" % [path, nums.size(), width * height])
		return {}

	return {
		"path": path,
		"width": width,
		"height": height,
		"tile_size": Vector2i(tile_w, tile_h),
		"first_gid": first_gid,
		"gids": nums,
	}


static func write_map(path: String, meta: Dictionary, gids: PackedInt32Array) -> Error:
	var width: int = meta.width
	var height: int = meta.height
	var tile_w: int = meta.get("tile_size", Vector2i(8, 8)).x
	var tile_h: int = meta.get("tile_size", Vector2i(8, 8)).y
	var first_gid: int = meta.get("first_gid", 1)
	var tileset_src: String = meta.get("tileset_src", "tiles.tsx")

	var lines: PackedStringArray = []
	for y in height:
		var row: PackedStringArray = []
		for x in width:
			row.append(str(gids[y * width + x]))
		lines.append(",".join(row) + ("," if y < height - 1 else ""))

	var body := """<?xml version="1.0" encoding="UTF-8"?>
<map version="1.4" tiledversion="1.4.1" orientation="orthogonal" renderorder="right-down" width="%d" height="%d" tilewidth="%d" tileheight="%d" infinite="0">
 <tileset firstgid="%d" source="%s"/>
 <layer id="1" name="Tile Layer 1" width="%d" height="%d">
  <data encoding="csv">
%s
  </data>
 </layer>
</map>
""" % [width, height, tile_w, tile_h, first_gid, tileset_src, width, height, "\n".join(lines)]

	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(body)
	return OK


static func _attr_int(text: String, name: String) -> int:
	var rx := RegEx.new()
	rx.compile("%s=\"(\\d+)\"" % name)
	var m := rx.search(text)
	return m.get_string(1).to_int() if m else 0
