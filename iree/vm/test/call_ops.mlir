vm.module @call_ops {

  vm.rodata private @buffer dense<[1, 2, 3]> : tensor<3xi8>

  vm.export @fail_call_v_v
  vm.func @fail_call_v_v() {
    vm.call @_v_v_fail() : () -> ()
    vm.return
  }

  vm.export @test_call_i_v
  vm.func @test_call_i_v() {
    %c1 = vm.const.i32 1 : i32
    vm.call @_i_v(%c1) : (i32) -> ()
    vm.return
  }

  vm.export @test_call_r_v
  vm.func @test_call_r_v() {
    %ref = vm.const.ref.zero : !vm.ref<?>
    vm.call @_r_v(%ref) : (!vm.ref<?>) -> ()
    vm.return
  }

  // Check that reused ref argument slots are handled properly
  vm.export @test_call_r_v_reuse_reg
  vm.func @test_call_r_v_reuse_reg() {
    %ref = vm.const.ref.zero : !vm.buffer
    %unused = vm.const.ref.zero : !vm.buffer
    vm.call @_r_v_reuse_reg(%ref, %unused) : (!vm.buffer, !vm.buffer) -> ()
    vm.return
  }

  // Check passing refs as arguments doesn't alter values on the call site
  vm.export @test_call_r_v_preserve_ref
  vm.func @test_call_r_v_preserve_ref() {
    %ref = vm.const.ref.zero : !vm.buffer
    %unused = vm.const.ref.rodata @buffer : !vm.buffer
    %unusued_dno_1 = util.do_not_optimize(%unused) : !vm.buffer
    vm.check.nz %unused : !vm.buffer
    vm.call @_r_v_preserve_reg(%ref, %unused) : (!vm.buffer, !vm.buffer) -> ()
    %unusued_dno_2 = util.do_not_optimize(%unused) : !vm.buffer
    vm.check.nz %unusued_dno_2 : !vm.buffer
    vm.return
  }

  vm.export @test_call_v_i
  vm.func @test_call_v_i() {
    %c1 = vm.const.i32 1 : i32
    %0 = vm.call @_v_i() : () -> (i32)
    vm.check.eq %0, %c1, "_v_i()=1" : i32
    vm.return
  }

  vm.export @test_call_v_r
  vm.func @test_call_v_r() {
    %ref = vm.const.ref.zero : !vm.ref<?>
    %ref_dno = util.do_not_optimize(%ref) : !vm.ref<?>
    %res = vm.call @_v_r() : () -> (!vm.ref<?>)
    vm.check.eq %ref_dno, %res, "_v_r()=NULL" : !vm.ref<?>
    vm.return
  }

  vm.export @test_call_v_ii
  vm.func @test_call_v_ii() {
    %c1 = vm.const.i32 1 : i32
    %c2 = vm.const.i32 2 : i32
    %0:2 = vm.call @_v_ii() : () -> (i32, i32)
    vm.check.eq %0#0, %c1, "_v_ii()#0=1" : i32
    vm.check.eq %0#1, %c2, "_v_ii()#1=2" : i32
    vm.return
  }

  vm.export @test_call_v_v
  vm.func @test_call_v_v() {
    vm.call @_v_v() : () -> ()
    vm.return
  }

  vm.func @_i_v(%arg : i32) attributes {noinline} {
    %c1 = vm.const.i32 1 : i32
    vm.check.eq %arg, %c1, "Expected %arg to be 1" : i32
    vm.return
  }

  vm.func @_r_v(%arg : !vm.ref<?>) attributes {noinline} {
    %ref = vm.const.ref.zero : !vm.ref<?>
    %ref_dno = util.do_not_optimize(%ref) : !vm.ref<?>
    vm.check.eq %arg, %ref_dno, "Expected %arg to be NULL" : !vm.ref<?>
    vm.return
  }

  vm.func @_r_v_reuse_reg(%arg : !vm.ref<?>, %unused : !vm.ref<?>) attributes {noinline} {
    %ref = vm.const.ref.zero : !vm.ref<?>
    %ref_dno = util.do_not_optimize(%ref) : !vm.ref<?>
    vm.check.eq %arg, %ref_dno, "Expected %arg to be NULL" : !vm.ref<?>
    vm.return
  }

  vm.func @_r_v_preserve_reg(%arg1 : !vm.ref<?>, %arg2 : !vm.ref<?>) attributes {noinline} {
    %ref = vm.const.ref.zero : !vm.ref<?>
    %ref_dno = util.do_not_optimize(%ref) : !vm.ref<?>
    vm.check.eq %arg1, %ref_dno, "Expected %arg1 to be NULL" : !vm.ref<?>
    vm.check.nz %arg2, "Expected %arg2 to be not NULL" : !vm.ref<?>
    vm.return
  }

  vm.func @_v_i() -> i32 attributes {noinline} {
    %c1 = vm.const.i32 1 : i32
    vm.return %c1 : i32
  }

  vm.func @_v_r() -> !vm.ref<?> attributes {noinline} {
    %ref = vm.const.ref.zero : !vm.ref<?>
    vm.return %ref : !vm.ref<?>
  }

  vm.func @_v_ii() -> (i32, i32) attributes {noinline} {
    %c1 = vm.const.i32 1 : i32
    %c2 = vm.const.i32 2 : i32
    vm.return %c1, %c2 : i32, i32
  }

  vm.func @_v_v() attributes {noinline} {
    vm.return
  }

  vm.func @_v_v_fail() attributes {noinline} {
    %c2 = vm.const.i32 2 : i32
    vm.fail %c2
  }

}
