# Copyright 2021 The IREE Authors
#
# Licensed under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

from .util import ImportContext, ImportHooks, ImportStage
from .importer import Importer
from .intrinsic_def import def_ir_macro_intrinsic, def_pattern_call_intrinsic, def_pyfunc_intrinsic
