#include <AppKit/AppKit.h>
#include <Cocoa/Cocoa.h>
#include <Foundation/Foundation.h>
#include <Foundation/NSObjCRuntime.h>
#include <Metal/MTLRenderPass.h>
#include <Metal/MTLResource.h>
#include <QuartzCore/QuartzCore.h>
#include <math.h>
#import <Metal/Metal.h>
#include <stdio.h>
#import <MetalKit/MetalKit.h>
#include <sys/stat.h>



typedef struct DescApp {
  void (*init_cb)(void);
  void (*update_cb)(void);
  void (*cleanup_cb)(void);
} DescApp;

typedef struct {
  bool fullscreen;
  int window_width;
  int window_height;
  void* window;
  DescApp* desc;
} AppState;

static AppState app_state;

@interface MacosAppDelegate : NSObject<NSApplicationDelegate>
@end
@interface MacosWindow : NSWindow
@end
@interface MacosWindowDelegate : NSObject<NSWindowDelegate>
@end
@interface MacosView : MTKView
@end

void macos_frame() {

}


@implementation MacosView


- (void)drawRect:(NSRect)rect {
    @autoreleasepool {
        macos_frame();
    }
}

- (BOOL)isOpaque {
    return YES;
}
- (BOOL)canBecomeKeyView {
    return YES;
}
- (BOOL)acceptsFirstResponder {
    return YES;
}

@end


@implementation MacosWindow
- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backingStoreType
                              defer:(BOOL)flag {
  if (self = [super initWithContentRect:contentRect styleMask:style backing:backingStoreType defer:flag]) {
      #if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101300
        [self registerForDraggedTypes:[NSArray arrayWithObject:NSPasteboardTypeFileURL]];
      #endif
  }
  return self;
}
@end

#ifndef _UNUSED
  #define _UNUSED(x) (void)(x)
#endif

// TODO: handle resize
@implementation MacosWindowDelegate

- (BOOL)windowShouldClose:(id)sender {
  return YES;
}

@end


@implementation MacosAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification {
  if ((app_state.window_width == 0) || (app_state.window_height == 0)) {
    NSRect screen_rect = NSScreen.mainScreen.frame;
    if (app_state.window_width == 0) {
      app_state.window_width = (int)roundf((screen_rect.size.width * 4.0f) / 5.0f);
    }
    if (app_state.window_height == 0) {
      app_state.window_width = (int)roundf((screen_rect.size.width * 4.0f) / 5.0f);
    }
  }

  NSMutableArray *ids_pool = [NSMutableArray arrayWithCapacity:1024];

  const NSUInteger style =
    NSWindowStyleMaskTitled | 
    NSWindowStyleMaskClosable |
    NSWindowStyleMaskMiniaturizable |
    NSWindowStyleMaskResizable;

  NSRect window_rect = NSMakeRect(0, 0, app_state.window_width, app_state.window_height);
  MacosWindow *window = [[MacosWindow alloc]
    initWithContentRect:window_rect
    styleMask:style
    backing:NSBackingStoreBuffered
    defer:NO];
  app_state.window = (void *)window;
  window.releasedWhenClosed = NO;
  window.title = [NSString stringWithUTF8String:"Some title"];
  window.acceptsMouseMovedEvents = YES;
  window.restorable = YES;
  MacosWindowDelegate *window_dlg  = [[MacosWindowDelegate alloc] init];
  window.delegate = window_dlg;
  NSInteger max_fps = 60;
  #if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 120000)
    if (@available(macOS 12.0, *)) {
      max_fps = [NSScreen.mainScreen maximumFramesPerSecond];
    }
  #endif

  NSApp.activationPolicy = NSApplicationActivationPolicyRegular;
  [NSApp activateIgnoringOtherApps:YES];
  [window center];
  [window makeKeyAndOrderFront:nil];

   NSEvent *focusevent = [NSEvent otherEventWithType:NSEventTypeAppKitDefined
        location:NSZeroPoint
        modifierFlags:0x40
        timestamp:0
        windowNumber:0
        context:nil
        subtype:NSEventSubtypeApplicationActivated
        data1:0
        data2:0];
  [NSApp postEvent:focusevent atStart:YES];

  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  CAMetalLayer *swapchain = [CAMetalLayer layer];
  [swapchain setDevice:device];
  [swapchain setPixelFormat:MTLPixelFormatBGRA8Unorm];
  [swapchain setFramebufferOnly:YES];
  [swapchain setFrame:window.frame];
  [[window contentView] setLayer:swapchain];
  [window setOpaque:YES];
  [window setBackgroundColor:nil];

  id<MTLCommandQueue> command_queue = [device newCommandQueue];
  MTLCompileOptions *compile_options = [[MTLCompileOptions alloc] init];
  NSError *err;
  id<MTLLibrary> lib = [device newLibraryWithSource:[NSString stringWithUTF8String:shader]
                                            options:compile_options
                                              error:&err];
  if (err != nil) {
    NSLog(@"%@", [err localizedDescription]);
  }

  id<MTLFunction> vertex_main = [lib newFunctionWithName:@"vertex_main"];
  id<MTLFunction> fragment_main = [lib newFunctionWithName:@"fragment_main"];
  NSAssert(vertex_main != nil, @"vertex_main is nil");
  NSAssert(fragment_main != nil, @"fragment_main is nil");

  MTLRenderPipelineDescriptor *pipeline_descriptor = [[MTLRenderPipelineDescriptor alloc] init];
  [[pipeline_descriptor colorAttachments][0] setPixelFormat:MTLPixelFormatBGRA8Unorm];
  [pipeline_descriptor setVertexFunction:vertex_main];
  [pipeline_descriptor setFragmentFunction:fragment_main];

  id<MTLRenderPipelineState> pipeline_state = [device newRenderPipelineStateWithDescriptor:pipeline_descriptor error:&err];
  if (err != nil) {
    NSLog(@"%@", [err localizedDescription]);
  }

  float positions[][4] = {
    { 0.0,  0.5, 0.0, 1.0},
		{-0.5, -0.5, 0.0, 1.0},
		{ 0.5, -0.5, 0.0, 1.0},
  };
  float colors[][4] = {
    {1.0, 0.0, 0.0, 1.0},
		{0.0, 1.0, 0.0, 1.0},
		{0.0, 0.0, 1.0, 1.0},
  };


  id<MTLBuffer> position_buffer = [device newBufferWithBytes:&positions length:sizeof(positions) options:MTLResourceCPUCacheModeDefaultCache];
  id<MTLBuffer> colors_buffer =   [device newBufferWithBytes:&colors length:sizeof(colors) options:MTLResourceCPUCacheModeDefaultCache];


  // PASS
  id<CAMetalDrawable> drawable = [swapchain nextDrawable];
  MTLRenderPassDescriptor * pass = [MTLRenderPassDescriptor renderPassDescriptor];
  MTLRenderPassColorAttachmentDescriptor *colorAttachment = [pass colorAttachments][0];
  [colorAttachment setClearColor:MTLClearColorMake(0.25, 0.5, 1.0, 1.0)];
  [colorAttachment setLoadAction:MTLLoadActionClear];
  [colorAttachment setStoreAction:MTLStoreActionStore];
  [colorAttachment setTexture:[drawable texture]];

  id <MTLCommandBuffer> command_buffer = [command_queue commandBuffer];
  id <MTLRenderCommandEncoder> render_encoder = [command_buffer renderCommandEncoderWithDescriptor:pass];
  [render_encoder setRenderPipelineState:pipeline_state];
  [render_encoder setVertexBuffer:position_buffer offset:0 atIndex:0];
  [render_encoder setVertexBuffer:colors_buffer offset:0 atIndex:1];
  [render_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:1];
  [render_encoder endEncoding];
  [command_buffer presentDrawable:drawable];
  [command_buffer commit];

  //[compile_options release];
}

const char * shader = "using namespace metal;\n"
"\tstruct ColoredVertex {\n"
"\t\tfloat4 position [[position]];\n"
"\t\tfloat4 color;\n"
"\t};\n"
"\tvertex ColoredVertex vertex_main(constant float4 *position [[buffer(0)]],\n"
"\t                                 constant float4 *color    [[buffer(1)]],\n"
"\t                                 uint vid                  [[vertex_id]]) {\n"
"\t\tColoredVertex vert;\n"
"\t\tvert.position = position[vid];\n"
"\t\tvert.color    = color[vid];\n"
"\t\treturn vert;\n"
"\t}\n"
"\tfragment float4 fragment_main(ColoredVertex vert [[stage_in]]) {\n"
"\t\treturn vert.color;\n"
"\t}";


- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    return YES;
}

@end

void run_app(DescApp* app_desc) {
  app_state.window_width = 1024;
  app_state.window_height = 768;
  NSApplication *app = [NSApplication sharedApplication];
  app.delegate = [[MacosAppDelegate alloc] init];
  [app run];
}

int main(int argc, const char *argv[]) {
  run_app(&(DescApp){}); 
}

