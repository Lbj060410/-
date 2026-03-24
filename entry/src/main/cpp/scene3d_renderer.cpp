/**
 * scene3d_renderer.cpp
 *
 * HarmonyOS 3D 场景渲染器（OpenGL ES 3.2）
 *
 * 功能：
 * - 渲染小车模型（位姿实时更新）
 * - 渲染路径线（A* 规划结果）
 * - 渲染障碍物标记
 * - 相机控制（跟随/鸟瞰/自由视角）
 *
 * 依赖：
 * - OpenGL ES 3.2 (HarmonyOS 自带)
 * - GLM (数学库，需添加到 third_party)
 * - tinygltf (GLB 模型加载)
 */

#include "napi/native_api.h"
#include "glb_loader.h"
#include <GLES3/gl32.h>
#include <EGL/egl.h>
#include <cstdio>
#include <string>
#include <vector>
#include <cmath>

// ===== 全局状态 =====
struct Scene3DState {
    // EGL 上下文
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLSurface surface = EGL_NO_SURFACE;
    EGLContext context = EGL_NO_CONTEXT;

    // 渲染表面尺寸
    int width = 0;
    int height = 0;

    // 小车位姿
    float carX = 0.5f;
    float carY = 0.5f;
    float carHeading = 0.0f;

    // 路径
    std::vector<std::string> pathNodes;
    int pathIndex = 0;

    // 障碍物
    std::vector<std::string> blockedNodes;

    // 相机
    int cameraMode = 2; // 0=FREE, 1=FOLLOW, 2=BIRD_EYE, 3=FIRST_PERSON
    float cameraDistance = 5.0f;
    float cameraAngle = 45.0f;

    // 渲染选项
    bool showGrid = true;
    bool showPath = true;
    bool showObstacles = true;
    bool showBoundingBoxes = true;

    // OpenGL 资源
    GLuint shaderProgram = 0;
    GLuint vao = 0;
    GLuint vbo = 0;

    // GLB 模型
    Model carModel1;  // 第一个小车模型
    Model carModel2;  // 第二个小车模型
    int activeCarModel = 0;  // 0=model1, 1=model2
    GLBLoader loader;
};

static Scene3DState g_scene;

// ===== 辅助函数 =====

static void LogError(const char* tag, const char* msg) {
    // TODO: 使用 hilog
    printf("[ERROR][%s] %s\n", tag, msg);
}

static void LogInfo(const char* tag, const char* msg) {
    printf("[INFO][%s] %s\n", tag, msg);
}

// ===== OpenGL 初始化 =====

static bool InitEGL(int width, int height) {
    // TODO: 完整 EGL 初始化流程
    // 1. eglGetDisplay
    // 2. eglInitialize
    // 3. eglChooseConfig
    // 4. eglCreateWindowSurface (从 XComponent 获取 NativeWindow)
    // 5. eglCreateContext
    // 6. eglMakeCurrent

    g_scene.width = width;
    g_scene.height = height;

    LogError("Scene3D", "EGL init is stubbed, renderer not ready");
    return false;
}

static void DestroyEGL() {
    // 释放模型资源
    g_scene.loader.ReleaseGL(g_scene.carModel1);
    g_scene.loader.ReleaseGL(g_scene.carModel2);

    // TODO: 释放 EGL 资源
    LogInfo("Scene3D", "EGL destroyed (stub)");
}

static bool LoadCarModels() {
    // 加载第一个小车模型
    bool success1 = g_scene.loader.LoadFromRawfile("models/car_model_1.glb", g_scene.carModel1);
    if (success1) {
        g_scene.carModel1.name = "CarModel1";
        g_scene.loader.UploadToGL(g_scene.carModel1);
        LogInfo("Scene3D", "Loaded car_model_1.glb");
    } else {
        LogError("Scene3D", "Failed to load car_model_1.glb");
    }

    // 加载第二个小车模型
    bool success2 = g_scene.loader.LoadFromRawfile("models/car_model_2.glb", g_scene.carModel2);
    if (success2) {
        g_scene.carModel2.name = "CarModel2";
        g_scene.loader.UploadToGL(g_scene.carModel2);
        LogInfo("Scene3D", "Loaded car_model_2.glb");
    } else {
        LogError("Scene3D", "Failed to load car_model_2.glb");
    }

    return success1 || success2;  // 至少一个模型加载成功即可
}

static bool InitShaders() {
    // TODO: 编译顶点/片段着色器
    // 简单示例：纯色渲染
    const char* vertexShaderSource = R"(
        #version 320 es
        layout(location = 0) in vec3 aPos;
        uniform mat4 uMVP;
        void main() {
            gl_Position = uMVP * vec4(aPos, 1.0);
        }
    )";

    const char* fragmentShaderSource = R"(
        #version 320 es
        precision mediump float;
        out vec4 FragColor;
        uniform vec4 uColor;
        void main() {
            FragColor = uColor;
        }
    )";

    // TODO: glCreateShader, glCompileShader, glLinkProgram
    LogError("Scene3D", "Shader init is stubbed, renderer not ready");
    return false;
}

static void InitGeometry() {
    // TODO: 创建 VAO/VBO
    // 简单立方体（代表小车）
    float vertices[] = {
        -0.5f, -0.5f, -0.5f,
         0.5f, -0.5f, -0.5f,
         0.5f,  0.5f, -0.5f,
        -0.5f,  0.5f, -0.5f,
        // ... 其他顶点
    };

    // glGenVertexArrays, glGenBuffers, glBufferData
    LogInfo("Scene3D", "Geometry initialized (stub)");
}

// ===== 渲染循环 =====

static void RenderCarModel(const Model& model, float x, float y, float heading) {
    if (model.meshes.empty()) return;

    // TODO: 计算 Model 矩阵（位置 + 旋转）
    // glm::mat4 modelMatrix = glm::translate(glm::mat4(1.0f), glm::vec3(x, 0.0f, y));
    // modelMatrix = glm::rotate(modelMatrix, glm::radians(heading), glm::vec3(0.0f, 1.0f, 0.0f));

    // 绘制所有 Mesh
    for (const auto& mesh : model.meshes) {
        if (mesh.vao == 0) continue;

        glBindVertexArray(mesh.vao);

        // 绑定材质纹理（如果有）
        if (mesh.materialIndex >= 0 && mesh.materialIndex < model.materials.size()) {
            const Material& mat = model.materials[mesh.materialIndex];
            if (mat.baseColorTexture > 0) {
                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_2D, mat.baseColorTexture);
            }
        }

        // 绘制
        if (!mesh.indices.empty()) {
            glDrawElements(GL_TRIANGLES, mesh.indices.size(), GL_UNSIGNED_INT, 0);
        } else {
            glDrawArrays(GL_TRIANGLES, 0, mesh.vertices.size());
        }

        glBindVertexArray(0);
    }
}

static void RenderFrame() {
    if (g_scene.display == EGL_NO_DISPLAY) return;

    // 1. 清屏
    glClearColor(0.2f, 0.3f, 0.3f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glEnable(GL_DEPTH_TEST);

    // 2. 计算 MVP 矩阵
    // TODO: 使用 GLM 计算 Model/View/Projection

    // 3. 渲染网格（可选）
    if (g_scene.showGrid) {
        // TODO: 绘制地面网格
    }

    // 4. 渲染路径
    if (g_scene.showPath && !g_scene.pathNodes.empty()) {
        // TODO: 绘制路径线
    }

    // 5. 渲染障碍物
    if (g_scene.showObstacles && !g_scene.blockedNodes.empty()) {
        // TODO: 绘制障碍物标记
    }

    // 6. 渲染小车（使用当前激活的模型）
    const Model& activeModel = (g_scene.activeCarModel == 0) ? g_scene.carModel1 : g_scene.carModel2;
    RenderCarModel(activeModel, g_scene.carX, g_scene.carY, g_scene.carHeading);

    // 7. 交换缓冲区
    // eglSwapBuffers(g_scene.display, g_scene.surface);
}

// ===== NAPI 导出函数 =====

static napi_value Scene3DInit(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t width, height;
    napi_get_value_int32(env, args[0], &width);
    napi_get_value_int32(env, args[1], &height);

    bool success = InitEGL(width, height) && InitShaders();
    if (success) {
        InitGeometry();
        // 加载 GLB 模型
        LoadCarModels();
    }

    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

static napi_value Scene3DDestroy(napi_env env, napi_callback_info info) {
    DestroyEGL();

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value Scene3DUpdateCarPose(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    double xNorm, yNorm, headingDeg;
    napi_get_value_double(env, args[0], &xNorm);
    napi_get_value_double(env, args[1], &yNorm);
    napi_get_value_double(env, args[2], &headingDeg);

    g_scene.carX = static_cast<float>(xNorm);
    g_scene.carY = static_cast<float>(yNorm);
    g_scene.carHeading = static_cast<float>(headingDeg);

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value Scene3DUpdatePath(napi_env env, napi_callback_info info) {
    // TODO: 解析 Array<string> 参数
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value Scene3DUpdateObstacles(napi_env env, napi_callback_info info) {
    // TODO: 解析 Array<string> 参数
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value Scene3DUpdateCamera(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t mode;
    double distance, angle;
    napi_get_value_int32(env, args[0], &mode);
    napi_get_value_double(env, args[1], &distance);
    napi_get_value_double(env, args[2], &angle);

    g_scene.cameraMode = mode;
    g_scene.cameraDistance = static_cast<float>(distance);
    g_scene.cameraAngle = static_cast<float>(angle);

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value Scene3DRender(napi_env env, napi_callback_info info) {
    RenderFrame();

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value Scene3DSwitchCarModel(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t modelIndex;
    napi_get_value_int32(env, args[0], &modelIndex);

    // 切换模型（0 或 1）
    g_scene.activeCarModel = (modelIndex == 0) ? 0 : 1;

    printf("[Scene3D] Switched to car model %d\n", g_scene.activeCarModel);

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ===== 模块注册 =====

napi_status Scene3DRegisterExports(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "scene3dInit", nullptr, Scene3DInit, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "scene3dDestroy", nullptr, Scene3DDestroy, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "scene3dUpdateCarPose", nullptr, Scene3DUpdateCarPose, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "scene3dUpdatePath", nullptr, Scene3DUpdatePath, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "scene3dUpdateObstacles", nullptr, Scene3DUpdateObstacles, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "scene3dUpdateCamera", nullptr, Scene3DUpdateCamera, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "scene3dRender", nullptr, Scene3DRender, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "scene3dSwitchCarModel", nullptr, Scene3DSwitchCarModel, nullptr, nullptr, nullptr, napi_default, nullptr }
    };

    return napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
