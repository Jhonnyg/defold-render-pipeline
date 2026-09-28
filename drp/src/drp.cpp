// Copyright 2026 Jhonny Göransson
// Licensed under the MIT License.

#include <dmsdk/sdk.h>

#include <new>

#include "drp.h"

static const char* const DRP_CONTEXT_NAME = "drp";

static dmExtension::Result AppInitialize(dmExtension::AppParams* params)
{
    HContextRegistry registry = ExtensionAppParamsGetContextRegistry(params);
    if (!registry || ContextRegistryGet(registry, DRP_CONTEXT_NAME))
    {
        dmLogError("DRP context registry is unavailable or already contains a DRP context");
        return dmExtension::RESULT_INIT_ERROR;
    }

    dmDRP::DRPContext* context = new (std::nothrow) dmDRP::DRPContext;
    if (!context)
        return dmExtension::RESULT_INIT_ERROR;

    if (ContextRegistrySet(registry, DRP_CONTEXT_NAME, context) != 0)
    {
        delete context;
        return dmExtension::RESULT_INIT_ERROR;
    }
    return dmExtension::RESULT_OK;
}

static dmExtension::Result Initialize(dmExtension::Params* params)
{
    HContextRegistry registry = ExtensionParamsGetContextRegistry(params);
    if (!registry)
        return dmExtension::RESULT_INIT_ERROR;

    dmDRP::DRPContext* context = (dmDRP::DRPContext*) ContextRegistryGet(registry, DRP_CONTEXT_NAME);
    dmGraphics::HContext graphics_context = (dmGraphics::HContext) ContextRegistryGet(registry, GRAPHICS_CONTEXT_NAME);
    lua_State* L = (lua_State*) ContextRegistryGet(registry, LUA_CONTEXT_NAME);
    if (!context || !graphics_context || !L)
    {
        dmLogError("DRP initialization requires the DRP, graphics, and Lua contexts");
        return dmExtension::RESULT_INIT_ERROR;
    }

    dmDRP::InitializeGraphics(context, graphics_context);
    dmDRP::InitializeScript(L, context);
    return dmExtension::RESULT_OK;
}

static dmExtension::Result Finalize(dmExtension::Params* params)
{
    HContextRegistry registry = ExtensionParamsGetContextRegistry(params);
    if (!registry)
        return dmExtension::RESULT_OK;

    lua_State* L = (lua_State*) ContextRegistryGet(registry, LUA_CONTEXT_NAME);
    if (L)
        dmDRP::FinalizeScript(L);

    dmDRP::DRPContext* context = (dmDRP::DRPContext*) ContextRegistryGet(registry, DRP_CONTEXT_NAME);
    dmDRP::FinalizeGraphics(context);
    return dmExtension::RESULT_OK;
}

static dmExtension::Result AppFinalize(dmExtension::AppParams* params)
{
    HContextRegistry registry = ExtensionAppParamsGetContextRegistry(params);
    if (!registry)
        return dmExtension::RESULT_OK;

    dmDRP::DRPContext* context = (dmDRP::DRPContext*) ContextRegistryGet(registry, DRP_CONTEXT_NAME);
    ContextRegistrySet(registry, DRP_CONTEXT_NAME, 0);
    // The engine has already destroyed graphics. Finalize released the GPU
    // buffers; deleting the context here only releases its CPU storage.
    delete context;
    return dmExtension::RESULT_OK;
}

// The exported symbol must match the name in ext.manifest. Extender emits a
// direct call to this symbol from dmExportedSymbols() when linking the engine.
DM_DECLARE_EXTENSION(drp, "DrpNative", AppInitialize, AppFinalize, Initialize, 0, 0, Finalize)
