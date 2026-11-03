// Copyright 2026 Jhonny Göransson
// Licensed under the MIT License.

// Runs the production extension, graphics, and Lua sources against real Lua.
// Only engine-owned services are mocked; no GPU or window is required.
#include <dmsdk/sdk.h>
#include <dmsdk/gamesys/resources/res_material.h>
#include <dmsdk/gamesys/components/comp_light.h>
#include <dmsdk/gamesys/script.h>
extern "C" {
#include <lua/lualib.h>
}
#include "../drp/src/drp.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <map>
#include <set>
#include <string>
#include <vector>

struct ContextRegistry
{
    std::map<std::string, void*> m_Entries;
    bool m_RejectRegistration = false;
};

struct ExtensionParamsImpl
{
    HContextRegistry m_Registry;
};

struct Callbacks
{
    FExtensionAppInitialize m_AppInitialize;
    FExtensionAppFinalize m_AppFinalize;
    FExtensionInitialize m_Initialize;
    FExtensionFinalize m_Finalize;
    FExtensionOnEvent m_OnEvent;
};

static Callbacks s_Callbacks;

extern "C" void drp();

void ExtensionRegister(void*, uint32_t, const char* name,
    FExtensionAppInitialize app_initialize, FExtensionAppFinalize app_finalize,
    FExtensionInitialize initialize, FExtensionFinalize finalize,
    FExtensionUpdate, FExtensionOnEvent on_event)
{
    assert(strcmp(name, "DrpNative") == 0);
    s_Callbacks = {app_initialize, app_finalize, initialize, finalize, on_event};
}

HContextRegistry ExtensionAppParamsGetContextRegistry(ExtensionAppParams* params)
{
    return params->m_Impl->m_Registry;
}

HContextRegistry ExtensionParamsGetContextRegistry(ExtensionParams* params)
{
    return params->m_Impl->m_Registry;
}

int ContextRegistrySet(HContextRegistry registry, const char* name, void* context)
{
    if (!registry || (context && registry->m_RejectRegistration))
        return -1;
    if (context)
        registry->m_Entries[name] = context;
    else
        registry->m_Entries.erase(name);
    return 0;
}

void* ContextRegistryGet(HContextRegistry registry, const char* name)
{
    if (!registry)
        return 0;
    auto entry = registry->m_Entries.find(name);
    return entry == registry->m_Entries.end() ? 0 : entry->second;
}

void LogInternal(LogSeverity, const char*, const char*, ...) {}

namespace dmScript
{
    LuaStackCheck::LuaStackCheck(lua_State* L, int diff, const char* file, int line)
    : m_L(L), m_Filename(file), m_Linenumber(line), m_Top(lua_gettop(L)), m_Diff(diff) {}

    LuaStackCheck::~LuaStackCheck() { Verify(m_Diff); }

    void LuaStackCheck::Verify(int diff)
    {
        if (lua_gettop(m_L) != m_Top + diff)
        {
            fprintf(stderr, "%s:%d: unbalanced Lua stack\n", m_Filename, m_Linenumber);
            assert(false);
        }
    }
}

namespace dmGraphics
{
    struct VertexStream
    {
        std::string m_Name;
        uint32_t m_Size;
        Type m_Type;
        bool m_Normalize;
    };

    struct VertexStreamDeclaration
    {
        HContext m_Context;
        std::vector<VertexStream> m_Streams;
    };

    struct VertexDeclaration
    {
        HContext m_Context;
        std::vector<VertexStream> m_Streams;
        uint32_t m_Stride;
    };

    struct GraphicsContext
    {
        bool m_Alive = true;
        bool m_Supported = true;
        uint32_t m_DeleteCount = 0;
        std::map<HStorageBuffer, std::vector<char> > m_Buffers;
        std::map<uint32_t, HStorageBuffer> m_Bindings;
        bool m_FailStream = false;
        bool m_FailDeclaration = false;
        bool m_FailVertexBuffer = false;
        uint32_t m_VertexCreates = 0;
        uint32_t m_VertexDeletes = 0;
        std::set<HVertexStreamDeclaration> m_Streams;
        std::set<HVertexDeclaration> m_Declarations;
        std::map<HVertexBuffer, std::vector<float> > m_Vertices;
    };

    static HStorageBuffer s_NextBuffer = 1;
    static std::map<HVertexBuffer, HContext> s_VertexOwners;

    HVertexStreamDeclaration NewVertexStreamDeclaration(HContext context)
    {
        assert(context && context->m_Alive);
        if (context->m_FailStream)
            return 0;
        auto stream = new VertexStreamDeclaration{context, {}};
        context->m_Streams.insert(stream);
        return stream;
    }

    void AddVertexStream(HVertexStreamDeclaration declaration, const char* name,
        uint32_t size, Type type, bool normalize)
    {
        assert(declaration && declaration->m_Context->m_Alive);
        declaration->m_Streams.push_back({name, size, type, normalize});
    }

    void DeleteVertexStreamDeclaration(HVertexStreamDeclaration declaration)
    {
        assert(declaration && declaration->m_Context->m_Alive);
        assert(declaration->m_Context->m_Streams.erase(declaration) == 1);
        delete declaration;
    }

    HVertexDeclaration NewVertexDeclaration(HContext context,
        HVertexStreamDeclaration stream, uint32_t stride)
    {
        assert(context && context->m_Alive && stream->m_Context == context);
        if (context->m_FailDeclaration)
            return 0;
        auto declaration = new VertexDeclaration{context, stream->m_Streams, stride};
        context->m_Declarations.insert(declaration);
        return declaration;
    }

    void DeleteVertexDeclaration(HVertexDeclaration declaration)
    {
        assert(declaration && declaration->m_Context->m_Alive);
        assert(declaration->m_Context->m_Declarations.erase(declaration) == 1);
        delete declaration;
    }

    HVertexBuffer NewVertexBuffer(HContext context, uint32_t size, const void* data, BufferUsage usage)
    {
        assert(context && context->m_Alive && data && size % sizeof(float) == 0);
        assert(usage == BUFFER_USAGE_STATIC_DRAW);
        if (context->m_FailVertexBuffer)
            return 0;
        HVertexBuffer buffer = s_NextBuffer++;
        auto& vertices = context->m_Vertices[buffer];
        vertices.resize(size / sizeof(float));
        memcpy(vertices.data(), data, size);
        s_VertexOwners[buffer] = context;
        ++context->m_VertexCreates;
        return buffer;
    }

    void DeleteVertexBuffer(HVertexBuffer buffer)
    {
        auto owner = s_VertexOwners.find(buffer);
        assert(owner != s_VertexOwners.end() && owner->second->m_Alive);
        assert(owner->second->m_Vertices.erase(buffer) == 1);
        ++owner->second->m_VertexDeletes;
        s_VertexOwners.erase(owner);
    }

    static std::vector<char>& Buffer(HContext context, HStorageBuffer buffer)
    {
        assert(context && context->m_Alive);
        auto entry = context->m_Buffers.find(buffer);
        assert(entry != context->m_Buffers.end());
        return entry->second;
    }

    AdapterFamily GetInstalledAdapterFamily() { return ADAPTER_FAMILY_NULL; }

    bool IsContextFeatureSupported(HContext context, ContextFeature)
    {
        assert(context && context->m_Alive);
        return context->m_Supported;
    }

    void GetGraphicsContextLimits(HContext context, GraphicsContextLimits& limits)
    {
        assert(context && context->m_Alive);
        memset(&limits, 0, sizeof(limits));
        limits.m_MaxStorageBufferRange = 4096;
    }

    HStorageBuffer NewStorageBuffer(HContext context, uint32_t size, const void* data, BufferUsage)
    {
        assert(context && context->m_Alive);
        HStorageBuffer buffer = s_NextBuffer++;
        auto& bytes = context->m_Buffers[buffer];
        bytes.resize(size);
        if (data)
            memcpy(bytes.data(), data, size);
        return buffer;
    }

    void DisableStorageBuffer(HContext context, HStorageBuffer buffer)
    {
        Buffer(context, buffer);
        for (auto entry = context->m_Bindings.begin(); entry != context->m_Bindings.end();)
        {
            if (entry->second == buffer)
                entry = context->m_Bindings.erase(entry);
            else
                ++entry;
        }
    }

    void DeleteStorageBuffer(HContext context, HStorageBuffer buffer)
    {
        DisableStorageBuffer(context, buffer);
        context->m_Buffers.erase(buffer);
        ++context->m_DeleteCount;
    }

    void SetStorageBufferData(HContext context, HStorageBuffer buffer, uint32_t size,
        const void* data, BufferUsage)
    {
        auto& bytes = Buffer(context, buffer);
        bytes.resize(size);
        if (data)
            memcpy(bytes.data(), data, size);
    }

    void SetStorageBufferSubData(HContext context, HStorageBuffer buffer, uint32_t offset,
        uint32_t size, const void* data)
    {
        auto& bytes = Buffer(context, buffer);
        assert(offset <= bytes.size() && size <= bytes.size() - offset);
        memcpy(bytes.data() + offset, data, size);
    }

    uint32_t GetStorageBufferSize(HContext context, HStorageBuffer buffer)
    {
        return (uint32_t) Buffer(context, buffer).size();
    }

    void EnableStorageBuffer(HContext context, HStorageBuffer buffer, uint32_t set, uint32_t binding)
    {
        Buffer(context, buffer);
        context->m_Bindings[set * dmDRP::MAX_BINDINGS_PER_SET + binding] = buffer;
    }
}

namespace dmRender
{
    struct Material
    {
        uint32_t m_TagListKey;
    };

    struct Dispatch
    {
        RenderListDispatchFn m_Function;
        void* m_UserData;
    };

    struct RenderContext
    {
        bool m_Alive = true;
        bool m_FailDispatch = false;
        bool m_FailEntry = false;
        bool m_InBatch = false;
        uint32_t m_SubmitCount = 0;
        std::vector<Dispatch> m_Dispatches;
        std::vector<RenderListEntry> m_Entries;
        std::vector<RenderObject*> m_Objects;

        void BeginFrame()
        {
            assert(m_Alive);
            // Engine render-list entries and dispatch handles expire each frame.
            m_Dispatches.clear();
            m_Entries.clear();
            m_Objects.clear();
        }

        void DispatchEntries(RenderListOperation operation)
        {
            m_InBatch = operation == RENDER_LIST_OPERATION_BATCH;
            for (uint32_t i = 0; i < m_Entries.size(); ++i)
            {
                auto& entry = m_Entries[i];
                assert(entry.m_Dispatch < m_Dispatches.size());
                auto& dispatch = m_Dispatches[entry.m_Dispatch];
                RenderListDispatchParams params = {};
                params.m_Context = this;
                params.m_UserData = dispatch.m_UserData;
                params.m_Operation = operation;
                params.m_Buf = m_Entries.data();
                params.m_Begin = &i;
                params.m_End = &i + 1;
                dispatch.m_Function(params);
            }
            m_InBatch = false;
        }
    };

    // These SDK value constructors have no rendering side effects.
    StencilTestParams::StencilTestParams() { Init(); }
    void StencilTestParams::Init() { memset(this, 0, sizeof(*this)); }
    RenderObject::RenderObject() { Init(); }
    void RenderObject::Init()
    {
        memset((void*) this, 0, sizeof(*this));
        m_WorldTransform = dmVMath::Matrix4::identity();
        m_TextureTransform = dmVMath::Matrix4::identity();
    }

    HRenderListDispatch RenderListMakeDispatch(HRenderContext context,
        RenderListDispatchFn callback, RenderListVisibilityFn visibility, void* user_data)
    {
        assert(context && context->m_Alive && callback && !visibility);
        if (context->m_FailDispatch)
            return 0xff;
        context->m_Dispatches.push_back({callback, user_data});
        return (HRenderListDispatch) (context->m_Dispatches.size() - 1);
    }

    RenderListEntry* RenderListAlloc(HRenderContext context, uint32_t count)
    {
        assert(context && context->m_Alive && count == 1);
        if (context->m_FailEntry)
            return 0;
        size_t offset = context->m_Entries.size();
        context->m_Entries.resize(offset + count);
        return &context->m_Entries[offset];
    }

    void RenderListSubmit(HRenderContext context, RenderListEntry* begin, RenderListEntry* end)
    {
        assert(context && context->m_Alive && end == begin + 1);
        assert(begin >= context->m_Entries.data() && end <= context->m_Entries.data() + context->m_Entries.size());
        ++context->m_SubmitCount;
    }

    uint32_t GetMaterialTagListKey(HMaterial material)
    {
        assert(material);
        return material->m_TagListKey;
    }

    Result AddToRender(HRenderContext context, RenderObject* object)
    {
        assert(context && context->m_Alive && context->m_InBatch && object);
        context->m_Objects.push_back(object);
        return RESULT_OK;
    }
}

struct ResourceFactory
{
    bool m_Alive = true;
    bool m_FailGet = false;
    uint32_t m_GetCount = 0;
    uint32_t m_ReleaseCount = 0;
    std::map<std::string, dmGameSystem::MaterialResource*> m_Resources;
    std::map<void*, uint32_t> m_References;
    dmRender::HRenderContext m_RenderContext = 0;
};

ResourceResult ResourceGetWithExt(HResourceFactory factory, const char* path,
    const char* extension, void** resource)
{
    assert(factory && factory->m_Alive && strcmp(extension, "materialc") == 0);
    ++factory->m_GetCount;
    auto entry = factory->m_Resources.find(path);
    if (factory->m_FailGet || entry == factory->m_Resources.end())
        return RESOURCE_RESULT_RESOURCE_NOT_FOUND;
    *resource = entry->second;
    ++factory->m_References[entry->second];
    return RESOURCE_RESULT_OK;
}

void ResourceRelease(HResourceFactory factory, void* resource)
{
    assert(factory && factory->m_Alive && resource);
    assert(factory->m_RenderContext && factory->m_RenderContext->m_Alive);
    auto entry = factory->m_References.find(resource);
    assert(entry != factory->m_References.end() && entry->second > 0);
    if (--entry->second == 0)
        factory->m_References.erase(entry);
    ++factory->m_ReleaseCount;
}

static void RunLua(lua_State* L, const char* source)
{
    int top = lua_gettop(L);
    if (luaL_dostring(L, source))
    {
        fprintf(stderr, "%s\n", lua_tostring(L, -1));
        assert(false);
    }
    assert(lua_gettop(L) == top);
}

struct Application
{
    ContextRegistry m_Registry;
    ExtensionParamsImpl m_Impl;
    ExtensionAppParams m_AppParams;
    ExtensionParams m_Params;
    dmGraphics::GraphicsContext m_Graphics;
    dmRender::RenderContext m_Render;
    ResourceFactory m_Factory;
    dmRender::Material m_Material = {23};
    dmGameSystem::MaterialResource m_MaterialResource = {};
    lua_State* m_L;

    Application() : m_Impl{&m_Registry}, m_AppParams{}, m_Params{}, m_L(luaL_newstate())
    {
        assert(m_L);
        luaL_openlibs(m_L);
        m_AppParams.m_Impl = &m_Impl;
        m_Params.m_Impl = &m_Impl;
        // Deliberately leave the deprecated field empty: initialization must
        // retrieve Lua through the shared context registry.
        ContextRegistrySet(&m_Registry, LUA_CONTEXT_NAME, m_L);
        m_Factory.m_RenderContext = &m_Render;
        m_MaterialResource.m_Material = &m_Material;
        m_Factory.m_Resources["/drp/features/hdr/tonemap.materialc"] = &m_MaterialResource;
    }

    ~Application()
    {
        assert(ContextRegistryGet(&m_Registry, "drp") == 0);
        assert(m_Graphics.m_Buffers.empty());
        assert(m_Graphics.m_Streams.empty() && m_Graphics.m_Declarations.empty() && m_Graphics.m_Vertices.empty());
        assert(m_Factory.m_References.empty());
        lua_close(m_L);
    }

    dmDRP::DRPContext* Context()
    {
        return static_cast<dmDRP::DRPContext*>(ContextRegistryGet(&m_Registry, "drp"));
    }

    void AttachGraphics()
    {
        ContextRegistrySet(&m_Registry, GRAPHICS_CONTEXT_NAME, &m_Graphics);
    }

    void Start()
    {
        assert(s_Callbacks.m_AppInitialize(&m_AppParams) == EXTENSION_RESULT_OK);
        AttachGraphics();
        assert(s_Callbacks.m_Initialize(&m_Params) == EXTENSION_RESULT_OK);
    }

    void AttachRendering()
    {
        // Render and factory contexts become available after extension Initialize.
        ContextRegistrySet(&m_Registry, RENDER_CONTEXT_NAME, &m_Render);
        ContextRegistrySet(&m_Registry, RESOURCE_FACTORY_CONTEXT_NAME, &m_Factory);
    }

    void Stop()
    {
        ExtensionEvent event = {EXTENSION_EVENT_ID_ENGINE_DELETE};
        s_Callbacks.m_OnEvent(&m_Params, &event);
        s_Callbacks.m_OnEvent(&m_Params, &event);
        m_Render.m_Alive = false;
        m_Factory.m_Alive = false;
        assert(s_Callbacks.m_Finalize(&m_Params) == EXTENSION_RESULT_OK);
        assert(s_Callbacks.m_Finalize(&m_Params) == EXTENSION_RESULT_OK);
        m_Graphics.m_Alive = false;
        assert(s_Callbacks.m_AppFinalize(&m_AppParams) == EXTENSION_RESULT_OK);
    }
};

// Verifies independent native contexts keep their storage buffers and IDs isolated.
static void TestIndependentContexts()
{
    dmGraphics::GraphicsContext gpu_a, gpu_b;
    dmDRP::DRPContext a, b;
    assert(!dmDRP::GetGraphicsContext(&a));
    dmDRP::InitializeGraphics(&a, &gpu_a);
    dmDRP::InitializeGraphics(&b, &gpu_b);
    auto id_a = dmDRP::CreateStorageBuffer(&a, 4, "aaaa", dmGraphics::BUFFER_USAGE_DYNAMIC_DRAW);
    auto id_b = dmDRP::CreateStorageBuffer(&b, 8, "bbbbbbbb", dmGraphics::BUFFER_USAGE_STATIC_DRAW);
    assert(id_a == 1 && id_b == 1);
    assert(dmDRP::GetStorageBufferSize(&a, id_a) == 4);
    assert(dmDRP::GetStorageBufferSize(&b, id_b) == 8);
    assert(dmDRP::BindStorageBuffer(&a, id_a, 1, 2));
    dmDRP::DeleteAllStorageBuffers(&a);
    assert(gpu_a.m_Buffers.empty() && gpu_a.m_Bindings.empty());
    assert(!dmDRP::IsStorageBufferValid(&a, id_a));
    assert(dmDRP::IsStorageBufferValid(&b, id_b));
    auto next = dmDRP::CreateStorageBuffer(&a, 4, 0, dmGraphics::BUFFER_USAGE_DYNAMIC_DRAW);
    assert(next > id_a);
    dmDRP::FinalizeGraphics(&a);
    assert(!dmDRP::GetGraphicsContext(&a));
    assert(!dmDRP::CreateStorageBuffer(&a, 4, 0, dmGraphics::BUFFER_USAGE_DYNAMIC_DRAW));
    assert(dmDRP::GetStorageBufferSize(&b, id_b) == 8);
    dmDRP::FinalizeGraphics(&b);
    assert(gpu_a.m_Buffers.empty() && gpu_b.m_Buffers.empty());
}

// Verifies Lua detachment and graphics cleanup remain safe across repeated lifecycle calls.
static void TestLifecycleAndLua()
{
    Application app, other;
    assert(s_Callbacks.m_AppInitialize(&app.m_AppParams) == EXTENSION_RESULT_OK);
    assert(s_Callbacks.m_AppInitialize(&other.m_AppParams) == EXTENSION_RESULT_OK);
    assert(app.Context() && other.Context() && app.Context() != other.Context());
    auto original = app.Context();
    assert(s_Callbacks.m_AppInitialize(&app.m_AppParams) != EXTENSION_RESULT_OK);
    assert(app.Context() == original);
    assert(!app.Context()->m_GraphicsContext);
    app.AttachGraphics();
    other.AttachGraphics();
    assert(s_Callbacks.m_Initialize(&app.m_Params) == EXTENSION_RESULT_OK);
    assert(s_Callbacks.m_Initialize(&other.m_Params) == EXTENSION_RESULT_OK);
    RunLua(app.m_L, R"LUA(
        saved_create = drp_native.create_storage_buffer
        saved_reset = drp_native.reset
        saved_capabilities = drp_native.get_capabilities
        assert(require('drp_native') == drp_native)
        assert(drp_native.get_capabilities().features.storage_buffers)
        id = drp_native.create_storage_buffer(4, nil, 'abcd')
        assert(drp_native.resize_storage_buffer(id, 8, nil, 'abcdefgh'))
        assert(drp_native.get_storage_buffer_size(id) == 8)
        assert(drp_native.update_storage_buffer(id, 4, 'WXYZ'))
        assert(drp_native.bind_storage_buffer(id, 1, 2))
        assert(drp_native.unbind_storage_buffer(id))
    )LUA");
    const auto& bytes = app.m_Graphics.m_Buffers.begin()->second;
    assert(bytes.size() == 8 && memcmp(bytes.data(), "abcdWXYZ", 8) == 0);
    RunLua(app.m_L, R"LUA(
        assert(drp_native.reset())
        assert(not pcall(drp_native.get_storage_buffer_size, id))
        next_id = saved_create(4)
        assert(next_id > id)
    )LUA");
    RunLua(other.m_L, "id = drp_native.create_storage_buffer(12); assert(id == 1)");
    assert(app.m_Graphics.m_Buffers.size() == 1 && other.m_Graphics.m_Buffers.size() == 1);
    assert(s_Callbacks.m_Finalize(&app.m_Params) == EXTENSION_RESULT_OK);
    assert(app.m_Graphics.m_DeleteCount == 2 && app.m_Graphics.m_Buffers.empty());
    assert(!app.Context()->m_GraphicsContext);
    assert(s_Callbacks.m_Finalize(&app.m_Params) == EXTENSION_RESULT_OK);
    assert(app.m_Graphics.m_DeleteCount == 2);
    RunLua(app.m_L, R"LUA(
        for _, callback in ipairs({saved_create, saved_reset, saved_capabilities}) do
            local ok, message = pcall(callback, 4)
            assert(not ok and message:find('context'), tostring(message))
        end
    )LUA");
    RunLua(other.m_L, "assert(drp_native.get_storage_buffer_size(id) == 12)");
    app.m_Graphics.m_Alive = false;
    assert(s_Callbacks.m_AppFinalize(&app.m_AppParams) == EXTENSION_RESULT_OK);
    assert(!app.Context());
    assert(s_Callbacks.m_AppFinalize(&app.m_AppParams) == EXTENSION_RESULT_OK);
    assert(s_Callbacks.m_Finalize(&app.m_Params) == EXTENSION_RESULT_OK);
    RunLua(app.m_L, "assert(not pcall(saved_create, 4))");

    // A new application context can attach to the same Lua state safely.
    assert(s_Callbacks.m_AppInitialize(&app.m_AppParams) == EXTENSION_RESULT_OK);
    app.m_Graphics.m_Alive = true;
    assert(s_Callbacks.m_Initialize(&app.m_Params) == EXTENSION_RESULT_OK);
    RunLua(app.m_L, "assert(drp_native.create_storage_buffer(4) == 1); assert(drp_native.reset())");
    assert(s_Callbacks.m_Finalize(&app.m_Params) == EXTENSION_RESULT_OK);
    app.m_Graphics.m_Alive = false;
    assert(s_Callbacks.m_AppFinalize(&app.m_AppParams) == EXTENSION_RESULT_OK);
    assert(s_Callbacks.m_Finalize(&other.m_Params) == EXTENSION_RESULT_OK);
    other.m_Graphics.m_Alive = false;
    assert(s_Callbacks.m_AppFinalize(&other.m_AppParams) == EXTENSION_RESULT_OK);
}

// Verifies failed startup never leaks a registered context or touches missing graphics.
static void TestFailedInitialization()
{
    Application app;
    app.m_Impl.m_Registry = 0;
    assert(s_Callbacks.m_AppInitialize(&app.m_AppParams) != EXTENSION_RESULT_OK);
    assert(s_Callbacks.m_Initialize(&app.m_Params) != EXTENSION_RESULT_OK);
    app.m_Impl.m_Registry = &app.m_Registry;
    app.AttachGraphics();
    assert(s_Callbacks.m_Initialize(&app.m_Params) != EXTENSION_RESULT_OK);
    assert(!app.Context());

    app.m_Registry.m_RejectRegistration = true;
    assert(s_Callbacks.m_AppInitialize(&app.m_AppParams) != EXTENSION_RESULT_OK);
    assert(!app.Context());
    app.m_Registry.m_RejectRegistration = false;
    assert(s_Callbacks.m_AppInitialize(&app.m_AppParams) == EXTENSION_RESULT_OK);

    ContextRegistrySet(&app.m_Registry, LUA_CONTEXT_NAME, 0);
    assert(s_Callbacks.m_Initialize(&app.m_Params) != EXTENSION_RESULT_OK);
    assert(!app.Context()->m_GraphicsContext);
    ContextRegistrySet(&app.m_Registry, LUA_CONTEXT_NAME, app.m_L);

    ContextRegistrySet(&app.m_Registry, GRAPHICS_CONTEXT_NAME, 0);
    assert(s_Callbacks.m_Initialize(&app.m_Params) != EXTENSION_RESULT_OK);
    assert(!app.Context()->m_GraphicsContext && app.m_Graphics.m_DeleteCount == 0);
    // Failed Initialize is not followed by Finalize in the engine.
    app.m_Graphics.m_Alive = false;
    assert(s_Callbacks.m_AppFinalize(&app.m_AppParams) == EXTENSION_RESULT_OK);
    assert(!app.Context());

    // Application startup can also stop before Initialize runs at all.
    assert(s_Callbacks.m_AppInitialize(&app.m_AppParams) == EXTENSION_RESULT_OK);
    assert(s_Callbacks.m_AppFinalize(&app.m_AppParams) == EXTENSION_RESULT_OK);
    assert(!app.Context() && app.m_Graphics.m_DeleteCount == 0);
}

static const char* const TONEMAP_PATH = "/drp/features/hdr/tonemap.materialc";

static void AssertFullscreenTriangle(const dmRender::RenderObject& object, const Application& app)
{
    assert(object.m_PrimitiveType == dmGraphics::PRIMITIVE_TRIANGLES);
    assert(object.m_VertexStart == 0 && object.m_VertexCount == 3);
    assert(!object.m_IndexBuffer);
    const auto declaration = object.m_VertexDeclaration;
    assert(declaration && declaration->m_Stride == 6 * sizeof(float));
    assert(declaration->m_Streams.size() == 2);
    const auto& position = declaration->m_Streams[0];
    const auto& uv = declaration->m_Streams[1];
    assert(position.m_Name == "position" && position.m_Size == 4);
    assert(uv.m_Name == "texcoord0" && uv.m_Size == 2);
    assert(position.m_Type == dmGraphics::TYPE_FLOAT && !position.m_Normalize);
    assert(uv.m_Type == dmGraphics::TYPE_FLOAT && !uv.m_Normalize);
    const auto& vertices = app.m_Graphics.m_Vertices.at(object.m_VertexBuffer);
    assert(vertices.size() == 18);
    for (size_t i = 0; i < 3; ++i)
    {
        const float* v = &vertices[i * 6];
        assert(v[2] == 0 && v[3] == 1);
        // Clip-space corners must sample the corresponding texture corners.
        assert(v[4] == (v[0] + 1) * 0.5f && v[5] == (v[1] + 1) * 0.5f);
    }
    // Every clip-space corner is on or inside the counterclockwise triangle.
    const float corners[][2] = {{-1, -1}, {-1, 1}, {1, -1}, {1, 1}};
    for (const auto& corner : corners)
    {
        for (size_t i = 0; i < 3; ++i)
        {
            const float* a = &vertices[i * 6];
            const float* b = &vertices[((i + 1) % 3) * 6];
            assert((b[0] - a[0]) * (corner[1] - a[1]) - (b[1] - a[1]) * (corner[0] - a[0]) >= 0);
        }
    }
}

// Verifies late context discovery, per-frame render-list submission and deferred drawing with reusable fullscreen geometry.
static void TestFullscreenSubmission()
{
    Application app;
    app.Start();
    RunLua(app.m_L, R"LUA(
        saved_fullscreen = drp_native.submit_fullscreen
        local ok, reason = saved_fullscreen('/drp/features/hdr/tonemap.materialc')
        assert(not ok and type(reason) == 'string')
    )LUA");
    app.AttachRendering();
    ContextRegistrySet(&app.m_Registry, RESOURCE_FACTORY_CONTEXT_NAME, 0);
    RunLua(app.m_L, "local ok, err = saved_fullscreen('/drp/features/hdr/tonemap.materialc'); assert(not ok and type(err) == 'string')");
    ContextRegistrySet(&app.m_Registry, RESOURCE_FACTORY_CONTEXT_NAME, &app.m_Factory);
    RunLua(app.m_L, "local ok, err = saved_fullscreen(''); assert(not ok and type(err) == 'string')");
    assert(app.m_Factory.m_GetCount == 0 && app.m_Graphics.m_VertexCreates == 0);
    for (uint32_t frame = 0; frame < 3; ++frame)
    {
        app.m_Render.BeginFrame();
        // Vary the handle each frame, exposing cached dispatch handles.
        for (uint32_t i = 0; i < frame; ++i)
            app.m_Render.m_Dispatches.push_back({0, 0});
        RunLua(app.m_L, "assert(saved_fullscreen('/drp/features/hdr/tonemap.materialc'))");
        assert(app.m_Render.m_Entries.size() == 1 && app.m_Render.m_Objects.empty());
        assert(app.m_Render.m_SubmitCount == frame + 1);
        const auto& entry = app.m_Render.m_Entries[0];
        assert(entry.m_TagListKey == app.m_Material.m_TagListKey);
        assert(entry.m_Visibility == dmRender::VISIBILITY_FULL);
        app.m_Render.DispatchEntries(dmRender::RENDER_LIST_OPERATION_BEGIN);
        assert(app.m_Render.m_Objects.empty());
        app.m_Render.DispatchEntries(dmRender::RENDER_LIST_OPERATION_BATCH);
        assert(app.m_Render.m_Objects.size() == 1);
        assert(app.m_Render.m_Objects[0]->m_Material == &app.m_Material);
        AssertFullscreenTriangle(*app.m_Render.m_Objects[0], app);
        app.m_Render.DispatchEntries(dmRender::RENDER_LIST_OPERATION_END);
        assert(app.m_Render.m_Objects.size() == 1);
    }
    assert(app.m_Graphics.m_VertexCreates == 1 && app.m_Graphics.m_Vertices.size() == 1);
    assert(app.m_Graphics.m_Declarations.size() == 1 && app.m_Graphics.m_Streams.empty());
    assert(app.m_Factory.m_GetCount == 1 && app.m_Factory.m_References.size() == 1);
    app.Stop();
    assert(app.m_Graphics.m_VertexDeletes == 1 && app.m_Factory.m_ReleaseCount == 1);
    RunLua(app.m_L, "local ok, err = pcall(saved_fullscreen, '/drp/features/hdr/tonemap.materialc'); assert(not ok and err:find('context'))");
}

// Verifies multiple material passes share geometry and cached render objects survive cache growth and material hot reload.
static void TestFullscreenMaterials()
{
    Application app;
    app.Start();
    app.AttachRendering();
    const char* error = 0;
    assert(dmDRP::SubmitFullscreen(app.Context(), TONEMAP_PATH, &error));
    dmRender::Material materials[12];
    dmGameSystem::MaterialResource resources[12] = {};
    for (uint32_t i = 0; i < 12; ++i)
    {
        materials[i].m_TagListKey = 100 + i;
        resources[i].m_Material = &materials[i];
        std::string path = "/pass" + std::to_string(i) + ".materialc";
        app.m_Factory.m_Resources[path] = &resources[i];
        assert(dmDRP::SubmitFullscreen(app.Context(), path.c_str(), &error));
    }
    assert(app.m_Render.m_Entries.size() == 13 && app.m_Render.m_Objects.empty());
    app.m_Render.DispatchEntries(dmRender::RENDER_LIST_OPERATION_BATCH);
    assert(app.m_Render.m_Objects.size() == 13);
    assert(app.m_Render.m_Objects[0]->m_Material == &app.m_Material);
    const auto first_object = app.m_Render.m_Objects[0];
    for (uint32_t i = 0; i < 12; ++i)
    {
        assert(app.m_Render.m_Entries[i + 1].m_TagListKey == materials[i].m_TagListKey);
        assert(app.m_Render.m_Objects[i + 1]->m_Material == &materials[i]);
        assert(app.m_Render.m_Objects[i + 1]->m_VertexBuffer == first_object->m_VertexBuffer);
    }
    dmRender::Material reloaded = {902};
    app.m_MaterialResource.m_Material = &reloaded;
    app.m_Render.BeginFrame();
    assert(dmDRP::SubmitFullscreen(app.Context(), TONEMAP_PATH, &error));
    assert(app.m_Render.m_Entries[0].m_TagListKey == reloaded.m_TagListKey);
    app.m_Render.DispatchEntries(dmRender::RENDER_LIST_OPERATION_BATCH);
    assert(app.m_Render.m_Objects[0] == first_object);
    assert(first_object->m_Material == &reloaded);
    assert(app.m_Factory.m_GetCount == 13 && app.m_Graphics.m_VertexCreates == 1);
    app.Stop();
    assert(app.m_Factory.m_ReleaseCount == 13);
}

// Verifies failed fullscreen allocation releases partial resources and allows a later retry.
static void TestFullscreenAllocationFailures()
{
    for (uint32_t failure = 0; failure < 4; ++failure)
    {
        Application app;
        app.Start();
        app.AttachRendering();
        app.m_Factory.m_FailGet = failure == 0;
        app.m_Graphics.m_FailStream = failure == 1;
        app.m_Graphics.m_FailDeclaration = failure == 2;
        app.m_Graphics.m_FailVertexBuffer = failure == 3;
        const char* error = 0;
        assert(!dmDRP::SubmitFullscreen(app.Context(), TONEMAP_PATH, &error) && error);
        assert(app.m_Render.m_Entries.empty() && app.m_Render.m_Objects.empty());
        assert(app.m_Graphics.m_Streams.empty() && app.m_Graphics.m_Declarations.empty() && app.m_Graphics.m_Vertices.empty());
        assert(app.m_Factory.m_References.empty());
        app.m_Factory.m_FailGet = false;
        app.m_Graphics.m_FailStream = false;
        app.m_Graphics.m_FailDeclaration = false;
        app.m_Graphics.m_FailVertexBuffer = false;
        assert(dmDRP::SubmitFullscreen(app.Context(), TONEMAP_PATH, &error));
        app.m_Render.DispatchEntries(dmRender::RENDER_LIST_OPERATION_BATCH);
        assert(app.m_Render.m_Objects.size() == 1);
        app.Stop();
    }
}

// Verifies render-list exhaustion reports failure without drawing and permits the next frame to retry.
static void TestFullscreenRenderListFailures()
{
    for (uint32_t failure = 0; failure < 2; ++failure)
    {
        Application app;
        app.Start();
        app.AttachRendering();
        app.m_Render.m_FailDispatch = failure == 0;
        app.m_Render.m_FailEntry = failure == 1;
        const char* error = 0;
        assert(!dmDRP::SubmitFullscreen(app.Context(), TONEMAP_PATH, &error) && error);
        assert(app.m_Render.m_SubmitCount == 0 && app.m_Render.m_Objects.empty());
        app.m_Render.m_FailDispatch = false;
        app.m_Render.m_FailEntry = false;
        app.m_Render.BeginFrame();
        assert(dmDRP::SubmitFullscreen(app.Context(), TONEMAP_PATH, &error));
        app.m_Render.DispatchEntries(dmRender::RENDER_LIST_OPERATION_BATCH);
        assert(app.m_Render.m_SubmitCount == 1 && app.m_Render.m_Objects.size() == 1);
        app.Stop();
    }
}

// Verifies shutdown releases render-owned resources before render destruction and refuses late resource recreation.
static void TestFullscreenShutdown()
{
    Application app;
    app.Start();
    app.AttachRendering();
    const char* error = 0;
    assert(dmDRP::SubmitFullscreen(app.Context(), TONEMAP_PATH, &error));
    ExtensionEvent event = {EXTENSION_EVENT_ID_ENGINE_DELETE};
    s_Callbacks.m_OnEvent(&app.m_Params, &event);
    assert(app.m_Graphics.m_Vertices.empty() && app.m_Factory.m_References.empty());
    app.m_Render.DispatchEntries(dmRender::RENDER_LIST_OPERATION_BATCH);
    assert(app.m_Render.m_Objects.empty());
    assert(!dmDRP::SubmitFullscreen(app.Context(), TONEMAP_PATH, &error) && error);
    RunLua(app.m_L, "local ok, reason = drp_native.submit_fullscreen('/drp/features/hdr/tonemap.materialc'); assert(not ok and type(reason) == 'string')");
    assert(app.m_Graphics.m_VertexCreates == 1 && app.m_Factory.m_GetCount == 1);
    app.Stop();
    assert(app.m_Graphics.m_VertexDeletes == 1 && app.m_Factory.m_ReleaseCount == 1);
}

// Engine-light mocks preserve versioned handles and simulate compact-index changes.
static std::map<dmRender::HLightInstance, dmRender::LightInstanceRenderData> s_Lights;
static uint64_t s_LightRevision = 1;
namespace dmScript
{
    void GetComponentFromLua(lua_State* L, int index, const char* type,
        dmGameObject::HComponentWorld*, dmGameObject::HComponent* component, dmMessage::URL*)
    {
        assert(strcmp(type, "lightc") == 0);
        *component = (dmGameObject::HComponent)(uintptr_t)luaL_checkinteger(L, index);
    }
}
namespace dmGameSystem
{
    dmRender::HLightInstance CompLightGetLightInstance(HLightComponent light)
    {
        return (dmRender::HLightInstance)(uintptr_t)light;
    }
}
namespace dmRender
{
    bool GetLightInstanceRenderData(HRenderContext, HLightInstance handle, LightInstanceRenderData* data)
    {
        auto entry = s_Lights.find(handle);
        if (entry == s_Lights.end())
        {
            data->m_BufferIndex = INVALID_LIGHT_BUFFER_INDEX;
            data->m_BufferRevision = s_LightRevision;
            return false;
        }
        *data = entry->second;
        data->m_BufferRevision = s_LightRevision;
        return true;
    }
}

// Verifies native identity, per-frame compaction, invalidation, settings transactions and Lua-world sharing.
static void TestShadowRegistration()
{
    Application app;
    app.Start();
    app.AttachRendering();
    dmRender::LightInstanceRenderData light = {};
    light.m_Position = dmVMath::Point3(1, 2, 3);
    light.m_Direction = dmVMath::Vector3(0, 0, -1);
    light.m_Type = dmRender::LIGHT_TYPE_SPOT;
    light.m_Range = 10;
    light.m_OuterConeAngle = 1;
    light.m_BufferIndex = 4;
    s_Lights[65537] = light;
    RunLua(app.m_L, R"LUA(
        registration = drp_native.register_shadow_light(65537, {priority = 3, cache = true})
        assert(registration == 1)
        assert(not pcall(drp_native.register_shadow_light, 65537))
        local lights, revision = drp_native.get_shadow_lights()
        assert(#lights == 1 and lights[1].index == 4 and lights[1].position[3] == 3)
        assert(lights[1].cache and lights[1].priority == 3 and revision == 1)
        assert(not pcall(drp_native.update_shadow_light, registration, {priority = 10, softness = -1}))
        assert(drp_native.get_shadow_lights()[1].priority == 3)
        assert(not pcall(drp_native.update_shadow_light, registration, {enabled = 0}))
        assert(drp_native.reset()) -- Pipeline restart must not unregister game-object scripts.
        assert(#drp_native.get_shadow_lights() == 1)
        assert(#drp_native.pack_floats({1, 0, -2, 0.125}) == 16)
        assert(not pcall(drp_native.pack_floats, {0 / 0}))
        assert(not pcall(drp_native.pack_floats, {math.huge}))
        assert(not pcall(drp_native.pack_floats, {1, false}))
    )LUA");
    lua_State* render_lua = luaL_newstate();
    luaL_openlibs(render_lua);
    dmDRP::InitializeScript(render_lua, app.Context());
    s_Lights[65537].m_BufferIndex = 1;
    s_LightRevision = UINT64_MAX; // Kept native, never rounded through a Lua number.
    RunLua(render_lua, R"LUA(
        assert(drp_native.get_shadow_lights()[1].index == 1)
        drp_native.invalidate_shadows()
    )LUA");
    RunLua(app.m_L, "local _, revision = drp_native.get_shadow_lights(); assert(revision == 2)");
    s_Lights.erase(65537);
    s_Lights[131073] = light; // Same engine slot, different version must not inherit registration.
    RunLua(render_lua, "assert(#drp_native.get_shadow_lights() == 0)");
    RunLua(app.m_L, R"LUA(
        assert(drp_native.unregister_shadow_light(registration))
        assert(not drp_native.unregister_shadow_light(registration))
        assert(not pcall(drp_native.update_shadow_light, registration, {}))
        local next = drp_native.register_shadow_light(131073)
        assert(next > registration)
        drp_native.update_shadow_light(next, {enabled = false})
        assert(#drp_native.get_shadow_lights() == 0)
        drp_native.update_shadow_light(next, {enabled = true})
        assert(#drp_native.get_shadow_lights() == 1)
        drp_native.unregister_shadow_light(next)
    )LUA");
    dmDRP::FinalizeScript(render_lua);
    RunLua(render_lua, "assert(not pcall(drp_native.get_shadow_lights))");
    lua_close(render_lua);
    s_Lights.clear();
    app.Stop();
}

int main()
{
    drp();
    assert(s_Callbacks.m_AppInitialize && s_Callbacks.m_AppFinalize);
    assert(s_Callbacks.m_Initialize && s_Callbacks.m_Finalize && s_Callbacks.m_OnEvent);
    TestIndependentContexts();
    TestLifecycleAndLua();
    TestFailedInitialization();
    TestFullscreenSubmission();
    TestFullscreenMaterials();
    TestFullscreenAllocationFailures();
    TestFullscreenRenderListFailures();
    TestFullscreenShutdown();
    TestShadowRegistration();
    puts("native_context_spec: PASS");
    return 0;
}
