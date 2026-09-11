local pipeline = require("drp.pipeline")
local quality = require("drp.quality")

---@class drp.CapabilityRecord
---@field platform string Normalized platform name, such as `macos`, `windows`, or `html5`.
---@field source string Name of the provider that produced this record.
---@field strict boolean Whether unknown required capabilities are treated as unsupported.
---@field features table<string, boolean|nil> Supported (`true`), unsupported (`false`), or unknown (`nil`) GPU features.
---@field limits table<string, number> GPU limits reported by the active capability provider.

---@class drp.Profile
---@field name string Registered profile name.
---@field description string|nil Human-readable description.
---@field fallback string|nil Profile to try when a required capability is unavailable.
---@field requirements string[] Required keys from `drp.CapabilityRecord.features`.
---@field settings table Resolved rendering settings after inheritance and platform overrides.
---@field platform_overrides table Platform-specific settings retained for inspection.

---@class drp.QualityResolution
---@field requested string Profile requested by the application.
---@field effective string Supported profile selected after capability fallback.
---@field profile drp.Profile Fully resolved effective profile.
---@field reasons string[] Reasons that higher-priority profiles were rejected.

---@class drp.State
---@field initialized boolean Whether the pipeline has been initialized.
---@field frame integer Number of frames begun through `drp.begin_frame()`.
---@field requested_quality string|nil Latest requested profile, including a pending request.
---@field effective_quality string|nil Currently active effective profile.
---@field pending_quality string|nil Profile waiting for the next frame boundary.
---@field active_profile drp.Profile|nil Defensive copy of the active profile.
---@field capabilities drp.CapabilityRecord|nil Defensive copy of current capabilities.

---@class drp.QualityTransition
---@field frame integer Frame on which the transition became active.
---@field dt number Delta time passed to `drp.begin_frame()`.
---@field previous drp.QualityResolution|nil Previously active resolution.
---@field current drp.QualityResolution Newly active resolution.

---@class drp.InitializeOptions
---@field quality string|nil Initial requested profile. Defaults to `drp.default_profile`.
---@field platform string|nil Platform override, primarily useful for tests.
---@field capabilities table|nil Capability values supplied by a native provider or test.
---@field strict_capabilities boolean|nil Whether unknown required capabilities cause fallback.
---@field overrides table|nil Runtime settings merged onto the resolved profile.

---@class drp
local M = {
	---Semantic version of the public DRP Lua API.
	---@type string
	VERSION = "0.1.0",
}

---Initializes the DRP singleton.
---
---The initial quality profile is resolved immediately and becomes active during
---initialization. Repeated calls are idempotent and return the current state.
---@param options drp.InitializeOptions|nil Optional startup configuration.
---@return drp.State|nil state Current pipeline state, or `nil` on failure.
---@return string|nil error Error message when initialization fails.
function M.initialize(options)
	return pipeline.initialize(options)
end

---Finalizes the pipeline and clears resource declarations and listeners.
---
---Call this from the render script's `final()` lifecycle function. The bundled
---DRP render script already does this.
---@return boolean finalized Always `true` after cleanup completes.
function M.finalize()
	return pipeline.finalize()
end

---Re-resolves the requested quality profile after a hot reload.
---
---When DRP is already initialized, the resolution is queued for activation at
---the next `begin_frame()`. If DRP is not initialized, this initializes it.
---@return drp.QualityResolution|drp.State|nil result Queued resolution or initialized state.
---@return string|nil error Error message when resolution or initialization fails.
function M.reload()
	return pipeline.reload()
end

---Begins a pipeline frame and commits any pending quality transition.
---
---The bundled render script calls this automatically. Applications using that
---render script should not call it themselves.
---@param dt number Delta time in seconds.
---@return drp.QualityTransition|nil transition The committed transition, or `nil` if no quality change was pending.
---@return string|nil error Error message if implicit initialization fails.
function M.begin_frame(dt)
	return pipeline.begin_frame(dt)
end

---Returns whether the DRP singleton has been initialized.
---@return boolean initialized
function M.is_initialized()
	return pipeline.is_initialized()
end

---Returns a defensive snapshot of the current pipeline state.
---
---Mutating the returned table does not change DRP's internal state.
---@return drp.State state
function M.get_state()
	return pipeline.get_state()
end

---Returns a defensive copy of the current capability record.
---@return drp.CapabilityRecord|nil capabilities `nil` before initialization.
function M.get_capabilities()
	return pipeline.get_capabilities()
end

---Replaces detected capability values and re-resolves the active request.
---
---The resulting quality resolution is queued until the next frame boundary.
---This function is primarily the integration point for a future native GPU
---capability provider and for tests.
---@param capability_overrides table Capability record fields to apply over Lua baseline detection.
---@return drp.QualityResolution|nil resolution Queued resolution, or `nil` on failure.
---@return string|nil error Error message when DRP is uninitialized or resolution fails.
function M.set_capabilities(capability_overrides)
	return pipeline.set_capabilities(capability_overrides)
end

---Returns the latest requested quality name.
---
---Unlike `get_effective_quality()`, this includes a request that is still
---waiting for the next frame boundary.
---@return string|nil name
function M.get_requested_quality()
	return pipeline.get_requested_quality()
end

---Returns the currently active quality after capability fallback.
---@return string|nil name
function M.get_effective_quality()
	return pipeline.get_effective_quality()
end

---Returns a defensive copy of the active, fully resolved profile.
---@return drp.Profile|nil profile
function M.get_active_profile()
	return pipeline.get_active_profile()
end

---Requests a quality profile.
---
---The profile, inheritance chain, platform overrides, requirements, and
---fallbacks are validated immediately. A successful request becomes active on
---the next `begin_frame()` call.
---@param name string Registered profile name.
---@return drp.QualityResolution|nil resolution Queued effective resolution.
---@return string|nil error Error message when the request is invalid.
function M.set_quality(name)
	return pipeline.set_quality(name)
end

---Registers or replaces a quality profile.
---
---Register project profiles before requesting them. Existing resolved-profile
---caches are invalidated automatically.
---@param name string Lowercase profile name.
---@param profile table Profile definition, including optional inheritance and fallback.
---@return boolean|nil registered `true` when the definition is accepted.
---@return string|nil error Validation error.
function M.register_profile(name, profile)
	return quality.register(name, profile)
end

---Removes a registered quality profile.
---@param name string Registered profile name.
---@return boolean removed Whether a profile existed and was removed.
function M.unregister_profile(name)
	return quality.unregister(name)
end

---Returns a defensive copy of a resolved profile definition.
---
---Inheritance is resolved, but platform overrides are not applied because no
---target platform is supplied to this inspection function.
---@param name string Registered profile name.
---@return drp.Profile|nil profile
---@return string|nil error Error message for an unknown or invalid inheritance chain.
function M.get_profile(name)
	return quality.get(name)
end

---Returns all registered quality profile names in alphabetical order.
---@return string[] names
function M.get_profile_names()
	return quality.get_names()
end

---Replaces the complete runtime settings-override table.
---
---Overrides are recursively merged onto the effective profile without mutating
---the registered definition. The new resolution activates next frame.
---@param overrides table Settings keyed like `profile.settings`.
---@return drp.QualityResolution|nil resolution Queued resolution.
---@return string|nil error Error message when DRP is uninitialized or the value is invalid.
function M.set_runtime_overrides(overrides)
	return pipeline.set_runtime_overrides(overrides)
end

---Clears all runtime settings overrides.
---
---The unmodified requested profile is re-resolved and activates next frame.
---@return drp.QualityResolution|nil resolution Queued resolution.
---@return string|nil error Error message when DRP is uninitialized.
function M.clear_runtime_overrides()
	return pipeline.clear_runtime_overrides()
end

---Registers a callback for committed quality transitions.
---
---Callbacks run after a pending profile becomes active at a frame boundary.
---Listener errors are logged and do not abort other listeners.
---@param callback fun(transition: drp.QualityTransition)
---@return integer|nil handle Handle used by `remove_quality_listener()`.
---@return string|nil error Error message when callback is not a function.
function M.on_quality_changed(callback)
	return pipeline.on_quality_changed(callback)
end

---Removes a quality-transition listener.
---@param handle integer Handle returned by `on_quality_changed()`.
---@return boolean removed Whether a listener existed and was removed.
function M.remove_quality_listener(handle)
	return pipeline.remove_quality_listener(handle)
end

return M
