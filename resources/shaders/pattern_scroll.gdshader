// agent: composer-2.5 | 2026-07-11 | texture scale uniform | 97d861
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D pattern_texture : filter_linear, repeat_enable;
uniform vec2 texture_scale = vec2(1.0, 1.0);
uniform vec2 scroll_direction = vec2(1.0, 0.0);
uniform float scroll_speed : hint_range(-2.0, 2.0, 0.01) = 0.05;
uniform vec4 color_a : source_color = vec4(0.12, 0.18, 0.32, 1.0);
uniform vec4 color_b : source_color = vec4(0.45, 0.62, 0.95, 0.35);

void fragment() {
	vec2 uv = UV * texture_scale + scroll_direction * scroll_speed * TIME;
	float pattern = texture(pattern_texture, uv).r;
	vec4 color = mix(color_a, color_b, pattern);
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
