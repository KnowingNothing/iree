################################################################################
# Autogenerated by build_tools/bazel_to_cmake/bazel_to_cmake.py from           #
# iree/hal/local/BUILD                                                         #
#                                                                              #
# Use iree_cmake_extra_content from iree/build_defs.oss.bzl to add arbitrary   #
# CMake-only content.                                                          #
#                                                                              #
# To disable autogeneration for this file entirely, delete this header.        #
################################################################################

iree_add_all_subdirs()

iree_cc_library(
  NAME
    executable_library
  HDRS
    "executable_library.h"
  PUBLIC
)

iree_cc_test(
  NAME
    executable_library_benchmark
  SRCS
    "executable_library_benchmark.c"
  DEPS
    ::executable_library
    ::local
    iree::base
    iree::base::internal::flags
    iree::base::tracing
    iree::hal
    iree::hal::local::loaders::embedded_library_loader
    iree::testing::benchmark
)

iree_cc_test(
  NAME
    executable_library_test
  SRCS
    "executable_library_demo.c"
    "executable_library_demo.h"
    "executable_library_test.c"
  DEPS
    iree::base
    iree::base::core_headers
    iree::hal::local::executable_library
)

iree_cc_library(
  NAME
    local
  HDRS
    "executable_loader.h"
    "inline_command_buffer.h"
    "local_descriptor_set.h"
    "local_descriptor_set_layout.h"
    "local_executable.h"
    "local_executable_cache.h"
    "local_executable_layout.h"
  SRCS
    "executable_loader.c"
    "inline_command_buffer.c"
    "local_descriptor_set.c"
    "local_descriptor_set_layout.c"
    "local_executable.c"
    "local_executable_cache.c"
    "local_executable_layout.c"
  DEPS
    ::executable_library
    iree::base
    iree::base::core_headers
    iree::base::internal
    iree::base::tracing
    iree::hal
  PUBLIC
)

iree_cc_library(
  NAME
    sync_driver
  HDRS
    "sync_device.h"
    "sync_driver.h"
    "sync_event.h"
    "sync_semaphore.h"
  SRCS
    "sync_device.c"
    "sync_driver.c"
    "sync_event.c"
    "sync_semaphore.c"
  DEPS
    ::local
    iree::base
    iree::base::core_headers
    iree::base::internal
    iree::base::internal::arena
    iree::base::internal::synchronization
    iree::base::tracing
    iree::hal
  PUBLIC
)

if(NOT ${IREE_ENABLE_THREADING})
  return()
endif()

iree_cc_library(
  NAME
    event_pool
  HDRS
    "event_pool.h"
  SRCS
    "event_pool.c"
  DEPS
    iree::base
    iree::base::core_headers
    iree::base::internal
    iree::base::internal::synchronization
    iree::base::internal::wait_handle
    iree::base::tracing
  PUBLIC
)

iree_cc_library(
  NAME
    task_driver
  HDRS
    "task_command_buffer.h"
    "task_device.h"
    "task_driver.h"
    "task_event.h"
    "task_queue.h"
    "task_queue_state.h"
    "task_semaphore.h"
  SRCS
    "task_command_buffer.c"
    "task_device.c"
    "task_driver.c"
    "task_event.c"
    "task_queue.c"
    "task_queue_state.c"
    "task_semaphore.c"
  DEPS
    ::event_pool
    ::executable_library
    ::local
    iree::base
    iree::base::core_headers
    iree::base::internal
    iree::base::internal::arena
    iree::base::internal::synchronization
    iree::base::internal::wait_handle
    iree::base::tracing
    iree::hal
    iree::task
  PUBLIC
)

### BAZEL_TO_CMAKE_PRESERVES_ALL_CONTENT_BELOW_THIS_LINE ###
