// Copyright 2026 Jhonny Göransson
// Licensed under the MIT License.

#include <dmsdk/sdk.h>
#include <dmsdk/gamesys/script.h>
#include <dmsdk/gamesys/components/comp_light.h>
#include <float.h>
#include <math.h>
#include "drp.h"

namespace dmDRP
{
    static uint32_t CheckId(lua_State* L, int index)
    {
        double id = luaL_checknumber(L, index);
        if (!(id >= 1 && id <= UINT32_MAX) || floor(id) != id)
        {
            luaL_error(L, "shadow registration must be an unsigned nonzero integer");
        }
        return (uint32_t) id;
    }

    static float Number(lua_State* L, const char* field, float fallback, float low, float high)
    {
        lua_getfield(L, 2, field);
        double value = lua_isnil(L, -1) ? fallback : luaL_checknumber(L, -1);
        lua_pop(L, 1);
        if (!(value >= low && value <= high))
        {
            luaL_error(L, "shadow %s is outside its supported range", field);
        }
        return (float) value;
    }

    static bool Boolean(lua_State* L, const char* field, bool fallback)
    {
        lua_getfield(L, 2, field);
        if (!lua_isnil(L, -1) && !lua_isboolean(L, -1))
        {
            luaL_error(L, "shadow %s must be a boolean", field);
        }
        bool value = lua_isnil(L, -1) ? fallback : lua_toboolean(L, -1) != 0;
        lua_pop(L, 1);
        return value;
    }

    static void Settings(lua_State* L, ShadowLight* record)
    {
        if (lua_isnoneornil(L, 2))
        {
            return;
        }
        luaL_checktype(L, 2, LUA_TTABLE);
        // Parse a copy before committing, so a Lua error cannot partially update settings.
        record->m_Priority   = Number(L, "priority", record->m_Priority, -100000, 100000);
        record->m_Bias       = Number(L, "bias", record->m_Bias, 0, 0.1f);
        record->m_NormalBias = Number(L, "normal_bias", record->m_NormalBias, 0, 100);
        record->m_Softness   = Number(L, "softness", record->m_Softness, 0, 8);
        record->m_Enabled    = Boolean(L, "enabled", record->m_Enabled);
        record->m_Cache      = Boolean(L, "cache", record->m_Cache);
    }

    static int Register(lua_State* L)
    {
        DRPContext* context = CheckContext(L);
        if (context->m_FullscreenFinalized)
        {
            return luaL_error(L, "the DRP context is shutting down");
        }

        // Resolve only in the game-object script context. Keep the versioned light
        // handle, never the component pointer (collections may unload at any time).
        dmGameObject::HComponent component = 0;
        dmScript::GetComponentFromLua(L, 1, "lightc", 0, &component, 0);
        ShadowLight record = {};
        record.m_Light = dmGameSystem::CompLightGetLightInstance((dmGameSystem::HLightComponent) component);
        if (!record.m_Light)
        {
            return luaL_error(L, "light has no render instance");
        }

        // A light has one settings owner, even when scripts use separate Lua worlds.
        for (uint32_t i = 0; i < context->m_ShadowLights.Size(); ++i)
        {
            if (context->m_ShadowLights[i].m_Light == record.m_Light)
            {
                return luaL_error(L, "light already has a shadow registration");
            }
        }

        // IDs are never recycled. Reject exhaustion before assigning a new record.
        if (!context->m_NextShadowLightId || context->m_ShadowLights.Size() >= 1024)
        {
            return luaL_error(L, "shadow registration limit reached");
        }

        // Validate into a local record first: a Lua error must leave the registry
        // and the next ID untouched.
        record.m_Id         = context->m_NextShadowLightId;
        record.m_Bias       = 0.001f;
        record.m_NormalBias = 0.02f;
        record.m_Softness   = 1.5f;
        record.m_Enabled    = true;
        Settings(L, &record);

        // Publish only after component resolution and every setting have passed.
        if (context->m_ShadowLights.Full())
        {
            context->m_ShadowLights.OffsetCapacity(16);
        }
        context->m_ShadowLights.Push(record);
        ++context->m_NextShadowLightId;

        lua_pushnumber(L, record.m_Id);
        return 1;
    }

    static int Update(lua_State* L)
    {
        DRPContext* context = CheckContext(L);
        uint32_t id = CheckId(L, 1);

        for (uint32_t i = 0; i < context->m_ShadowLights.Size(); ++i)
        {
            if (context->m_ShadowLights[i].m_Id != id)
            {
                continue;
            }

            // Keep the current registration intact if validation raises a Lua error.
            ShadowLight record = context->m_ShadowLights[i];
            Settings(L, &record);
            context->m_ShadowLights[i] = record;
            lua_pushboolean(L, 1);
            return 1;
        }
        return luaL_error(L, "shadow registration no longer exists");
    }

    static int Unregister(lua_State* L)
    {
        DRPContext* context = CheckContext(L);
        uint32_t id = CheckId(L, 1);

        for (uint32_t i = 0; i < context->m_ShadowLights.Size(); ++i)
        {
            if (context->m_ShadowLights[i].m_Id != id)
            {
                continue;
            }
            context->m_ShadowLights.EraseSwap(i);
            lua_pushboolean(L, 1);
            return 1;
        }
        lua_pushboolean(L, 0);
        return 1;
    }

    static void SetNumber(lua_State* L, const char* name, double value)
    {
        lua_pushnumber(L, value);
        lua_setfield(L, -2, name);
    }

    static void SetVector(lua_State* L, const char* name, float x, float y, float z)
    {
        lua_createtable(L, 3, 0);
        lua_pushnumber(L, x);
        lua_rawseti(L, -2, 1);
        lua_pushnumber(L, y);
        lua_rawseti(L, -2, 2);
        lua_pushnumber(L, z);
        lua_rawseti(L, -2, 3);
        lua_setfield(L, -2, name);
    }

    static int Snapshot(lua_State* L)
    {
        DRPContext* context = CheckContext(L);
        dmRender::HRenderContext render_context = !context->m_FullscreenFinalized && context->m_ContextRegistry
            ? (dmRender::HRenderContext) ContextRegistryGet(context->m_ContextRegistry, RENDER_CONTEXT_NAME) : 0;
        lua_newtable(L);
        uint32_t count = 0;
        uint64_t revision = 0;
        bool has_revision = false;

        // Resolve transient buffer indices afresh after this frame's submission.
        // Registrations retain only versioned handles between frames.
        for (uint32_t i = 0; render_context && i < context->m_ShadowLights.Size(); ++i)
        {
            const ShadowLight& record = context->m_ShadowLights[i];
            if (!record.m_Enabled)
            {
                continue;
            }

            dmRender::LightInstanceRenderData light;
            bool valid = dmRender::GetLightInstanceRenderData(render_context, record.m_Light, &light);

            // This is a snapshot after component submission. Even failed queries
            // carry the revision. Never mix compact indices from different snapshots.
            if (has_revision && revision != light.m_BufferRevision)
            {
                return luaL_error(L, "light buffer changed during shadow snapshot");
            }
            revision = light.m_BufferRevision;
            has_revision = true;

            if (!valid)
            {
                continue;         // Disabled, unsubmitted, deleted, or ambient.
            }

            // Publish the engine snapshot together with extension-owned settings.
            lua_newtable(L);
            SetNumber(L, "id", record.m_Id);
            SetNumber(L, "index", light.m_BufferIndex);
            SetNumber(L, "type", light.m_Type);
            SetNumber(L, "range", light.m_Range);
            SetNumber(L, "outer_cone", light.m_OuterConeAngle);
            SetNumber(L, "priority", record.m_Priority);
            SetNumber(L, "bias", record.m_Bias);
            SetNumber(L, "normal_bias", record.m_NormalBias);
            SetNumber(L, "softness", record.m_Softness);
            lua_pushboolean(L, record.m_Cache);
            lua_setfield(L, -2, "cache");
            SetVector(L, "position", light.m_Position.getX(), light.m_Position.getY(), light.m_Position.getZ());
            SetVector(L, "direction", light.m_Direction.getX(), light.m_Direction.getY(), light.m_Direction.getZ());
            lua_rawseti(L, -2, ++count);
        }

        // Buffer revision is intentionally NOT a cache key: it changes when
        // submission order/intensity changes even if a depth map remains valid.
        lua_pushnumber(L, context->m_ShadowSceneRevision);
        return 2;
    }

    static int Invalidate(lua_State* L)
    {
        ++CheckContext(L)->m_ShadowSceneRevision;
        return 0;
    }

    static int PackFloats(lua_State* L)
    {
        CheckContext(L);
        luaL_checktype(L, 1, LUA_TTABLE);

        size_t count = lua_objlen(L, 1);
        if (!count || count > 65536)
        {
            return luaL_error(L, "float data must contain 1..65536 values");
        }

        // Lua owns this temporary allocation, including on luaL_error/longjmp.
        float* values = (float*) lua_newuserdata(L, count * sizeof(float));
        for (size_t i = 0; i < count; ++i)
        {
            lua_rawgeti(L, 1, i + 1);
            double value = luaL_checknumber(L, -1);
            if (!(value >= -FLT_MAX && value <= FLT_MAX))
            {
                return luaL_error(L, "float data contains a non-finite or out-of-range value");
            }
            values[i] = (float) value;
            lua_pop(L, 1);
        }

        lua_pushlstring(L, (const char*) values, count * sizeof(float));
        return 1;
    }

    void InitializeShadowScript(lua_State* L)
    {
        static const luaL_reg methods[] = {
            {"register_shadow_light",   Register},
            {"update_shadow_light",     Update},
            {"unregister_shadow_light", Unregister},
            {"get_shadow_lights",       Snapshot},
            {"invalidate_shadows",      Invalidate},
            {"pack_floats",             PackFloats},
            {0, 0}
        };

        luaL_register(L, "drp_native", methods);
        lua_pop(L, 1);
    }
}
