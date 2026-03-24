/**
 * glb_loader.h
 *
 * GLB/glTF 2.0 模型加载器（基于 tinygltf）
 *
 * 功能：
 * - 从 rawfile 加载 .glb 文件
 * - 解析顶点/索引/纹理数据
 * - 上传到 OpenGL ES
 * - 支持多个模型实例
 */

#ifndef GLB_LOADER_H
#define GLB_LOADER_H

#include <GLES3/gl32.h>
#include <string>
#include <vector>
#include <map>

// 顶点数据结构
struct Vertex {
    float position[3];
    float normal[3];
    float texCoord[2];
};

// Mesh 数据（一个模型可能包含多个 Mesh）
struct Mesh {
    std::vector<Vertex> vertices;
    std::vector<uint32_t> indices;

    // OpenGL 资源
    GLuint vao = 0;
    GLuint vbo = 0;
    GLuint ebo = 0;

    // 材质
    int materialIndex = -1;
};

// 材质数据
struct Material {
    float baseColorFactor[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    GLuint baseColorTexture = 0;
    float metallicFactor = 1.0f;
    float roughnessFactor = 1.0f;
};

// 模型数据
struct Model {
    std::vector<Mesh> meshes;
    std::vector<Material> materials;
    std::string name;
};

class GLBLoader {
public:
    GLBLoader();
    ~GLBLoader();

    /**
     * 从 rawfile 加载 .glb 模型
     * @param rawfilePath rawfile 相对路径（如 "models/car_model_1.glb"）
     * @param outModel 输出模型数据
     * @return 成功返回 true
     */
    bool LoadFromRawfile(const std::string& rawfilePath, Model& outModel);

    /**
     * 从内存加载 .glb 模型
     * @param data 二进制数据
     * @param size 数据大小
     * @param outModel 输出模型数据
     * @return 成功返回 true
     */
    bool LoadFromMemory(const unsigned char* data, size_t size, Model& outModel);

    /**
     * 上传模型到 OpenGL（创建 VAO/VBO/EBO）
     * @param model 模型数据
     */
    void UploadToGL(Model& model);

    /**
     * 释放模型 OpenGL 资源
     * @param model 模型数据
     */
    void ReleaseGL(Model& model);

private:
    bool ParseGLTF(const std::string& gltfData, bool isBinary, Model& outModel);
    void ExtractMeshData(const void* gltfModel, Model& outModel);
    void ExtractMaterialData(const void* gltfModel, Model& outModel);
    GLuint LoadTexture(const unsigned char* data, int width, int height, int channels);
};

#endif // GLB_LOADER_H
