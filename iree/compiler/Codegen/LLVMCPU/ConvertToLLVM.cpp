// Copyright 2020 The IREE Authors
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "iree/compiler/Codegen/PassDetail.h"
#include "iree/compiler/Codegen/Passes.h"
#include "iree/compiler/Codegen/Utils/Utils.h"
#include "iree/compiler/Dialect/HAL/IR/HALDialect.h"
#include "iree/compiler/Dialect/HAL/IR/HALOps.h"
#include "iree/compiler/Dialect/Shape/IR/ShapeDialect.h"
#include "iree/compiler/Dialect/Util/IR/UtilDialect.h"
#include "iree/compiler/Dialect/Util/IR/UtilOps.h"
#include "llvm/ADT/Triple.h"
#include "llvm/Support/raw_ostream.h"
#include "mlir/Analysis/DataLayoutAnalysis.h"
#include "mlir/Conversion/AffineToStandard/AffineToStandard.h"
#include "mlir/Conversion/LLVMCommon/ConversionTarget.h"
#include "mlir/Conversion/LLVMCommon/LoweringOptions.h"
#include "mlir/Conversion/LLVMCommon/Pattern.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Conversion/LinalgToLLVM/LinalgToLLVM.h"
#include "mlir/Conversion/MathToLLVM/MathToLLVM.h"
#include "mlir/Conversion/MemRefToLLVM/MemRefToLLVM.h"
#include "mlir/Conversion/SCFToStandard/SCFToStandard.h"
#include "mlir/Conversion/StandardToLLVM/ConvertStandardToLLVM.h"
#include "mlir/Conversion/StandardToLLVM/ConvertStandardToLLVMPass.h"
#include "mlir/Conversion/TosaToStandard/TosaToStandard.h"
#include "mlir/Conversion/VectorToLLVM/ConvertVectorToLLVM.h"
#include "mlir/Conversion/VectorToSCF/VectorToSCF.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/Math/Transforms/Passes.h"
#include "mlir/Dialect/StandardOps/IR/Ops.h"
#include "mlir/Dialect/StandardOps/Transforms/Passes.h"
#include "mlir/Dialect/Tosa/IR/TosaOps.h"
#include "mlir/Dialect/Vector/VectorOps.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

namespace mlir {
namespace iree_compiler {

namespace {

// NOTE: HALDispatchABI and the associated conversion patterns should live under
// iree/compiler/Dialect/HAL/Target/LLVM/ instead of here as they have nothing
// to do with linalg. If we need to use the patterns in this conversion we can
// expose a populate*Patterns() function to access them without needing them
// defined here.

// Utility for accessing the IREE HAL dispatch function ABI values.
// All accesses should route through this vs directly manipulating LLVM function
// arguments so that we can adjust the ABI over time and support multiple
// versions in the same compiled output.
class HALDispatchABI {
 public:
  // Returns a Type representing iree_hal_vec3_t.
  static Type getVec3Type(MLIRContext *context) {
    auto uint32Type = IntegerType::get(context, 32);
    return LLVM::LLVMArrayType::get(uint32Type, 3);
  }

  // Matches the field order in iree_hal_executable_dispatch_state_v0_t.
  enum class Field {
    workgroup_count = 0,
    workgroup_size = 1,
    push_constant_count = 2,
    push_constants = 3,
    binding_count = 4,
    binding_ptrs = 5,
    binding_lengths = 6,
  };

  // Returns a Type representing iree_hal_executable_dispatch_state_v0_t.
  static LLVM::LLVMStructType getDispatchStateType(
      MLIRContext *context, LLVMTypeConverter *typeConverter) {
    auto structType = LLVM::LLVMStructType::getIdentified(
        context, "iree_hal_executable_dispatch_state_v0_t");
    if (structType.isInitialized()) return structType;

    auto indexType = typeConverter->convertType(IndexType::get(context));
    auto int8Type = IntegerType::get(context, 8);
    auto uint32Type = IntegerType::get(context, 32);
    auto vec3Type = getVec3Type(context);
    SmallVector<Type, 4> fieldTypes;

    // iree_hal_vec3_t workgroup_count;
    // iree_hal_vec3_t workgroup_size;
    fieldTypes.push_back(vec3Type);
    fieldTypes.push_back(vec3Type);

    // size_t push_constant_count;
    // const uint32_t * push_constants;
    fieldTypes.push_back(indexType);
    fieldTypes.push_back(LLVM::LLVMPointerType::get(uint32Type));

    // size_t binding_count;
    // void *const * binding_ptrs;
    // const size_t * binding_lengths;
    fieldTypes.push_back(indexType);
    fieldTypes.push_back(
        LLVM::LLVMPointerType::get(LLVM::LLVMPointerType::get(int8Type)));
    fieldTypes.push_back(LLVM::LLVMPointerType::get(indexType));

    // TODO(benvanik): import_thunk/import and a callImport() helper function.

    LogicalResult bodySet = structType.setBody(fieldTypes, /*isPacked=*/false);
    assert(succeeded(bodySet) &&
           "could not set the body of an identified struct");
    (void)bodySet;

    return structType;
  }

  // Returns the types of the LLVM function inputs for the ABI.
  // This matches the signature of `iree_hal_executable_dispatch_v0_t` in
  // `iree/hal/local/executable_library.h`.
  static SmallVector<Type, 5> getInputTypes(MLIRContext *context,
                                            LLVMTypeConverter *typeConverter) {
    return SmallVector<Type, 5>{
        // const iree_hal_executable_dispatch_state_v0_t* IREE_RESTRICT
        //   dispatch_state
        LLVM::LLVMPointerType::get(
            getDispatchStateType(context, typeConverter)),
        // const iree_hal_vec3_t* IREE_RESTRICT workgroup_id
        LLVM::LLVMPointerType::get(getVec3Type(context)),
        // void* IREE_RESTRICT local_memory
        LLVM::LLVMPointerType::get(IntegerType::get(context, 8)),
    };
  }

  explicit HALDispatchABI(LLVM::LLVMFuncOp &funcOp,
                          LLVMTypeConverter *typeConverter)
      : funcOp(funcOp),
        typeConverter(typeConverter),
        dispatchStateType(
            getDispatchStateType(funcOp.getContext(), typeConverter)) {}

  // Loads the workgroup_id[dim] value (XYZ) and casts it to |resultType|.
  Value loadWorkgroupID(Location loc, int32_t dim, Type resultType,
                        OpBuilder &builder) {
    auto workgroupIdPtrValue = funcOp.getArgument(1);
    auto workgroupIdValue =
        builder.createOrFold<LLVM::LoadOp>(loc, workgroupIdPtrValue);
    auto dimValue = builder.createOrFold<LLVM::ExtractValueOp>(
        loc, builder.getIntegerType(32), workgroupIdValue,
        builder.getI64ArrayAttr({dim}));
    return castValueToType(loc, dimValue, resultType, builder);
  }

  // Loads the workgroup_count[dim] value (XYZ) and casts it to |resultType|.
  Value loadWorkgroupCount(Location loc, int32_t dim, Type resultType,
                           OpBuilder &builder) {
    auto workgroupCountValue =
        loadFieldValue(loc, Field::workgroup_count, builder);
    auto dimValue = builder.createOrFold<LLVM::ExtractValueOp>(
        loc, builder.getIntegerType(32), workgroupCountValue,
        builder.getI64ArrayAttr(dim));
    return castValueToType(loc, dimValue, resultType, builder);
  }

  // Loads the workgroup_size[dim] value (XYZ) and casts it to |resultType|.
  Value loadWorkgroupSize(Location loc, int32_t dim, Type resultType,
                          OpBuilder &builder) {
    auto workgroupSizeValue =
        loadFieldValue(loc, Field::workgroup_size, builder);
    auto dimValue = builder.createOrFold<LLVM::ExtractValueOp>(
        loc, builder.getIntegerType(32), workgroupSizeValue,
        builder.getI64ArrayAttr(dim));
    return castValueToType(loc, dimValue, resultType, builder);
  }

  // Loads the base pointer of the workgroup local memory.
  // Note that this may be NULL if no workgroup local memory was requested.
  Value loadWorkgroupLocalMemoryPtr(Location loc, OpBuilder &builder) {
    return funcOp.getArgument(2);
  }

  // Returns the total push constant count as an index-converted type.
  Value loadPushConstantCount(Location loc, OpBuilder &builder) {
    auto value = loadFieldValue(loc, Field::push_constant_count, builder);
    return castValueToType(loc, value,
                           typeConverter->convertType(builder.getIndexType()),
                           builder);
  }

  // Loads a push constant at |offset| and casts it to |resultType|.
  Value loadPushConstant(Location loc, int64_t offset, Type resultType,
                         OpBuilder &builder) {
    auto constantsPtrValue =
        loadFieldValue(loc, Field::push_constants, builder);
    auto offsetValue = getIndexValue(loc, offset, builder);
    Value constantPtrValue = builder.create<LLVM::GEPOp>(
        loc, constantsPtrValue.getType(), constantsPtrValue, offsetValue);
    Value constantValue = builder.create<LLVM::LoadOp>(loc, constantPtrValue);
    return castValueToType(loc, constantValue, resultType, builder);
  }

  // Returns the total binding count as an index-converted type.
  Value loadBindingCount(Location loc, OpBuilder &builder) {
    auto value = loadFieldValue(loc, Field::binding_count, builder);
    return castValueToType(loc, value,
                           typeConverter->convertType(builder.getIndexType()),
                           builder);
  }

  // Loads the base pointer of the binding |ordinal| as an `i8**`.
  // Equivalent to:
  //   int8_t** base_ptr = &state->binding_ptrs[ordinal];
  Value loadBindingPtr(Location loc, int64_t ordinal, OpBuilder &builder) {
    auto ptrsPtrValue = loadFieldValue(loc, Field::binding_ptrs, builder);
    auto ordinalValue = getIndexValue(loc, ordinal, builder);
    auto elementPtrValue = builder.createOrFold<LLVM::GEPOp>(
        loc, ptrsPtrValue.getType(), ptrsPtrValue, ordinalValue);
    return builder.createOrFold<LLVM::LoadOp>(loc, elementPtrValue);
  }

  // Loads the byte length of the binding |ordinal| as an index-converted type.
  Value loadBindingLength(Location loc, int64_t ordinal, OpBuilder &builder) {
    auto lengthsPtrValue = loadFieldValue(loc, Field::binding_lengths, builder);
    auto ordinalValue = getIndexValue(loc, ordinal, builder);
    auto elementPtrValue = builder.createOrFold<LLVM::GEPOp>(
        loc, lengthsPtrValue.getType(), lengthsPtrValue, ordinalValue);
    return builder.createOrFold<LLVM::LoadOp>(loc, elementPtrValue);
  }

  // Loads a binding as a constructed MemRefDescriptor.
  // |baseOffset| can optionally adjust the base byte offset of the buffer.
  MemRefDescriptor loadBinding(Location loc, int64_t ordinal,
                               Value baseOffsetValue, MemRefType memRefType,
                               ValueRange dynamicDims, OpBuilder &builder) {
    // Load the base buffer pointer in the appropriate type (f32*, etc).
    Value basePtrValue = loadBindingPtr(loc, ordinal, builder);

    // Adjust by baseOffset (if needed).
    if (baseOffsetValue) {
      basePtrValue = builder.createOrFold<LLVM::GEPOp>(
          loc, basePtrValue.getType(), basePtrValue, baseOffsetValue);
    }

    // NOTE: if we wanted to check the range was in bounds here would be the
    // place to do it.

    // Cast to the desired memref element type.
    auto elementType = typeConverter->convertType(memRefType.getElementType());
    Value typedPtrValue = builder.createOrFold<LLVM::BitcastOp>(
        loc,
        LLVM::LLVMPointerType::get(elementType,
                                   memRefType.getMemorySpaceAsInt()),
        basePtrValue);

    // Construct the MemRefDescriptor type based on the information we have.
    // NOTE: we could use the binding length to clamp this/check that the
    // requested range is valid.
    if (memRefType.hasStaticShape()) {
      return MemRefDescriptor::fromStaticShape(builder, loc, *typeConverter,
                                               memRefType, typedPtrValue);
    } else {
      assert(memRefType.getNumDynamicDims() == dynamicDims.size());
      int64_t rank = memRefType.getRank();

      // Build MemRef descriptor for this interface binding.
      auto desc = MemRefDescriptor::undef(
          builder, loc, typeConverter->convertType(memRefType));
      desc.setAllocatedPtr(builder, loc, typedPtrValue);
      desc.setAlignedPtr(builder, loc, typedPtrValue);
      desc.setConstantOffset(builder, loc, 0);

      // Update memref descriptor shape. Dynamic dimensions can be mixed with
      // static dimensions, like [128, ?, 128].
      int dynamicDimIndex = 0;
      for (int i = 0; i < rank; ++i) {
        if (memRefType.isDynamicDim(i)) {
          desc.setSize(builder, loc, i, dynamicDims[dynamicDimIndex++]);
        } else {
          desc.setConstantSize(builder, loc, i, memRefType.getDimSize(i));
        }
      }

      // Compute and update strides. Assume that MemRefs are row-major, that is,
      // following index linearization:
      //   x[i, j, k] = i * x.dim[1] * x.dim[2] + j * x.dim[2] + k
      desc.setConstantStride(builder, loc, rank - 1, 1);
      for (int i = rank - 2; i >= 0; --i) {
        auto stride = desc.stride(builder, loc, i + 1);
        auto dim = desc.size(builder, loc, i + 1);
        Value strideVal = builder.create<LLVM::MulOp>(loc, stride, dim);
        desc.setStride(builder, loc, i, strideVal);
      }

      return desc;
    }
  }

 private:
  Value loadFieldValue(Location loc, Field field, OpBuilder &builder) {
    auto statePtrValue = funcOp.getArgument(0);
    auto stateValue = builder.createOrFold<LLVM::LoadOp>(loc, statePtrValue);
    auto fieldType = dispatchStateType.getBody()[(int)field];
    return builder.createOrFold<LLVM::ExtractValueOp>(
        loc, fieldType, stateValue, builder.getI64ArrayAttr((int)field));
  }

  Value getIndexValue(Location loc, int64_t value, OpBuilder &builder) {
    SmallVector<Value> folded;
    builder.createOrFold<UnrealizedConversionCastOp>(
        folded, loc, typeConverter->convertType(builder.getIndexType()),
        builder.createOrFold<ConstantIndexOp>(loc, value));
    return folded.front();
  }

  Value castValueToType(Location loc, Value value, Type resultType,
                        OpBuilder &builder) {
    // NOTE: we should handle more cases here (and proper sign extension).
    if (value.getType() == resultType) return value;
    return builder.createOrFold<LLVM::ZExtOp>(loc, resultType, value);
  }

  LLVM::LLVMFuncOp funcOp;
  LLVMTypeConverter *typeConverter;
  LLVM::LLVMStructType dispatchStateType;
};

/// Converts Standard MLIR FuncOps to LLVMFuncOps matching the IREE HAL ABI.
/// This is an IREE-specific conversion that assumes the input function is
/// `() -> ()` and that hal.interface.* ops are used to access all state.
///
/// Source function:
///
/// ```
/// func @foo() {
///   %0 = hal.interface.binding.subspan ...
/// }
/// ```
///
/// into:
///
/// ```
/// llvm.func foo(%state: !llvm.ptr<!...>,
///               %workgroup_id : !llvm.ptr<!llvm.array<i32, 3>>) {
///   %0 = <GEP/loads to access binding in %state>
/// }
/// ```
///
/// See `iree/hal/local/executable_library.h` for more information.
///
/// NOTE: we bump the benefit of the pattern to 100 to pick this pattern instead
/// of a competing pattern inserted by `populateStdToLLVMConversionPatterns`.
class ConvertHALEntryPointFuncOp : public ConvertToLLVMPattern {
 public:
  explicit ConvertHALEntryPointFuncOp(MLIRContext *context,
                                      LLVMTypeConverter &converter)
      : ConvertToLLVMPattern(mlir::FuncOp::getOperationName(), context,
                             converter, 100) {}

  LogicalResult matchAndRewrite(
      Operation *op, ArrayRef<Value> operands,
      ConversionPatternRewriter &rewriter) const override {
    auto stdFuncOp = cast<FuncOp>(op);
    if (!stdFuncOp.isPublic()) return failure();
    FunctionType fnType = stdFuncOp.getType();
    if (fnType.getNumInputs() != 0 || fnType.getNumResults() != 0) {
      op->emitWarning() << "public functions on executables must be () -> ()";
      return failure();
    }

    // Convert the function signature to take the HAL ABI LLVM pointers.
    TypeConverter::SignatureConversion signatureConverter(/*numOrigInputs=*/0);
    MLIRContext *context = rewriter.getContext();
    auto abiInputTypes =
        HALDispatchABI::getInputTypes(context, getTypeConverter());
    signatureConverter.addInputs(abiInputTypes);

    // Copy all attributes onto the LLVM function except the ones handled by
    // MLIR implicitly.
    SmallVector<NamedAttribute, 4> funcAttrs;
    for (auto attr : stdFuncOp->getAttrs()) {
      if (attr.first == SymbolTable::getSymbolAttrName() ||
          attr.first == mlir::function_like_impl::getTypeAttrName()) {
        continue;
      }
      funcAttrs.push_back(attr);
    }

    // Clone the function as an LLVMFuncOp and convert all interior types.
    auto llvmFuncType = LLVM::LLVMFunctionType::get(
        IntegerType::get(rewriter.getContext(), 32), abiInputTypes);
    auto llvmFuncOp = rewriter.create<LLVM::LLVMFuncOp>(
        stdFuncOp.getLoc(), stdFuncOp.getName(), llvmFuncType,
        LLVM::Linkage::Internal, /*dso_local=*/false, funcAttrs);
    rewriter.inlineRegionBefore(stdFuncOp.getBody(), llvmFuncOp.getBody(),
                                llvmFuncOp.end());
    if (failed(rewriter.convertRegionTypes(
            &llvmFuncOp.getBody(), *typeConverter, &signatureConverter))) {
      return failure();
    }

    // Add default zero return value.
    // TODO(ataei): do something meaningful with the return value; non-zero will
    // have the runtime bail out with an error.
    for (auto returnOp :
         llvm::make_early_inc_range(llvmFuncOp.getOps<mlir::ReturnOp>())) {
      rewriter.setInsertionPoint(returnOp);
      auto returnValue =
          rewriter.createOrFold<mlir::ConstantIntOp>(returnOp.getLoc(), 0, 32);
      rewriter.replaceOpWithNewOp<mlir::ReturnOp>(returnOp, returnValue);
    }

    rewriter.eraseOp(stdFuncOp);
    return success();
  }
};

/// Rewrites hal.interface.workgroup.id to ops loading from the ABI structs.
///
/// The parent LLVMFuncOp must be compatible with HALDispatchABI.
class ConvertHALInterfaceWorkgroupIDOp : public ConvertToLLVMPattern {
 public:
  explicit ConvertHALInterfaceWorkgroupIDOp(MLIRContext *context,
                                            LLVMTypeConverter &converter)
      : ConvertToLLVMPattern(
            IREE::HAL::InterfaceWorkgroupIDOp::getOperationName(), context,
            converter) {}

  LogicalResult matchAndRewrite(
      Operation *op, ArrayRef<Value> operands,
      ConversionPatternRewriter &rewriter) const override {
    auto llvmFuncOp = op->getParentOfType<LLVM::LLVMFuncOp>();
    if (!llvmFuncOp) return failure();
    HALDispatchABI abi(llvmFuncOp, getTypeConverter());
    int32_t dim = (int32_t)cast<IREE::HAL::InterfaceWorkgroupIDOp>(op)
                      .dimension()
                      .getZExtValue();
    auto resultType = typeConverter->convertType(op->getResult(0).getType());
    rewriter.replaceOp(
        op, abi.loadWorkgroupID(op->getLoc(), dim, resultType, rewriter));
    return success();
  }
};

/// Rewrites hal.interface.workgroup.size to ops loading from the ABI structs.
///
/// The parent LLVMFuncOp must be compatible with HALDispatchABI.
class ConvertHALInterfaceWorkgroupSizeOp : public ConvertToLLVMPattern {
 public:
  explicit ConvertHALInterfaceWorkgroupSizeOp(MLIRContext *context,
                                              LLVMTypeConverter &converter)
      : ConvertToLLVMPattern(
            IREE::HAL::InterfaceWorkgroupSizeOp::getOperationName(), context,
            converter) {}

  LogicalResult matchAndRewrite(
      Operation *op, ArrayRef<Value> operands,
      ConversionPatternRewriter &rewriter) const override {
    auto llvmFuncOp = op->getParentOfType<LLVM::LLVMFuncOp>();
    if (!llvmFuncOp) return failure();
    HALDispatchABI abi(llvmFuncOp, getTypeConverter());
    int32_t dim = (int32_t)cast<IREE::HAL::InterfaceWorkgroupSizeOp>(op)
                      .dimension()
                      .getZExtValue();
    auto resultType = typeConverter->convertType(op->getResult(0).getType());
    rewriter.replaceOp(
        op, abi.loadWorkgroupSize(op->getLoc(), dim, resultType, rewriter));
    return success();
  }
};

/// Rewrites hal.interface.workgroup.count to ops loading from the ABI structs.
///
/// The parent LLVMFuncOp must be compatible with HALDispatchABI.
class ConvertHALInterfaceWorkgroupCountOp : public ConvertToLLVMPattern {
 public:
  explicit ConvertHALInterfaceWorkgroupCountOp(MLIRContext *context,
                                               LLVMTypeConverter &converter)
      : ConvertToLLVMPattern(
            IREE::HAL::InterfaceWorkgroupCountOp::getOperationName(), context,
            converter) {}

  LogicalResult matchAndRewrite(
      Operation *op, ArrayRef<Value> operands,
      ConversionPatternRewriter &rewriter) const override {
    auto llvmFuncOp = op->getParentOfType<LLVM::LLVMFuncOp>();
    if (!llvmFuncOp) return failure();
    HALDispatchABI abi(llvmFuncOp, getTypeConverter());
    int32_t dim = (int32_t)cast<IREE::HAL::InterfaceWorkgroupCountOp>(op)
                      .dimension()
                      .getZExtValue();
    auto resultType = typeConverter->convertType(op->getResult(0).getType());
    rewriter.replaceOp(
        op, abi.loadWorkgroupCount(op->getLoc(), dim, resultType, rewriter));
    return success();
  }
};

/// Rewrites hal.interface.load.constant to ops loading from the ABI structs.
///
/// The parent LLVMFuncOp must be compatible with HALDispatchABI.
class ConvertHALInterfaceLoadConstant : public ConvertToLLVMPattern {
 public:
  explicit ConvertHALInterfaceLoadConstant(MLIRContext *context,
                                           LLVMTypeConverter &converter)
      : ConvertToLLVMPattern(
            IREE::HAL::InterfaceLoadConstantOp::getOperationName(), context,
            converter) {}

  LogicalResult matchAndRewrite(
      Operation *op, ArrayRef<Value> operands,
      ConversionPatternRewriter &rewriter) const override {
    auto llvmFuncOp = op->getParentOfType<LLVM::LLVMFuncOp>();
    if (!llvmFuncOp) return failure();
    HALDispatchABI abi(llvmFuncOp, getTypeConverter());
    auto loadConstantOp = cast<IREE::HAL::InterfaceLoadConstantOp>(op);
    int64_t offset = loadConstantOp.offset().getZExtValue();
    auto resultType = typeConverter->convertType(op->getResult(0).getType());
    rewriter.replaceOp(
        op, abi.loadPushConstant(op->getLoc(), offset, resultType, rewriter));
    return success();
  }
};

/// Rewrites hal.interface.binding.subspan to ops loading from the ABI structs.
///
/// The parent LLVMFuncOp must be compatible with HALDispatchABI.
class ConvertHALInterfaceBindingSubspanOp : public ConvertToLLVMPattern {
 public:
  explicit ConvertHALInterfaceBindingSubspanOp(MLIRContext *context,
                                               LLVMTypeConverter &converter)
      : ConvertToLLVMPattern(
            IREE::HAL::InterfaceBindingSubspanOp::getOperationName(), context,
            converter) {}

  LogicalResult matchAndRewrite(
      Operation *op, ArrayRef<Value> operands,
      ConversionPatternRewriter &rewriter) const override {
    auto llvmFuncOp = op->getParentOfType<LLVM::LLVMFuncOp>();
    if (!llvmFuncOp) return failure();
    HALDispatchABI abi(llvmFuncOp, getTypeConverter());
    auto interfaceBindingOp =
        cast<IREE::HAL::InterfaceBindingSubspanOp>(op).queryBindingOp();
    IREE::HAL::InterfaceBindingSubspanOpAdaptor newOperands(
        operands, op->getAttrDictionary());
    MemRefType memRefType = op->getResult(0).getType().cast<MemRefType>();
    auto memRefDesc = abi.loadBinding(
        op->getLoc(), interfaceBindingOp.binding().getZExtValue(),
        newOperands.byte_offset(), memRefType, newOperands.dynamic_dims(),
        rewriter);
    rewriter.replaceOp(op, {memRefDesc});
    return success();
  }
};

class RemoveHALInterfaceOpPattern : public ConvertToLLVMPattern {
 public:
  explicit RemoveHALInterfaceOpPattern(MLIRContext *context,
                                       LLVMTypeConverter &typeconverter)
      : ConvertToLLVMPattern(IREE::HAL::InterfaceOp::getOperationName(),
                             context, typeconverter) {}
  LogicalResult matchAndRewrite(
      Operation *op, ArrayRef<Value> operands,
      ConversionPatternRewriter &rewriter) const override {
    rewriter.eraseOp(op);
    return success();
  }
};

class ConvertToLLVMPass : public ConvertToLLVMBase<ConvertToLLVMPass> {
 public:
  ConvertToLLVMPass() = default;
  ConvertToLLVMPass(const ConvertToLLVMPass &pass) {}
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<LLVM::LLVMDialect>();
  }

  void runOnOperation() override;

 private:
  Option<std::string> targetTriple{
      *this, "target-triple", llvm::cl::desc("Code generation target triple."),
      llvm::cl::init("")};
  Option<std::string> targetDataLayout{
      *this, "target-data-layout",
      llvm::cl::desc("Code generation target data layout."),
      llvm::cl::init("")};
};

}  // namespace

static std::string getStringAttrFromTargetAttr(ModuleOp module,
                                               StringRef attrName) {
  if (auto variantOp =
          module->getParentOfType<IREE::HAL::ExecutableVariantOp>()) {
    IREE::HAL::ExecutableTargetAttr targetAttr = variantOp.target();
    if (auto config = targetAttr.getConfiguration()) {
      if (auto attr = config.getAs<StringAttr>(attrName)) {
        return attr.getValue().str();
      }
    }
  }
  return "";
}

void ConvertToLLVMPass::runOnOperation() {
  auto module = getOperation();
  std::string dataLayoutStr = targetDataLayout.getValue();
  if (targetDataLayout.empty()) {
    dataLayoutStr = getStringAttrFromTargetAttr(module, "data_layout");
  }
  std::string targetTripleStr = targetTriple.getValue();
  if (targetTripleStr.empty()) {
    targetTripleStr = getStringAttrFromTargetAttr(module, "target_triple");
  }

  // Add required attributes to the module so that the lowering knows how to
  // handle structs and data layouts.
  module->setAttr(LLVM::LLVMDialect::getTargetTripleAttrName(),
                  StringAttr::get(module->getContext(), targetTripleStr));
  module->setAttr(LLVM::LLVMDialect::getDataLayoutAttrName(),
                  StringAttr::get(module->getContext(), dataLayoutStr));

  // Run Vector -> Vector transformations ahead of conversion to LLVM.
  {
    OwningRewritePatternList patterns(&getContext());
    vector::populateVectorToVectorCanonicalizationPatterns(patterns);
    vector::populateVectorContractLoweringPatterns(patterns);
    vector::populateVectorTransposeLoweringPatterns(patterns);
    (void)applyPatternsAndFoldGreedily(getOperation(), std::move(patterns));
  }
  {
    OwningRewritePatternList vectorToLoopsPatterns(&getContext());
    populateVectorToSCFConversionPatterns(
        vectorToLoopsPatterns, VectorTransferToSCFOptions().setUnroll(true));
    (void)applyPatternsAndFoldGreedily(getOperation(),
                                       std::move(vectorToLoopsPatterns));
  }

  // math dialect elementry functions -> polynomial form.
  {
    OwningRewritePatternList mathPatterns(&getContext());
    populateMathPolynomialApproximationPatterns(mathPatterns);
    (void)applyPatternsAndFoldGreedily(getOperation(), std::move(mathPatterns));
  }

  const auto &dataLayoutAnalysis = getAnalysis<DataLayoutAnalysis>();
  LowerToLLVMOptions options(&getContext(),
                             dataLayoutAnalysis.getAtOrAbove(module));
  options.dataLayout = llvm::DataLayout(dataLayoutStr);
  options.overrideIndexBitwidth(options.dataLayout.getPointerSizeInBits());
  LLVMTypeConverter converter(&getContext(), options, &dataLayoutAnalysis);

  OwningRewritePatternList patterns(&getContext());

  // Use the default 64-bit lowering for TOSA's ApplyScale operator:
  //   This lowering widens integer types to 64-bit an performs the non-fused
  //   operations, specifically multiply, add, and shift. Bit-widening
  //   is used to guarantee higher-order bits are not truncated during the
  //   multiply or add.
  //
  // TODO(bjacob): Use a lowering that uses specific ARM/X86 intrinsics.
  tosa::populateTosaRescaleToStandardConversionPatterns(&patterns);

  populateAffineToStdConversionPatterns(patterns);
  populateLoopToStdConversionPatterns(patterns);
  populateExpandTanhPattern(patterns);

  populateMathToLLVMConversionPatterns(converter, patterns);
  populateMemRefToLLVMConversionPatterns(converter, patterns);
  populateStdToLLVMConversionPatterns(converter, patterns);
  populateVectorToSCFConversionPatterns(patterns);
  populateVectorToLLVMMatrixConversionPatterns(converter, patterns);
  populateVectorToLLVMConversionPatterns(converter, patterns);
  populateLinalgToLLVMConversionPatterns(converter, patterns);

  // clang-format off
  patterns.insert<
    ConvertHALEntryPointFuncOp,
    ConvertHALInterfaceWorkgroupIDOp,
    ConvertHALInterfaceWorkgroupSizeOp,
    ConvertHALInterfaceWorkgroupCountOp,
    ConvertHALInterfaceLoadConstant,
    ConvertHALInterfaceBindingSubspanOp,
    RemoveHALInterfaceOpPattern
  >(&getContext(), converter);
  // clang-format on

  LLVMConversionTarget target(getContext());
  // IREE::HAL::InterfaceOp will be removed after successful conversion of the
  // rest of the IR.
  target.addLegalOp<ModuleOp, IREE::HAL::InterfaceOp,
                    IREE::HAL::InterfaceBindingOp, IREE::HAL::InterfaceEndOp>();
  target.addIllegalDialect<ShapeDialect, StandardOpsDialect,
                           IREE::Util::UtilDialect, IREE::HAL::HALDialect,
                           math::MathDialect, tosa::TosaDialect>();
  target.addIllegalOp<UnrealizedConversionCastOp>();

  // Don't apply patterns to private function (e.g num_workgroups func).
  target.addDynamicallyLegalOp<FuncOp>([&](FuncOp funcOp) {
    if (isEntryPoint(funcOp)) return false;
    return true;
  });
  target.addDynamicallyLegalDialect<ShapeDialect, StandardOpsDialect,
                                    IREE::Util::UtilDialect,
                                    IREE::HAL::HALDialect, math::MathDialect>(
      [&](Operation *op) {
        auto funcParent = op->getParentOfType<FuncOp>();
        if (!funcParent) return false;
        if (isEntryPoint(funcParent)) return false;
        return true;
      });

  if (failed(applyPartialConversion(module, target, std::move(patterns)))) {
    signalPassFailure();
    return;
  }

  // Once we're done with conversion, remove InterfaceOp.
  module.walk([](IREE::HAL::InterfaceOp op) { op.erase(); });

  // Post conversion patterns.
  {
    OwningRewritePatternList postPatterns(&getContext());
    // TODO(ravishankarm): Move this to a separate pass.
    llvm::Triple triple(targetTripleStr);
    if (triple.isWasm()) {
      populateUnfusedFMAOpsPassPatterns(&getContext(), postPatterns);
      (void)applyPatternsAndFoldGreedily(module, std::move(postPatterns));
    }
  }
}

std::unique_ptr<OperationPass<ModuleOp>> createConvertToLLVMPass() {
  return std::make_unique<ConvertToLLVMPass>();
}

}  // namespace iree_compiler
}  // namespace mlir
