#pragma once

namespace bridge {

// Initializes MoltenVK Vulkan instance and binds to the CAMetalLayer
bool InitializeVulkanOnMetalLayer(void *metalLayerPtr);

// Executes Xenos GPU command translation and presents the frame
void RenderFrame(double deltaTime);

// Shuts down graphics pipeline cleanly
void ShutdownGraphics();

} // namespace bridge
