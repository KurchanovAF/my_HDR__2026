struct VS_OUTPUT
{
    float4 Pos : SV_POSITION; 
    float2 Tex : TEXCOORD0;   
};

VS_OUTPUT VS(float4 Pos : POSITION, float2 Tex : TEXCOORD)
{
    VS_OUTPUT output = (VS_OUTPUT)0;
    output.Pos = Pos;
    output.Tex = Tex;
    return output;
}

Texture2D shaderTexture : register(t0);

// ИСПРАВЛЕНО: Явно назвали сэмплер для строгого соответствия регистру s0
SamplerState samplerState0 : register(s0);

float4 PS(VS_OUTPUT input) : SV_Target
{
    float2 texo = input.Tex;
    texo.y = texo.y / 2.0f; 

    float2 tex_dy = float2(0.0f, 0.5f);

    // ИСПРАВЛЕНО: Используем сэмплер samplerState0
    float4 k0 = shaderTexture.Sample(samplerState0, texo);
    float4 k1 = shaderTexture.Sample(samplerState0, texo + tex_dy);

    float4 k = (k0 + k1) / 2.0f;
    k = k + 0.0001f; 

    return k; 
}
