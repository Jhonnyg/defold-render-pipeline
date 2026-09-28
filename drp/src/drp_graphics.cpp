// Copyright 2026 Jhonny Göransson
// Licensed under the MIT License.

#include "drp.h"

namespace dmDRP
{
    static StorageBufferRecord* FindStorageBuffer(DRPContext* drp_context, StorageBufferId buffer_id, uint32_t* index_out)
    {
        if (!drp_context)
            return 0;
        for (uint32_t i = 0; i < drp_context->m_StorageBuffers.Size(); ++i)
        {
            if (drp_context->m_StorageBuffers[i].m_Id == buffer_id)
            {
                if (index_out)
                    *index_out = i;
                return &drp_context->m_StorageBuffers[i];
            }
        }
        return 0;
    }

    static StorageBufferId AllocateStorageBufferId(DRPContext* drp_context)
    {
        StorageBufferId buffer_id = drp_context->m_NextStorageBufferId++;
        if (buffer_id == 0)
        {
            buffer_id = drp_context->m_NextStorageBufferId++;
            while (FindStorageBuffer(drp_context, buffer_id, 0))
                buffer_id = drp_context->m_NextStorageBufferId++;
        }
        return buffer_id;
    }

    void InitializeGraphics(DRPContext* drp_context, dmGraphics::HContext graphics_context)
    {
        if (drp_context)
            drp_context->m_GraphicsContext = graphics_context;
    }

    void FinalizeGraphics(DRPContext* drp_context)
    {
        if (!drp_context)
            return;
        DeleteAllStorageBuffers(drp_context);
        drp_context->m_GraphicsContext = 0;
    }

    dmGraphics::HContext GetGraphicsContext(DRPContext* drp_context)
    {
        return drp_context ? drp_context->m_GraphicsContext : 0;
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

    bool IsStorageBufferSupported(DRPContext* drp_context)
    {
        dmGraphics::HContext context = GetGraphicsContext(drp_context);
        return context && dmGraphics::IsContextFeatureSupported(context, dmGraphics::CONTEXT_FEATURE_STORAGE_BUFFER);
    }

    bool IsStorageBufferValid(DRPContext* drp_context, StorageBufferId buffer_id)
    {
        return buffer_id != 0 && FindStorageBuffer(drp_context, buffer_id, 0) != 0;
    }

    StorageBufferId CreateStorageBuffer(DRPContext* drp_context, uint32_t size, const void* data, dmGraphics::BufferUsage usage)
    {
        dmGraphics::HContext context = GetGraphicsContext(drp_context);
        if (!context || !IsStorageBufferSupported(drp_context) || size == 0 || (size & 3) != 0)
            return 0;

        dmGraphics::HStorageBuffer buffer = dmGraphics::NewStorageBuffer(context, size, data, usage);
        if (!buffer)
            return 0;

        if (drp_context->m_StorageBuffers.Full())
            drp_context->m_StorageBuffers.OffsetCapacity(drp_context->m_StorageBuffers.Capacity() == 0 ? 8 : drp_context->m_StorageBuffers.Capacity());

        StorageBufferRecord record;
        record.m_Id = AllocateStorageBufferId(drp_context);
        record.m_Buffer = buffer;
        record.m_Usage = usage;
        drp_context->m_StorageBuffers.Push(record);
        return record.m_Id;
    }

    bool ResizeStorageBuffer(DRPContext* drp_context, StorageBufferId buffer_id, uint32_t size, const void* data, dmGraphics::BufferUsage usage)
    {
        StorageBufferRecord* record = FindStorageBuffer(drp_context, buffer_id, 0);
        dmGraphics::HContext context = GetGraphicsContext(drp_context);
        if (!record || !context || size == 0 || (size & 3) != 0)
            return false;

        dmGraphics::SetStorageBufferData(context, record->m_Buffer, size, data, usage);
        if (dmGraphics::GetStorageBufferSize(context, record->m_Buffer) != size)
            return false;

        record->m_Usage = usage;
        return true;
    }

    bool UpdateStorageBuffer(DRPContext* drp_context, StorageBufferId buffer_id, uint32_t offset, uint32_t size, const void* data)
    {
        StorageBufferRecord* record = FindStorageBuffer(drp_context, buffer_id, 0);
        dmGraphics::HContext context = GetGraphicsContext(drp_context);
        if (!record || !context || !data || size == 0 || ((offset | size) & 3) != 0)
            return false;

        uint32_t buffer_size = dmGraphics::GetStorageBufferSize(context, record->m_Buffer);
        if (offset > buffer_size || size > buffer_size - offset)
            return false;

        dmGraphics::SetStorageBufferSubData(context, record->m_Buffer, offset, size, data);
        return true;
    }

    uint32_t GetStorageBufferSize(DRPContext* drp_context, StorageBufferId buffer_id)
    {
        StorageBufferRecord* record = FindStorageBuffer(drp_context, buffer_id, 0);
        dmGraphics::HContext context = GetGraphicsContext(drp_context);
        if (!record || !context)
            return 0;
        return dmGraphics::GetStorageBufferSize(context, record->m_Buffer);
    }

    dmGraphics::BufferUsage GetStorageBufferUsage(DRPContext* drp_context, StorageBufferId buffer_id)
    {
        StorageBufferRecord* record = FindStorageBuffer(drp_context, buffer_id, 0);
        return record ? record->m_Usage : dmGraphics::BUFFER_USAGE_DYNAMIC_DRAW;
    }

    bool BindStorageBuffer(DRPContext* drp_context, StorageBufferId buffer_id, uint32_t set, uint32_t binding)
    {
        StorageBufferRecord* record = FindStorageBuffer(drp_context, buffer_id, 0);
        dmGraphics::HContext context = GetGraphicsContext(drp_context);
        if (!record || !context || set >= MAX_DESCRIPTOR_SETS || binding >= MAX_BINDINGS_PER_SET)
            return false;

        dmGraphics::EnableStorageBuffer(context, record->m_Buffer, set, binding);
        return true;
    }

    bool UnbindStorageBuffer(DRPContext* drp_context, StorageBufferId buffer_id)
    {
        StorageBufferRecord* record = FindStorageBuffer(drp_context, buffer_id, 0);
        dmGraphics::HContext context = GetGraphicsContext(drp_context);
        if (!record || !context)
            return false;

        dmGraphics::DisableStorageBuffer(context, record->m_Buffer);
        return true;
    }

    bool DeleteStorageBuffer(DRPContext* drp_context, StorageBufferId buffer_id)
    {
        uint32_t record_index = 0;
        StorageBufferRecord* record = FindStorageBuffer(drp_context, buffer_id, &record_index);
        dmGraphics::HContext context = GetGraphicsContext(drp_context);
        if (!record || !context)
            return false;

        dmGraphics::DeleteStorageBuffer(context, record->m_Buffer);
        drp_context->m_StorageBuffers.EraseSwap(record_index);
        return true;
    }

    void DeleteAllStorageBuffers(DRPContext* drp_context)
    {
        if (!drp_context)
            return;
        dmGraphics::HContext context = GetGraphicsContext(drp_context);
        if (context)
        {
            for (uint32_t i = 0; i < drp_context->m_StorageBuffers.Size(); ++i)
                dmGraphics::DeleteStorageBuffer(context, drp_context->m_StorageBuffers[i].m_Buffer);
        }
        drp_context->m_StorageBuffers.SetSize(0);
    }
}
