// Copyright 2026 Jhonny Göransson
// Licensed under the MIT License.

#ifndef DM_DRP_H
#define DM_DRP_H

#include <dmsdk/dlib/array.h>
#include <dmsdk/graphics/graphics.h>

#include <stdint.h>

struct lua_State;

/**
 * @file
 * Internal interface shared by the DRP extension lifecycle, Lua bindings, and
 * graphics implementation. This is not a public dmSDK header.
 *
 * The extension owns one DRPContext per application, registered as "drp" in
 * the engine's context registry. Each context owns its buffer records and GPU
 * buffers, and borrows its graphics context. Lua bindings borrow the DRPContext.
 * State is unsynchronized; use the engine's graphics thread for GPU operations.
 * Finalize graphics before the engine destroys its context, then delete the
 * DRPContext during app finalization. The destructor releases CPU memory only.
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
     * Opaque ID for a buffer owned by one DRPContext, not a dmGraphics GPU handle.
     * IDs are scoped to that context and must not be passed to another context.
     * Zero is invalid. Deletion, DeleteAllStorageBuffers(), and FinalizeGraphics()
     * invalidate IDs; callers must not keep using them after those operations.
     */
    typedef uint32_t StorageBufferId;

    /** One GPU allocation tracked by its owning DRPContext. */
    struct StorageBufferRecord
    {
        StorageBufferId            m_Id;
        dmGraphics::HStorageBuffer m_Buffer;
        dmGraphics::BufferUsage    m_Usage;
    };

    /**
     * Application-owned native state. Construct/register in AppInitialize,
     * attach graphics in Initialize, release GPU resources in Finalize, and
     * unregister/delete in AppFinalize. Never copy ownership of GPU buffers.
     */
    struct DRPContext
    {
        dmGraphics::HContext         m_GraphicsContext;       ///< Borrowed; 0 before initialization and after finalization.
        dmArray<StorageBufferRecord> m_StorageBuffers;        ///< Owned allocations; released by FinalizeGraphics().
        StorageBufferId              m_NextStorageBufferId;   ///< Next ID candidate; preserved by buffer reset.

        DRPContext()
        : m_GraphicsContext(0)
        , m_NextStorageBufferId(1)
        {
        }

        DRPContext(const DRPContext&) = delete;
        DRPContext& operator=(const DRPContext&) = delete;
    };

    /**
     * Attach a borrowed graphics context without creating or destroying it.
     * Existing buffers are not cleared: finalize them before replacing their
     * graphics context. Passing 0 leaves graphics unavailable; no global lookup
     * is performed.
     */
    void InitializeGraphics(DRPContext* context, dmGraphics::HContext graphics_context);

    /**
     * Delete this context's buffers and clear its borrowed graphics pointer.
     * Call while the engine graphics context is alive. Safe to repeat; retains
     * the DRPContext and its ID counter, and does not detach Lua bindings.
     */
    void FinalizeGraphics(DRPContext* context);

    /**
     * Register drp_native functions/constants and a borrowed context in Lua's
     * registry. L and context must be valid and outlive the binding. Stack depth
     * is preserved; no GPU resources are created or SSBO support checks made.
     */
    void InitializeScript(lua_State* L, DRPContext* context);

    /**
     * Remove this Lua state's borrowed context without deleting native state.
     * L must be valid. Stack depth is preserved; retained Lua functions report
     * an unavailable context when called after detachment.
     */
    void FinalizeScript(lua_State* L);

    /**
     * Return this DRPContext's borrowed graphics pointer, or 0 when unattached.
     * Never reacquires the engine's installed context after finalization.
     */
    dmGraphics::HContext GetGraphicsContext(DRPContext* context);

    /**
     * Return a static lowercase adapter name (for example, "metal").
     * Unknown values and ADAPTER_FAMILY_NONE return "none". Do not free the string.
     */
    const char* GetGraphicsAdapterName(dmGraphics::AdapterFamily family);

    /** Return false if no context is available or its adapter lacks SSBO support. */
    bool IsStorageBufferSupported(DRPContext* context);

    /**
     * Test whether a nonzero ID is present in the supplied context's buffer registry.
     * This does not query the graphics context, GPU allocation, or current bindings.
     */
    bool IsStorageBufferValid(DRPContext* context, StorageBufferId buffer_id);

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
    StorageBufferId CreateStorageBuffer(DRPContext* context, uint32_t size, const void* data, dmGraphics::BufferUsage usage);

    /**
     * Replace a buffer's storage and usage hint, keeping its DRP ID and bindings.
     * This is a full replacement, not a content-preserving resize.
     * @param buffer_id A live DRP buffer ID.
     * @param size Nonzero byte count divisible by four and within adapter limits.
     * @param data Optional replacement source with at least size readable bytes,
     *             valid through this call. With 0, contents are unspecified.
     * @param usage New usage hint; pass GetStorageBufferUsage(context, buffer_id)
     *              to keep the old one.
     * @return False for an invalid ID, missing context, invalid size, or if the
     *         engine reports a different size after replacement. True only
     *         confirms the reported size; this is not a GPU completion check or
     *         a transactional operation with a rollback guarantee.
     */
    bool ResizeStorageBuffer(DRPContext* context, StorageBufferId buffer_id, uint32_t size, const void* data, dmGraphics::BufferUsage usage);

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
    bool UpdateStorageBuffer(DRPContext* context, StorageBufferId buffer_id, uint32_t offset, uint32_t size, const void* data);

    /** Return the logical size in bytes, or 0 for an invalid ID or missing context. */
    uint32_t GetStorageBufferSize(DRPContext* context, StorageBufferId buffer_id);

    /**
     * Return the stored usage hint. Invalid IDs return BUFFER_USAGE_DYNAMIC_DRAW;
     * use IsStorageBufferValid(context, buffer_id) to distinguish that fallback.
     */
    dmGraphics::BufferUsage GetStorageBufferUsage(DRPContext* context, StorageBufferId buffer_id);

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
    bool BindStorageBuffer(DRPContext* context, StorageBufferId buffer_id, uint32_t set, uint32_t binding);

    /**
     * Remove all descriptor bindings of a buffer without deleting its storage.
     * @return False for an invalid ID or missing context; otherwise true, even
     *         when the buffer was already unbound.
     */
    bool UnbindStorageBuffer(DRPContext* context, StorageBufferId buffer_id);

    /**
     * Clear all bindings of a buffer, release it through the engine, and remove
     * its ID from the registry. The backend may defer GPU resource destruction
     * until in-flight work completes.
     * @return False for an invalid/deleted ID or missing context; otherwise true.
     *         On success, the ID is invalid and must not be used again.
     */
    bool DeleteStorageBuffer(DRPContext* context, StorageBufferId buffer_id);

    /**
     * Release this context's buffers and invalidate their IDs. Used by the Lua
     * reset() binding and FinalizeGraphics(); retains the DRPContext, borrowed
     * graphics pointer, and ID counter. If graphics is unavailable, only the
     * records are cleared, so call before graphics destruction to release GPU
     * resources.
     */
    void DeleteAllStorageBuffers(DRPContext* context);
}

#endif // DM_DRP_H
