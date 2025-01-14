// RUN: iree-opt -allow-unregistered-dialect -split-input-file %s | iree-opt -allow-unregistered-dialect -split-input-file | IreeFileCheck %s

// CHECK-LABEL: descriptor_set_layout_binding.basic
"descriptor_set_layout_binding.basic"() {
  // CHECK: dslb0 = #hal.descriptor_set_layout_binding<0, "StorageBuffer", RA>
  dslb0 = #hal.descriptor_set_layout_binding<0, "StorageBuffer", "Read|MayAlias">,
  // CHECK: dslb1 = #hal.descriptor_set_layout_binding<0, "StorageBuffer", RA>
  dslb1 = #hal.descriptor_set_layout_binding<0, "StorageBuffer", RA>
} : () -> ()
