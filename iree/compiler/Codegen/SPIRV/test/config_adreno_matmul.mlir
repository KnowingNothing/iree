// RUN: iree-opt -split-input-file -mlir-print-local-scope -pass-pipeline='hal.executable(hal.executable.variant(iree-spirv-lower-executable-target-pass{test-lowering-configuration=true}))' %s | IreeFileCheck %s

// Large matmul that can match the best tiling scheme.

hal.executable @matmul_1024x2048x512 {
  hal.interface @io {
    hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b2_xw_external, set=0, binding=2, type="StorageBuffer", access="Write|Discard"
  }
  hal.executable.variant @vulkan_spirv_fb, target = #hal.executable.target<"vulkan", "vulkan-spirv-fb", {
      spv.target_env = #spv.target_env<#spv.vce<v1.4, [Shader], []>, Qualcomm:IntegratedGPU, {
        max_compute_shared_memory_size = 32768 : i32,
        max_compute_workgroup_invocations = 1024 : i32,
        max_compute_workgroup_size = dense<[1024, 1024, 64]> : vector<3xi32>,
        subgroup_size = 64 : i32}>
    }> {
    hal.executable.entry_point @matmul_1024x2048x512 attributes {interface = @io, ordinal = 0 : index}
    builtin.module  {
      func @matmul_1024x2048x512() {
        %c0 = constant 0 : index
        %c2048 = constant 2048 : index
        %c1024 = constant 1024 : index
        %cst = constant 0.000000e+00 : f32
        %0 = hal.interface.binding.subspan @io::@s0b0_ro_external[%c0] : !flow.dispatch.tensor<readonly:1024x512xf32>
        %1 = hal.interface.binding.subspan @io::@s0b1_ro_external[%c0] : !flow.dispatch.tensor<readonly:512x2048xf32>
        %2 = hal.interface.binding.subspan @io::@s0b2_xw_external[%c0] : !flow.dispatch.tensor<writeonly:1024x2048xf32>
        %workgroup_size_x = hal.interface.workgroup.size[0] : index
        %workgroup_size_y = hal.interface.workgroup.size[1] : index
        %workgroup_id_x = hal.interface.workgroup.id[0] : index
        %workgroup_count_x = hal.interface.workgroup.count[0] : index
        %workgroup_id_y = hal.interface.workgroup.id[1] : index
        %workgroup_count_y = hal.interface.workgroup.count[1] : index
        %3 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_id_y, %workgroup_size_y]
        %4 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_count_y, %workgroup_size_y]
        scf.for %arg0 = %3 to %c1024 step %4 {
          %5 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_id_x, %workgroup_size_x]
          %6 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_count_x, %workgroup_size_x]
          scf.for %arg1 = %5 to %c2048 step %6 {
            %7 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 1024)>(%arg0)[%workgroup_size_y]
            %8 = flow.dispatch.tensor.load %0, offsets = [%arg0, 0], sizes = [%7, 512], strides = [1, 1] : !flow.dispatch.tensor<readonly:1024x512xf32> -> tensor<?x512xf32>
            %9 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 2048)>(%arg1)[%workgroup_size_x]
            %10 = flow.dispatch.tensor.load %1, offsets = [0, %arg1], sizes = [512, %9], strides = [1, 1] : !flow.dispatch.tensor<readonly:512x2048xf32> -> tensor<512x?xf32>
            %11 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 1024)>(%arg0)[%workgroup_size_y]
            %12 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 2048)>(%arg1)[%workgroup_size_x]
            %13 = affine.min affine_map<(d0)[s0] -> (-d0 + 1024, s0)>(%arg0)[%workgroup_size_y]
            %14 = affine.min affine_map<(d0)[s0] -> (-d0 + 2048, s0)>(%arg1)[%workgroup_size_x]
            %15 = linalg.init_tensor [%13, %14] : tensor<?x?xf32>
            %16 = linalg.fill(%cst, %15) : f32, tensor<?x?xf32> -> tensor<?x?xf32>
            %17 = linalg.matmul {__internal_linalg_transform__ = "workgroup"} ins(%8, %10 : tensor<?x512xf32>, tensor<512x?xf32>) outs(%16 : tensor<?x?xf32>) -> tensor<?x?xf32>
            flow.dispatch.tensor.store %17, %2, offsets = [%arg0, %arg1], sizes = [%11, %12], strides = [1, 1] : tensor<?x?xf32> -> !flow.dispatch.tensor<writeonly:1024x2048xf32>
          }
        }
        return
      }
      hal.interface @io attributes {sym_visibility = "private"} {
        hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b2_xw_external, set=0, binding=2, type="StorageBuffer", access="Write|Discard"
      }
    }
  }
}

//          CHECK-LABEL: hal.executable.entry_point public @matmul_1024x2048x512
//           CHECK-SAME:   translation.info = {passPipeline = 6 : i32, workloadPerWorkgroup = [128, 16]}
//           CHECK-SAME:   workgroup_size = [32 : index, 2 : index, 1 : index]
//           CHECK-NEXT: ^{{.+}}(%[[X:.+]]: index, %[[Y:.+]]: index, %{{.+}}: index):
//           CHECK-NEXT:   %[[ONE:.+]] = constant 1 : index
//           CHECK-NEXT:   %[[X_COUNT:.+]] = affine.apply affine_map<()[s0] -> (s0 ceildiv 128)>()[%[[X]]]
//           CHECK-NEXT:   %[[Y_COUNT:.+]] = affine.apply affine_map<()[s0] -> (s0 ceildiv 16)>()[%[[Y]]]
//           CHECK-NEXT:   hal.return %[[X_COUNT]], %[[Y_COUNT]], %[[ONE]]

//                CHECK: func @matmul_1024x2048x512()
//                CHECK:   linalg.matmul
//  CHECK-SAME{LITERAL}:     lowering.config = {tileSizes = [[16, 128, 16], [], [8, 4, 16]]}

// -----

// Small matmul N that can still tile to all threads in a workgroup.

hal.executable @matmul_3136x24x96 {
  hal.interface @io {
    hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b2_xw_external, set=0, binding=2, type="StorageBuffer", access="Write|Discard"
  }
  hal.executable.variant @vulkan_spirv_fb, target = #hal.executable.target<"vulkan", "vulkan-spirv-fb", {
      spv.target_env = #spv.target_env<#spv.vce<v1.4, [Shader], []>, Qualcomm:IntegratedGPU, {
        max_compute_shared_memory_size = 32768 : i32,
        max_compute_workgroup_invocations = 1024 : i32,
        max_compute_workgroup_size = dense<[1024, 1024, 64]> : vector<3xi32>,
        subgroup_size = 64 : i32}>
    }> {
    hal.executable.entry_point @matmul_3136x24x96 attributes {interface = @io, ordinal = 0 : index}
    builtin.module  {
      func @matmul_3136x24x96() {
        %c0 = constant 0 : index
        %c24 = constant 24 : index
        %c3136 = constant 3136 : index
        %cst = constant 0.000000e+00 : f32
        %0 = hal.interface.binding.subspan @io::@s0b0_ro_external[%c0] : !flow.dispatch.tensor<readonly:3136x96xf32>
        %1 = hal.interface.binding.subspan @io::@s0b1_ro_external[%c0] : !flow.dispatch.tensor<readonly:96x24xf32>
        %2 = hal.interface.binding.subspan @io::@s0b2_xw_external[%c0] : !flow.dispatch.tensor<writeonly:3136x24xf32>
        %workgroup_size_x = hal.interface.workgroup.size[0] : index
        %workgroup_size_y = hal.interface.workgroup.size[1] : index
        %workgroup_id_x = hal.interface.workgroup.id[0] : index
        %workgroup_count_x = hal.interface.workgroup.count[0] : index
        %workgroup_id_y = hal.interface.workgroup.id[1] : index
        %workgroup_count_y = hal.interface.workgroup.count[1] : index
        %3 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_id_y, %workgroup_size_y]
        %4 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_count_y, %workgroup_size_y]
        scf.for %arg0 = %3 to %c3136 step %4 {
          %5 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_id_x, %workgroup_size_x]
          %6 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_count_x, %workgroup_size_x]
          scf.for %arg1 = %5 to %c24 step %6 {
            %7 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 3136)>(%arg0)[%workgroup_size_y]
            %8 = flow.dispatch.tensor.load %0, offsets = [%arg0, 0], sizes = [%7, 96], strides = [1, 1] : !flow.dispatch.tensor<readonly:3136x96xf32> -> tensor<?x96xf32>
            %9 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 24)>(%arg1)[%workgroup_size_x]
            %10 = flow.dispatch.tensor.load %1, offsets = [0, %arg1], sizes = [96, %9], strides = [1, 1] : !flow.dispatch.tensor<readonly:96x24xf32> -> tensor<96x?xf32>
            %11 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 3136)>(%arg0)[%workgroup_size_y]
            %12 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 24)>(%arg1)[%workgroup_size_x]
            %13 = affine.min affine_map<(d0)[s0] -> (-d0 + 3136, s0)>(%arg0)[%workgroup_size_y]
            %14 = affine.min affine_map<(d0)[s0] -> (-d0 + 24, s0)>(%arg1)[%workgroup_size_x]
            %15 = linalg.init_tensor [%13, %14] : tensor<?x?xf32>
            %16 = linalg.fill(%cst, %15) : f32, tensor<?x?xf32> -> tensor<?x?xf32>
            %17 = linalg.matmul {__internal_linalg_transform__ = "workgroup"} ins(%8, %10 : tensor<?x96xf32>, tensor<96x?xf32>) outs(%16 : tensor<?x?xf32>) -> tensor<?x?xf32>
            flow.dispatch.tensor.store %17, %2, offsets = [%arg0, %arg1], sizes = [%11, %12], strides = [1, 1] : tensor<?x?xf32> -> !flow.dispatch.tensor<writeonly:3136x24xf32>
          }
        }
        return
      }
      hal.interface @io attributes {sym_visibility = "private"} {
        hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b2_xw_external, set=0, binding=2, type="StorageBuffer", access="Write|Discard"
      }
    }
  }
}

//          CHECK-LABEL: hal.executable.entry_point public @matmul_3136x24x96
//           CHECK-SAME:   translation.info = {passPipeline = 6 : i32, workloadPerWorkgroup = [8, 224]}
//           CHECK-SAME:   workgroup_size = [2 : index, 32 : index, 1 : index]
//           CHECK-NEXT: ^{{.+}}(%[[X:.+]]: index, %[[Y:.+]]: index, %{{.+}}: index):
//           CHECK-NEXT:   %[[ONE:.+]] = constant 1 : index
//           CHECK-NEXT:   %[[X_COUNT:.+]] = affine.apply affine_map<()[s0] -> (s0 ceildiv 8)>()[%[[X]]]
//           CHECK-NEXT:   %[[Y_COUNT:.+]] = affine.apply affine_map<()[s0] -> (s0 ceildiv 224)>()[%[[Y]]]
//           CHECK-NEXT:   hal.return %[[X_COUNT]], %[[Y_COUNT]], %[[ONE]]

//                CHECK: func @matmul_3136x24x96()
//                CHECK:   linalg.matmul
//  CHECK-SAME{LITERAL}:     lowering.config = {tileSizes = [[224, 8, 16], [], [7, 4, 16]]}

// -----

// Small matmul M that can still tile to all threads in a workgroup.

hal.executable @matmul_196x64x192 {
  hal.interface @io {
    hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b2_xw_external, set=0, binding=2, type="StorageBuffer", access="Write|Discard"
  }
  hal.executable.variant @vulkan_spirv_fb, target = #hal.executable.target<"vulkan", "vulkan-spirv-fb", {
      spv.target_env = #spv.target_env<#spv.vce<v1.4, [Shader], []>, Qualcomm:IntegratedGPU, {
        max_compute_shared_memory_size = 32768 : i32,
        max_compute_workgroup_invocations = 1024 : i32,
        max_compute_workgroup_size = dense<[1024, 1024, 64]> : vector<3xi32>,
        subgroup_size = 64 : i32}>
    }> {
    hal.executable.entry_point @matmul_196x64x192 attributes {interface = @io, ordinal = 0 : index}
    builtin.module  {
      func @matmul_196x64x192() {
        %c0 = constant 0 : index
        %c64 = constant 64 : index
        %c196 = constant 196 : index
        %cst = constant 0.000000e+00 : f32
        %0 = hal.interface.binding.subspan @io::@s0b0_ro_external[%c0] : !flow.dispatch.tensor<readonly:196x192xf32>
        %1 = hal.interface.binding.subspan @io::@s0b1_ro_external[%c0] : !flow.dispatch.tensor<readonly:192x64xf32>
        %2 = hal.interface.binding.subspan @io::@s0b2_xw_external[%c0] : !flow.dispatch.tensor<writeonly:196x64xf32>
        %workgroup_size_x = hal.interface.workgroup.size[0] : index
        %workgroup_size_y = hal.interface.workgroup.size[1] : index
        %workgroup_id_x = hal.interface.workgroup.id[0] : index
        %workgroup_count_x = hal.interface.workgroup.count[0] : index
        %workgroup_id_y = hal.interface.workgroup.id[1] : index
        %workgroup_count_y = hal.interface.workgroup.count[1] : index
        %3 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_id_y, %workgroup_size_y]
        %4 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_count_y, %workgroup_size_y]
        scf.for %arg0 = %3 to %c196 step %4 {
          %5 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_id_x, %workgroup_size_x]
          %6 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_count_x, %workgroup_size_x]
          scf.for %arg1 = %5 to %c64 step %6 {
            %7 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 196)>(%arg0)[%workgroup_size_y]
            %8 = flow.dispatch.tensor.load %0, offsets = [%arg0, 0], sizes = [%7, 192], strides = [1, 1] : !flow.dispatch.tensor<readonly:196x192xf32> -> tensor<?x192xf32>
            %9 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 64)>(%arg1)[%workgroup_size_x]
            %10 = flow.dispatch.tensor.load %1, offsets = [0, %arg1], sizes = [192, %9], strides = [1, 1] : !flow.dispatch.tensor<readonly:192x64xf32> -> tensor<192x?xf32>
            %11 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 196)>(%arg0)[%workgroup_size_y]
            %12 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 64)>(%arg1)[%workgroup_size_x]
            %13 = affine.min affine_map<(d0)[s0] -> (-d0 + 196, s0)>(%arg0)[%workgroup_size_y]
            %14 = affine.min affine_map<(d0)[s0] -> (-d0 + 64, s0)>(%arg1)[%workgroup_size_x]
            %15 = linalg.init_tensor [%13, %14] : tensor<?x?xf32>
            %16 = linalg.fill(%cst, %15) : f32, tensor<?x?xf32> -> tensor<?x?xf32>
            %17 = linalg.matmul {__internal_linalg_transform__ = "workgroup"} ins(%8, %10 : tensor<?x192xf32>, tensor<192x?xf32>) outs(%16 : tensor<?x?xf32>) -> tensor<?x?xf32>
            flow.dispatch.tensor.store %17, %2, offsets = [%arg0, %arg1], sizes = [%11, %12], strides = [1, 1] : tensor<?x?xf32> -> !flow.dispatch.tensor<writeonly:196x64xf32>
          }
        }
        return
      }
      hal.interface @io attributes {sym_visibility = "private"} {
        hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b2_xw_external, set=0, binding=2, type="StorageBuffer", access="Write|Discard"
      }
    }
  }
}

//          CHECK-LABEL: hal.executable.entry_point public @matmul_196x64x192
//           CHECK-SAME:   translation.info = {passPipeline = 6 : i32, workloadPerWorkgroup = [64, 28]}
//           CHECK-SAME:   workgroup_size = [16 : index, 4 : index, 1 : index]
//           CHECK-NEXT: ^{{.+}}(%[[X:.+]]: index, %[[Y:.+]]: index, %{{.+}}: index):
//           CHECK-NEXT:   %[[ONE:.+]] = constant 1 : index
//           CHECK-NEXT:   %[[X_COUNT:.+]] = affine.apply affine_map<()[s0] -> (s0 ceildiv 64)>()[%[[X]]]
//           CHECK-NEXT:   %[[Y_COUNT:.+]] = affine.apply affine_map<()[s0] -> (s0 ceildiv 28)>()[%[[Y]]]
//           CHECK-NEXT:   hal.return %[[X_COUNT]], %[[Y_COUNT]], %[[ONE]]

//                CHECK: func @matmul_196x64x192()
//                CHECK:   linalg.matmul
//  CHECK-SAME{LITERAL}:      lowering.config = {tileSizes = [[28, 64, 16], [], [7, 4, 16]]}

// -----

// Small matmul K that can still tile to all threads in a workgroup.

hal.executable @matmul_12544x96x16 {
  hal.interface @io {
    hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b2_xw_external, set=0, binding=2, type="StorageBuffer", access="Write|Discard"
  }
  hal.executable.variant @vulkan_spirv_fb, target = #hal.executable.target<"vulkan", "vulkan-spirv-fb", {
      spv.target_env = #spv.target_env<#spv.vce<v1.4, [Shader], []>, Qualcomm:IntegratedGPU, {
        max_compute_shared_memory_size = 32768 : i32,
        max_compute_workgroup_invocations = 1024 : i32,
        max_compute_workgroup_size = dense<[1024, 1024, 64]> : vector<3xi32>,
        subgroup_size = 64 : i32}>
    }> {
    hal.executable.entry_point @matmul_12544x96x16 attributes {interface = @io, ordinal = 0 : index}
    builtin.module  {
      func @matmul_12544x96x16() {
        %c0 = constant 0 : index
        %c96 = constant 96 : index
        %c12544 = constant 12544 : index
        %cst = constant 0.000000e+00 : f32
        %0 = hal.interface.binding.subspan @io::@s0b0_ro_external[%c0] : memref<12544x16xf32>
        %1 = hal.interface.binding.subspan @io::@s0b1_ro_external[%c0] : memref<16x96xf32>
        %2 = hal.interface.binding.subspan @io::@s0b2_xw_external[%c0] : memref<12544x96xf32>
        %workgroup_size_x = hal.interface.workgroup.size[0] : index
        %workgroup_size_y = hal.interface.workgroup.size[1] : index
        %workgroup_id_x = hal.interface.workgroup.id[0] : index
        %workgroup_count_x = hal.interface.workgroup.count[0] : index
        %workgroup_id_y = hal.interface.workgroup.id[1] : index
        %workgroup_count_y = hal.interface.workgroup.count[1] : index
        %3 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_id_y, %workgroup_size_y]
        %4 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_count_y, %workgroup_size_y]
        scf.for %arg0 = %3 to %c12544 step %4 {
          %5 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_id_x, %workgroup_size_x]
          %6 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_count_x, %workgroup_size_x]
          scf.for %arg1 = %5 to %c96 step %6 {
            %7 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 12544)>(%arg0)[%workgroup_size_y]
            %8 = memref.subview %0[%arg0, 0] [%7, 16] [1, 1] : memref<12544x16xf32> to memref<?x16xf32, affine_map<(d0, d1)[s0] -> (d0 * 16 + s0 + d1)>>
            %9 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 96)>(%arg1)[%workgroup_size_x]
            %10 = memref.subview %1[0, %arg1] [16, %9] [1, 1] : memref<16x96xf32> to memref<16x?xf32, affine_map<(d0, d1)[s0] -> (d0 * 96 + s0 + d1)>>
            %11 = memref.subview %2[%arg0, %arg1] [%7, %9] [1, 1] : memref<12544x96xf32> to memref<?x?xf32, affine_map<(d0, d1)[s0] -> (d0 * 96 + s0 + d1)>>
            linalg.fill(%cst, %11) : f32, memref<?x?xf32, affine_map<(d0, d1)[s0] -> (d0 * 96 + s0 + d1)>>
            linalg.matmul {__internal_linalg_transform__ = "workgroup"} ins(%8, %10 : memref<?x16xf32, affine_map<(d0, d1)[s0] -> (d0 * 16 + s0 + d1)>>, memref<16x?xf32, affine_map<(d0, d1)[s0] -> (d0 * 96 + s0 + d1)>>) outs(%11 : memref<?x?xf32, affine_map<(d0, d1)[s0] -> (d0 * 96 + s0 + d1)>>)
          }
        }
        return
      }
      hal.interface @io attributes {sym_visibility = "private"} {
        hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b2_xw_external, set=0, binding=2, type="StorageBuffer", access="Write|Discard"
      }
    }
  }
}

//          CHECK-LABEL: hal.executable.entry_point public @matmul_12544x96x16
//           CHECK-SAME:   translation.info = {passPipeline = 6 : i32, workloadPerWorkgroup = [32, 64]}
//           CHECK-SAME:   workgroup_size = [8 : index, 8 : index, 1 : index]
//           CHECK-NEXT: ^{{.+}}(%[[X:.+]]: index, %[[Y:.+]]: index, %{{.+}}: index):
//           CHECK-NEXT:   %[[ONE:.+]] = constant 1 : index
//           CHECK-NEXT:   %[[X_COUNT:.+]] = affine.apply affine_map<()[s0] -> (s0 ceildiv 32)>()[%[[X]]]
//           CHECK-NEXT:   %[[Y_COUNT:.+]] = affine.apply affine_map<()[s0] -> (s0 ceildiv 64)>()[%[[Y]]]
//           CHECK-NEXT:   hal.return %[[X_COUNT]], %[[Y_COUNT]], %[[ONE]]

//                CHECK: func @matmul_12544x96x16()
//                CHECK:   linalg.matmul
//  CHECK-SAME{LITERAL}:     lowering.config =  {tileSizes = [[64, 32, 16], [], [8, 4, 16]]}

// -----

// Odd matmul M and small N that cannot utilize all threads in a workgroup.

hal.executable @matmul_49x160x576 {
  hal.interface @io {
    hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b2_xw_external, set=0, binding=2, type="StorageBuffer", access="Write|Discard"
  }
  hal.executable.variant @vulkan_spirv_fb, target = #hal.executable.target<"vulkan", "vulkan-spirv-fb", {
      spv.target_env = #spv.target_env<#spv.vce<v1.4, [Shader], []>, Qualcomm:IntegratedGPU, {
        max_compute_shared_memory_size = 32768 : i32,
        max_compute_workgroup_invocations = 1024 : i32,
        max_compute_workgroup_size = dense<[1024, 1024, 64]> : vector<3xi32>,
        subgroup_size = 64 : i32}>
    }> {
    hal.executable.entry_point @matmul_49x160x576 attributes {interface = @io, ordinal = 0 : index}
    builtin.module  {
      func @matmul_49x160x576() {
        %c0 = constant 0 : index
        %c160 = constant 160 : index
        %c49 = constant 49 : index
        %cst = constant 0.000000e+00 : f32
        %0 = hal.interface.binding.subspan @io::@s0b0_ro_external[%c0] : !flow.dispatch.tensor<readonly:49x576xf32>
        %1 = hal.interface.binding.subspan @io::@s0b1_ro_external[%c0] : !flow.dispatch.tensor<readonly:576x160xf32>
        %2 = hal.interface.binding.subspan @io::@s0b2_xw_external[%c0] : !flow.dispatch.tensor<writeonly:49x160xf32>
        %workgroup_size_x = hal.interface.workgroup.size[0] : index
        %workgroup_size_y = hal.interface.workgroup.size[1] : index
        %workgroup_id_x = hal.interface.workgroup.id[0] : index
        %workgroup_count_x = hal.interface.workgroup.count[0] : index
        %workgroup_id_y = hal.interface.workgroup.id[1] : index
        %workgroup_count_y = hal.interface.workgroup.count[1] : index
        %3 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_id_y, %workgroup_size_y]
        %4 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_count_y, %workgroup_size_y]
        scf.for %arg0 = %3 to %c49 step %4 {
          %5 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_id_x, %workgroup_size_x]
          %6 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%workgroup_count_x, %workgroup_size_x]
          scf.for %arg1 = %5 to %c160 step %6 {
            %7 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 49)>(%arg0)[%workgroup_size_y]
            %8 = flow.dispatch.tensor.load %0, offsets = [%arg0, 0], sizes = [%7, 576], strides = [1, 1] : !flow.dispatch.tensor<readonly:49x576xf32> -> tensor<?x576xf32>
            %9 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 160)>(%arg1)[%workgroup_size_x]
            %10 = flow.dispatch.tensor.load %1, offsets = [0, %arg1], sizes = [576, %9], strides = [1, 1] : !flow.dispatch.tensor<readonly:576x160xf32> -> tensor<576x?xf32>
            %11 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 49)>(%arg0)[%workgroup_size_y]
            %12 = affine.min affine_map<(d0)[s0] -> (s0, -d0 + 160)>(%arg1)[%workgroup_size_x]
            %13 = affine.min affine_map<(d0)[s0] -> (-d0 + 49, s0)>(%arg0)[%workgroup_size_y]
            %14 = affine.min affine_map<(d0)[s0] -> (-d0 + 160, s0)>(%arg1)[%workgroup_size_x]
            %15 = linalg.init_tensor [%13, %14] : tensor<?x?xf32>
            %16 = linalg.fill(%cst, %15) : f32, tensor<?x?xf32> -> tensor<?x?xf32>
            %17 = linalg.matmul {__internal_linalg_transform__ = "workgroup"} ins(%8, %10 : tensor<?x576xf32>, tensor<576x?xf32>) outs(%16 : tensor<?x?xf32>) -> tensor<?x?xf32>
            flow.dispatch.tensor.store %17, %2, offsets = [%arg0, %arg1], sizes = [%11, %12], strides = [1, 1] : tensor<?x?xf32> -> !flow.dispatch.tensor<writeonly:49x160xf32>
          }
        }
        return
      }
      hal.interface @io attributes {sym_visibility = "private"} {
        hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b2_xw_external, set=0, binding=2, type="StorageBuffer", access="Write|Discard"
      }
    }
  }
}

//          CHECK-LABEL: hal.executable.entry_point public @matmul_49x160x576
//           CHECK-SAME:   translation.info = {passPipeline = 6 : i32, workloadPerWorkgroup = [32, 7]}
//           CHECK-SAME:   workgroup_size = [8 : index, 1 : index, 1 : index]
//           CHECK-NEXT: ^{{.+}}(%[[X:.+]]: index, %[[Y:.+]]: index, %{{.+}}: index):
//           CHECK-NEXT:   %[[ONE:.+]] = constant 1 : index
//           CHECK-NEXT:   %[[X_COUNT:.+]] = affine.apply affine_map<()[s0] -> (s0 ceildiv 32)>()[%[[X]]]
//           CHECK-NEXT:   %[[Y_COUNT:.+]] = affine.apply affine_map<()[s0] -> (s0 ceildiv 7)>()[%[[Y]]]
//           CHECK-NEXT:   hal.return %[[X_COUNT]], %[[Y_COUNT]], %[[ONE]]

//                CHECK: func @matmul_49x160x576()
//                CHECK:   linalg.matmul
//  CHECK-SAME{LITERAL}:     lowering.config = {tileSizes = [[7, 32, 16], [], [7, 4, 16]]}
