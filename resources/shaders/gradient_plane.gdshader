// agent: composer-2.5 | 2026-07-11 | gradient plane shader | e1ca94
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 color_a : source_color = vec4(0.05, 0.08, 0.14, 1.0);
uniform vec4 color_b : source_color = vec4(0.2, 0.35, 0.55, 1.0);
uniform vec2 gradient_direction = vec2(0.0, 1.0);
uniform float sharpness : hint_range(0.1, 50.0, 0.1) = 2.0;

void fragment() {
	vec2 dir = gradient_direction;
	float dir_len = length(dir);
	if (dir_len > 0.0001) {
		dir /= dir_len;
	}

	float t = dot(UV - vec2(0.5), dir) + 0.5;
	t = clamp(t, 0.0, 1.0);
	float edge = 0.5 / sharpness;
	float blend = smoothstep(0.5 - edge, 0.5 + edge, t);
	vec4 color = mix(color_a, color_b, blend);
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
