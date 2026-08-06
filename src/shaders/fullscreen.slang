struct VSOutput {
	float4 Pos : SV_POSITION;
	float2 UV;
};

struct Post_Settings {
	float2 pixel_size;
	float2 fade;
	float4 min_brightness;
	bool enable_crt;
};

// vk::binding(binding, set)
[[vk::binding(0, 0)]]
Texture2D<float4> tex;

[[vk::binding(1, 0)]]
SamplerState sampler;

[[vk::binding(2, 0)]]
ConstantBuffer<Post_Settings> post;

[shader("vertex")]
VSOutput vertMain(uint vertex_id: SV_VertexID)
{
	float2 pos[3] = {
		float2(-1.0, -1.0),
		float2(3.0, -1.0),
		float2(-1.0, 3.0),
	};

	VSOutput output;
	output.Pos = float4(pos[vertex_id], 0.0, 1.0);
	output.UV = pos[vertex_id] * 0.5 + 0.5;
	return output;
}

[shader("fragment")]
float4 fragMain(VSOutput input, float4 coord: SV_Position)
{
	float3 color = tex.Sample(sampler, input.UV).rgb;

	if (post.enable_crt) {
		float sub_pix_size = post.pixel_size.x / 3.0;
		float sub_pix_x = fmod(coord.x, post.pixel_size.x);
		float pix_y = fmod(coord.y, post.pixel_size.y);

		float r_thresh = sub_pix_size;
		float g_thresh = sub_pix_size * 2.0;
		float b_thresh = sub_pix_size * 3.0;

		float r_step = step(sub_pix_x, r_thresh);
		float g_step = step(sub_pix_x, g_thresh) - r_step;
		float b_step = step(sub_pix_x, b_thresh) - r_step - g_step;

		float x_fade = post.fade.x;
		float dist_offset = sub_pix_x - sub_pix_size * 0.5;
		sub_pix_size *= x_fade;

		float m = sub_pix_size - abs(dist_offset);
		color.r *= (m / (sub_pix_size * x_fade)) * r_step;

		m = sub_pix_size - abs(dist_offset - r_thresh);
		color.g *= (m / (sub_pix_size * x_fade)) * g_step;

		m = sub_pix_size - abs(dist_offset - g_thresh);
		color.b *= (m / (sub_pix_size * x_fade)) * b_step;

		float y_thresh = post.pixel_size.y * post.fade.y;
		float dist = abs(pix_y - post.pixel_size.y * 0.5);

		m = y_thresh - dist;
		color *= 1.0 - (m / y_thresh);
	}

	return float4(color.rgb, 1.0);
}
