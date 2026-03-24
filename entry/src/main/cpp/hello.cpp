#include "napi/native_api.h"

// Forward declaration from ncnn_detector.cpp
napi_status NcnnRegisterExports(napi_env env, napi_value exports);
napi_status GbkRegisterExports(napi_env env, napi_value exports);
napi_status Scene3DRegisterExports(napi_env env, napi_value exports);

// MindSpore Lite (infer_engine.cpp) 已移除
// ONNX Runtime (onnx_engine.cpp) 已移除

static napi_value Add(napi_env env, napi_callback_info info)
{
    size_t requireArgc = 2;
    size_t argc = 2;
    napi_value args[2] = {nullptr};

    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);

    napi_valuetype valuetype0;
    napi_typeof(env, args[0], &valuetype0);

    napi_valuetype valuetype1;
    napi_typeof(env, args[1], &valuetype1);

    double value0;
    napi_get_value_double(env, args[0], &value0);

    double value1;
    napi_get_value_double(env, args[1], &value1);

    napi_value sum;
    napi_create_double(env, value0 + value1, &sum);

    return sum;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_status addStatus = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

    // Register ncnn inference exports
    napi_status ncnnStatus = NcnnRegisterExports(env, exports);
    napi_status gbkStatus = GbkRegisterExports(env, exports);
    napi_status scene3dStatus = Scene3DRegisterExports(env, exports);

    bool hasLoadNcnnModel = false;
    bool hasDetectNcnn = false;
    bool hasEncodeGbk = false;
    napi_has_named_property(env, exports, "loadNcnnModel", &hasLoadNcnnModel);
    napi_has_named_property(env, exports, "detectNcnn", &hasDetectNcnn);
    napi_has_named_property(env, exports, "encodeGbk", &hasEncodeGbk);

    napi_value vAddStatus;
    napi_create_int32(env, static_cast<int32_t>(addStatus), &vAddStatus);
    napi_set_named_property(env, exports, "__addRegStatus", vAddStatus);

    napi_value vNcnnStatus;
    napi_create_int32(env, static_cast<int32_t>(ncnnStatus), &vNcnnStatus);
    napi_set_named_property(env, exports, "__ncnnRegStatus", vNcnnStatus);

    napi_value vGbkStatus;
    napi_create_int32(env, static_cast<int32_t>(gbkStatus), &vGbkStatus);
    napi_set_named_property(env, exports, "__gbkRegStatus", vGbkStatus);

    napi_value vHasLoadNcnnModel;
    napi_get_boolean(env, hasLoadNcnnModel, &vHasLoadNcnnModel);
    napi_set_named_property(env, exports, "__hasLoadNcnnModel", vHasLoadNcnnModel);

    napi_value vHasDetectNcnn;
    napi_get_boolean(env, hasDetectNcnn, &vHasDetectNcnn);
    napi_set_named_property(env, exports, "__hasDetectNcnn", vHasDetectNcnn);

    napi_value vHasEncodeGbk;
    napi_get_boolean(env, hasEncodeGbk, &vHasEncodeGbk);
    napi_set_named_property(env, exports, "__hasEncodeGbk", vHasEncodeGbk);

    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
