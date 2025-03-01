// RUN: iree-opt -split-input-file -pass-pipeline='hal.executable(hal.executable.variant(builtin.module(builtin.func(iree-spirv-tile-and-distribute))))' %s | IreeFileCheck %s

hal.executable private @static_scatter_update_slice  {
  hal.interface @io {
    hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
    hal.interface.binding @s0b2_rw_external, set=0, binding=2, type="StorageBuffer", access="Read|Write"
  }

  hal.executable.variant @vulkan_spirv_fb, target = #hal.executable.target<"vulkan", "vulkan-spirv-fb"> {
    hal.executable.entry_point @static_scatter_update_slice attributes {
      interface = @io, ordinal = 0 : index,
      translation.info = {passPipeline = 5 : i32, workloadPerWorkgroup = [16, 1]},
      workgroup_size = [16 : index, 1 : index, 1 : index]
    }

    builtin.module {
      builtin.func @static_scatter_update_slice() {
        %c40 = constant 40 : index
        %c500 = constant 500 : index
        %c0 = constant 0 : index
        %0 = hal.interface.binding.subspan @io::@s0b0_ro_external[%c0] : memref<40x500xi32>
        %1 = hal.interface.binding.subspan @io::@s0b1_ro_external[%c0] : memref<40x1xi32>
        %2 = hal.interface.binding.subspan @io::@s0b2_rw_external[%c0] : memref<100x500xi32>
        %workgroup_id_x = hal.interface.workgroup.id[0] : index
        %workgroup_count_x = hal.interface.workgroup.count[0] : index
        %workgroup_id_y = hal.interface.workgroup.id[1] : index
        %workgroup_count_y = hal.interface.workgroup.count[1] : index
        scf.for %arg0 = %workgroup_id_y to %c40 step %workgroup_count_y {
          %3 = affine.apply affine_map<()[s0] -> (s0 * 16)>()[%workgroup_id_x]
          %4 = affine.apply affine_map<()[s0] -> (s0 * 16)>()[%workgroup_count_x]
          scf.for %arg1 = %3 to %c500 step %4 {
            %5 = affine.min affine_map<(d0) -> (16, -d0 + 500)>(%arg1)
            %6 = memref.subview %0[%arg0, %arg1] [1, %5] [1, 1] : memref<40x500xi32> to memref<1x?xi32, affine_map<(d0, d1)[s0] -> (d0 * 500 + s0 + d1)>>
            %7 = memref.cast %6 : memref<1x?xi32, affine_map<(d0, d1)[s0] -> (d0 * 500 + s0 + d1)>> to memref<?x?xi32, affine_map<(d0, d1)[s0] -> (d0 * 500 + s0 + d1)>>
            %8 = memref.subview %1[%arg0, 0] [1, 1] [1, 1] : memref<40x1xi32> to memref<1x1xi32, affine_map<(d0, d1)[s0] -> (d0 + s0 + d1)>>
            %9 = memref.cast %8 : memref<1x1xi32, affine_map<(d0, d1)[s0] -> (d0 + s0 + d1)>> to memref<?x1xi32, affine_map<(d0, d1)[s0] -> (d0 + s0 + d1)>>
            %10 = memref.subview %2[0, %arg1] [100, %5] [1, 1] : memref<100x500xi32> to memref<100x?xi32, affine_map<(d0, d1)[s0] -> (d0 * 500 + s0 + d1)>>
            linalg_ext.scatter {__internal_linalg_transform__ = "workgroup", lowering.config = {tileSizes = [[1, 16], [], [1, 1]]}} ins(%7, %9 : memref<?x?xi32, affine_map<(d0, d1)[s0] -> (d0 * 500 + s0 + d1)>>, memref<?x1xi32, affine_map<(d0, d1)[s0] -> (d0 + s0 + d1)>>) outs(%10 : memref<100x?xi32, affine_map<(d0, d1)[s0] -> (d0 * 500 + s0 + d1)>>)  {
            ^bb0(%arg2: i32, %arg3: i32):  // no predecessors
              linalg_ext.yield %arg2 : i32
            }
          }
        }
        return
      }
      hal.interface private @io  {
        hal.interface.binding @s0b0_ro_external, set=0, binding=0, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b1_ro_external, set=0, binding=1, type="StorageBuffer", access="Read"
        hal.interface.binding @s0b2_rw_external, set=0, binding=2, type="StorageBuffer", access="Read|Write"
      }
    }
  }
}

// CHECK-LABEL: func @static_scatter_update_slice()
//       CHECK: %[[ARG0:.+]] = hal.interface.binding.subspan @io::@s0b0_ro_external
//       CHECK: %[[ARG1:.+]] = hal.interface.binding.subspan @io::@s0b1_ro_external
//       CHECK: %[[ARG2:.+]] = hal.interface.binding.subspan @io::@s0b2_rw_external
//       CHECK: scf.for
//       CHECK:   scf.for
//       CHECK:     %[[WG_UPDATE:.+]] = memref.subview %[[ARG0]]
//       CHECK:     %[[WG_INDEX:.+]] = memref.subview %[[ARG1]]
//       CHECK:     %[[WG_TARGET:.+]] = memref.subview %[[ARG2]]
//       CHECK:     %[[TID_X:.+]] = "gpu.thread_id"() {dimension = "x"} : () -> index
//       CHECK:     %[[DIM_X:.+]] = "gpu.block_dim"() {dimension = "x"} : () -> index
//       CHECK:     %[[TID_Y:.+]] = "gpu.thread_id"() {dimension = "y"} : () -> index
//       CHECK:     scf.for %[[IV:.+]] = %[[TID_X]] to %{{.+}} step %[[DIM_X]]
//       CHECK:       %[[T_UPDATE:.+]] = memref.subview %[[WG_UPDATE]][%[[TID_Y]], %[[IV]]] [1, 1] [1, 1]
//       CHECK:       %[[T_UPDATE_CAST:.+]] = memref.cast %[[T_UPDATE]]
//       CHECK:       %[[T_INDEX:.+]] = memref.cast %[[WG_INDEX]]
//       CHECK:       %[[T_TARGET:.+]] = memref.subview %[[WG_TARGET]][0, %[[IV]]] [100, 1] [1, 1]
//       CHECK:       %[[T_TARGET_CAST:.+]] = memref.cast %[[T_TARGET]]
//       CHECK:       linalg_ext.scatter
//  CHECK-SAME:         __internal_linalg_transform__ = "vectorize"
//  CHECK-SAME:         ins(%[[T_UPDATE_CAST]], %[[T_INDEX]]
//  CHECK-SAME:         outs(%[[T_TARGET_CAST]]
