#pragma once

#include <cstdint>
#include <string>
#include "virtual_gamepad.h"

namespace dmc4 {

// Sets the root directory or ISO path where DMC4 game files reside
void SetGameRootDirectory(const char *path);
const char *GetGameRootDirectory();

// Directly mounts and boots from an Xbox 360 ISO image
void MountGameIso(const char *isoPath);

// Initializes MT Framework engine hooks on Apple Silicon ARM64
void InitializeEngineHooks();

// Updates Xbox 360 controller state from touch overlay or physical gamepad
void UpdateControllerState(const VirtualGamepadState *state);
const VirtualGamepadState *GetControllerState();

// Applies ProMotion 120Hz physics delta scaling
void ApplyProMotionFramerateHooks(int targetFPS);

// Widescreen 19.5:9 and notch / safe area viewport patch
void ApplyWidescreenViewportPatch(float aspectRatio);

// Game engine simulation tick (invoked per CADisplayLink frame)
void TickGameEngine(float deltaTime);

// Checks if game assets or recompiled code are ready
bool IsGameReady();
bool IsRecompiledGameActive();

// MT Framework VFS resolver (resolves paths like "nativeXenon/rom/player/uPlayerDante.arc")
std::string ResolveGameAssetPath(const std::string &relativeSubPath);

// Guest memory management (512MB RAM map for Xbox 360 guest)
void *GetGuestMemoryBase();
size_t GetGuestMemorySize();

} // namespace dmc4

