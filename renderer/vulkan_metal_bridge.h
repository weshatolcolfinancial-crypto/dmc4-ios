#pragma once

#include <cstdint>
#include <cstddef>

namespace bridge {

// Initializes MoltenVK Vulkan instance and binds to the CAMetalLayer
bool InitializeVulkanOnMetalLayer(void *metalLayerPtr);

// Executes hardware presentation and presents the active game frame
void RenderFrame(double deltaTime);

// Shuts down graphics pipeline cleanly
void ShutdownGraphics();

// Feeds decompressed game frame buffer / textures directly from MT Framework assets
void UpdateGameFrame(const void *pixelData, uint32_t width, uint32_t height, uint32_t bytesPerRow);

// Clears frame
void ClearGameFrame();

// Returns true if an active game frame is ready to render
bool HasActiveGameFrame();

} // namespace bridge
