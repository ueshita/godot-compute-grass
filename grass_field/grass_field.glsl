#[compute]
#version 450

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Our textures.
layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D current_image;
layout(rgba16f, set = 1, binding = 0) uniform restrict readonly image2D previous_image;
layout(rgba16f, set = 2, binding = 0) uniform restrict writeonly image2D output_image;

// Our push PushConstant.
layout(push_constant, std430) uniform Params {
	vec3 collider_position;
	float collider_radius;
	vec2 texture_size;
	float damp;
	float delta;
} params;

// The code we want to execute in each invocation.
void main() {
	ivec2 tl = ivec2(0, 0);
	ivec2 size = ivec2(params.texture_size.x - 1, params.texture_size.y - 1);
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the texture size is not divisable by 8.
	if ((uv.x > size.x) || (uv.y > size.y)) {
		return;
	}

	float current_v = imageLoad(current_image, uv).r;
	float side_y1_v = imageLoad(current_image, clamp(uv - ivec2(0, 1), tl, size)).r;
	float side_y2_v = imageLoad(current_image, clamp(uv + ivec2(0, 1), tl, size)).r;
	float side_x1_v = imageLoad(current_image, clamp(uv - ivec2(1, 0), tl, size)).r;
	float side_x2_v = imageLoad(current_image, clamp(uv + ivec2(1, 0), tl, size)).r;
	float previous_v = imageLoad(previous_image, uv).r;

    float grad_x = (side_x1_v.x - side_x2_v.x) * 1.0;
    float grad_y = (side_y1_v.x - side_y2_v.x) * 1.0;

	float intensity = current_v;
	vec3 position = vec3(vec2(uv) / vec2(size) * 2.0 - 1.0, 0.0);
	position = position.xzy;
	vec3 diff = params.collider_position - position;
	float dist = length(diff);
	if (dist <= params.collider_radius) {
		intensity = (params.collider_radius - dist) * 100.0;
	}
	
    float diffusion_v = (intensity + side_y1_v + side_y2_v + side_x1_v + side_x2_v) * 0.2;
    float velocity = (current_v - previous_v) * 0.95;
    float accel = (diffusion_v - current_v);
    float next_v = current_v + velocity + accel * params.delta * 10.0;

    vec4 result = vec4(next_v, grad_x, grad_y, 0.0);

	if (result.x < 0.0) {
		result.x = 0.0;
	}
	
	imageStore(output_image, uv, result);
}
