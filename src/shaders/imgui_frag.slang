struct VSOutput {
	float4 pos : SV_POSITION;
	float4 color;
	float2 uv;
};

[[vk::binding(0, 0)]]
Texture2D<float4> tex;

[[vk::binding(0, 1)]]
SamplerState sampler;

[shader("fragment")]
float4 main(VSOutput input, float4 coord: SV_Position)
{
	float4 color = input.color * tex.Sample(sampler, input.uv);
	return color;
}
