#pragma once

#include <cstdint>
#include <cstddef>

namespace dmc4_recomp {

#if defined(__GNUC__) || defined(__clang__)
#define DMC4_RECOMP_WEAK __attribute__((weak))
#else
#define DMC4_RECOMP_WEAK
#endif

// Registers host pointers and memory base with the recompiled runtime
void RegisterHostInterface(void *guestMemoryBase, size_t guestMemorySize, const char *gameRootPath);

// Initializes MT Framework engine subsystems (Heap memory, VFS, Renderer, Sound, Input)
void InitializeMtFrameworkSubsystems();

// Executes a single simulation/render tick (called from iOS CADisplayLink presentation loop)
// Returns false if termination/exit is requested
bool ExecuteGameTick(float deltaTime);

// Executes the main blocking game loop (for thread-driven recompiled execution)
void ExecuteMainGameLoop();

// Checks if recompiled game translation units are actively compiled in and running
bool IsRecompiledCodeActive();

} // namespace dmc4_recomp
