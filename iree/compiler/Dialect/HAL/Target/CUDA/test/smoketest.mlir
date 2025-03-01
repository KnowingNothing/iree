// RUN: iree-opt -split-input-file -iree-hal-transformation-pipeline %s | IreeFileCheck %s
// RUN: iree-opt -split-input-file -iree-hal-transformation-pipeline -iree-cuda-dump-ptx %s 2>&1 | IreeFileCheck %s -check-prefix=PTX

#map = affine_map<(d0) -> (d0)>

module attributes {
  hal.device.targets = [
    #hal.device.target<"cuda", {
      executable_targets = [
        #hal.executable.target<"cuda", "cuda-nvptx-fb">
      ]
    }>
  ]
} {

flow.executable @add_dispatch_0 {
  flow.dispatch.entry @add_dispatch_0 attributes {
    workgroup_rank = 3 : index
  }
  builtin.module  {
    func @add_dispatch_0(%arg0: !flow.dispatch.tensor<readonly:16xf32>, %arg1: !flow.dispatch.tensor<readonly:16xf32>, %arg2: !flow.dispatch.tensor<writeonly:16xf32>) {
      %0 = linalg.init_tensor [16] : tensor<16xf32>
      %1 = flow.dispatch.tensor.load %arg0, offsets=[], sizes=[], strides=[] : !flow.dispatch.tensor<readonly:16xf32> -> tensor<16xf32>
      %2 = flow.dispatch.tensor.load %arg1, offsets=[], sizes=[], strides=[] : !flow.dispatch.tensor<readonly:16xf32> -> tensor<16xf32>
      %3 = linalg.generic {indexing_maps = [#map, #map, #map], iterator_types = ["parallel"]} ins(%1, %2 : tensor<16xf32>, tensor<16xf32>) outs(%0 : tensor<16xf32>) {
      ^bb0(%arg3: f32, %arg4: f32, %arg5: f32):  // no predecessors
        %4 = addf %arg3, %arg4 : f32
        %5 = math.sqrt %4 : f32
        linalg.yield %5 : f32
      } -> tensor<16xf32>
      flow.dispatch.tensor.store %3, %arg2, offsets=[], sizes=[], strides=[] : tensor<16xf32> -> !flow.dispatch.tensor<writeonly:16xf32>
      return
    }
  }
}

}

// PTX: .entry add_dispatch_0
// PTX:   add.rn.f32
// PTX:   sqrt

//      CHECK:   hal.executable.binary public @cuda_nvptx_fb attributes {
// CHECK-SAME:     data = dense
// CHECK-SAME:     format = "cuda-nvptx-fb"
