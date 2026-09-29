// Copyright 2026 Jhonny Göransson
// Licensed under the MIT License.

#include "drp.h"

#include <dmsdk/gamesys/resources/res_material.h>

#include <new>
#include <stdlib.h>
#include <string.h>

namespace dmDRP
{
    struct FullscreenMaterial
    {
        char*                           m_Path;
        dmGameSystem::MaterialResource* m_Resource;
        dmRender::RenderObject          m_RenderObject;

        FullscreenMaterial()
        : m_Path(0)
        , m_Resource(0)
        {
        }
    };

    static bool Fail(const char** error, const char* message)
    {
        if (error)
            *error = message;
        return false;
    }

    static void DispatchFullscreen(const dmRender::RenderListDispatchParams& params)
    {
        DRPContext* context = (DRPContext*) params.m_UserData;
        if (params.m_Operation != dmRender::RENDER_LIST_OPERATION_BATCH || context->m_FullscreenFinalized)
            return;

        for (uint32_t* index = params.m_Begin; index != params.m_End; ++index)
        {
            FullscreenMaterial* material = (FullscreenMaterial*) (uintptr_t) params.m_Buf[*index].m_UserData;
            // Resource recreation can replace the material handle while keeping
            // the resource record alive. Read it when preparing each draw.
            material->m_RenderObject.m_Material = material->m_Resource->m_Material;
            dmRender::AddToRender(params.m_Context, &material->m_RenderObject);
        }
    }

    static bool CreateGeometry(DRPContext* context, const char** error)
    {
        if (context->m_FullscreenVertexBuffer)
            return true;

        dmGraphics::HVertexStreamDeclaration streams = dmGraphics::NewVertexStreamDeclaration(context->m_GraphicsContext);
        if (!streams)
            return Fail(error, "failed to create fullscreen vertex streams");

        dmGraphics::AddVertexStream(streams, "position", 4, dmGraphics::TYPE_FLOAT, false);
        dmGraphics::AddVertexStream(streams, "texcoord0", 2, dmGraphics::TYPE_FLOAT, false);
        dmGraphics::HVertexDeclaration declaration = dmGraphics::NewVertexDeclaration(context->m_GraphicsContext, streams, 6 * sizeof(float));
        dmGraphics::DeleteVertexStreamDeclaration(streams);
        if (!declaration)
            return Fail(error, "failed to create fullscreen vertex declaration");

        // One oversized triangle covers clip space. UVs interpolate to [0,1]
        // across the viewport, with the same orientation as the former quad.
        static const float vertices[] = {
            -1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 0.0f,
             3.0f, -1.0f, 0.0f, 1.0f, 2.0f, 0.0f,
            -1.0f,  3.0f, 0.0f, 1.0f, 0.0f, 2.0f,
        };
        dmGraphics::HVertexBuffer buffer = dmGraphics::NewVertexBuffer(context->m_GraphicsContext, sizeof(vertices), vertices, dmGraphics::BUFFER_USAGE_STATIC_DRAW);
        if (!buffer)
        {
            dmGraphics::DeleteVertexDeclaration(declaration);
            return Fail(error, "failed to create fullscreen vertex buffer");
        }

        context->m_FullscreenVertexDeclaration = declaration;
        context->m_FullscreenVertexBuffer = buffer;
        return true;
    }

    static FullscreenMaterial* GetFullscreenMaterial(DRPContext* context, const char* path, const char** error)
    {
        for (uint32_t i = 0; i < context->m_FullscreenMaterials.Size(); ++i)
        {
            FullscreenMaterial* material = context->m_FullscreenMaterials[i];
            if (strcmp(material->m_Path, path) == 0)
                return material;
        }

        dmGameSystem::MaterialResource* resource = 0;
        if (ResourceGetWithExt(context->m_ResourceFactory, path, "materialc", (void**) &resource) != RESOURCE_RESULT_OK)
        {
            Fail(error, "failed to load fullscreen material resource");
            return 0;
        }

        FullscreenMaterial* material = new (std::nothrow) FullscreenMaterial;
        if (material)
        {
            size_t path_size = strlen(path) + 1;
            material->m_Path = (char*) malloc(path_size);
            if (material->m_Path)
                memcpy(material->m_Path, path, path_size);
        }

        if (!material || !material->m_Path || !CreateGeometry(context, error))
        {
            if (!material || !material->m_Path)
                Fail(error, "failed to allocate fullscreen material record");
            if (material)
            {
                free(material->m_Path);
                delete material;
            }
            ResourceRelease(context->m_ResourceFactory, resource);
            return 0;
        }

        material->m_Resource = resource;
        material->m_RenderObject.m_Material = resource->m_Material;
        material->m_RenderObject.m_VertexBuffer = context->m_FullscreenVertexBuffer;
        material->m_RenderObject.m_VertexDeclaration = context->m_FullscreenVertexDeclaration;
        material->m_RenderObject.m_PrimitiveType = dmGraphics::PRIMITIVE_TRIANGLES;
        material->m_RenderObject.m_VertexCount = 3;

        if (context->m_FullscreenMaterials.Full())
            context->m_FullscreenMaterials.OffsetCapacity(4);
        // Keep records separately allocated: render-list entries and queued draw
        // objects must remain valid when this cache grows during a frame.
        context->m_FullscreenMaterials.Push(material);
        return material;
    }

    bool SubmitFullscreen(DRPContext* context, const char* material_path, const char** error)
    {
        if (error)
            *error = 0;
        if (!context || !context->m_ContextRegistry || !context->m_GraphicsContext)
            return Fail(error, "fullscreen rendering requires an initialized DRP context");
        if (context->m_FullscreenFinalized)
            return Fail(error, "fullscreen rendering is shutting down");
        if (!material_path || !material_path[0])
            return Fail(error, "fullscreen rendering requires a compiled material path");

        // Extension Initialize precedes render-context creation. Resolve these
        // borrowed contexts only when the render script first submits a pass.
        if (!context->m_RenderContext)
            context->m_RenderContext = (dmRender::HRenderContext) ContextRegistryGet(context->m_ContextRegistry, RENDER_CONTEXT_NAME);
        if (!context->m_ResourceFactory)
            context->m_ResourceFactory = (HResourceFactory) ContextRegistryGet(context->m_ContextRegistry, RESOURCE_FACTORY_CONTEXT_NAME);
        if (!context->m_RenderContext || !context->m_ResourceFactory)
            return Fail(error, "fullscreen rendering requires render and resource contexts");

        FullscreenMaterial* material = GetFullscreenMaterial(context, material_path, error);
        if (!material)
            return false;

        // The engine resets dispatch handles with the render list every frame.
        dmRender::HRenderListDispatch dispatch = dmRender::RenderListMakeDispatch(context->m_RenderContext, DispatchFullscreen, 0, context);
        // The SDK handle is uint8_t; render.cpp uses 0xff for exhausted dispatches.
        if (dispatch == 0xff)
            return Fail(error, "fullscreen render dispatch capacity exhausted");

        dmRender::RenderListEntry* entry = dmRender::RenderListAlloc(context->m_RenderContext, 1);
        if (!entry)
            return Fail(error, "failed to allocate fullscreen render entry");
        entry->m_WorldPosition = dmVMath::Point3(0.0f, 0.0f, 0.0f);
        entry->m_UserData = (uint64_t) (uintptr_t) material;
        entry->m_Order = 0;
        entry->m_BatchKey = dmHashString32(material_path);
        entry->m_TagListKey = dmRender::GetMaterialTagListKey(material->m_Resource->m_Material);
        entry->m_MinorOrder = 0;
        entry->m_MajorOrder = dmRender::RENDER_ORDER_AFTER_WORLD;
        entry->m_Dispatch = dispatch;
        entry->m_Visibility = dmRender::VISIBILITY_FULL;
        dmRender::RenderListSubmit(context->m_RenderContext, entry, entry + 1);
        return true;
    }

    void FinalizeFullscreen(DRPContext* context)
    {
        if (!context || context->m_FullscreenFinalized)
            return;
        context->m_FullscreenFinalized = true;

        for (uint32_t i = 0; i < context->m_FullscreenMaterials.Size(); ++i)
        {
            FullscreenMaterial* material = context->m_FullscreenMaterials[i];
            ResourceRelease(context->m_ResourceFactory, material->m_Resource);
            free(material->m_Path);
            delete material;
        }
        context->m_FullscreenMaterials.SetSize(0);
        if (context->m_FullscreenVertexBuffer)
            dmGraphics::DeleteVertexBuffer(context->m_FullscreenVertexBuffer);
        if (context->m_FullscreenVertexDeclaration)
            dmGraphics::DeleteVertexDeclaration(context->m_FullscreenVertexDeclaration);
        context->m_FullscreenVertexBuffer = 0;
        context->m_FullscreenVertexDeclaration = 0;
        context->m_RenderContext = 0;
        context->m_ResourceFactory = 0;
    }
}
