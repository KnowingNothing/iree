# Copyright 2019 The IREE Authors
#
# Licensed under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

load("//build_tools/bazel:iree_tablegen_doc.bzl", "iree_tablegen_doc")
load("@llvm-project//mlir:tblgen.bzl", "gentbl_cc_library", "td_library")
load("//build_tools/bazel:enforce_glob.bzl", "enforce_glob")

package(
    default_visibility = ["//visibility:public"],
    features = ["layering_check"],
    licenses = ["notice"],  # Apache 2.0
)

exports_files([
    "HALBase.td",
    "HALDialect.td",
])

td_library(
    name = "td_files",
    srcs = enforce_glob(
        [
            "HALBase.td",
            "HALDialect.td",
            "HALInterfaces.td",
            "HALOps.td",
            "LoweringConfig.td",
        ],
        include = ["*.td"],
    ),
    deps = [
        "//iree/compiler/Dialect/Shape/IR:td_files",
        "//iree/compiler/Dialect/Util/IR:td_files",
        "@llvm-project//mlir:OpBaseTdFiles",
        "@llvm-project//mlir:StdOpsTdFiles",
        "@llvm-project//mlir:ViewLikeInterfaceTdFiles",
    ],
)

cc_library(
    name = "IR",
    srcs = [
        "HALOpFolders.cpp",
        "HALOps.cpp",
        "HALTypes.cpp",
        "LoweringConfig.cpp",
    ],
    hdrs = [
        "HALDialect.h",
        "HALOps.h",
        "HALTraits.h",
        "HALTypes.h",
        "LoweringConfig.h",
    ],
    textual_hdrs = [
        "HALAttrs.cpp.inc",
        "HALAttrs.h.inc",
        "HALAttrInterfaces.cpp.inc",
        "HALAttrInterfaces.h.inc",
        "HALEnums.cpp.inc",
        "HALEnums.h.inc",
        "HALOpInterfaces.cpp.inc",
        "HALOpInterfaces.h.inc",
        "HALOps.cpp.inc",
        "HALOps.h.inc",
        "HALStructs.cpp.inc",
        "HALStructs.h.inc",
        "HALTypeInterfaces.cpp.inc",
        "HALTypeInterfaces.h.inc",
        "LoweringConfig.h.inc",
        "LoweringConfig.cpp.inc",
        "LoweringConfigEnums.h.inc",
        "LoweringConfigEnums.cpp.inc",
    ],
    deps = [
        ":HALInterfacesGen",
        ":HALOpsGen",
        ":HALStructsGen",
        ":HALTypesGen",
        ":LoweringConfigEnumGen",
        ":LoweringConfigGen",
        "//iree/compiler/Dialect/Shape/IR",
        "//iree/compiler/Dialect/Util/IR",
        "@llvm-project//llvm:Support",
        "@llvm-project//mlir:IR",
        "@llvm-project//mlir:MemRefDialect",
        "@llvm-project//mlir:Parser",
        "@llvm-project//mlir:SideEffects",
        "@llvm-project//mlir:StandardOps",
        "@llvm-project//mlir:Support",
        "@llvm-project//mlir:TransformUtils",
        "@llvm-project//mlir:ViewLikeInterface",
    ],
)

cc_library(
    name = "HALDialect",
    srcs = ["HALDialect.cpp"],
    hdrs = ["HALDialect.h"],
    deps = [
        ":IR",
        "//iree/compiler/Dialect/HAL:hal_imports",
        "//iree/compiler/Dialect/HAL/Conversion/HALToHAL",
        "//iree/compiler/Dialect/HAL/Conversion/HALToVM",
        "//iree/compiler/Dialect/Shape/IR",
        "//iree/compiler/Dialect/Util/IR",
        "//iree/compiler/Dialect/VM/Conversion",
        "@llvm-project//llvm:Support",
        "@llvm-project//mlir:IR",
        "@llvm-project//mlir:MemRefDialect",
        "@llvm-project//mlir:Parser",
        "@llvm-project//mlir:StandardOps",
        "@llvm-project//mlir:TransformUtils",
    ],
)

gentbl_cc_library(
    name = "HALInterfacesGen",
    tbl_outs = [
        (
            ["-gen-attr-interface-decls"],
            "HALAttrInterfaces.h.inc",
        ),
        (
            ["-gen-attr-interface-defs"],
            "HALAttrInterfaces.cpp.inc",
        ),
        (
            ["-gen-op-interface-decls"],
            "HALOpInterfaces.h.inc",
        ),
        (
            ["-gen-op-interface-defs"],
            "HALOpInterfaces.cpp.inc",
        ),
        (
            ["-gen-type-interface-decls"],
            "HALTypeInterfaces.h.inc",
        ),
        (
            ["-gen-type-interface-defs"],
            "HALTypeInterfaces.cpp.inc",
        ),
    ],
    tblgen = "@llvm-project//mlir:mlir-tblgen",
    td_file = "HALInterfaces.td",
    deps = [":td_files"],
)

gentbl_cc_library(
    name = "HALOpsGen",
    tbl_outs = [
        (
            ["-gen-op-decls"],
            "HALOps.h.inc",
        ),
        (
            ["-gen-op-defs"],
            "HALOps.cpp.inc",
        ),
    ],
    tblgen = "@llvm-project//mlir:mlir-tblgen",
    td_file = "HALOps.td",
    deps = [":td_files"],
)

gentbl_cc_library(
    name = "HALStructsGen",
    tbl_outs = [
        (
            ["-gen-iree-struct-attr-decls"],
            "HALStructs.h.inc",
        ),
        (
            ["-gen-iree-struct-attr-defs"],
            "HALStructs.cpp.inc",
        ),
    ],
    tblgen = "//iree/tools:iree-tblgen",
    td_file = "HALBase.td",
    deps = [":td_files"],
)

gentbl_cc_library(
    name = "HALTypesGen",
    tbl_outs = [
        (
            ["-gen-attrdef-decls"],
            "HALAttrs.h.inc",
        ),
        (
            ["-gen-attrdef-defs"],
            "HALAttrs.cpp.inc",
        ),
        (
            ["-gen-enum-decls"],
            "HALEnums.h.inc",
        ),
        (
            ["-gen-enum-defs"],
            "HALEnums.cpp.inc",
        ),
    ],
    tblgen = "@llvm-project//mlir:mlir-tblgen",
    td_file = "HALBase.td",
    deps = [":td_files"],
)

iree_tablegen_doc(
    name = "HALDialectDocGen",
    tbl_outs = [
        (
            ["-gen-dialect-doc"],
            "HALDialect.md",
        ),
    ],
    tblgen = "@llvm-project//mlir:mlir-tblgen",
    td_file = "HALOps.td",
    deps = [":td_files"],
)

gentbl_cc_library(
    name = "LoweringConfigGen",
    tbl_outs = [
        (
            ["-gen-struct-attr-decls"],
            "LoweringConfig.h.inc",
        ),
        (
            ["-gen-struct-attr-defs"],
            "LoweringConfig.cpp.inc",
        ),
    ],
    tblgen = "@llvm-project//mlir:mlir-tblgen",
    td_file = "LoweringConfig.td",
    deps = [":td_files"],
)

gentbl_cc_library(
    name = "LoweringConfigEnumGen",
    tbl_outs = [
        (
            ["-gen-enum-decls"],
            "LoweringConfigEnums.h.inc",
        ),
        (
            ["-gen-enum-defs"],
            "LoweringConfigEnums.cpp.inc",
        ),
    ],
    tblgen = "@llvm-project//mlir:mlir-tblgen",
    td_file = "LoweringConfig.td",
    deps = [":td_files"],
)
