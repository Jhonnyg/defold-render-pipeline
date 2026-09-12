// Copyright 2026 The Defold Render Pipeline Authors
// Licensed under the MIT License.

#ifndef DM_DRP_H
#define DM_DRP_H

#include <dmsdk/graphics/graphics.h>

#include <stdint.h>

struct lua_State;

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
