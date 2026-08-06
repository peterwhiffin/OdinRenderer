struct VSInput {
	float2 pos;
	float2 uv;
	float4 color;
};

struct VSOutput {
	float4 pos : SV_POSITION;
	float4 color;
	float2 uv;
};

struct push_constants {
	float2 scale;
	float2 translate;
}

[shader("vertex")]
VSOutput main(VSInput input, uint vertex_id: SV_VertexID, uniform push_constants pc)
{
	VSOutput out;
	out.color = input.color;
	out.uv = input.uv;
	out.pos = float4(input.pos * pc.scale + pc.translate, 0, 1);
	return out;
}

