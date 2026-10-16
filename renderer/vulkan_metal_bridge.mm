#include "vulkan_metal_bridge.h"
#include "../src/dmc4_hooks.h"
#include <iostream>

#ifdef __APPLE__
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#endif

namespace bridge {

static void *s_metalLayer = nullptr;
static bool s_isInitialized = false;

#ifdef __APPLE__
static id<MTLCommandQueue> s_commandQueue = nil;
static id<MTLRenderPipelineState> s_pipelineState = nil;
static id<MTLTexture> s_gameTexture = nil;
static id<MTLSamplerState> s_sampler = nil;
static id<MTLDevice> s_metalDevice = nil;

static const char *s_metalShaderSource = R"(
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoords = texCoords[vertexID];
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> colorTexture [[texture(0)]],
                               sampler textureSampler [[sampler(0)]]) {
    return colorTexture.sample(textureSampler, in.texCoords);
}
)";
#endif

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
    s_metalDevice = layer.device;
    s_commandQueue = [s_metalDevice newCommandQueue];

    std::cout << "[Vulkan_Metal_Bridge] Hardware GPU: " << [s_metalDevice.name UTF8String] << std::endl;

    // Build Metal Shader Pipeline for native presentation
    NSError *error = nil;
    NSString *source = [NSString stringWithUTF8String:s_metalShaderSource];
    id<MTLLibrary> library = [s_metalDevice newLibraryWithSource:source options:nil error:&error];
    if (library) {
        id<MTLFunction> vertFunc = [library newFunctionWithName:@"vertexShader"];
        id<MTLFunction> fragFunc = [library newFunctionWithName:@"fragmentShader"];

        MTLRenderPipelineDescriptor *pipeDesc = [[MTLRenderPipelineDescriptor alloc] init];
        pipeDesc.vertexFunction = vertFunc;
        pipeDesc.fragmentFunction = fragFunc;
        pipeDesc.colorAttachments[0].pixelFormat = layer.pixelFormat;

        s_pipelineState = [s_metalDevice newRenderPipelineStateWithDescriptor:pipeDesc error:&error];
        if (s_pipelineState) {
            std::cout << "[Vulkan_Metal_Bridge] Hardware presentation pipeline created successfully." << std::endl;
        }

        MTLSamplerDescriptor *samplerDesc = [[MTLSamplerDescriptor alloc] init];
        samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
        samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
        samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
        samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
        s_sampler = [s_metalDevice newSamplerStateWithDescriptor:samplerDesc];
    } else if (error) {
        std::cerr << "[Vulkan_Metal_Bridge] Pipeline error: " << [[error localizedDescription] UTF8String] << std::endl;
    }

    // Reset game texture - no static background images loaded!
    s_gameTexture = nil;
#endif

    s_isInitialized = true;
    return true;
}

void UpdateGameFrame(const void *pixelData, uint32_t width, uint32_t height, uint32_t bytesPerRow) {
    if (!pixelData || width == 0 || height == 0) return;

#ifdef __APPLE__
    if (!s_metalDevice) return;

    if (!s_gameTexture || s_gameTexture.width != width || s_gameTexture.height != height) {
        MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:NO];
        texDesc.usage = MTLTextureUsageShaderRead;
        s_gameTexture = [s_metalDevice newTextureWithDescriptor:texDesc];
    }

    if (s_gameTexture) {
        MTLRegion region = MTLRegionMake2D(0, 0, width, height);
        [s_gameTexture replaceRegion:region
                        mipmapLevel:0
                          withBytes:pixelData
                        bytesPerRow:bytesPerRow > 0 ? bytesPerRow : (width * 4)];
    }
#endif
}

void ClearGameFrame() {
#ifdef __APPLE__
    s_gameTexture = nil;
#endif
}

bool HasActiveGameFrame() {
#ifdef __APPLE__
    return s_gameTexture != nil;
#else
    return false;
#endif
}

void RenderFrame(double deltaTime) {
    (void)deltaTime;
    if (!s_isInitialized || !s_metalLayer) return;

#ifdef __APPLE__
    @autoreleasepool {
        CAMetalLayer *layer = (__bridge CAMetalLayer *)s_metalLayer;
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) return;

        MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
        passDesc.colorAttachments[0].texture = drawable.texture;
        passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0); // Clean black background
        passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

        if (!s_commandQueue) {
            s_commandQueue = [layer.device newCommandQueue];
        }

        id<MTLCommandBuffer> commandBuffer = [s_commandQueue commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];

        // Only draw when the actual game engine produces a frame
        if (s_pipelineState && s_gameTexture) {
            [encoder setRenderPipelineState:s_pipelineState];
            [encoder setFragmentTexture:s_gameTexture atIndex:0];
            [encoder setFragmentSamplerState:s_sampler atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        }

        [encoder endEncoding];

        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];
    }
#endif
}

void ShutdownGraphics() {
    std::cout << "[Vulkan_Metal_Bridge] Shutting down MoltenVK graphics pipeline." << std::endl;
    s_isInitialized = false;
    s_metalLayer = nullptr;
#ifdef __APPLE__
    s_commandQueue = nil;
    s_pipelineState = nil;
    s_gameTexture = nil;
    s_sampler = nil;
    s_metalDevice = nil;
#endif
}

} // namespace bridge
