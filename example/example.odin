package example
import zefir "../zefir"
import metal "vendor:darwin/Metal"

ctx := zefir.Context{}

main :: proc() {
  zefir.init({
    width = 800,
    height = 800,
    title = "MY APP",
    draw = proc(ctx: ^zefir.Context) {
      ctx.apple.view->setClearColor(metal.ClearColor{0.25, 0.5, 1.0, 1.0})
    }
  }, &ctx)
}

