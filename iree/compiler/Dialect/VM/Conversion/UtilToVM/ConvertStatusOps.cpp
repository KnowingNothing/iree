// Copyright 2020 The IREE Authors
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "iree/compiler/Dialect/Util/IR/UtilOps.h"
#include "iree/compiler/Dialect/VM/IR/VMOps.h"
#include "mlir/Transforms/DialectConversion.h"

namespace mlir {
namespace iree_compiler {

class StatusCheckOkOpConversion
    : public OpConversionPattern<IREE::Util::StatusCheckOkOp> {
 public:
  StatusCheckOkOpConversion(MLIRContext *context, TypeConverter &typeConverter)
      : OpConversionPattern(context) {}

  LogicalResult matchAndRewrite(
      IREE::Util::StatusCheckOkOp op, llvm::ArrayRef<Value> newOperands,
      ConversionPatternRewriter &rewriter) const override {
    IREE::Util::StatusCheckOkOp::Adaptor operands(newOperands);
    // If status value is non-zero, fail.
    rewriter.replaceOpWithNewOp<IREE::VM::CondFailOp>(
        op, operands.status(), op.message().getValueOr(""));
    return success();
  }
};

void populateUtilStatusToVMPatterns(MLIRContext *context,
                                    ConversionTarget &conversionTarget,
                                    TypeConverter &typeConverter,
                                    OwningRewritePatternList &patterns) {
  conversionTarget.addIllegalOp<IREE::Util::StatusCheckOkOp>();
  patterns.insert<StatusCheckOkOpConversion>(context, typeConverter);
}

}  // namespace iree_compiler
}  // namespace mlir
