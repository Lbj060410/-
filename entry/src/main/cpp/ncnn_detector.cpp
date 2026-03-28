#include "napi/native_api.h"

#include <algorithm>
#include <array>
#include <cfloat>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include <hilog/log.h>

#include "allocator.h"
#include "layer.h"
#include "mat.h"
#include "net.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "NcnnDetector"

namespace {

struct Object {
    float x;
    float y;
    float w;
    float h;
    int label;
    float prob;
};

struct OutputGroup {
    const char* out8;
    const char* out16;
    const char* out32;
};

struct ModelState {
    std::string modelName;
    std::string inputName = "images";
    OutputGroup preferredOutputs{"output", "354", "366"};
    std::vector<char> paramText;
    std::vector<uint32_t> modelWords;
    ncnn::Net net;
};

static std::string g_lastError;
static std::mutex g_errorMutex;
static std::mutex g_modelsMutex;
static std::mutex g_inferMutex;
static std::unordered_map<std::string, std::shared_ptr<ModelState>> g_models;
static ncnn::UnlockedPoolAllocator g_blobPoolAllocator;
static ncnn::PoolAllocator g_workspacePoolAllocator;

class YoloV5Focus : public ncnn::Layer {
public:
    YoloV5Focus() {
        one_blob_only = true;
    }

    int forward(const ncnn::Mat& bottomBlob, ncnn::Mat& topBlob, const ncnn::Option& opt) const override {
        const int w = bottomBlob.w;
        const int h = bottomBlob.h;
        const int channels = bottomBlob.c;

        const int outw = w / 2;
        const int outh = h / 2;
        const int outc = channels * 4;

        topBlob.create(outw, outh, outc, 4u, 1, opt.blob_allocator);
        if (topBlob.empty()) {
            return -100;
        }

        for (int p = 0; p < outc; p++) {
            const float* ptr = bottomBlob.channel(p % channels).row((p / channels) % 2) + ((p / channels) / 2);
            float* outptr = topBlob.channel(p);

            for (int i = 0; i < outh; i++) {
                for (int j = 0; j < outw; j++) {
                    *outptr = *ptr;
                    outptr += 1;
                    ptr += 2;
                }

                ptr += w;
            }
        }

        return 0;
    }
};

DEFINE_LAYER_CREATOR(YoloV5Focus)

static const OutputGroup kOutputs354{"output", "354", "366"};
static const OutputGroup kOutputs364{"output", "364", "381"};
static const std::array<float, 6> kAnchors8{10.f, 13.f, 16.f, 30.f, 33.f, 23.f};
static const std::array<float, 6> kAnchors16{30.f, 61.f, 62.f, 45.f, 59.f, 119.f};
static const std::array<float, 6> kAnchors32{116.f, 90.f, 156.f, 198.f, 373.f, 326.f};

std::string MakeError(const std::string& error) {
    {
        std::lock_guard<std::mutex> lock(g_errorMutex);
        g_lastError = error;
    }
    OH_LOG_ERROR(LOG_APP, "%{public}s", error.c_str());
    return error;
}

void ClearError() {
    std::lock_guard<std::mutex> lock(g_errorMutex);
    g_lastError.clear();
}

bool ReadUtf8(napi_env env, napi_value value, std::string& out) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }

    std::string buffer(length + 1, '\0');
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) {
        return false;
    }

    out.assign(buffer.c_str(), length);
    return true;
}

bool ReadArrayBuffer(napi_env env, napi_value value, void*& data, size_t& length) {
    return napi_get_arraybuffer_info(env, value, &data, &length) == napi_ok;
}

napi_value MakeBool(napi_env env, bool value) {
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value MakeString(napi_env env, const std::string& value) {
    napi_value result;
    napi_create_string_utf8(env, value.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

OutputGroup GuessOutputs(const std::string& modelName) {
    (void)modelName;
    return kOutputs354;
}

void ConfigureNet(ncnn::Net& net) {
    ncnn::Option opt;
    opt.lightmode = true;
    opt.num_threads = 1;
    // Use default allocators for stability on OpenHarmony 3.2.
    // Custom pool allocator clear() has triggered tagged-pointer aborts on some devices.
    opt.blob_allocator = nullptr;
    opt.workspace_allocator = nullptr;
    // Disable fp16/bf16/packing paths to avoid arm fp16 concat crashes on OH 3.2.
    opt.use_packing_layout = false;
    opt.use_fp16_packed = false;
    opt.use_fp16_storage = false;
    opt.use_fp16_arithmetic = false;
    opt.use_bf16_storage = false;
    opt.use_int8_inference = false;
    opt.use_vulkan_compute = false;

    net.opt = opt;
    net.register_custom_layer("YoloV5Focus", YoloV5Focus_layer_creator);
}

float IntersectionArea(const Object& a, const Object& b) {
    if (a.x > b.x + b.w || a.x + a.w < b.x || a.y > b.y + b.h || a.y + a.h < b.y) {
        return 0.f;
    }

    const float interWidth = std::min(a.x + a.w, b.x + b.w) - std::max(a.x, b.x);
    const float interHeight = std::min(a.y + a.h, b.y + b.h) - std::max(a.y, b.y);
    return interWidth * interHeight;
}

void SortObjects(std::vector<Object>& objects, int left, int right) {
    int i = left;
    int j = right;
    const float pivot = objects[(left + right) / 2].prob;

    while (i <= j) {
        while (objects[i].prob > pivot) i++;
        while (objects[j].prob < pivot) j--;

        if (i <= j) {
            std::swap(objects[i], objects[j]);
            i++;
            j--;
        }
    }

    if (left < j) SortObjects(objects, left, j);
    if (i < right) SortObjects(objects, i, right);
}

void SortObjects(std::vector<Object>& objects) {
    if (!objects.empty()) {
        SortObjects(objects, 0, static_cast<int>(objects.size()) - 1);
    }
}

void NmsSortedBboxes(const std::vector<Object>& objects, std::vector<int>& picked, float nmsThreshold) {
    picked.clear();

    const int objectCount = static_cast<int>(objects.size());
    std::vector<float> areas(objectCount);
    for (int i = 0; i < objectCount; i++) {
        areas[i] = objects[i].w * objects[i].h;
    }

    for (int i = 0; i < objectCount; i++) {
        const Object& candidate = objects[i];
        bool keep = true;

        for (int pickedIndex : picked) {
            const Object& existing = objects[pickedIndex];
            if (existing.label != candidate.label) {
                continue;
            }
            const float interArea = IntersectionArea(candidate, existing);
            const float unionArea = areas[i] + areas[pickedIndex] - interArea;
            if (unionArea > 0.f && interArea / unionArea > nmsThreshold) {
                keep = false;
                break;
            }
        }

        if (keep) {
            picked.push_back(i);
        }
    }
}

inline float Sigmoid(float x) {
    return 1.f / (1.f + std::exp(-x));
}

void GenerateProposals(
    const ncnn::Mat& anchors,
    int stride,
    const ncnn::Mat& inPad,
    const ncnn::Mat& featBlob,
    float probThreshold,
    std::vector<Object>& objects) {
    const int numGrid = featBlob.h;

    int numGridX = 0;
    int numGridY = 0;
    if (inPad.w > inPad.h) {
        numGridX = inPad.w / stride;
        numGridY = numGrid / numGridX;
    } else {
        numGridY = inPad.h / stride;
        numGridX = numGrid / numGridY;
    }

    const int numClass = featBlob.w - 5;
    const int numAnchors = anchors.w / 2;

    for (int q = 0; q < numAnchors; q++) {
        const float anchorW = anchors[q * 2];
        const float anchorH = anchors[q * 2 + 1];
        const ncnn::Mat feat = featBlob.channel(q);

        for (int i = 0; i < numGridY; i++) {
            for (int j = 0; j < numGridX; j++) {
                const float* featPtr = feat.row(i * numGridX + j);

                int classIndex = 0;
                float classScore = -FLT_MAX;
                for (int k = 0; k < numClass; k++) {
                    const float score = featPtr[5 + k];
                    if (score > classScore) {
                        classIndex = k;
                        classScore = score;
                    }
                }

                const float boxScore = featPtr[4];
                const float confidence = Sigmoid(boxScore) * Sigmoid(classScore);
                if (confidence < probThreshold) {
                    continue;
                }

                const float dx = Sigmoid(featPtr[0]);
                const float dy = Sigmoid(featPtr[1]);
                const float dw = Sigmoid(featPtr[2]);
                const float dh = Sigmoid(featPtr[3]);

                const float pbCx = (dx * 2.f - 0.5f + j) * stride;
                const float pbCy = (dy * 2.f - 0.5f + i) * stride;
                const float pbW = std::pow(dw * 2.f, 2.f) * anchorW;
                const float pbH = std::pow(dh * 2.f, 2.f) * anchorH;

                Object obj{};
                obj.x = pbCx - pbW * 0.5f;
                obj.y = pbCy - pbH * 0.5f;
                obj.w = pbW;
                obj.h = pbH;
                obj.label = classIndex;
                obj.prob = confidence;
                objects.push_back(obj);
            }
        }
    }
}

ncnn::Mat MakeAnchorMat(const std::array<float, 6>& values) {
    ncnn::Mat anchors(6);
    for (int i = 0; i < 6; i++) {
        anchors[i] = values[static_cast<size_t>(i)];
    }
    return anchors;
}

bool RunExtractor(
    const ModelState& state,
    const ncnn::Mat& inPad,
    const char* inputName,
    const OutputGroup& outputs,
    float probThreshold,
    std::vector<Object>& proposals,
    std::string& err) {
    ncnn::Extractor ex = state.net.create_extractor();
    if (ex.input(inputName, inPad) != 0) {
        err = std::string("extractor input failed: ") + inputName;
        return false;
    }

    ncnn::Mat out8;
    ncnn::Mat out16;
    ncnn::Mat out32;
    if (ex.extract(outputs.out8, out8) != 0 || ex.extract(outputs.out16, out16) != 0 || ex.extract(outputs.out32, out32) != 0) {
        err = std::string("extract outputs failed: ") + outputs.out8 + "," + outputs.out16 + "," + outputs.out32;
        return false;
    }

    GenerateProposals(MakeAnchorMat(kAnchors8), 8, inPad, out8, probThreshold, proposals);
    GenerateProposals(MakeAnchorMat(kAnchors16), 16, inPad, out16, probThreshold, proposals);
    GenerateProposals(MakeAnchorMat(kAnchors32), 32, inPad, out32, probThreshold, proposals);
    return true;
}

bool DecodeOut0(
    const std::string& modelName,
    const ncnn::Mat& outRaw,
    int width,
    int height,
    int inPadW,
    int inPadH,
    float scale,
    int wpad,
    int hpad,
    float probThreshold,
    float nmsThreshold,
    std::vector<Object>& objects,
    std::string& err) {
    ncnn::Mat out;
    if (outRaw.elempack != 1) {
        ncnn::Option opt;
        opt.blob_allocator = nullptr;
        opt.workspace_allocator = nullptr;
        ncnn::convert_packing(outRaw, out, 1, opt);
        if (out.empty()) {
            err = "convert out0 packing failed";
            return false;
        }
    } else {
        out = outRaw;
    }

    const int total = out.w * out.h * out.c;
    if (total <= 0 || out.data == nullptr) {
        err = "out0 empty";
        return false;
    }
    const float* base = static_cast<const float*>(out.data);
    std::vector<float> baseTranspose;

    std::vector<std::pair<int, int>> layouts;
    const auto pushLayout = [&](int rows, int cols) {
        if (rows <= 0 || cols <= 0) return;
        if (rows * cols != total) return;
        for (const auto& p : layouts) {
            if (p.first == rows && p.second == cols) return;
        }
        layouts.emplace_back(rows, cols);
    };

    // Try several plausible matrix layouts. We expect Nx(4+num_classes), e.g. 8400x7.
    pushLayout(out.h * std::max(1, out.c), out.w);
    pushLayout(out.w * std::max(1, out.c), out.h);
    pushLayout(out.h * out.w, std::max(1, out.c));
    pushLayout(std::max(1, out.c), out.h * out.w);
    pushLayout(out.h, out.w * std::max(1, out.c));
    pushLayout(out.w, out.h * std::max(1, out.c));

    if (layouts.empty()) {
        err = "out0 no valid layout";
        return false;
    }

    int bestRows = -1;
    int bestCols = -1;
    int expectedCols = 0;
    if (modelName == "barrier" ||
        modelName == "yolov26barrier" ||
        modelName == "yolov5berrier" ||
        modelName == "honglvdeng") {
        expectedCols = 7; // 4 box dims + 3 classes
    }

    // out0 may come as [7, 8400] (field-major). Transpose to [8400, 7] before row-wise parse.
    if (expectedCols > 0 && out.dims == 2 && out.h == expectedCols && out.w > expectedCols) {
        baseTranspose.resize(static_cast<size_t>(total));
        const int srcRows = out.h;
        const int srcCols = out.w;
        for (int r = 0; r < srcRows; r++) {
            const float* src = base + static_cast<size_t>(r) * static_cast<size_t>(srcCols);
            for (int c = 0; c < srcCols; c++) {
                baseTranspose[static_cast<size_t>(c) * static_cast<size_t>(srcRows) + static_cast<size_t>(r)] = src[c];
            }
        }
        base = baseTranspose.data();
    }
    if (expectedCols > 0 && total % expectedCols == 0) {
        const int rows = total / expectedCols;
        if (rows >= 100) {
            bestRows = rows;
            bestCols = expectedCols;
        }
    }
    if (bestRows <= 0 || bestCols <= 0) {
        int bestRank = -2147483647;
        for (const auto& layout : layouts) {
            const int rows = layout.first;
            const int cols = layout.second;
            if (rows < 100) continue;
            if (cols < 5 || cols > 64) continue;
            // Prefer YOLO-style matrix near 8400x7.
            int rank = 0;
            if (rows > cols) rank += 100000;
            if (cols <= 16) rank += 10000;
            rank += std::max(0, 50000 - std::abs(rows - 8400) * 5);
            rank += std::max(0, 5000 - std::abs(cols - 7) * 500);
            if (rank > bestRank) {
                bestRank = rank;
                bestRows = rows;
                bestCols = cols;
            }
        }
    }
    if (bestRows <= 0 || bestCols <= 0) {
        err = "out0 layout not recognized";
        return false;
    }

    auto parseWithMode = [&](bool xyxyMode, std::vector<Object>& outProps, int& saneCount) {
        outProps.clear();
        saneCount = 0;
        outProps.reserve(static_cast<size_t>(bestRows / 4));
        const float inArea = static_cast<float>(inPadW * inPadH);
        for (int r = 0; r < bestRows; r++) {
            const float* row = base + static_cast<size_t>(r) * static_cast<size_t>(bestCols);
            const float a0 = row[0];
            const float a1 = row[1];
            const float a2 = row[2];
            const float a3 = row[3];
            if (!std::isfinite(a0) || !std::isfinite(a1) || !std::isfinite(a2) || !std::isfinite(a3)) continue;

            int cls = -1;
            float score = -FLT_MAX;
            for (int c = 4; c < bestCols; c++) {
                const float v = row[c];
                if (v > score) {
                    score = v;
                    cls = c - 4;
                }
            }
            if (cls < 0 || score < probThreshold) continue;

            float x = 0.f;
            float y = 0.f;
            float w = 0.f;
            float h = 0.f;
            if (xyxyMode) {
                x = a0;
                y = a1;
                w = a2 - a0;
                h = a3 - a1;
            } else {
                x = a0 - a2 * 0.5f;
                y = a1 - a3 * 0.5f;
                w = a2;
                h = a3;
            }
            if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(w) || !std::isfinite(h)) continue;
            if (w <= 1e-6f || h <= 1e-6f) continue;

            const float area = w * h;
            const bool saneArea = area > inArea * 0.0002f && area < inArea * 0.85f;
            const bool sanePos = x > -inPadW && y > -inPadH && x < inPadW * 2.f && y < inPadH * 2.f;
            if (saneArea && sanePos) saneCount += 1;

            Object obj{};
            obj.x = x;
            obj.y = y;
            obj.w = w;
            obj.h = h;
            obj.label = cls;
            obj.prob = score;
            outProps.push_back(obj);
        }
    };

    std::vector<Object> propsXywh;
    std::vector<Object> propsXyxy;
    int saneXywh = 0;
    int saneXyxy = 0;
    parseWithMode(false, propsXywh, saneXywh);
    parseWithMode(true, propsXyxy, saneXyxy);
    std::vector<Object>& bestProposals = (saneXyxy > saneXywh) ? propsXyxy : propsXywh;

    SortObjects(bestProposals);
    std::vector<int> picked;
    NmsSortedBboxes(bestProposals, picked, nmsThreshold);

    objects.resize(picked.size());
    for (size_t i = 0; i < picked.size(); i++) {
        Object obj = bestProposals[picked[i]];

        // out0 coordinates are in padded-resized space; map back to source image.
        float x0 = (obj.x - static_cast<float>(wpad / 2)) / scale;
        float y0 = (obj.y - static_cast<float>(hpad / 2)) / scale;
        float x1 = (obj.x + obj.w - static_cast<float>(wpad / 2)) / scale;
        float y1 = (obj.y + obj.h - static_cast<float>(hpad / 2)) / scale;

        x0 = std::max(std::min(x0, static_cast<float>(width - 1)), 0.f);
        y0 = std::max(std::min(y0, static_cast<float>(height - 1)), 0.f);
        x1 = std::max(std::min(x1, static_cast<float>(width - 1)), 0.f);
        y1 = std::max(std::min(y1, static_cast<float>(height - 1)), 0.f);

        obj.x = x0;
        obj.y = y0;
        obj.w = std::max(0.f, x1 - x0);
        obj.h = std::max(0.f, y1 - y0);
        objects[i] = obj;
    }

    return true;
}

bool DecodeYolo(
    const ModelState& state,
    const unsigned char* rgba,
    int width,
    int height,
    float probThreshold,
    float nmsThreshold,
    std::vector<Object>& objects,
    std::string& err) {
    constexpr int targetSize = 640;

    int resizedW = width;
    int resizedH = height;
    float scale = 1.f;
    if (resizedW > resizedH) {
        scale = static_cast<float>(targetSize) / static_cast<float>(resizedW);
        resizedW = targetSize;
        resizedH = static_cast<int>(resizedH * scale);
    } else {
        scale = static_cast<float>(targetSize) / static_cast<float>(resizedH);
        resizedH = targetSize;
        resizedW = static_cast<int>(resizedW * scale);
    }

    ncnn::Mat in = ncnn::Mat::from_pixels_resize(
        rgba,
        ncnn::Mat::PIXEL_RGBA2RGB,
        width,
        height,
        resizedW,
        resizedH);
    if (in.empty()) {
        err = "from_pixels_resize failed";
        return false;
    }

    // Ultralytics NCNN exports are decoded against a fixed 640x640 letterbox grid (8400 anchors).
    // Use target-size padding instead of 32-aligned padding to keep decode geometry consistent.
    const int wpad = targetSize - resizedW;
    const int hpad = targetSize - resizedH;

    ncnn::Mat inPad;
    ncnn::copy_make_border(
        in,
        inPad,
        hpad / 2,
        hpad - hpad / 2,
        wpad / 2,
        wpad - wpad / 2,
        ncnn::BORDER_CONSTANT,
        114.f);

    const float normVals[3] = {1.f / 255.f, 1.f / 255.f, 1.f / 255.f};
    inPad.substract_mean_normalize(nullptr, normVals);

    std::vector<Object> proposals;
    std::string runErr;
    const std::array<const char*, 3> inputCandidates{state.inputName.c_str(), "in0", "images"};
    const OutputGroup alternateOutputs = std::strcmp(state.preferredOutputs.out16, kOutputs364.out16) == 0 ? kOutputs354 : kOutputs364;
    const std::array<OutputGroup, 2> outputCandidates{state.preferredOutputs, alternateOutputs};

    bool ran = false;
    for (const char* inputName : inputCandidates) {
        for (const OutputGroup& outputs : outputCandidates) {
            proposals.clear();
            if (RunExtractor(state, inPad, inputName, outputs, probThreshold, proposals, runErr)) {
                ran = true;
                break;
            }
        }
        if (ran) {
            break;
        }
    }

    if (!ran) {
        std::string out0Err;
        ncnn::Mat out0;
        bool out0Extracted = false;
        for (const char* inputName : inputCandidates) {
            ncnn::Extractor ex = state.net.create_extractor();
            if (ex.input(inputName, inPad) != 0) {
                out0Err = std::string("out0 extractor input failed: ") + inputName;
                continue;
            }
            if (ex.extract("out0", out0) == 0) {
                out0Extracted = true;
                break;
            }
            out0Err = "extract out0 failed";
        }

        if (out0Extracted) {
            std::string parseErr;
            if (DecodeOut0(state.modelName, out0, width, height, inPad.w, inPad.h, scale, wpad, hpad, probThreshold, nmsThreshold, objects, parseErr)) {
                return true;
            }
            out0Err = parseErr;
        }

        err = runErr;
        if (!out0Err.empty()) {
            err += " | ";
            err += out0Err;
        }
        return false;
    }

    SortObjects(proposals);
    std::vector<int> picked;
    NmsSortedBboxes(proposals, picked, nmsThreshold);

    objects.resize(picked.size());
    for (size_t i = 0; i < picked.size(); i++) {
        Object obj = proposals[picked[i]];

        float x0 = (obj.x - static_cast<float>(wpad / 2)) / scale;
        float y0 = (obj.y - static_cast<float>(hpad / 2)) / scale;
        float x1 = (obj.x + obj.w - static_cast<float>(wpad / 2)) / scale;
        float y1 = (obj.y + obj.h - static_cast<float>(hpad / 2)) / scale;

        x0 = std::max(std::min(x0, static_cast<float>(width - 1)), 0.f);
        y0 = std::max(std::min(y0, static_cast<float>(height - 1)), 0.f);
        x1 = std::max(std::min(x1, static_cast<float>(width - 1)), 0.f);
        y1 = std::max(std::min(y1, static_cast<float>(height - 1)), 0.f);

        obj.x = x0;
        obj.y = y0;
        obj.w = x1 - x0;
        obj.h = y1 - y0;
        objects[i] = obj;
    }

    return true;
}

std::string ObjectsToJson(const std::vector<Object>& objects) {
    std::ostringstream oss;
    oss << std::fixed << std::setprecision(4) << '[';
    for (size_t i = 0; i < objects.size(); i++) {
        const Object& obj = objects[i];
        const float centerX = obj.x + obj.w * 0.5f;
        const float centerY = obj.y + obj.h * 0.5f;
        if (i > 0) {
            oss << ',';
        }
        oss << "{\"cls\":" << obj.label
            << ",\"score\":" << obj.prob
            << ",\"x\":" << centerX
            << ",\"y\":" << centerY
            << ",\"w\":" << obj.w
            << ",\"h\":" << obj.h
            << '}';
    }
    oss << ']';
    return oss.str();
}

} // namespace

static napi_value LoadNcnnModel(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 3) {
        MakeError("loadNcnnModel requires 3 arguments");
        return MakeBool(env, false);
    }

    std::string modelName;
    if (!ReadUtf8(env, args[0], modelName)) {
        MakeError("loadNcnnModel failed to read model name");
        return MakeBool(env, false);
    }

    void* paramData = nullptr;
    size_t paramLen = 0;
    if (!ReadArrayBuffer(env, args[1], paramData, paramLen) || paramData == nullptr || paramLen == 0) {
        MakeError("loadNcnnModel param buffer invalid");
        return MakeBool(env, false);
    }

    void* binData = nullptr;
    size_t binLen = 0;
    if (!ReadArrayBuffer(env, args[2], binData, binLen) || binData == nullptr || binLen == 0) {
        MakeError("loadNcnnModel bin buffer invalid");
        return MakeBool(env, false);
    }

    auto state = std::make_shared<ModelState>();
    state->modelName = modelName;
    state->preferredOutputs = GuessOutputs(modelName);
    const char* paramChars = reinterpret_cast<const char*>(paramData);
    state->paramText.assign(paramChars, paramChars + paramLen);
    state->paramText.push_back('\0');
    state->modelWords.assign((binLen + sizeof(uint32_t) - 1) / sizeof(uint32_t), 0u);
    std::memcpy(state->modelWords.data(), binData, binLen);

    ConfigureNet(state->net);

    const int paramRet = state->net.load_param_mem(state->paramText.data());
    if (paramRet != 0) {
        MakeError("load_param_mem failed for model " + modelName + ", ret=" + std::to_string(paramRet));
        return MakeBool(env, false);
    }

    const size_t modelConsumed = state->net.load_model(reinterpret_cast<const unsigned char*>(state->modelWords.data()));
    if (modelConsumed == 0) {
        MakeError("load_model failed for model " + modelName);
        return MakeBool(env, false);
    }

    {
        std::lock_guard<std::mutex> lock(g_modelsMutex);
        g_models[modelName] = state;
    }

    ClearError();
    OH_LOG_INFO(LOG_APP, "loadNcnnModel ok: model=%{public}s param=%{public}zu bin=%{public}zu consumed=%{public}zu",
        modelName.c_str(), paramLen, binLen, modelConsumed);
    return MakeBool(env, true);
}

static napi_value DetectNcnn(napi_env env, napi_callback_info info) {
    size_t argc = 6;
    napi_value args[6] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 6) {
        MakeError("detectNcnn requires 6 arguments");
        return MakeString(env, "[]");
    }

    std::string modelName;
    if (!ReadUtf8(env, args[0], modelName)) {
        MakeError("detectNcnn failed to read model name");
        return MakeString(env, "[]");
    }

    void* rgbaData = nullptr;
    size_t rgbaLen = 0;
    if (!ReadArrayBuffer(env, args[1], rgbaData, rgbaLen) || rgbaData == nullptr) {
        MakeError("detectNcnn rgba buffer invalid");
        return MakeString(env, "[]");
    }

    int32_t width = 0;
    int32_t height = 0;
    double conf = 0.25;
    double nms = 0.45;
    napi_get_value_int32(env, args[2], &width);
    napi_get_value_int32(env, args[3], &height);
    napi_get_value_double(env, args[4], &conf);
    napi_get_value_double(env, args[5], &nms);

    if (width <= 0 || height <= 0) {
        MakeError("detectNcnn invalid image size");
        return MakeString(env, "[]");
    }

    const size_t expectedBytes = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
    if (rgbaLen < expectedBytes) {
        MakeError("detectNcnn rgba buffer too small");
        return MakeString(env, "[]");
    }

    std::shared_ptr<ModelState> state;
    {
        std::lock_guard<std::mutex> lock(g_modelsMutex);
        auto it = g_models.find(modelName);
        if (it != g_models.end()) {
            state = it->second;
        }
    }

    if (!state) {
        MakeError("detectNcnn model not loaded: " + modelName);
        return MakeString(env, "[]");
    }

    std::vector<Object> objects;
    std::string err;
    bool ok = false;
    {
        // g_blobPoolAllocator/g_workspacePoolAllocator are shared globals.
        // Serialize inference to avoid allocator races under concurrent detect calls.
        std::lock_guard<std::mutex> lock(g_inferMutex);
        ok = DecodeYolo(
            *state,
            static_cast<const unsigned char*>(rgbaData),
            width,
            height,
            static_cast<float>(conf),
            static_cast<float>(nms),
            objects,
            err);
    }

    if (!ok) {
        MakeError("detectNcnn failed for model " + modelName + ": " + err);
        return MakeString(env, "[]");
    }

    ClearError();
    return MakeString(env, ObjectsToJson(objects));
}

static napi_value GetNcnnLastError(napi_env env, napi_callback_info info) {
    std::string err;
    {
        std::lock_guard<std::mutex> lock(g_errorMutex);
        err = g_lastError;
    }
    return MakeString(env, err);
}

static napi_value GetLastError(napi_env env, napi_callback_info info) {
    return GetNcnnLastError(env, info);
}

napi_status NcnnRegisterExports(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"loadNcnnModel", nullptr, LoadNcnnModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"detectNcnn", nullptr, DetectNcnn, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getNcnnLastError", nullptr, GetNcnnLastError, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getLastError", nullptr, GetLastError, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    return napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}






