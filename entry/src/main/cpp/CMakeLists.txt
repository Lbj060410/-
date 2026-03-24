# the minimum version of CMake.
cmake_minimum_required(VERSION 3.4.1)
project(car)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
set(PROJECT_ROOT_PATH ${NATIVERENDER_ROOT_PATH}/../../../..)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# zxing-cpp: build only QR readers as static library for offline decode.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build third-party static libraries" FORCE)
set(ZXING_READERS ON CACHE BOOL "Build readers" FORCE)
set(ZXING_WRITERS OFF CACHE STRING "Disable writers" FORCE)
set(ZXING_C_API OFF CACHE BOOL "Disable C-API wrapper" FORCE)
set(ZXING_ENABLE_1D OFF CACHE BOOL "Disable 1D formats" FORCE)
set(ZXING_ENABLE_AZTEC OFF CACHE BOOL "Disable Aztec" FORCE)
set(ZXING_ENABLE_DATAMATRIX OFF CACHE BOOL "Disable DataMatrix" FORCE)
set(ZXING_ENABLE_MAXICODE OFF CACHE BOOL "Disable MaxiCode" FORCE)
set(ZXING_ENABLE_PDF417 OFF CACHE BOOL "Disable PDF417" FORCE)
set(ZXING_ENABLE_QRCODE ON CACHE BOOL "Enable QRCode" FORCE)
add_subdirectory(${PROJECT_ROOT_PATH}/third_party/zxing-cpp/core ${CMAKE_CURRENT_BINARY_DIR}/zxing-core)

# ncnn configuration
set(NCNN_INCLUDE_DIR "${PROJECT_ROOT_PATH}/third_party/ncnn/include")
set(NCNN_HEADER "${NCNN_INCLUDE_DIR}/net.h")
set(NCNN_LIB_DIR "${PROJECT_ROOT_PATH}/third_party/ncnn/lib/${OHOS_ARCH}")
set(NCNN_LIB "${NCNN_LIB_DIR}/libncnn.a")

# ONNX Runtime 已移除
# set(ONNXRUNTIME_INCLUDE_DIR "${PROJECT_ROOT_PATH}/third_party/onnxruntime/include")
# set(ONNXRUNTIME_HEADER "${ONNXRUNTIME_INCLUDE_DIR}/onnxruntime_cxx_api.h")
# set(ONNXRUNTIME_LIB_DIR "${PROJECT_ROOT_PATH}/third_party/onnxruntime/lib/${OHOS_ARCH}")

set(ENTRY_SOURCES hello.cpp ncnn_detector.cpp gbk_encoder.cpp scene3d_renderer.cpp glb_loader.cpp)

# infer_engine.cpp (MindSpore) 已移除
# onnx_engine.cpp (ONNX) 已移除

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include
                    ${PROJECT_ROOT_PATH}/third_party/zxing-cpp/core/src/libzueci
                    ${PROJECT_ROOT_PATH}/third_party/tinygltf)

set(TINYGLTF_DIR "${PROJECT_ROOT_PATH}/third_party/tinygltf")
set(TINYGLTF_HEADER "${TINYGLTF_DIR}/tiny_gltf.h")
set(TINYGLTF_JSON_HEADER "${TINYGLTF_DIR}/json.hpp")
set(TINYGLTF_STB_IMAGE_HEADER "${TINYGLTF_DIR}/stb_image.h")
if(EXISTS "${TINYGLTF_HEADER}" AND EXISTS "${TINYGLTF_JSON_HEADER}" AND EXISTS "${TINYGLTF_STB_IMAGE_HEADER}")
    message(STATUS "tinygltf full mode enabled")
else()
    message(WARNING "tinygltf deps incomplete(json.hpp/stb_image.h), GLB loader will run in stub mode")
endif()

# Check ncnn availability
if(EXISTS "${NCNN_HEADER}")
    include_directories(${NCNN_INCLUDE_DIR})
    set(ENABLE_NCNN TRUE)
    message(STATUS "ncnn headers found at ${NCNN_HEADER}")
else()
    set(ENABLE_NCNN FALSE)
    message(WARNING "ncnn headers not found, ncnn detector will run in stub mode")
endif()

# ONNX Runtime 检查已移除
# MindSpore Lite 使用系统库，无需检查

add_library(entry SHARED ${ENTRY_SOURCES})

target_link_libraries(entry PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    librawfile.z.so
    ZXing
    GLESv3
    EGL)

# MindSpore Lite 已移除
# libmindspore-lite.huawei.so

# Link ncnn library (暂时禁用，等待 HarmonyOS 版本)
# if(ENABLE_NCNN)
#     if(EXISTS "${NCNN_LIB_DIR}/libncnn.a")
#         target_link_libraries(entry PUBLIC ${NCNN_LIB_DIR}/libncnn.a)
#         message(STATUS "Linking static ncnn library: ${NCNN_LIB_DIR}/libncnn.a")
#     endif()
# endif()
if(ENABLE_NCNN)
    if(EXISTS "${NCNN_LIB}")
        target_link_libraries(entry PUBLIC ${NCNN_LIB})
        message(STATUS "Linking static ncnn library: ${NCNN_LIB}")
    else()
        message(WARNING "ncnn library not found at ${NCNN_LIB}, detector will stay in stub mode")
    endif()
endif()
