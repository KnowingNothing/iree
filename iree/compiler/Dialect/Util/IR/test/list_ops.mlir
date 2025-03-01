// RUN: iree-opt -split-input-file %s | iree-opt -split-input-file | IreeFileCheck %s

// CHECK-LABEL: @list_init_ops
func @list_init_ops() {
  // CHECK: %[[CAPACITY:.+]] = constant 5
  %capacity = constant 5 : index
  // CHECK: = util.list.create %[[CAPACITY]] : !util.list<?>
  %list_initial_capacity = util.list.create %capacity : !util.list<?>

  // CHECK: %[[LIST:.+]] = util.list.create : !util.list<?>
  %list = util.list.create : !util.list<?>

  // CHECK: %[[NEW_SIZE:.+]] = constant 100
  %new_size = constant 100 : index
  // CHECK: util.list.resize %[[LIST]], %[[NEW_SIZE]] : !util.list<?>
  util.list.resize %list, %new_size : !util.list<?>

  return
}

// -----

// CHECK-LABEL: @list_access
// CHECK-SAME: (%[[LIST:.+]]: !util.list<i32>)
func @list_access(%list: !util.list<i32>) {
  %c10 = constant 10 : index

  // CHECK: = util.list.get %[[LIST]][%c10] : !util.list<i32>
  %0 = util.list.get %list[%c10] : !util.list<i32>
  // CHECK: = util.list.get %[[LIST]][%c10] : !util.list<i32>
  %1 = util.list.get %list[%c10] : !util.list<i32> -> i32

  // CHECK: %[[NEW_VALUE:.+]] = constant 100 : i32
  %new_value = constant 100 : i32
  // CHECK: util.list.set %[[LIST]][%c10], %[[NEW_VALUE]] : !util.list<i32>
  util.list.set %list[%c10], %new_value : !util.list<i32>

  return
}

// -----

// CHECK-LABEL: @list_access_tensor
// CHECK-SAME: (%[[LIST:.+]]: !util.list<tensor<*xf32>>)
func @list_access_tensor(%list: !util.list<tensor<*xf32>>) {
  %c10 = constant 10 : index

  // CHECK: = util.list.get %[[LIST]][%c10] : !util.list<tensor<*xf32>> -> tensor<?xf32>
  %0 = util.list.get %list[%c10] : !util.list<tensor<*xf32>> -> tensor<?xf32>

  // CHECK: %[[NEW_VALUE:.+]] = constant dense<1> : tensor<5xi32>
  %new_value = constant dense<1> : tensor<5xi32>
  // CHECK: util.list.set %[[LIST]][%c10], %[[NEW_VALUE]] : tensor<5xi32> -> !util.list<tensor<*xf32>>
  util.list.set %list[%c10], %new_value : tensor<5xi32> -> !util.list<tensor<*xf32>>

  return
}

// -----

// CHECK-LABEL: @list_access_variant
// CHECK-SAME: (%[[LIST:.+]]: !util.list<?>)
func @list_access_variant(%list: !util.list<?>) {
  %c10 = constant 10 : index
  %c11 = constant 11 : index

  // CHECK: = util.list.get %[[LIST]][%c10] : !util.list<?> -> i32
  %0 = util.list.get %list[%c10] : !util.list<?> -> i32

  // CHECK: %[[NEW_I32_VALUE:.+]] = constant 100 : i32
  %new_i32_value = constant 100 : i32
  // CHECK: util.list.set %[[LIST]][%c10], %[[NEW_I32_VALUE]] : i32 -> !util.list<?>
  util.list.set %list[%c10], %new_i32_value : i32 -> !util.list<?>

  // CHECK: = util.list.get %[[LIST]][%c11] : !util.list<?> -> tensor<5xf32>
  %1 = util.list.get %list[%c11] : !util.list<?> -> tensor<5xf32>

  // CHECK: %[[NEW_TENSOR_VALUE:.+]] = constant dense<1> : tensor<5xi32>
  %new_tensor_value = constant dense<1> : tensor<5xi32>
  // CHECK: util.list.set %[[LIST]][%c11], %[[NEW_TENSOR_VALUE]] : tensor<5xi32> -> !util.list<?>
  util.list.set %list[%c11], %new_tensor_value : tensor<5xi32> -> !util.list<?>

  return
}

