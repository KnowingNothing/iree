// Copyright 2021 The IREE Authors
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef IREE_COMPILER_INPUTCONVERSION_TOSA_PASSES
#define IREE_COMPILER_INPUTCONVERSION_TOSA_PASSES

include "mlir/Pass/PassBase.td"

def VerifyCompilerTOSAInputLegality :
    Pass<"iree-tosa-verify-compiler-input-legality", "ModuleOp"> {
  let summary = "Verifies that only supported IR constructs are passed to the compiler.";
  let constructor = "mlir::iree_compiler::createVerifyCompilerTOSAInputLegality()";
}

#endif // IREE_COMPILER_INPUTCONVERSION_TOSA_PASSES
