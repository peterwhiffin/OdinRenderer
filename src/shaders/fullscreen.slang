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
float4 fragMain(VSOutput input, float4 frag_coord: SV_Position)
{
	float3 color = tex.Sample(sampler, input.UV).rgb;

	if (post.enable_crt) {
		float2 uv = input.UV / 3.0;
		float4 coord = frag_coord;

		// float2 pixel_size = float2(3.0, 3.0);

		float p_norm = fmod(coord.x, post.pixel_size.x);
		float sub_pix_size_x = post.pixel_size.x / 3.0;
		float p_norm_y = fmod(coord.y, post.pixel_size.y);

		float r_thresh = sub_pix_size_x;
		float g_thresh = sub_pix_size_x * 2.0;
		float b_thresh = sub_pix_size_x * 3.0;

		float x_fade = post.fade.x;
		if (p_norm < r_thresh) {
			color = float3(color.r, 0.0, 0.0);
			float x_thresh = sub_pix_size_x * x_fade;
			float dist = abs(p_norm - (sub_pix_size_x * 0.5));
			float m = x_thresh - dist;
			color *= (m / x_thresh);
			color.r = max(color.r, post.min_brightness.r);
		} else if (p_norm < g_thresh) {
			color = float3(0.0, color.g, 0.0);
			float x_thresh = sub_pix_size_x * x_fade;
			float dist = abs((p_norm - (r_thresh)) - sub_pix_size_x * 0.5);
			float m = x_thresh - dist;
			color *= (m / x_thresh);
			color.b = max(color.b, post.min_brightness.b);
		} else {
			color = float3(0.0, 0.0, color.b);
			float x_thresh = sub_pix_size_x * x_fade;
			float dist = abs((p_norm - (g_thresh)) - sub_pix_size_x * 0.5);
			float m = x_thresh - dist;
			color *= (m / x_thresh);
			color.g = max(color.g, post.min_brightness.g);
		}

		float y_thres = post.pixel_size.y * post.fade.y;
		float dist = abs(p_norm_y - (post.pixel_size.y * 0.5));

		if (dist < y_thres) {
			float m = y_thres - dist;
			color *= 1.0 - (m / y_thres);
		}
	}

	return float4(color.rgb, 1.0);
}
