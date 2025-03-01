// Copyright 2021 The IREE Authors
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "iree/compiler/Dialect/HAL/IR/HALDialect.h"
#include "iree/compiler/Dialect/Modules/VMVX/Conversion/HALToVMVX/ConvertHALToVMVX.h"
#include "iree/compiler/Dialect/Modules/VMVX/Conversion/StandardToVMVX/ConvertStandardToVMVX.h"
#include "iree/compiler/Dialect/Modules/VMVX/IR/VMVXDialect.h"
#include "iree/compiler/Dialect/Modules/VMVX/IR/VMVXTypes.h"
#include "iree/compiler/Dialect/Modules/VMVX/Transforms/Passes.h"
#include "iree/compiler/Dialect/Util/IR/UtilDialect.h"
#include "iree/compiler/Dialect/VM/IR/VMDialect.h"
#include "llvm/ADT/STLExtras.h"
#include "mlir/Conversion/TosaToStandard/TosaToStandard.h"
#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/StandardOps/IR/Ops.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/DialectConversion.h"

namespace mlir {
namespace iree_compiler {
namespace IREE {
namespace VMVX {

// Runs conversion with registered input dialects.
class ConversionPass
    : public PassWrapper<ConversionPass, OperationPass<mlir::ModuleOp>> {
 public:
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<IREE::Util::UtilDialect, IREE::HAL::HALDialect,
                    IREE::VM::VMDialect, IREE::VMVX::VMVXDialect,
                    memref::MemRefDialect>();
  }

  StringRef getArgument() const override { return "iree-vmvx-conversion"; }

  StringRef getDescription() const override {
    return "Converts from various dialects to the VMVX dialect";
  }

  void runOnOperation() override {
    auto *context = &getContext();

    TypeConverter typeConverter;

    typeConverter.addConversion([](Type type) { return type; });

    // Run a pre-pass that updates the entry function signature.
    for (auto funcOp : getOperation().getOps<FuncOp>()) {
      if (funcOp.isPublic()) {
        if (failed(updateHALToVMVXEntryFuncOp(funcOp, typeConverter))) {
          return signalPassFailure();
        }
      }
    }

    // Ensure all input dialects go away.
    ConversionTarget conversionTarget(*context);
    conversionTarget.addIllegalDialect<IREE::HAL::HALDialect>();
    conversionTarget.addIllegalDialect<tensor::TensorDialect>();
    conversionTarget.addLegalDialect<IREE::Util::UtilDialect>();
    conversionTarget.addLegalDialect<IREE::VMVX::VMVXDialect>();
    conversionTarget.addLegalDialect<mlir::StandardOpsDialect>();
    conversionTarget.addLegalDialect<mlir::AffineDialect>();
    conversionTarget.addLegalDialect<memref::MemRefDialect>();
    conversionTarget.addLegalOp<mlir::UnrealizedConversionCastOp>();

    OwningRewritePatternList conversionPatterns(&getContext());
    populateHALToVMVXPatterns(context, conversionPatterns, typeConverter);
    populateStandardToVMVXPatterns(context, conversionPatterns, typeConverter);

    // Use the default 64-bit lowering for TOSA's ApplyScale operator:
    //   This lowering widens integer types to 64-bit an performs the non-fused
    //   operations, specifically multiply, add, and shift. Bit-widening
    //   is used to guarantee higher-order bits are not truncated during the
    //   multiply or add.
    //
    // TODO(suderman): remove the TOSA layering violation and lower to standard/
    // math ops instead.
    tosa::populateTosaRescaleToStandardConversionPatterns(&conversionPatterns);

    if (failed(applyPartialConversion(getOperation(), conversionTarget,
                                      std::move(conversionPatterns)))) {
      getOperation().emitError() << "conversion to the VMVX dialect failed";
      return signalPassFailure();
    }
  }
};

std::unique_ptr<OperationPass<mlir::ModuleOp>> createConversionPass() {
  return std::make_unique<ConversionPass>();
}

static PassRegistration<ConversionPass> pass;

}  // namespace VMVX
}  // namespace IREE
}  // namespace iree_compiler
}  // namespace mlir
