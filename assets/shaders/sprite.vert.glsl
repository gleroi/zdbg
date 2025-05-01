#version 450

struct SpriteData
{
    vec3 Position;
    float Rotation;
    vec2 Scale;
    vec2 Padding;
    float TexU;
    float TexV;
    float TexW;
    float TexH;
    vec4 Color;
};

const uint triangleIndices[6] = uint[](0u, 1u, 2u, 3u, 2u, 1u);
const vec2 vertexPos[4] = vec2[](vec2(0.0), vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(1.0));

layout(binding = 0, std430) readonly buffer type_StructuredBuffer_SpriteData
{
    SpriteData sprites[];
} DataBuffer;

layout(binding = 0, std140) uniform type_UniformBlock
{
    layout(row_major) mat4 ViewProjectionMatrix;
} UniformBlock;

layout(location = 0) out vec2 out_texCoord;
layout(location = 1) out vec4 out_Color;

mat4 spvWorkaroundRowMajor(mat4 wrap) { return wrap; }

void main()
{
    uint spriteIndex = uint(gl_VertexID) / 6u;
    uint vertIndex = uint(gl_VertexID) % 6u;
    
    float texURight = DataBuffer.sprites[spriteIndex].TexU + DataBuffer.sprites[spriteIndex].TexW;
    float texVBottom = DataBuffer.sprites[spriteIndex].TexV + DataBuffer.sprites[spriteIndex].TexH;
    vec2 textcoord[4] = vec2[](
        vec2(DataBuffer.sprites[spriteIndex].TexU, DataBuffer.sprites[spriteIndex].TexV),
        vec2(texURight, DataBuffer.sprites[spriteIndex].TexV),
        vec2(DataBuffer.sprites[spriteIndex].TexU, texVBottom),
        vec2(texURight, texVBottom));

    float c = cos(DataBuffer.sprites[spriteIndex].Rotation);
    float s = sin(DataBuffer.sprites[spriteIndex].Rotation);
    out_texCoord = textcoord[triangleIndices[vertIndex]];
    out_Color = DataBuffer.sprites[spriteIndex].Color;
    gl_Position = vec4((mat2(vec2(c, s), vec2(-s, c)) * (vertexPos[triangleIndices[vertInde]] * DataBuffer.sprites[spriteIndex].Scale)) + DataBuffer.sprites[spriteIndex].Position.xy, DataBuffer.sprites[spriteIndex].Position.z, 1.0) * spvWorkaroundRowMajor(UniformBlock.ViewProjectionMatrix);
}

