#include "glb_loader.h"

#include <cstddef>
#include <cstdio>
#include <cstring>

// Build-safe GLB loader:
// - If tinygltf + required headers exist, compile full loader.
// - Otherwise compile stub implementation so native build still succeeds.
#if __has_include("tiny_gltf.h") && __has_include("json.hpp") && __has_include("stb_image.h")
#define GLB_LOADER_HAS_TINYGLTF 1
#else
#define GLB_LOADER_HAS_TINYGLTF 0
#endif

#if GLB_LOADER_HAS_TINYGLTF

#define TINYGLTF_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define TINYGLTF_NO_STB_IMAGE_WRITE

#include "tiny_gltf.h"
#include <rawfile/raw_file_manager.h>

GLBLoader::GLBLoader() {}
GLBLoader::~GLBLoader() {}

bool GLBLoader::LoadFromRawfile(const std::string& rawfilePath, Model& outModel) {
    NativeResourceManager* resMgr = OH_ResourceManager_InitNativeResourceManager(nullptr, nullptr);
    if (!resMgr) {
        std::printf("[GLBLoader] Failed to init resource manager\n");
        return false;
    }

    RawFile* rawFile = OH_ResourceManager_OpenRawFile(resMgr, rawfilePath.c_str());
    if (!rawFile) {
        std::printf("[GLBLoader] Failed to open rawfile: %s\n", rawfilePath.c_str());
        OH_ResourceManager_ReleaseNativeResourceManager(resMgr);
        return false;
    }

    long fileSize = OH_ResourceManager_GetRawFileSize(rawFile);
    if (fileSize <= 0) {
        std::printf("[GLBLoader] Invalid file size: %ld\n", fileSize);
        OH_ResourceManager_CloseRawFile(rawFile);
        OH_ResourceManager_ReleaseNativeResourceManager(resMgr);
        return false;
    }

    std::vector<unsigned char> buffer(static_cast<size_t>(fileSize));
    int bytesRead = OH_ResourceManager_ReadRawFile(rawFile, buffer.data(), fileSize);
    OH_ResourceManager_CloseRawFile(rawFile);
    OH_ResourceManager_ReleaseNativeResourceManager(resMgr);

    if (bytesRead != fileSize) {
        std::printf("[GLBLoader] Read size mismatch: %d != %ld\n", bytesRead, fileSize);
        return false;
    }

    return LoadFromMemory(buffer.data(), buffer.size(), outModel);
}

bool GLBLoader::LoadFromMemory(const unsigned char* data, size_t size, Model& outModel) {
    tinygltf::TinyGLTF loader;
    tinygltf::Model gltfModel;
    std::string err;
    std::string warn;

    const bool success = loader.LoadBinaryFromMemory(&gltfModel, &err, &warn, data, size);

    if (!warn.empty()) {
        std::printf("[GLBLoader] Warning: %s\n", warn.c_str());
    }

    if (!success || !err.empty()) {
        std::printf("[GLBLoader] Error: %s\n", err.c_str());
        return false;
    }

    ExtractMeshData(&gltfModel, outModel);
    ExtractMaterialData(&gltfModel, outModel);

    std::printf("[GLBLoader] Loaded model: %zu meshes, %zu materials\n",
                outModel.meshes.size(), outModel.materials.size());
    return true;
}

void GLBLoader::ExtractMeshData(const void* gltfModelPtr, Model& outModel) {
    const tinygltf::Model* gltfModel = static_cast<const tinygltf::Model*>(gltfModelPtr);

    for (const auto& mesh : gltfModel->meshes) {
        for (const auto& primitive : mesh.primitives) {
            Mesh outMesh;

            const auto& posAccessor = gltfModel->accessors[primitive.attributes.at("POSITION")];
            const auto& posBufferView = gltfModel->bufferViews[posAccessor.bufferView];
            const auto& posBuffer = gltfModel->buffers[posBufferView.buffer];
            const float* positions = reinterpret_cast<const float*>(
                posBuffer.data.data() + posBufferView.byteOffset + posAccessor.byteOffset);

            const float* normals = nullptr;
            if (primitive.attributes.count("NORMAL")) {
                const auto& normAccessor = gltfModel->accessors[primitive.attributes.at("NORMAL")];
                const auto& normBufferView = gltfModel->bufferViews[normAccessor.bufferView];
                const auto& normBuffer = gltfModel->buffers[normBufferView.buffer];
                normals = reinterpret_cast<const float*>(
                    normBuffer.data.data() + normBufferView.byteOffset + normAccessor.byteOffset);
            }

            const float* texCoords = nullptr;
            if (primitive.attributes.count("TEXCOORD_0")) {
                const auto& texAccessor = gltfModel->accessors[primitive.attributes.at("TEXCOORD_0")];
                const auto& texBufferView = gltfModel->bufferViews[texAccessor.bufferView];
                const auto& texBuffer = gltfModel->buffers[texBufferView.buffer];
                texCoords = reinterpret_cast<const float*>(
                    texBuffer.data.data() + texBufferView.byteOffset + texAccessor.byteOffset);
            }

            const size_t vertexCount = posAccessor.count;
            outMesh.vertices.resize(vertexCount);
            for (size_t i = 0; i < vertexCount; ++i) {
                Vertex& v = outMesh.vertices[i];

                v.position[0] = positions[i * 3 + 0];
                v.position[1] = positions[i * 3 + 1];
                v.position[2] = positions[i * 3 + 2];

                if (normals) {
                    v.normal[0] = normals[i * 3 + 0];
                    v.normal[1] = normals[i * 3 + 1];
                    v.normal[2] = normals[i * 3 + 2];
                } else {
                    v.normal[0] = 0.0f;
                    v.normal[1] = 1.0f;
                    v.normal[2] = 0.0f;
                }

                if (texCoords) {
                    v.texCoord[0] = texCoords[i * 2 + 0];
                    v.texCoord[1] = texCoords[i * 2 + 1];
                } else {
                    v.texCoord[0] = 0.0f;
                    v.texCoord[1] = 0.0f;
                }
            }

            if (primitive.indices >= 0) {
                const auto& indexAccessor = gltfModel->accessors[primitive.indices];
                const auto& indexBufferView = gltfModel->bufferViews[indexAccessor.bufferView];
                const auto& indexBuffer = gltfModel->buffers[indexBufferView.buffer];
                const unsigned char* indexData = indexBuffer.data.data() +
                                                 indexBufferView.byteOffset +
                                                 indexAccessor.byteOffset;

                outMesh.indices.resize(indexAccessor.count);
                if (indexAccessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT) {
                    const uint16_t* indices16 = reinterpret_cast<const uint16_t*>(indexData);
                    for (size_t i = 0; i < indexAccessor.count; ++i) {
                        outMesh.indices[i] = indices16[i];
                    }
                } else if (indexAccessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT) {
                    const uint32_t* indices32 = reinterpret_cast<const uint32_t*>(indexData);
                    std::memcpy(outMesh.indices.data(), indices32, indexAccessor.count * sizeof(uint32_t));
                }
            }

            outMesh.materialIndex = primitive.material;
            outModel.meshes.push_back(outMesh);
        }
    }
}

void GLBLoader::ExtractMaterialData(const void* gltfModelPtr, Model& outModel) {
    const tinygltf::Model* gltfModel = static_cast<const tinygltf::Model*>(gltfModelPtr);

    for (const auto& mat : gltfModel->materials) {
        Material outMat;

        if (mat.pbrMetallicRoughness.baseColorFactor.size() == 4) {
            for (int i = 0; i < 4; ++i) {
                outMat.baseColorFactor[i] = static_cast<float>(mat.pbrMetallicRoughness.baseColorFactor[i]);
            }
        }

        outMat.metallicFactor = static_cast<float>(mat.pbrMetallicRoughness.metallicFactor);
        outMat.roughnessFactor = static_cast<float>(mat.pbrMetallicRoughness.roughnessFactor);

        if (mat.pbrMetallicRoughness.baseColorTexture.index >= 0) {
            const int texIndex = mat.pbrMetallicRoughness.baseColorTexture.index;
            const auto& texture = gltfModel->textures[texIndex];
            const auto& image = gltfModel->images[texture.source];

            outMat.baseColorTexture = LoadTexture(
                image.image.data(),
                image.width,
                image.height,
                image.component
            );
        }

        outModel.materials.push_back(outMat);
    }
}

GLuint GLBLoader::LoadTexture(const unsigned char* data, int width, int height, int channels) {
    GLuint textureID = 0;
    glGenTextures(1, &textureID);
    glBindTexture(GL_TEXTURE_2D, textureID);

    const GLenum format = (channels == 4) ? GL_RGBA : GL_RGB;
    glTexImage2D(GL_TEXTURE_2D, 0, format, width, height, 0, format, GL_UNSIGNED_BYTE, data);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glGenerateMipmap(GL_TEXTURE_2D);

    return textureID;
}

#else

GLBLoader::GLBLoader() {}
GLBLoader::~GLBLoader() {}

bool GLBLoader::LoadFromRawfile(const std::string& rawfilePath, Model& outModel) {
    outModel.meshes.clear();
    outModel.materials.clear();
    std::printf("[GLBLoader] tinygltf disabled: missing json.hpp/stb_image.h, skip rawfile load: %s\n",
                rawfilePath.c_str());
    return false;
}

bool GLBLoader::LoadFromMemory(const unsigned char* data, size_t size, Model& outModel) {
    (void)data;
    (void)size;
    outModel.meshes.clear();
    outModel.materials.clear();
    std::printf("[GLBLoader] tinygltf disabled: missing json.hpp/stb_image.h, skip memory load\n");
    return false;
}

void GLBLoader::ExtractMeshData(const void* gltfModelPtr, Model& outModel) {
    (void)gltfModelPtr;
    (void)outModel;
}

void GLBLoader::ExtractMaterialData(const void* gltfModelPtr, Model& outModel) {
    (void)gltfModelPtr;
    (void)outModel;
}

GLuint GLBLoader::LoadTexture(const unsigned char* data, int width, int height, int channels) {
    (void)data;
    (void)width;
    (void)height;
    (void)channels;
    return 0;
}

#endif

void GLBLoader::UploadToGL(Model& model) {
    for (auto& mesh : model.meshes) {
        glGenVertexArrays(1, &mesh.vao);
        glBindVertexArray(mesh.vao);

        glGenBuffers(1, &mesh.vbo);
        glBindBuffer(GL_ARRAY_BUFFER, mesh.vbo);
        glBufferData(GL_ARRAY_BUFFER,
                     mesh.vertices.size() * sizeof(Vertex),
                     mesh.vertices.data(),
                     GL_STATIC_DRAW);

        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex, position));

        glEnableVertexAttribArray(1);
        glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex, normal));

        glEnableVertexAttribArray(2);
        glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex, texCoord));

        if (!mesh.indices.empty()) {
            glGenBuffers(1, &mesh.ebo);
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, mesh.ebo);
            glBufferData(GL_ELEMENT_ARRAY_BUFFER,
                         mesh.indices.size() * sizeof(uint32_t),
                         mesh.indices.data(),
                         GL_STATIC_DRAW);
        }

        glBindVertexArray(0);
    }

    std::printf("[GLBLoader] Uploaded %zu meshes to OpenGL\n", model.meshes.size());
}

void GLBLoader::ReleaseGL(Model& model) {
    for (auto& mesh : model.meshes) {
        if (mesh.vao) glDeleteVertexArrays(1, &mesh.vao);
        if (mesh.vbo) glDeleteBuffers(1, &mesh.vbo);
        if (mesh.ebo) glDeleteBuffers(1, &mesh.ebo);
        mesh.vao = mesh.vbo = mesh.ebo = 0;
    }

    for (auto& mat : model.materials) {
        if (mat.baseColorTexture) {
            glDeleteTextures(1, &mat.baseColorTexture);
            mat.baseColorTexture = 0;
        }
    }

    std::printf("[GLBLoader] Released OpenGL resources\n");
}
