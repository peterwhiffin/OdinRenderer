struct VSInput {
	float3 Pos;
	float3 norm;
	float2 UV;
};

struct per_frame_uniforms {
	float4x4 proj;
	float4x4 view;
	float4x4 model;
};

struct entity {
	float4x4 model;
	float4x4 normal_matrix;
};

struct VSOutput {
	float4 Pos : SV_POSITION;
	float3 Norm;
	float2 UV;
	float3 frag_pos;
	nointerpolation float3 cam_pos;
	nointerpolation float3 light_dir;
};

struct push_const {
	per_frame_uniforms *pfu;
	uint32_t tex_index;
};

struct material {
	float specular_power;
};

// vk::binding(binding, set)
[[vk::binding(0, 0)]]
Texture2D<float4> tex[];

[[vk::binding(1, 0)]]
SamplerState sampler;

// [[vk::binding(1, 0)]]
// ConstantBuffer<material> materials[];

// [[vk::binding(0, 1)]]
// ConstantBuffer<entity> ebuf;

[shader("vertex")]
VSOutput vertMain(VSInput input, uniform push_const pc)
{
	per_frame_uniforms *pfu = pc.pfu;
	VSOutput output;
	output.Pos = mul(pfu.proj, mul(pfu.view, mul(pfu.model, float4(input.Pos.xyz, 1.0))));
	output.Norm = normalize(input.norm);
	output.UV = input.UV;
	output.light_dir = float3(0.2, -1.0, 0.0);
	return output;
}

float sd_circle(float2 v, float r)
{
	return length(v) - r;
}

[shader("fragment")]
float4 fragMain(VSOutput input, uniform push_const pc)
{
	// per_frame_uniforms *pfu = pc.pfu;
	float4 diffuse_color = tex[pc.tex_index].Sample(sampler, input.UV);
	// float4 diffuse_color = float4(1.0, 0.0, 1.0, 1.0);

	if (diffuse_color.a < 0.3f)
		discard;

	float3 ambient = mul(diffuse_color.rgb, 0.02);
	float3 final_color = float3(0.0);

	float3 norm = normalize(input.Norm);
	float3 albedo = diffuse_color.rgb;
	float3 direction = normalize(-input.light_dir);
	float diff = max(dot(norm, direction), 0.0);

	final_color = albedo * diff + ambient;

	// float3 N = normalize(input.Norm);
	// float3 L = normalize(input.light_dir);
	// float3 V = normalize(-input.frag_pos);
	// float3 R = reflect(-L, N);
	// float3 diffuse = max(dot(N, L), 0.0025);
	// float3 specular = pow(max(dot(R, V), 0.0), 16.0) * 0.75;
	//
	// final_color = diffuse * diffuse_color.rgb + specular;

	return float4(final_color.rgb, 1.0);
}
