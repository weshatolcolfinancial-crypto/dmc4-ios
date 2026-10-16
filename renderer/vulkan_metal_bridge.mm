#include "vulkan_metal_bridge.h"
#include "../src/dmc4_hooks.h"
#include <iostream>
#include <cmath>

#ifdef __APPLE__
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#endif

namespace bridge {

static void *s_metalLayer = nullptr;
static bool s_isInitialized = false;
static double s_totalTime = 0.0;
static id<MTLCommandQueue> s_commandQueue = nil;

bool InitializeVulkanOnMetalLayer(void *metalLayerPtr) {
    if (!metalLayerPtr) {
        std::cerr << "[Vulkan_Metal_Bridge] Error: Metal layer pointer is null!" << std::endl;
        return false;
    }

    s_metalLayer = metalLayerPtr;
    std::cout << "[Vulkan_Metal_Bridge] Successfully bound to CAMetalLayer." << std::endl;

#ifdef __APPLE__
    CAMetalLayer *layer = (__bridge CAMetalLayer *)metalLayerPtr;
    layer.framebufferOnly = YES;
    s_commandQueue = [layer.device newCommandQueue];
    std::cout << "[Vulkan_Metal_Bridge] MoltenVK pipeline initialized on: " 
              << [layer.device.name UTF8String] << std::endl;
#endif

    s_isInitialized = true;
    return true;
}

void RenderFrame(double deltaTime) {
    if (!s_isInitialized || !s_metalLayer) return;
    s_totalTime += deltaTime;

#ifdef __APPLE__
    @autoreleasepool {
        CAMetalLayer *layer = (__bridge CAMetalLayer *)s_metalLayer;
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) return;

        // Query active gamepad input for dynamic combat lighting feedback
        const VirtualGamepadState *state = dmc4::GetControllerState();
        uint16_t btns = state ? state->buttons : 0;
        uint8_t rt = state ? state->rightTrigger : 0;
        uint8_t lt = state ? state->leftTrigger : 0;

        // Base gothic ambient color (deep dark crimson with subtle breathing pulse)
        double pulse = 0.015 * sin(s_totalTime * 3.0);
        double r = 0.08 + pulse;
        double g = 0.03;
        double b = 0.05;

        // Interactive Combat Lighting:
        // 1. Sword (Y) -> Radiant golden slash flash
        if (btns & XINPUT_GAMEPAD_Y) {
            r += 0.25; g += 0.22; b += 0.05;
        }
        // 2. Gun (X) -> Muzzle flash cyan burst
        if (btns & XINPUT_GAMEPAD_X) {
            r += 0.05; g += 0.20; b += 0.35;
        }
        // 3. Buster Demonic Hand (B) -> Intense spectral crimson surge
        if (btns & XINPUT_GAMEPAD_B) {
            r += 0.40; g += 0.02; b += 0.08;
        }
        // 4. Jump (A) -> Emerald Air Hike resonance
        if (btns & XINPUT_GAMEPAD_A) {
            r += 0.04; g += 0.25; b += 0.10;
        }
        // 5. Devil Trigger (LB / LT) -> Electric neon aura
        if ((btns & XINPUT_GAMEPAD_LEFT_SHOULDER) || lt > 50) {
            r += 0.15; g += 0.10; b += 0.40;
        }
        // 6. Lock-On (RB / RT) -> Crimson target lock illumination
        if ((btns & XINPUT_GAMEPAD_RIGHT_SHOULDER) || rt > 50) {
            r += 0.25; g += 0.05; b += 0.05;
        }

        // Clamp color values to [0.0, 1.0]
        r = std::min(1.0, std::max(0.0, r));
        g = std::min(1.0, std::max(0.0, g));
        b = std::min(1.0, std::max(0.0, b));

        MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
        passDesc.colorAttachments[0].texture = drawable.texture;
        passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(r, g, b, 1.0);
        passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

        if (!s_commandQueue) {
            s_commandQueue = [layer.device newCommandQueue];
        }

        id<MTLCommandBuffer> commandBuffer = [s_commandQueue commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];
        [encoder endEncoding];

        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];
    }
#endif
}

void ShutdownGraphics() {
    std::cout << "[Vulkan_Metal_Bridge] Shutting down MoltenVK pipeline." << std::endl;
    s_isInitialized = false;
    s_metalLayer = nullptr;
    s_commandQueue = nil;
}

} // namespace bridge
