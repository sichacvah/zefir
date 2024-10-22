package zefir

import foundation "core:sys/darwin/Foundation"
import metal "vendor:darwin/Metal"
import mtk "vendor:darwin/MetalKit"
import "base:runtime"

Context :: struct {
	accum_time:       f32,
	platform_context: AppleContext,
  draw: proc(ctx: ^Context),
  fini: proc(ctx: ^Context),
}

AppleContext :: struct {
	view:   ^mtk.View,
	window: ^foundation.Window,
	device: ^metal.Device,
  view_delegate: mtk.ViewDelegate,
  command_queue: ^metal.CommandQueue 
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
  draw: proc(ctx: ^Context),
  fini: proc(ctx: ^Context),
}

fini :: proc(ctx: ^Context) {
	ctx.platform_context.window->release()
	ctx.platform_context.view->release()
	ctx.platform_context.device->release()
  ctx.platform_context.command_queue->release()
  if ctx.fini != nil {
    ctx.fini(ctx)
  }
}

app_will_terminate :: proc(notification: ^foundation.Notification) {
	ctx := cast(^Context)context.user_ptr
	fini(ctx)
}

draw_in_mtk_view :: proc "c" (self: ^mtk.ViewDelegate, view: ^mtk.View) {

  foundation.scoped_autoreleasepool()
  ctx := cast(^Context)self.user_data

  context = runtime.default_context()
  if ctx.draw != nil {
    ctx.draw(ctx)
  } 
  cmd := ctx.platform_context.command_queue->commandBuffer()
  render_pass_desc := view->currentRenderPassDescriptor()
  render_encoder := cmd->renderCommandEncoderWithDescriptor(render_pass_desc)
  render_encoder->endEncoding()
  cmd->presentDrawable(view->currentDrawable())
  cmd->commit()

}


init :: proc(desc: AppDesc, ctx: ^Context) {
  assert(ctx != nil)
  ctx.draw = desc.draw
  ctx.fini = desc.fini
	app := foundation.Application_sharedApplication()
	window_rect := foundation.Rect {
		size = {foundation.Float(desc.width), foundation.Float(desc.height)},
	}
  

	ctx.platform_context.window = foundation.Window_alloc()
	ctx.platform_context.window =
	ctx.platform_context.window->initWithContentRect(
		window_rect,
		{.Titled, .Closable, .Resizable, .Miniaturizable},
		.Buffered,
		false,
	)

	title := foundation.String_alloc()
	title = title->initWithOdinString(desc.title)
	ctx.platform_context.window->setTitle(title)

	app->setActivationPolicy(.Regular)
	//app->activate()
	app->activateIgnoringOtherApps(true)

	ctx.platform_context.window->makeKeyAndOrderFront(nil)
	ctx.platform_context.window->setOpaque(true)
	ctx.platform_context.window->setBackgroundColor(nil)

	ctx.platform_context.device = metal.CreateSystemDefaultDevice()
	ctx.platform_context.view =
	mtk.View_alloc()->initWithFrame(window_rect, ctx.platform_context.device)


	delegate_context := context
	delegate_context.user_ptr = ctx

	delegate := foundation.application_delegate_register_and_alloc(
		{applicationWillTerminate = app_will_terminate},
		"MyAppDelegate",
		delegate_context,
	)
  ctx.platform_context.window->setContentView(ctx.platform_context.view)
  ctx.platform_context.view_delegate.user_data = ctx
  ctx.platform_context.view_delegate.drawInMTKView = draw_in_mtk_view
  ctx.platform_context.view->setDelegate(&ctx.platform_context.view_delegate)
  ctx.platform_context.command_queue = ctx.platform_context.view->device()->newCommandQueue()
  app->setDelegate(delegate)
  app->run()

}
