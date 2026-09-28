// Copyright 2026 Jhonny Göransson
// Licensed under the MIT License.

#include "drp.h"

#include <dmsdk/dlib/array.h>

namespace dmDRP
{
    struct StorageBufferRecord
    {
        StorageBufferId             m_Id;
        dmGraphics::HStorageBuffer  m_Buffer;
        dmGraphics::BufferUsage     m_Usage;
    };

    static dmGraphics::HContext         g_GraphicsContext = 0;
    static dmArray<StorageBufferRecord> g_StorageBuffers;
    static StorageBufferId              g_NextStorageBufferId = 1;

    static StorageBufferRecord* FindStorageBuffer(StorageBufferId buffer_id, uint32_t* index_out)
    {
        for (uint32_t i = 0; i < g_StorageBuffers.Size(); ++i)
        {
            if (g_StorageBuffers[i].m_Id == buffer_id)
            {
                if (index_out)
                    *index_out = i;
                return &g_StorageBuffers[i];
            }
        }
        return 0;
    }

    static StorageBufferId AllocateStorageBufferId()
    {
        StorageBufferId buffer_id = g_NextStorageBufferId++;
        if (buffer_id == 0)
        {
            buffer_id = g_NextStorageBufferId++;
            while (FindStorageBuffer(buffer_id, 0))
                buffer_id = g_NextStorageBufferId++;
        }
        return buffer_id;
    }

    void InitializeGraphics(dmGraphics::HContext context)
    {
        g_GraphicsContext = context;
    }

    void FinalizeGraphics()
    {
        DeleteAllStorageBuffers();
        g_GraphicsContext = 0;
    }

    dmGraphics::HContext GetGraphicsContext()
    {
        if (!g_GraphicsContext)
            g_GraphicsContext = dmGraphics::GetInstalledContext();
        return g_GraphicsContext;
    }

    const char* GetGraphicsAdapterName(dmGraphics::AdapterFamily family)
    {
        switch (family)
        {
            case dmGraphics::ADAPTER_FAMILY_NULL:     return "null";
            case dmGraphics::ADAPTER_FAMILY_OPENGL:   return "opengl";
            case dmGraphics::ADAPTER_FAMILY_OPENGLES: return "opengles";
            case dmGraphics::ADAPTER_FAMILY_VULKAN:   return "vulkan";
            case dmGraphics::ADAPTER_FAMILY_VENDOR:   return "vendor";
            case dmGraphics::ADAPTER_FAMILY_WEBGPU:   return "webgpu";
            case dmGraphics::ADAPTER_FAMILY_DIRECTX:  return "directx";
            case dmGraphics::ADAPTER_FAMILY_METAL:    return "metal";
            case dmGraphics::ADAPTER_FAMILY_NONE:
            default:                                  return "none";
        }
    }

    bool IsStorageBufferSupported()
    {
        dmGraphics::HContext context = GetGraphicsContext();
        return context && dmGraphics::IsContextFeatureSupported(context, dmGraphics::CONTEXT_FEATURE_STORAGE_BUFFER);
    }

    bool IsStorageBufferValid(StorageBufferId buffer_id)
    {
        return buffer_id != 0 && FindStorageBuffer(buffer_id, 0) != 0;
    }

    StorageBufferId CreateStorageBuffer(uint32_t size, const void* data, dmGraphics::BufferUsage usage)
    {
        dmGraphics::HContext context = GetGraphicsContext();
        if (!context || !IsStorageBufferSupported() || size == 0 || (size & 3) != 0)
            return 0;

        dmGraphics::HStorageBuffer buffer = dmGraphics::NewStorageBuffer(context, size, data, usage);
        if (!buffer)
            return 0;

        if (g_StorageBuffers.Full())
            g_StorageBuffers.OffsetCapacity(g_StorageBuffers.Capacity() == 0 ? 8 : g_StorageBuffers.Capacity());

        StorageBufferRecord record;
        record.m_Id = AllocateStorageBufferId();
        record.m_Buffer = buffer;
        record.m_Usage = usage;
        g_StorageBuffers.Push(record);
        return record.m_Id;
    }

    bool ResizeStorageBuffer(StorageBufferId buffer_id, uint32_t size, const void* data, dmGraphics::BufferUsage usage)
    {
        StorageBufferRecord* record = FindStorageBuffer(buffer_id, 0);
        dmGraphics::HContext context = GetGraphicsContext();
        if (!record || !context || size == 0 || (size & 3) != 0)
            return false;

        dmGraphics::SetStorageBufferData(context, record->m_Buffer, size, data, usage);
        if (dmGraphics::GetStorageBufferSize(context, record->m_Buffer) != size)
            return false;

        record->m_Usage = usage;
        return true;
    }

    bool UpdateStorageBuffer(StorageBufferId buffer_id, uint32_t offset, uint32_t size, const void* data)
    {
        StorageBufferRecord* record = FindStorageBuffer(buffer_id, 0);
        dmGraphics::HContext context = GetGraphicsContext();
        if (!record || !context || !data || size == 0 || ((offset | size) & 3) != 0)
            return false;

        uint32_t buffer_size = dmGraphics::GetStorageBufferSize(context, record->m_Buffer);
        if (offset > buffer_size || size > buffer_size - offset)
            return false;

        dmGraphics::SetStorageBufferSubData(context, record->m_Buffer, offset, size, data);
        return true;
    }

    uint32_t GetStorageBufferSize(StorageBufferId buffer_id)
    {
        StorageBufferRecord* record = FindStorageBuffer(buffer_id, 0);
        dmGraphics::HContext context = GetGraphicsContext();
        if (!record || !context)
            return 0;
        return dmGraphics::GetStorageBufferSize(context, record->m_Buffer);
    }

    dmGraphics::BufferUsage GetStorageBufferUsage(StorageBufferId buffer_id)
    {
        StorageBufferRecord* record = FindStorageBuffer(buffer_id, 0);
        return record ? record->m_Usage : dmGraphics::BUFFER_USAGE_DYNAMIC_DRAW;
    }

    bool BindStorageBuffer(StorageBufferId buffer_id, uint32_t set, uint32_t binding)
    {
        StorageBufferRecord* record = FindStorageBuffer(buffer_id, 0);
        dmGraphics::HContext context = GetGraphicsContext();
        if (!record || !context || set >= MAX_DESCRIPTOR_SETS || binding >= MAX_BINDINGS_PER_SET)
            return false;

        dmGraphics::EnableStorageBuffer(context, record->m_Buffer, set, binding);
        return true;
    }

    bool UnbindStorageBuffer(StorageBufferId buffer_id)
    {
        StorageBufferRecord* record = FindStorageBuffer(buffer_id, 0);
        dmGraphics::HContext context = GetGraphicsContext();
        if (!record || !context)
            return false;

        dmGraphics::DisableStorageBuffer(context, record->m_Buffer);
        return true;
    }

    bool DeleteStorageBuffer(StorageBufferId buffer_id)
    {
        uint32_t record_index = 0;
        StorageBufferRecord* record = FindStorageBuffer(buffer_id, &record_index);
        dmGraphics::HContext context = GetGraphicsContext();
        if (!record || !context)
            return false;

        dmGraphics::DeleteStorageBuffer(context, record->m_Buffer);
        g_StorageBuffers.EraseSwap(record_index);
        return true;
    }

    void DeleteAllStorageBuffers()
    {
        dmGraphics::HContext context = GetGraphicsContext();
        if (context)
        {
            for (uint32_t i = 0; i < g_StorageBuffers.Size(); ++i)
                dmGraphics::DeleteStorageBuffer(context, g_StorageBuffers[i].m_Buffer);
        }
        g_StorageBuffers.SetSize(0);
    }
}
