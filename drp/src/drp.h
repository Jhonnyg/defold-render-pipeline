// Copyright 2026 Jhonny Göransson
// Licensed under the MIT License.

#ifndef DM_DRP_H
#define DM_DRP_H

#include <dmsdk/graphics/graphics.h>

#include <stdint.h>

struct lua_State;

/**
 * @file
 * Internal interface shared by the DRP extension lifecycle, Lua bindings, and
 * graphics implementation. This is not a public dmSDK header.
 *
 * dmDRP owns its storage-buffer records and GPU buffers, but borrows the engine's
 * graphics context and Lua state. State is process-global and unsynchronized;
 * callers must use the engine's graphics thread with a live context for GPU
 * operations. Finalize graphics before the engine destroys that context.
 */

// Engine-owned declarations: https://github.com/defold/defold/blob/dev/engine/graphics/src/graphics.h
// Implementations: https://github.com/defold/defold/blob/dev/engine/graphics/src/graphics.cpp
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
        NATIVE_API_VERSION   = 1,  ///< Lua API_VERSION and capabilities.native_bridge_version.
        MAX_DESCRIPTOR_SETS  = 4,  ///< Exclusive upper bound for descriptor set indices.
        MAX_BINDINGS_PER_SET = 32, ///< Exclusive upper bound for binding indices in each set.
    };

    /**
     * Opaque ID for a DRP-owned storage buffer, not a dmGraphics GPU handle.
     * Zero is invalid. Deletion, DeleteAllStorageBuffers(), and FinalizeGraphics()
     * invalidate IDs; callers must not keep using them after those operations.
     */
    typedef uint32_t StorageBufferId;

    /**
     * Store a borrowed graphics context without creating or destroying it.
     * Called by extension initialization before InitializeScript(). Existing
     * buffers are not cleared: finalize them before replacing their context.
     * Passing 0 leaves context lookup to GetGraphicsContext().
     */
    void InitializeGraphics(dmGraphics::HContext context);

    /**
     * Delete all tracked buffers and clear the cached context. Call while the
     * engine context is still alive; this does not destroy the engine context
     * or unregister the Lua module.
     */
    void FinalizeGraphics();

    /**
     * Register drp_native functions and constants in the supplied Lua state.
     * L must be valid; it remains caller-owned and its stack depth is preserved.
     * Registration does not create GPU resources or check SSBO support.
     */
    void InitializeScript(lua_State* L);

    /**
     * Return the borrowed context, lazily fetching and caching the engine's
     * installed context when the cache is empty. May return 0 if unavailable;
     * this lookup can also reacquire a context after FinalizeGraphics().
     */
    dmGraphics::HContext GetGraphicsContext();

    /**
     * Return a static lowercase adapter name (for example, "metal").
     * Unknown values and ADAPTER_FAMILY_NONE return "none". Do not free the string.
     */
    const char* GetGraphicsAdapterName(dmGraphics::AdapterFamily family);

    /** Return false if no context is available or its adapter lacks SSBO support. */
    bool IsStorageBufferSupported();

    /**
     * Test whether a nonzero ID is present in DRP's buffer registry.
     * This does not query the context, GPU allocation, or current bindings.
     */
    bool IsStorageBufferValid(StorageBufferId buffer_id);

    /**
     * Allocate and track a storage buffer. The caller must delete it explicitly
     * or let DeleteAllStorageBuffers()/FinalizeGraphics() release it.
     * @param size Nonzero byte count divisible by four and within adapter limits.
     * @param data Optional source of at least size readable bytes. The source
     *             remains caller-owned and need only live through this call.
     *             With 0, initial contents are unspecified, not guaranteed zero.
     * @param usage A BUFFER_USAGE_STREAM_DRAW, DYNAMIC_DRAW, or STATIC_DRAW hint.
     * @return A nonzero ID, or 0 for no context, missing SSBO support, invalid size,
     *         or a failed engine allocation. This wrapper does not validate usage.
     */
    StorageBufferId CreateStorageBuffer(uint32_t size, const void* data, dmGraphics::BufferUsage usage);

    /**
     * Replace a buffer's storage and usage hint, keeping its DRP ID and bindings.
     * This is a full replacement, not a content-preserving resize.
     * @param buffer_id A live DRP buffer ID.
     * @param size Nonzero byte count divisible by four and within adapter limits.
     * @param data Optional replacement source with at least size readable bytes,
     *             valid through this call. With 0, contents are unspecified.
     * @param usage New usage hint; pass GetStorageBufferUsage() to keep the old one.
     * @return False for an invalid ID, missing context, invalid size, or if the
     *         engine reports a different size after replacement. True only
     *         confirms the reported size; this is not a GPU completion check or
     *         a transactional operation with a rollback guarantee.
     */
    bool ResizeStorageBuffer(StorageBufferId buffer_id, uint32_t size, const void* data, dmGraphics::BufferUsage usage);

    /**
     * Update part of a buffer without changing its size or usage hint.
     * @param buffer_id A live DRP buffer ID.
     * @param offset Destination byte offset, divisible by four.
     * @param size Nonzero byte count divisible by four; the entire range must fit.
     * @param data Non-null source of at least size bytes, valid through this call.
     * @return False for an invalid ID, missing context, null source, or invalid
     *         alignment/range. True means the update was forwarded to the engine,
     *         not that GPU execution has completed.
     */
    bool UpdateStorageBuffer(StorageBufferId buffer_id, uint32_t offset, uint32_t size, const void* data);

    /** Return the logical size in bytes, or 0 for an invalid ID or missing context. */
    uint32_t GetStorageBufferSize(StorageBufferId buffer_id);

    /**
     * Return the stored usage hint. Invalid IDs return BUFFER_USAGE_DYNAMIC_DRAW;
     * use IsStorageBufferValid() if the caller needs to distinguish that fallback.
     */
    dmGraphics::BufferUsage GetStorageBufferUsage(StorageBufferId buffer_id);

    /**
     * Bind a live buffer to a shader's reflected descriptor set and binding.
     * Replaces that slot's previous buffer; other slots remain unchanged.
     * Bindings remain active until replaced, unbound, or deleted; the caller
     * must match shader declarations and observe the adapter's binding limits.
     * One buffer may occupy multiple slots, but DirectX 12 does not support
     * mixing readonly and writable declarations of it in one draw or dispatch.
     * @param set Zero-based descriptor set, less than MAX_DESCRIPTOR_SETS.
     * @param binding Zero-based binding, less than MAX_BINDINGS_PER_SET.
     * @return False for an invalid ID, missing context, or out-of-range index.
     *         True means the bind was forwarded, not that shader compatibility
     *         or all backend-specific restrictions were checked by this wrapper.
     */
    bool BindStorageBuffer(StorageBufferId buffer_id, uint32_t set, uint32_t binding);

    /**
     * Remove all descriptor bindings of a buffer without deleting its storage.
     * @return False for an invalid ID or missing context; otherwise true, even
     *         when the buffer was already unbound.
     */
    bool UnbindStorageBuffer(StorageBufferId buffer_id);

    /**
     * Clear all bindings of a buffer, release it through the engine, and remove
     * its ID from the registry. The backend may defer GPU resource destruction
     * until in-flight work completes.
     * @return False for an invalid/deleted ID or missing context; otherwise true.
     *         On success, the ID is invalid and must not be used again.
     */
    bool DeleteStorageBuffer(StorageBufferId buffer_id);

    /**
     * Release all tracked buffers and invalidate their IDs. Used by the Lua
     * reset() binding and FinalizeGraphics(); does not clear the cached context
     * or reset the ID counter. If no context is available, only the registry is
     * cleared, so call before context destruction to release GPU resources.
     */
    void DeleteAllStorageBuffers();
}

#endif // DM_DRP_H
