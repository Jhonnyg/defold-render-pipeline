// Copyright 2026 The Defold Render Pipeline Authors
// Licensed under the MIT License.

#include <dmsdk/sdk.h>

#include "drp.h"

static dmExtension::Result Initialize(dmExtension::Params* params)
{
    dmDRP::InitializeGraphics(dmGraphics::GetInstalledContext());
    dmDRP::InitializeScript(params->m_L);
    return dmExtension::RESULT_OK;
}

static dmExtension::Result Finalize(dmExtension::Params*)
{
    dmDRP::FinalizeGraphics();
    return dmExtension::RESULT_OK;
}

// The exported symbol must match the name in ext.manifest. Extender emits a
// direct call to this symbol from dmExportedSymbols() when linking the engine.
DM_DECLARE_EXTENSION(drp, "DrpNative", 0, 0, Initialize, 0, 0, Finalize)
