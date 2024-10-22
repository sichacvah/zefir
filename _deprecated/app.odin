package app
import "core:fmt"
import foundation "core:sys/darwin/Foundation"
import Metal "vendor:darwin/Metal"

import CA "vendor:darwin/QuartzCore"
import glm "core:math/linalg/glsl"

window: ^foundation.Window
Vertex :: struct {
  position: [2]f32,
  color:    [4]f32,
  center:   [2]f32,
  radius:   f32,
}

Camera :: struct {
  offset:           [2]f32,
  target:           [2]f32,
  rotation_radians: f32,
  zoom:             f32,
  near:             f32,
  far:              f32,
}

CameraDefault :: Camera {
  zoom = 1,
  near = -1,
  far  = 1,
}

CameraData :: struct {
  mvp: glm.mat4,
}

main :: proc() {
	app := foundation.Application_sharedApplication()
	// WINDOW CREATION
	window_rect := foundation.Rect {
		origin = {0.0, 0.0},
		size   = {800, 800},
	}
	window = foundation.Window_alloc()
	window =
	window->initWithContentRect(
		window_rect,
		{.Titled, .Closable, .Resizable, .Miniaturizable},
		.Buffered,
		false,
	)

	title := foundation.String_alloc()
	title = title->initWithOdinString("TITLE")
	window->setTitle(title)

	app->setActivationPolicy(.Regular)

	//app->activate()
  
  app->activateIgnoringOtherApps(true)
	window->makeKeyAndOrderFront(nil)


	device := Metal.CreateSystemDefaultDevice()
	fmt.println(device->name()->odinString())

	swapchain := CA.MetalLayer.layer()
	swapchain->setDevice(device)
	swapchain->setPixelFormat(.BGRA8Unorm_sRGB)
	swapchain->setFramebufferOnly(true)
	swapchain->setFrame(window->frame())
	window->contentView()->setLayer(swapchain)
	window->setOpaque(true)
	window->setBackgroundColor(nil)


	command_queue := device->newCommandQueue()
	compile_options := foundation.new(Metal.CompileOptions)
	defer compile_options->release()

	program_source :: `
  #include <metal_stdlib>
	using namespace metal;
  struct VertexData {
    packed_float2 position;
    packed_float4 color;
    packed_float2 center;
    float radius;
  };

  struct CameraData {
    float4x4 mvp;
  };

	struct ColoredVertex {
		float4 position [[position]];
		float4 color;
    float2 center;
    float radius;
    float2 origin;
	};
	vertex ColoredVertex vertex_main(device const VertexData* vertex_data [[buffer(0)]],
                                   device const CameraData& camera_data [[buffer(1)]],
	                                 uint vid                  [[vertex_id]]) {
		ColoredVertex vert;
		vert.color    = vertex_data[vid].color;
    vert.center   = vertex_data[vid].center;
    vert.radius   = vertex_data[vid].radius;
    vert.position = camera_data.mvp * float4(vertex_data[vid].position, 0.0, 1.0);
    vert.origin = float2(vertex_data[vid].position);
		return vert;
	}

  float fill_mask(float dist, float softness) {
    return smoothstep(-softness, softness, -dist);
  }

  float4 composite(float4 back, float4 front) {
    return mix(back, front, front.a);
  }

  float sdf_rounded_box(float2 point, float2 center, float2 b, float r) {
      float2 over_zero_x = float2((center.x - point.x) > 0.0);
      float over_zero_y = float((point.y - center.y) > 0.0);
      float2 xy = over_zero_x * float2(r) + (float2(1.0) - over_zero_x) * float2(r);
      float x  = over_zero_y * xy.x + (1.0 - over_zero_y) * xy.y;
      float2 q = abs(point - center) - b + x;
      return length(max(q, 0.0)) + min(max(q.x,q.y), 0.0) - x;
  }

	fragment float4 fragment_main(ColoredVertex vert [[stage_in]], float4 bg_color [[color(0)]]) {  
    float4 color  = bg_color;
    float dist    = sdf_rounded_box(vert.position.xy, vert.center, float2(200, 200), vert.radius);
    float factor  = fill_mask(dist, 1.0);
    color         = composite(color, float4(vert.color.rgb, vert.color.a * factor));

    return vert.color;
	}
	`

  program_library, err := device->newLibraryWithSource(foundation.AT(program_source), compile_options)
  if err != nil {
    fmt.println("Error library: ", err->localizedDescription()->odinString())
    return
  }

  vertex_program := program_library->newFunctionWithName(foundation.AT("vertex_main"))
	fragment_program := program_library->newFunctionWithName(foundation.AT("fragment_main"))
  assert(vertex_program != nil)
	assert(fragment_program != nil)

  pipeline_state_descriptor := foundation.new(Metal.RenderPipelineDescriptor)
  color_attachment_desc := pipeline_state_descriptor->colorAttachments()->object(0)
	color_attachment_desc->setPixelFormat(.BGRA8Unorm_sRGB)
  color_attachment_desc->setBlendingEnabled(true)
  color_attachment_desc->setRgbBlendOperation(.Add)
  color_attachment_desc->setAlphaBlendOperation(.Add)
  color_attachment_desc->setSourceRGBBlendFactor(.One)
  color_attachment_desc->setSourceAlphaBlendFactor(.One)
  color_attachment_desc->setDestinationRGBBlendFactor(.OneMinusDestinationAlpha)
  color_attachment_desc->setDestinationAlphaBlendFactor(.OneMinusDestinationAlpha)


	pipeline_state_descriptor->setVertexFunction(vertex_program)
	pipeline_state_descriptor->setFragmentFunction(fragment_program)
  pipeline_state, e := device->newRenderPipelineState(pipeline_state_descriptor)
  if e != nil {
    fmt.println("Error Pipline state: ", e)
    return
  }

  a := Vertex{ color = {1, 0, 0, 1}, position = { 0,  0 }, center = {400,400}, radius = 20 }
  b := Vertex{ color = {1, 1, 0, 1}, position = { 50, 0 }, center = {400,400}, radius = 20 }
  c := Vertex{ color = {0, 0, 1, 1}, position = { 50, 50 }, center = {400,400}, radius = 20 }
  d := Vertex{ color = {0, 1, 0, 1}, position = { 0, 50 }, center = {400,400}, radius = 20 }
  vertexes := [6]Vertex {
    a,b,c,
    a,c,d,
  }

	vertex_buffer := device->newBufferWithSlice(vertexes[:], {.StorageModeManaged})
  defer vertex_buffer->release()
  camera_buffer := device->newBufferWithLength(size_of(CameraData), {.StorageModeManaged})
  defer camera_buffer->release()

	for {
		event := foundation.Application_nextEventMatchingMask(
			app,
			foundation.EventMaskAny,
			foundation.Date_distantPast(),
			foundation.DefaultRunLoopMode,
			true,
		)
		if (event != nil) {
			app->sendEvent(event)
			app->updateWindows()
		}

		wnds := app->windows()
		if wnds != nil {
			if wnds->count() == 0 {
				app->terminate(nil)
			}
		}
    {
      camera := CameraDefault
      left :f32= 0
      right :f32= 800
      bottom :f32= 800
      top :f32= 0
      far := camera.far
      near := camera.near
      proj : glm.mat4
      proj[0, 0] = +2 / (right - left)
      proj[1, 1] = +2 / (top - bottom)
      proj[2, 2] = -1 / (far - near)
      proj[0, 3] = -(right + left)   / (right - left)
      proj[1, 3] = -(top   + bottom) / (top - bottom)
      proj[2, 3] = -(near) / (far- near)
      proj[3, 3] = 1

      camera_data := camera_buffer->contentsAsType(CameraData)
      origin := glm.mat4Translate({-camera.target.x, -camera.target.y, 0})
      rotation := glm.mat4Rotate({0, 0, 1}, camera.rotation_radians)
      scale := glm.mat4Scale({camera.zoom, camera.zoom, 1})
      translation := glm.mat4Translate({camera.offset.x, camera.offset.y, 0})
      view := origin * scale * rotation * translation
      camera_data.mvp = view * proj

      camera_buffer->didModifyRange(foundation.Range_Make(0, size_of(CameraData)))
    }

    foundation.scoped_autoreleasepool()

		drawable := swapchain->nextDrawable()
		assert(drawable != nil)

		pass := Metal.RenderPassDescriptor.renderPassDescriptor()
		color_attachment := pass->colorAttachments()->object(0)
		assert(color_attachment != nil)
		color_attachment->setLoadAction(.Clear)
		color_attachment->setStoreAction(.Store)
		color_attachment->setTexture(drawable->texture())
    color_attachment->setClearColor(Metal.ClearColor{0.25, 0.5, 1.0, 1.0})
    
		
		command_buffer := command_queue->commandBuffer()
		render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)

		render_encoder->setRenderPipelineState(pipeline_state)
		render_encoder->setVertexBuffer(vertex_buffer, 0, 0)
    render_encoder->setVertexBuffer(camera_buffer, 0, 1)
		render_encoder->drawPrimitivesWithInstanceCount(.Triangle, 0, 6, 1)

		render_encoder->endEncoding()

		command_buffer->presentDrawable(drawable)
		command_buffer->commit()

	}


}
