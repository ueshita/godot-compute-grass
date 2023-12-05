shader_type spatial;
render_mode cull_back;
render_mode skip_vertex_transform;

uniform vec2 effect_texture_size;
uniform sampler2D effect_texture : filter_linear, repeat_enable;
uniform sampler2D noise_texture : filter_linear, repeat_enable;

void vertex() {
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec2 pixel_size = vec2(1.0, 1.0) / effect_texture_size;
	vec2 uv = vec2(pos.x / 10.0, pos.z / 10.0) + 0.5;
	vec2 uv_t = uv + vec2(pixel_size.x, 0.0);
	vec2 uv_b = uv + vec2(0.0, pixel_size.y);
	
	vec2 grad = texture(effect_texture, uv).yz;
	float noise = texture(noise_texture, uv + vec2(TIME * 0.05, 0.0)).r;
	grad.x += (noise * 2.0 - 1.0) * 0.5;
	
	float wind_ratio = VERTEX.y * 0.2;
	vec3 wind_force = vec3(grad.x, 0.0, grad.y) * 1.0;

	VERTEX = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += wind_force * wind_ratio;
	VERTEX = (VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);	
}

void fragment() {
	ALBEDO = vec3(0.3, 0.8, 0.3);
}
