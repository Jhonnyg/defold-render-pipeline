// Copyright 2026 Jhonny Göransson
// Licensed under the MIT License.

#define LIB_NAME "drp_native"

#include <dmsdk/sdk.h>

#include "drp.h"

#include <stdint.h>
#include <string.h>

namespace dmDRP
{
    // The Lua registry borrows this pointer; the extension owns its lifetime.
    static DRPContext* CheckContext(lua_State* L)
    {
        lua_getfield(L, LUA_REGISTRYINDEX, LIB_NAME ".context");
        DRPContext* context = (DRPContext*) lua_touserdata(L, -1);
        lua_pop(L, 1);
        if (!context)
            luaL_error(L, "the DRP context is not available");
        return context;
    }

    static void SetBooleanField(lua_State* L, const char* name, bool value)
    {
        lua_pushboolean(L, value ? 1 : 0);
        lua_setfield(L, -2, name);
    }

    static void SetNumberField(lua_State* L, const char* name, lua_Number value)
    {
        lua_pushnumber(L, value);
        lua_setfield(L, -2, name);
    }

    static void SetStringField(lua_State* L, const char* name, const char* value)
    {
        lua_pushstring(L, value);
        lua_setfield(L, -2, name);
    }

    static uint32_t CheckUint32(lua_State* L, int index, const char* name, bool allow_zero)
    {
        const lua_Number value = luaL_checknumber(L, index);
        if (value != value || value < 0.0 || value > 4294967295.0)
            luaL_error(L, "%s must be an unsigned 32-bit integer", name);

        const uint32_t result = (uint32_t) value;
        if ((lua_Number) result != value)
            luaL_error(L, "%s must be an unsigned 32-bit integer", name);
        if (!allow_zero && result == 0)
            luaL_error(L, "%s must be greater than zero", name);
        return result;
    }

    static dmGraphics::BufferUsage CheckBufferUsage(lua_State* L, int index)
    {
        if (lua_isnoneornil(L, index))
            return dmGraphics::BUFFER_USAGE_DYNAMIC_DRAW;

        const uint32_t usage = CheckUint32(L, index, "buffer usage", true);
        switch (usage)
        {
            case dmGraphics::BUFFER_USAGE_STREAM_DRAW:
            case dmGraphics::BUFFER_USAGE_DYNAMIC_DRAW:
            case dmGraphics::BUFFER_USAGE_STATIC_DRAW:
                return (dmGraphics::BufferUsage) usage;
            default:
                luaL_error(L, "invalid storage-buffer usage %u", usage);
                return dmGraphics::BUFFER_USAGE_DYNAMIC_DRAW;
        }
    }

    static StorageBufferId CheckStorageBuffer(lua_State* L, DRPContext* context, int index)
    {
        const StorageBufferId buffer_id = CheckUint32(L, index, "storage-buffer handle", false);
        if (!IsStorageBufferValid(context, buffer_id))
            luaL_error(L, "invalid or deleted storage-buffer handle %u", buffer_id);
        return buffer_id;
    }

    static int GetCapabilities(lua_State* L)
    {
        DM_LUA_STACK_CHECK(L, 1);

        DRPContext* context = CheckContext(L);
        const dmGraphics::HContext graphics_context = GetGraphicsContext(context);
        const dmGraphics::AdapterFamily adapter = dmGraphics::GetInstalledAdapterFamily();

        lua_newtable(L);
        SetStringField(L, "source", "drp-native");
        SetStringField(L, "adapter", GetGraphicsAdapterName(adapter));
        SetNumberField(L, "native_bridge_version", NATIVE_API_VERSION);

        lua_newtable(L);
        SetBooleanField(L, "compute_shaders", graphics_context && dmGraphics::IsContextFeatureSupported(graphics_context, dmGraphics::CONTEXT_FEATURE_COMPUTE_SHADER));
        SetBooleanField(L, "storage_buffers", graphics_context && dmGraphics::IsContextFeatureSupported(graphics_context, dmGraphics::CONTEXT_FEATURE_STORAGE_BUFFER));
        SetBooleanField(L, "texture_arrays", graphics_context && dmGraphics::IsContextFeatureSupported(graphics_context, dmGraphics::CONTEXT_FEATURE_TEXTURE_ARRAY));
        SetBooleanField(L, "textures_3d", graphics_context && dmGraphics::IsContextFeatureSupported(graphics_context, dmGraphics::CONTEXT_FEATURE_3D_TEXTURES));
        SetBooleanField(L, "instancing", graphics_context && dmGraphics::IsContextFeatureSupported(graphics_context, dmGraphics::CONTEXT_FEATURE_INSTANCING));
        SetBooleanField(L, "multiple_render_targets", graphics_context && dmGraphics::IsContextFeatureSupported(graphics_context, dmGraphics::CONTEXT_FEATURE_MULTI_TARGET_RENDERING));
        SetBooleanField(L, "blend_equation_min_max", graphics_context && dmGraphics::IsContextFeatureSupported(graphics_context, dmGraphics::CONTEXT_FEATURE_BLEND_EQUATION_MIN_MAX));
        lua_setfield(L, -2, "features");

        lua_newtable(L);
        if (graphics_context)
        {
            dmGraphics::GraphicsContextLimits limits;
            memset(&limits, 0, sizeof(limits));
            dmGraphics::GetGraphicsContextLimits(graphics_context, limits);
            SetNumberField(L, "max_uniform_buffer_range", (lua_Number) limits.m_MaxUniformBufferRange);
            SetNumberField(L, "max_storage_buffer_range", (lua_Number) limits.m_MaxStorageBufferRange);
            SetNumberField(L, "max_texture_size_2d", limits.m_MaxTextureSize2D);
            SetNumberField(L, "max_texture_size_3d", limits.m_MaxTextureSize3D);
            SetNumberField(L, "max_texture_size_cube", limits.m_MaxTextureSizeCube);
            SetNumberField(L, "max_texture_array_layers", limits.m_MaxTextureArrayLayers);
            SetNumberField(L, "max_framebuffer_width", limits.m_MaxFramebufferWidth);
            SetNumberField(L, "max_framebuffer_height", limits.m_MaxFramebufferHeight);
            SetNumberField(L, "max_color_attachments", limits.m_MaxColorAttachments);
            SetNumberField(L, "max_samplers_per_stage", limits.m_MaxSamplersPerStage);
            SetNumberField(L, "max_textures_per_stage", limits.m_MaxTexturesPerStage);
            SetNumberField(L, "max_storage_buffers_per_stage", limits.m_MaxStorageBuffersPerStage);
            SetNumberField(L, "max_vertex_attributes", limits.m_MaxVertexAttributes);
            SetNumberField(L, "max_vertex_buffers", limits.m_MaxVertexBuffers);
            SetNumberField(L, "max_compute_workgroup_size_x", limits.m_MaxComputeWorkgroupSizeX);
            SetNumberField(L, "max_compute_workgroup_size_y", limits.m_MaxComputeWorkgroupSizeY);
            SetNumberField(L, "max_compute_workgroup_size_z", limits.m_MaxComputeWorkgroupSizeZ);
            SetNumberField(L, "max_compute_workgroup_invocations", limits.m_MaxComputeWorkgroupInvocations);
            SetNumberField(L, "max_compute_shared_memory_size", limits.m_MaxComputeSharedMemorySize);
        }
        lua_setfield(L, -2, "limits");
        return 1;
    }

    static int CreateStorageBuffer(lua_State* L)
    {
        DM_LUA_STACK_CHECK(L, 1);

        DRPContext* context = CheckContext(L);
        if (!GetGraphicsContext(context))
            return luaL_error(L, "the graphics context is not available");
        if (!IsStorageBufferSupported(context))
            return luaL_error(L, "storage buffers are not supported by the '%s' graphics adapter", GetGraphicsAdapterName(dmGraphics::GetInstalledAdapterFamily()));

        const uint32_t size = CheckUint32(L, 1, "storage-buffer size", false);
        if ((size & 3) != 0)
            return luaL_error(L, "storage-buffer size must be four-byte aligned");

        const dmGraphics::BufferUsage usage = CheckBufferUsage(L, 2);
        const void* data = 0;
        if (!lua_isnoneornil(L, 3))
        {
            size_t data_size = 0;
            data = luaL_checklstring(L, 3, &data_size);
            if (data_size != size)
                return luaL_error(L, "initial data must contain exactly %u bytes (got %u)", size, (uint32_t) data_size);
        }

        const StorageBufferId buffer = dmDRP::CreateStorageBuffer(context, size, data, usage);
        if (!buffer)
            return luaL_error(L, "failed to create a %u-byte storage buffer", size);

        lua_pushnumber(L, buffer);
        return 1;
    }

    static int ResizeStorageBuffer(lua_State* L)
    {
        DM_LUA_STACK_CHECK(L, 1);

        DRPContext* context = CheckContext(L);
        const StorageBufferId buffer = CheckStorageBuffer(L, context, 1);
        const uint32_t size = CheckUint32(L, 2, "storage-buffer size", false);
        if ((size & 3) != 0)
            return luaL_error(L, "storage-buffer size must be four-byte aligned");

        const dmGraphics::BufferUsage usage = lua_isnoneornil(L, 3) ? GetStorageBufferUsage(context, buffer) : CheckBufferUsage(L, 3);
        const void* data = 0;
        if (!lua_isnoneornil(L, 4))
        {
            size_t data_size = 0;
            data = luaL_checklstring(L, 4, &data_size);
            if (data_size != size)
                return luaL_error(L, "replacement data must contain exactly %u bytes (got %u)", size, (uint32_t) data_size);
        }

        if (!dmDRP::ResizeStorageBuffer(context, buffer, size, data, usage))
            return luaL_error(L, "failed to resize storage buffer to %u bytes", size);

        lua_pushboolean(L, 1);
        return 1;
    }

    static int UpdateStorageBuffer(lua_State* L)
    {
        DM_LUA_STACK_CHECK(L, 1);

        DRPContext* context = CheckContext(L);
        const StorageBufferId buffer = CheckStorageBuffer(L, context, 1);
        const uint32_t offset = CheckUint32(L, 2, "storage-buffer update offset", true);
        size_t data_size = 0;
        const void* data = luaL_checklstring(L, 3, &data_size);

        if (data_size == 0 || data_size > 4294967295u)
            return luaL_error(L, "storage-buffer update data must be non-empty and fit in 32 bits");
        if (((offset | (uint32_t) data_size) & 3) != 0)
            return luaL_error(L, "storage-buffer update offset and data size must be four-byte aligned");

        const uint32_t buffer_size = dmDRP::GetStorageBufferSize(context, buffer);
        if (offset > buffer_size || data_size > buffer_size - offset)
            return luaL_error(L, "storage-buffer update range exceeds the %u-byte buffer", buffer_size);

        if (!dmDRP::UpdateStorageBuffer(context, buffer, offset, (uint32_t) data_size, data))
            return luaL_error(L, "failed to update storage buffer");
        lua_pushboolean(L, 1);
        return 1;
    }

    static int GetStorageBufferSize(lua_State* L)
    {
        DM_LUA_STACK_CHECK(L, 1);
        DRPContext* context = CheckContext(L);
        const StorageBufferId buffer = CheckStorageBuffer(L, context, 1);
        lua_pushnumber(L, dmDRP::GetStorageBufferSize(context, buffer));
        return 1;
    }

    static int BindStorageBuffer(lua_State* L)
    {
        DM_LUA_STACK_CHECK(L, 1);

        DRPContext* context = CheckContext(L);
        const StorageBufferId buffer = CheckStorageBuffer(L, context, 1);
        const uint32_t set = CheckUint32(L, 2, "descriptor set", true);
        const uint32_t binding = CheckUint32(L, 3, "descriptor binding", true);
        if (set >= MAX_DESCRIPTOR_SETS)
            return luaL_error(L, "descriptor set must be less than %u", MAX_DESCRIPTOR_SETS);
        if (binding >= MAX_BINDINGS_PER_SET)
            return luaL_error(L, "descriptor binding must be less than %u", MAX_BINDINGS_PER_SET);

        if (!dmDRP::BindStorageBuffer(context, buffer, set, binding))
            return luaL_error(L, "failed to bind storage buffer");
        lua_pushboolean(L, 1);
        return 1;
    }

    static int UnbindStorageBuffer(lua_State* L)
    {
        DM_LUA_STACK_CHECK(L, 1);
        DRPContext* context = CheckContext(L);
        const StorageBufferId buffer = CheckStorageBuffer(L, context, 1);
        if (!dmDRP::UnbindStorageBuffer(context, buffer))
            return luaL_error(L, "failed to unbind storage buffer");
        lua_pushboolean(L, 1);
        return 1;
    }

    static int DeleteStorageBuffer(lua_State* L)
    {
        DM_LUA_STACK_CHECK(L, 1);

        DRPContext* context = CheckContext(L);
        const StorageBufferId buffer = CheckStorageBuffer(L, context, 1);
        if (!dmDRP::DeleteStorageBuffer(context, buffer))
            return luaL_error(L, "failed to delete storage buffer");
        lua_pushboolean(L, 1);
        return 1;
    }

    static int Reset(lua_State* L)
    {
        DM_LUA_STACK_CHECK(L, 1);
        DRPContext* context = CheckContext(L);
        DeleteAllStorageBuffers(context);
        lua_pushboolean(L, 1);
        return 1;
    }

    static const luaL_reg ModuleMethods[] =
    {
        {"get_capabilities",          GetCapabilities},
        {"create_storage_buffer",     CreateStorageBuffer},
        {"resize_storage_buffer",     ResizeStorageBuffer},
        {"update_storage_buffer",     UpdateStorageBuffer},
        {"get_storage_buffer_size",   GetStorageBufferSize},
        {"bind_storage_buffer",       BindStorageBuffer},
        {"unbind_storage_buffer",     UnbindStorageBuffer},
        {"delete_storage_buffer",     DeleteStorageBuffer},
        {"reset",                     Reset},
        {0, 0}
    };

    static void RegisterNumberConstant(lua_State* L, const char* name, lua_Number value)
    {
        lua_pushnumber(L, value);
        lua_setfield(L, -2, name);
    }

    void InitializeScript(lua_State* L, DRPContext* context)
    {
        DM_LUA_STACK_CHECK(L, 0);
        lua_pushlightuserdata(L, context);
        lua_setfield(L, LUA_REGISTRYINDEX, LIB_NAME ".context");
        luaL_register(L, LIB_NAME, ModuleMethods);
        RegisterNumberConstant(L, "API_VERSION", NATIVE_API_VERSION);
        RegisterNumberConstant(L, "BUFFER_USAGE_STREAM_DRAW", dmGraphics::BUFFER_USAGE_STREAM_DRAW);
        RegisterNumberConstant(L, "BUFFER_USAGE_DYNAMIC_DRAW", dmGraphics::BUFFER_USAGE_DYNAMIC_DRAW);
        RegisterNumberConstant(L, "BUFFER_USAGE_STATIC_DRAW", dmGraphics::BUFFER_USAGE_STATIC_DRAW);
        RegisterNumberConstant(L, "MAX_DESCRIPTOR_SETS", MAX_DESCRIPTOR_SETS);
        RegisterNumberConstant(L, "MAX_BINDINGS_PER_SET", MAX_BINDINGS_PER_SET);
        lua_pop(L, 1);
    }

    void FinalizeScript(lua_State* L)
    {
        DM_LUA_STACK_CHECK(L, 0);
        lua_pushnil(L);
        lua_setfield(L, LUA_REGISTRYINDEX, LIB_NAME ".context");
    }
}
