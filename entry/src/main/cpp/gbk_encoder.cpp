#include "napi/native_api.h"

#include <cstring>
#include <string>
#include <vector>

#include "zueci_common.h"
#include "zueci_gb2312.h"
#include "zueci_gbk.h"

namespace {

constexpr unsigned int UTF8_REJECT = 12;

unsigned int DecodeUtf8(unsigned int* state, zueci_u32* codePoint, unsigned char byte)
{
    static const unsigned char utf8d[] = {
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,  9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
        7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
        8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,  2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
        10,3,3,3,3,3,3,3,3,3,3,3,3,4,3,3, 11,6,6,6,5,8,8,8,8,8,8,8,8,8,8,8,
        0,12,24,36,60,96,84,12,12,12,48,72, 12,12,12,12,12,12,12,12,12,12,12,12,
        12, 0,12,12,12,12,12, 0,12, 0,12,12, 12,24,12,12,12,12,12,24,12,24,12,12,
        12,12,12,12,12,12,12,24,12,12,12,12, 12,24,12,12,12,12,12,12,12,24,12,12,
        12,12,12,12,12,12,12,36,12,36,12,12, 12,36,12,12,12,12,12,36,12,36,12,12,
        12,36,12,12,12,12,12,12,12,12,12,12,
    };

    const zueci_u32 type = utf8d[byte];
    *codePoint = *state ? (byte & 0x3fu) | (*codePoint << 6) : (0xff >> type) & byte;
    *state = utf8d[256 + *state + type];
    return *state;
}

int LookupUro(const zueci_u32 u, const zueci_u16* tab_u_u, const zueci_u16* tab_mb_ind,
    const zueci_u16* tab_u_mb, unsigned char* dest)
{
    zueci_u32 blockIndex = (u - 0x4E00) >> 4;
    zueci_u32 bit = static_cast<zueci_u32>(1) << (u & 0xF);
    if ((tab_u_u[blockIndex] & bit) == 0) {
        return 0;
    }
    zueci_u32 priorBits = tab_u_u[blockIndex] & (bit - 1);
    priorBits = priorBits - ((priorBits >> 1) & 0x55555555);
    priorBits = (priorBits & 0x33333333) + ((priorBits >> 2) & 0x33333333);
    priorBits = (((priorBits + (priorBits >> 4)) & 0xF0F0F0F) * 0x1010101) >> 24;
    const zueci_u16 mb = tab_u_mb[tab_mb_ind[blockIndex] + priorBits];
    dest[0] = static_cast<unsigned char>(mb >> 8);
    dest[1] = static_cast<unsigned char>(mb);
    return 2;
}

int EncodeGb2312(const zueci_u32 u, unsigned char* dest)
{
    if (u < 0x80) {
        dest[0] = static_cast<unsigned char>(u);
        return 1;
    }
    if (u >= 0x4E00 && u < 0x9E1F) {
        if (u >= 0x9CF0) {
            return 0;
        }
        return LookupUro(u, zueci_gb2312_uro_u, zueci_gb2312_uro_mb_ind, zueci_gb2312_u_mb, dest);
    }
    if (u >= zueci_gb2312_u_u[0] && u <= zueci_gb2312_u_u[ZUECI_ASIZE(zueci_gb2312_u_u) - 1]) {
        int start = zueci_gb2312_u_ind[(u - zueci_gb2312_u_u[0]) >> 8];
        int end = ZUECI_MIN(start + 0x100, ZUECI_ASIZE(zueci_gb2312_u_u)) - 1;
        while (start <= end) {
            const int middle = (start + end) >> 1;
            if (zueci_gb2312_u_u[middle] < u) {
                start = middle + 1;
            } else if (zueci_gb2312_u_u[middle] > u) {
                end = middle - 1;
            } else {
                const zueci_u16 mb = zueci_gb2312_u_mb[u > 0x4E00 ? middle + 6627 : middle];
                dest[0] = static_cast<unsigned char>(mb >> 8);
                dest[1] = static_cast<unsigned char>(mb);
                return 2;
            }
        }
    }
    return 0;
}

int EncodeGbkCodePoint(const zueci_u32 u, unsigned char* dest)
{
    if (u < 0x80) {
        dest[0] = static_cast<unsigned char>(u);
        return 1;
    }
    if (u == 0x30FB) {
        return 0;
    }
    if (u == 0x2015) {
        dest[0] = 0xA8;
        dest[1] = 0x44;
        return 2;
    }
    if (EncodeGb2312(u, dest)) {
        return 2;
    }
    if (u >= 0x4E00 && u < 0xF92C) {
        if (u >= 0x9FB0) {
            return 0;
        }
        return LookupUro(u, zueci_gbk_uro_u, zueci_gbk_uro_mb_ind, zueci_gbk_u_mb, dest);
    }
    if (u >= zueci_gbk_u_u[0] && u <= zueci_gbk_u_u[ZUECI_ASIZE(zueci_gbk_u_u) - 1]) {
        int start = 0;
        int end = ZUECI_ASIZE(zueci_gbk_u_u) - 1;
        while (start <= end) {
            const int middle = (start + end) >> 1;
            if (zueci_gbk_u_u[middle] < u) {
                start = middle + 1;
            } else if (zueci_gbk_u_u[middle] > u) {
                end = middle - 1;
            } else {
                const zueci_u16 mb = zueci_gbk_u_mb[u >= 0x4E00 ? middle + 14139 : middle];
                dest[0] = static_cast<unsigned char>(mb >> 8);
                dest[1] = static_cast<unsigned char>(mb);
                return 2;
            }
        }
    }
    return 0;
}

void PushFallback(std::vector<uint8_t>& out)
{
    out.push_back(static_cast<uint8_t>('?'));
}

std::vector<uint8_t> EncodeUtf8ToGbk(const std::string& utf8)
{
    std::vector<uint8_t> out;
    out.reserve(utf8.size() * 2);

    unsigned int state = 0;
    zueci_u32 codePoint = 0;
    unsigned char dest[2] = { 0, 0 };

    for (unsigned char byte : utf8) {
        if (DecodeUtf8(&state, &codePoint, byte) == UTF8_REJECT) {
            state = 0;
            codePoint = 0;
            PushFallback(out);
            continue;
        }
        if (state != 0) {
            continue;
        }
        const int written = EncodeGbkCodePoint(codePoint, dest);
        if (written <= 0) {
            PushFallback(out);
            continue;
        }
        out.push_back(dest[0]);
        if (written > 1) {
            out.push_back(dest[1]);
        }
    }

    if (state != 0) {
        PushFallback(out);
    }

    return out;
}

napi_value CreateArrayBufferFromBytes(napi_env env, const std::vector<uint8_t>& bytes)
{
    void* data = nullptr;
    napi_value out = nullptr;
    napi_create_arraybuffer(env, bytes.size(), &data, &out);
    if (!bytes.empty() && data != nullptr) {
        std::memcpy(data, bytes.data(), bytes.size());
    }
    return out;
}

napi_value EncodeGbk(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1 || args[0] == nullptr) {
        return CreateArrayBufferFromBytes(env, std::vector<uint8_t>());
    }

    napi_value textValue = args[0];
    napi_valuetype valueType = napi_undefined;
    napi_typeof(env, textValue, &valueType);
    if (valueType != napi_string) {
        napi_coerce_to_string(env, textValue, &textValue);
    }

    size_t utf8Len = 0;
    napi_get_value_string_utf8(env, textValue, nullptr, 0, &utf8Len);
    std::string utf8(utf8Len + 1, '\0');
    size_t copied = 0;
    napi_get_value_string_utf8(env, textValue, utf8.data(), utf8.size(), &copied);
    utf8.resize(copied);

    return CreateArrayBufferFromBytes(env, EncodeUtf8ToGbk(utf8));
}

} // namespace

napi_status GbkRegisterExports(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "encodeGbk", nullptr, EncodeGbk, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    return napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
