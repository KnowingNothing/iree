# Copyright 2019 The IREE Authors
#
# Licensed under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# ***THIS FILE DOES NOT BUILD WITH BAZEL***
#
# It is open sourced to enable Bazel->CMake conversion to maintain test coverage
# of our integration tests in open source while we figure out a long term plan
# for our integration testing.

load(
    "@iree//integrations/tensorflow/e2e:iree_e2e_cartesian_product_test_suite.bzl",
    "iree_e2e_cartesian_product_test_suite",
)

package(
    default_visibility = ["//visibility:public"],
    features = ["layering_check"],
    licenses = ["notice"],  # Apache 2.0
)

# Create binaries for all test srcs to allow them to be run manually.
py_binary(
    name = "slim_vision_model_test_manual",
    srcs = ["slim_vision_model_test.py"],
    args = ["--tf_hub_url=https://tfhub.dev/google/imagenet/"],
    main = "slim_vision_model_test.py",
    python_version = "PY3",
    deps = [
        "//third_party/py/absl:app",
        "//third_party/py/absl/flags",
        "//third_party/py/iree:pylib_tf_support",
        "//third_party/py/numpy",
        "//third_party/py/tensorflow",
        "//third_party/py/tensorflow_hub",
        "//util/debuginfo:signalsafe_addr2line_installer",
    ],
)

iree_e2e_cartesian_product_test_suite(
    name = "slim_vision_tests",
    size = "enormous",
    failing_configurations = [
        {
            # SavedModelV2 (classification/4) not available.
            "model": "amoebanet_a_n18_f448",
        },
        {
            # Failing vulkan and llvmaot.
            "model": [
                "inception_resnet_v2",
                "inception_v2",
                "inception_v3",
                "nasnet_mobile",
                "nasnet_large",
                "resnet_v2_152",
            ],
            "target_backends": [
                "iree_llvmaot",
                "iree_vulkan",
            ],
        },
    ],
    matrix = {
        "src": "slim_vision_model_test.py",
        "reference_backend": "tf",
        "tf_hub_url": ["https://tfhub.dev/google/imagenet/"],
        "model": [
            "amoebanet_a_n18_f448",
            "inception_resnet_v2",
            "inception_v1",
            "inception_v2",
            "inception_v3",
            # MobileNetV1
            "mobilenet_v1_025_128",
            "mobilenet_v1_025_160",
            "mobilenet_v1_025_192",
            "mobilenet_v1_025_224",
            "mobilenet_v1_050_128",
            "mobilenet_v1_050_160",
            "mobilenet_v1_050_192",
            "mobilenet_v1_050_224",
            "mobilenet_v1_075_128",
            "mobilenet_v1_075_160",
            "mobilenet_v1_075_192",
            "mobilenet_v1_075_224",
            "mobilenet_v1_100_128",
            "mobilenet_v1_100_160",
            "mobilenet_v1_100_192",
            "mobilenet_v1_100_224",
            # MobileNetV2:
            "mobilenet_v2_035_96",
            "mobilenet_v2_035_128",
            "mobilenet_v2_035_160",
            "mobilenet_v2_035_192",
            "mobilenet_v2_035_224",
            "mobilenet_v2_050_96",
            "mobilenet_v2_050_128",
            "mobilenet_v2_050_160",
            "mobilenet_v2_050_192",
            "mobilenet_v2_050_224",
            "mobilenet_v2_075_96",
            "mobilenet_v2_075_128",
            "mobilenet_v2_075_160",
            "mobilenet_v2_075_192",
            "mobilenet_v2_075_224",
            "mobilenet_v2_100_96",
            "mobilenet_v2_100_128",
            "mobilenet_v2_100_160",
            "mobilenet_v2_100_192",
            "mobilenet_v2_100_224",
            "mobilenet_v2_130_224",
            "mobilenet_v2_140_224",
            # MobileNetV3
            "mobilenet_v3_large_100_224",
            "nasnet_mobile",
            "nasnet_large",
            "pnasnet_large",
            # ResNetV1
            "resnet_v1_50",
            "resnet_v1_101",
            "resnet_v1_152",
            # ResNetV2
            "resnet_v2_50",
            "resnet_v2_101",
            "resnet_v2_152",
        ],
        "target_backends": [
            "iree_llvmaot",
            "iree_vulkan",
        ],
    },
    tags = [
        "external",
        "guitar",
        "manual",
        "no-remote",
        "nokokoro",
        "notap",
    ],
    deps = [
        "//third_party/py/absl:app",
        "//third_party/py/absl/flags",
        "//third_party/py/iree:pylib_tf_support",
        "//third_party/py/numpy",
        "//third_party/py/tensorflow",
        "//third_party/py/tensorflow_hub",
        "//util/debuginfo:signalsafe_addr2line_installer",
    ],
)
