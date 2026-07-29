struct VSInput {
	float3 Pos;
	float3 norm;
	float2 UV;
};

struct per_frame_uniforms {
	float4x4 proj;
	float4x4 view;
	float4 light_dir;
	float4 light_color;
	float ambient;
};

struct entity {
	float4x4 model;
	float4x4 normal_matrix;
	float4 color;
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

[[vk::binding(0, 1)]]
ConstantBuffer<entity> ebuf;

// [[vk::binding(1, 0)]]
// ConstantBuffer<material> materials[];

[shader("vertex")]
VSOutput vertMain(VSInput input, uniform push_const pc, uint inst: SV_InstanceID)
{
	per_frame_uniforms *pfu = pc.pfu;
	VSOutput output;
	output.Pos = mul(pfu.proj, mul(pfu.view, mul(ebuf.model, float4(input.Pos.xyz, 1.0))));
	output.Norm = mul(float3x3(ebuf.normal_matrix), input.norm);
	output.UV = input.UV;
	output.light_dir = pfu.light_dir.xyz;
	// output.frag_pos =
	output.frag_pos = mul(ebuf.model, float4(input.Pos, 1.0)).xyz;
	return output;
}

float sd_circle(float2 v, float r)
{
	return length(v) - r;
}

[shader("fragment")]
float4 fragMain(VSOutput input, uniform push_const pc)
{
	float4 diffuse_color = tex[pc.tex_index].Sample(sampler, input.UV);

	if (diffuse_color.a < 0.3f)
		discard;

	diffuse_color *= ebuf.color;
	float3 ambient = diffuse_color.rgb * pc.pfu.ambient;
	float3 final_color = float3(0.0);

	float3 norm = normalize(input.Norm);
	float3 albedo = diffuse_color.rgb;
	float3 direction = normalize(-input.light_dir);
	float diff = max(dot(norm, direction), 0.0);

	final_color = albedo * pc.pfu.light_color.rgb * pc.pfu.light_color.a * diff + ambient;

	return float4(final_color.rgb, ebuf.color.a);
}
