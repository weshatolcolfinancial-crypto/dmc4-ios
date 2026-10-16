#include "dmc4_recomp.h"
#include <iostream>

namespace dmc4_recomp {

// Default fallback stubs. These are marked WEAK so that any recompiled translation units
// (e.g. game_main.cpp, mt_framework.cpp, player.cpp) provided by the user will cleanly
// override them at link time without multiple definition errors.

DMC4_RECOMP_WEAK void RegisterHostInterface(void *guestMemoryBase, size_t guestMemorySize, const char *gameRootPath) {
    (void)guestMemoryBase;
    (void)guestMemorySize;
    (void)gameRootPath;
}

DMC4_RECOMP_WEAK void InitializeMtFrameworkSubsystems() {
    std::cout << "[dmc4_recomp] Initializing MT Framework guest subsystems..." << std::endl;
}

DMC4_RECOMP_WEAK bool ExecuteGameTick(float deltaTime) {
    (void)deltaTime;
    return true;
}

DMC4_RECOMP_WEAK void ExecuteMainGameLoop() {
    std::cout << "[dmc4_recomp] ExecuteMainGameLoop running." << std::endl;
}

DMC4_RECOMP_WEAK bool IsRecompiledCodeActive() {
#if defined(DMC4_WITH_GAME) && DMC4_WITH_GAME
    return true;
#else
    return false;
#endif
}

} // namespace dmc4_recomp
