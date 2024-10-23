package zefir

import "base:runtime"
import foundation "core:sys/darwin/Foundation"
import metal "vendor:darwin/Metal"
import mtk "vendor:darwin/MetalKit"
import "core:fmt"
import glm "core:math/linalg/glsl"

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

Context :: struct {
	accum_time: f32,
	apple:      AppleContext,
	draw:       proc(ctx: ^Context),
	fini:       proc(ctx: ^Context),
  program:    rawptr,
}

AppleContext :: struct {
	view:          ^mtk.View,
	window:        ^foundation.Window,
	device:        ^metal.Device,
	view_delegate: mtk.ViewDelegate,
	command_queue: ^metal.CommandQueue,
}

Shader :: struct {
	vertex_program:   ^metal.Library,
	fragment_program: ^metal.Library,
}

// TODO: add texture
DrawCall :: struct {
	shader: Shader,
	offset: int,
	length: int,
}

AppDesc :: struct {
	width:  int,
	height: int,
	title:  string,
	draw:   proc(ctx: ^Context),
	fini:   proc(ctx: ^Context),
}

fini :: proc(ctx: ^Context) {
	ctx.apple.window->release()
	ctx.apple.view->release()
	ctx.apple.device->release()
	ctx.apple.command_queue->release()
	if ctx.fini != nil {
		ctx.fini(ctx)
	}
}

app_will_terminate :: proc(notification: ^foundation.Notification) {
	ctx := cast(^Context)context.user_ptr
	fini(ctx)
}

Vertex :: struct {
  position: [2]f32,
  color:    [4]f32,
  center:   [2]f32,
  radius:   f32,
}

draw_in_mtk_view :: proc "c" (self: ^mtk.ViewDelegate, view: ^mtk.View) {
  foundation.scoped_autoreleasepool()
  
	ctx := cast(^Context)self.user_data
	context = runtime.default_context()

  pipeline_state := cast(^metal.RenderPipelineState)ctx.program

	if ctx.draw != nil {
		ctx.draw(ctx)
	}
	cmd := ctx.apple.command_queue->commandBuffer()
	render_pass_desc := view->currentRenderPassDescriptor()
	render_encoder := cmd->renderCommandEncoderWithDescriptor(render_pass_desc)

  a := Vertex{ color = {1, 0, 0, 1}, position = { 0,  0 }, center = {400,400}, radius = 20 }
  b := Vertex{ color = {1, 1, 0, 1}, position = { 50, 0 }, center = {400,400}, radius = 20 }
  c := Vertex{ color = {0, 0, 1, 1}, position = { 50, 50 }, center = {400,400}, radius = 20 }
  d := Vertex{ color = {0, 1, 0, 1}, position = { 0, 50 }, center = {400,400}, radius = 20 }
  vertexes := [6]Vertex {
    a,b,c,
    a,c,d,
  }

	vertex_buffer := view->device()->newBufferWithSlice(vertexes[:], {.StorageModeManaged})
  defer vertex_buffer->release()
  camera_buffer := view->device()->newBufferWithLength(size_of(CameraData), {.StorageModeManaged})
  defer camera_buffer->release()
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


  render_encoder->setRenderPipelineState(pipeline_state)
	render_encoder->setVertexBuffer(vertex_buffer, 0, 0)
  render_encoder->setVertexBuffer(camera_buffer, 0, 1)
	render_encoder->drawPrimitives(.Triangle, 0, 6)
	render_encoder->endEncoding()
	cmd->presentDrawable(view->currentDrawable())
	cmd->commit()

}

build_shaders :: proc(ctx: ^Context) {
  compile_options := foundation.new(metal.CompileOptions)
  defer compile_options->release()

  pipeline_state_descriptor := foundation.new(metal.RenderPipelineDescriptor)
  defer pipeline_state_descriptor->release()

  program_library, err := ctx.apple.view->device()->newLibraryWithSource(
    foundation.AT(program_source),
    compile_options,
  )
  if err != nil {
    fmt.println("Error library: ", err->localizedDescription()->odinString())
    return
  }

  vertex_program := program_library->newFunctionWithName(foundation.AT("vertex_main"))
	fragment_program := program_library->newFunctionWithName(foundation.AT("fragment_main"))
  defer vertex_program->release()
  defer fragment_program->release()
  assert(vertex_program != nil)
	assert(fragment_program != nil)

	pipeline_state_descriptor->setVertexFunction(vertex_program)
	pipeline_state_descriptor->setFragmentFunction(fragment_program)
  pipeline_state_descriptor->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)
  program, e := ctx.apple.view->device()->newRenderPipelineState(pipeline_state_descriptor)
  if e != nil {
    fmt.println("Error Pipline state: ", e->localizedDescription()->odinString())
  }
  ctx.program = program


}


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

init :: proc(desc: AppDesc, ctx: ^Context) {
	assert(ctx != nil)
	ctx.draw = desc.draw
	ctx.fini = desc.fini
	app := foundation.Application_sharedApplication()
	window_rect := foundation.Rect {
		size = {foundation.Float(desc.width), foundation.Float(desc.height)},
	}


	ctx.apple.window = foundation.Window_alloc()
	ctx.apple.window =
	ctx.apple.window->initWithContentRect(
		window_rect,
		{.Titled, .Closable, .Resizable, .Miniaturizable},
		.Buffered,
		false,
	)

	title := foundation.String_alloc()
	title = title->initWithOdinString(desc.title)
	ctx.apple.window->setTitle(title)

	app->setActivationPolicy(.Regular)
	//app->activate()
	app->activateIgnoringOtherApps(true)

	ctx.apple.window->makeKeyAndOrderFront(nil)
	ctx.apple.window->setOpaque(true)
	ctx.apple.window->setBackgroundColor(nil)

	ctx.apple.device = metal.CreateSystemDefaultDevice()
	ctx.apple.view = mtk.View_alloc()->initWithFrame(window_rect, ctx.apple.device)


	delegate_context := context
	delegate_context.user_ptr = ctx

	delegate := foundation.application_delegate_register_and_alloc({
			applicationWillTerminate = app_will_terminate,
			applicationShouldTerminateAfterLastWindowClosed = proc(
				sender: ^foundation.Application,
			) -> foundation.BOOL {return foundation.YES},
		}, "MyAppDelegate", delegate_context)
	ctx.apple.window->setContentView(ctx.apple.view)
	ctx.apple.view_delegate.user_data = ctx
	ctx.apple.view_delegate.drawInMTKView = draw_in_mtk_view
	ctx.apple.view->setDelegate(&ctx.apple.view_delegate)
  ctx.apple.view->setColorPixelFormat(.BGRA8Unorm_sRGB)
	ctx.apple.command_queue = ctx.apple.view->device()->newCommandQueue()

  build_shaders(ctx)

	app->setDelegate(delegate)
	app->run()

}
