# Copyright 2020 The IREE Authors
#
# Licensed under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

package(
    default_visibility = ["//visibility:public"],
    features = ["layering_check"],
    licenses = ["notice"],  # Apache 2.0
)

cc_library(
    name = "LinkerTools_internal",
    srcs = [
        "AndroidLinkerTool.cpp",
        "EmbeddedLinkerTool.cpp",
        "LinkerTools.cpp",
        "RiscvLinkerTool.cpp",
        "UnixLinkerTool.cpp",
        "WasmLinkerTool.cpp",
        "WindowsLinkerTool.cpp",
    ],
    deps = [
        "//iree/compiler/Dialect/HAL/Target/LLVM:LinkerTool_hdrs",
        "@llvm-project//llvm:Core",
        "@llvm-project//llvm:Support",
        "@llvm-project//mlir:Support",
    ],
)
