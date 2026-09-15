// Copyright 2026 The Defold Render Pipeline Authors
// Licensed under the MIT License.

#ifndef DM_DRP_H
#define DM_DRP_H

#include <dmsdk/graphics/graphics.h>

#include <stdint.h>

struct lua_State;

// TODO(engine-public-api): Replace these declarations when feature queries and
// graphics limits have a stable dmSDK API. They are engine-owned today; DRP
// uses the exported functions through this private bridge and must keep the
// declarations synchronized with graphics/graphics.h in the meantime.
namespace dmGraphics
{
    enum ContextFeature
    {
        CONTEXT_FEATURE_MULTI_TARGET_RENDERING = 0,
        CONTEXT_FEATURE_TEXTURE_ARRAY          = 1,
        CONTEXT_FEATURE_COMPUTE_SHADER         = 2,
        CONTEXT_FEATURE_STORAGE_BUFFER         = 3,
        CONTEXT_FEATURE_VSYNC                  = 4,
        CONTEXT_FEATURE_INSTANCING             = 5,
        CONTEXT_FEATURE_3D_TEXTURES            = 6,
        CONTEXT_FEATURE_ASTC_ARRAY_TEXTURES    = 7,
        CONTEXT_FEATURE_BLEND_EQUATION_MIN_MAX = 8,
        CONTEXT_FEATURE_BC_ARRAY_TEXTURES      = 9,
        MAX_CONTEXT_FEATURE_COUNT              = 10,
    };

    struct GraphicsContextLimits
    {
        uint64_t m_MaxUniformBufferRange;
        uint64_t m_MaxStorageBufferRange;

        uint32_t m_MaxTextureSize2D;
        uint32_t m_MaxTextureSize3D;
        uint32_t m_MaxTextureSizeCube;
        uint32_t m_MaxTextureArrayLayers;

        uint32_t m_MaxFramebufferWidth;
        uint32_t m_MaxFramebufferHeight;
        uint32_t m_MaxColorAttachments;

        uint32_t m_MaxSamplersPerStage;
        uint32_t m_MaxTexturesPerStage;
        uint32_t m_MaxStorageBuffersPerStage;
        uint32_t m_MaxVertexAttributes;
        uint32_t m_MaxVertexBuffers;

        uint32_t m_MaxComputeWorkgroupSizeX;
        uint32_t m_MaxComputeWorkgroupSizeY;
        uint32_t m_MaxComputeWorkgroupSizeZ;
        uint32_t m_MaxComputeWorkgroupInvocations;
        uint32_t m_MaxComputeSharedMemorySize;
    };

    bool IsContextFeatureSupported(HContext context, ContextFeature feature);
    void GetGraphicsContextLimits(HContext context, GraphicsContextLimits& limits);
}

namespace dmDRP
{
    enum
    {
        NATIVE_API_VERSION   = 1,
        MAX_DESCRIPTOR_SETS  = 4,
        MAX_BINDINGS_PER_SET = 32,
    };

    typedef uint32_t StorageBufferId;

    void InitializeGraphics(dmGraphics::HContext context);
    void FinalizeGraphics();
    void InitializeScript(lua_State* L);

    dmGraphics::HContext GetGraphicsContext();
    const char* GetGraphicsAdapterName(dmGraphics::AdapterFamily family);
    bool IsStorageBufferSupported();

    bool IsStorageBufferValid(StorageBufferId buffer_id);
    StorageBufferId CreateStorageBuffer(uint32_t size, const void* data, dmGraphics::BufferUsage usage);
    bool ResizeStorageBuffer(StorageBufferId buffer_id, uint32_t size, const void* data, dmGraphics::BufferUsage usage);
    bool UpdateStorageBuffer(StorageBufferId buffer_id, uint32_t offset, uint32_t size, const void* data);
    uint32_t GetStorageBufferSize(StorageBufferId buffer_id);
    dmGraphics::BufferUsage GetStorageBufferUsage(StorageBufferId buffer_id);
    bool BindStorageBuffer(StorageBufferId buffer_id, uint32_t set, uint32_t binding);
    bool UnbindStorageBuffer(StorageBufferId buffer_id);
    bool DeleteStorageBuffer(StorageBufferId buffer_id);
    void DeleteAllStorageBuffers();
}

#endif // DM_DRP_H
