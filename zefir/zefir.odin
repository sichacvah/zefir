package zefir

import foundation "core:sys/darwin/Foundation"
import metal "vendor:darwin/Metal"

Context :: struct {
  accum_time: f32
}

Shader :: struct {
  vertex_program: ^metal.Library,
  fragment_program: ^metal.Library,
}

// TODO: add texture
DrawCall :: struct {
  shader: Shader,
  offset: int,
  length: int,
}

init :: proc() {
}
