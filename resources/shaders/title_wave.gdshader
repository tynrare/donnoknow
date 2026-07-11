// agent: composer-2.5 | 2026-07-11 | fix wave depth write | da9c7a
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;

group_uniforms Wave;
uniform int wave_axis : hint_enum("Vertical", "Horizontal", "Z") = 0;
uniform float wave_amplitude : hint_range(0.0, 1.0, 0.001) = 0.04;
uniform float wave_frequency : hint_range(0.0, 50.0, 0.1) = 10.0;
uniform float wave_speed : hint_range(-10.0, 10.0, 0.01) = 1.5;
uniform float phase_offset : hint_range(-6.283, 6.283, 0.01) = 0.0;
uniform vec2 position_axis = vec2(1.0, 0.0);

void vertex() {
	vec3 n = NORMAL;
	vec3 perturbed = n;

	vec2 axis = position_axis;
	float axis_len = length(axis);
	if (axis_len > 0.0001) {
		axis /= axis_len;
	} else {
		axis = vec2(1.0, 0.0);
	}

	float pos = 0.0;
	float t = 0.0;
	float wave = 0.0;
	float slope = 0.0;

	if (wave_axis == 0) {
		pos = dot(VERTEX.xz, axis);
		t = pos * wave_frequency + TIME * wave_speed + phase_offset;
		wave = sin(t) * wave_amplitude;
		VERTEX.y += wave;
		slope = cos(t) * wave_amplitude * wave_frequency;
		float hx = slope * axis.x;
		float hz = slope * axis.y;
		perturbed = vec3(n.x - hx * n.y, n.y, n.z - hz * n.y);
	} else if (wave_axis == 1) {
		pos = dot(VERTEX.yz, axis);
		t = pos * wave_frequency + TIME * wave_speed + phase_offset;
		wave = sin(t) * wave_amplitude;
		VERTEX.x += wave;
		slope = cos(t) * wave_amplitude * wave_frequency;
		float hy = slope * axis.x;
		float hz = slope * axis.y;
		perturbed = vec3(n.x, n.y - hy * n.x - hz * n.z, n.z);
	} else {
		pos = dot(VERTEX.xy, axis);
		t = pos * wave_frequency + TIME * wave_speed + phase_offset;
		wave = sin(t) * wave_amplitude;
		VERTEX.z += wave;
		slope = cos(t) * wave_amplitude * wave_frequency;
		float hx = slope * axis.x;
		float hy = slope * axis.y;
		perturbed = vec3(n.x, n.y, n.z - hx * n.x - hy * n.y);
	}

	perturbed = normalize(perturbed);
	if (dot(perturbed, n) < 0.0) {
		perturbed = -perturbed;
	}
	NORMAL = perturbed;
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
