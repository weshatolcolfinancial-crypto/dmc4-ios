#pragma once

#include <cstdint>
#include <string>
#include "virtual_gamepad.h"

namespace dmc4 {

// Sets the root directory where DMC4 game files/ISO reside
void SetGameRootDirectory(const char *path);
const char *GetGameRootDirectory();

// Initializes MT Framework engine hooks on Apple Silicon ARM64
void InitializeEngineHooks();

// Updates Xbox 360 controller state from touch overlay or physical gamepad
void UpdateControllerState(const VirtualGamepadState *state);

// Applies ProMotion 120Hz physics delta scaling
void ApplyProMotionFramerateHooks(int targetFPS);

// Widescreen 19.5:9 and notch / safe area viewport patch
void ApplyWidescreenViewportPatch(float aspectRatio);

} // namespace dmc4
