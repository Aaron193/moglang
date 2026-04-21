#include "Crypto.hpp"

#include <algorithm>
#include <fstream>
#include <iomanip>
#include <memory>
#include <sstream>
#include <vector>

#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/x509.h>

namespace {

using EvpMdCtxPtr = std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)>;
using EvpPkeyPtr = std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)>;

std::string hexString(const unsigned char* data, size_t length) {
    std::ostringstream out;
    out << std::hex << std::setfill('0');
    for (size_t index = 0; index < length; ++index) {
        out << std::setw(2) << static_cast<unsigned int>(data[index]);
    }
    return out.str();
}

bool loadFileBytes(const std::filesystem::path& path,
                   std::vector<unsigned char>& outBytes,
                   std::string& outError) {
    outBytes.clear();
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        outError = "Could not open '" + path.string() + "'.";
        return false;
    }

    outBytes.assign(std::istreambuf_iterator<char>(file),
                    std::istreambuf_iterator<char>());
    return true;
}

bool sha256Bytes(const std::vector<unsigned char>& input,
                 std::string& outHex,
                 std::string& outError) {
    EVP_MD_CTX* rawCtx = EVP_MD_CTX_new();
    if (rawCtx == nullptr) {
        outError = "Could not allocate SHA-256 context.";
        return false;
    }
    EvpMdCtxPtr ctx(rawCtx, EVP_MD_CTX_free);

    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digestLength = 0;
    if (EVP_DigestInit_ex(ctx.get(), EVP_sha256(), nullptr) != 1 ||
        EVP_DigestUpdate(ctx.get(), input.data(), input.size()) != 1 ||
        EVP_DigestFinal_ex(ctx.get(), digest, &digestLength) != 1) {
        outError = "SHA-256 digest calculation failed.";
        return false;
    }

    outHex = hexString(digest, digestLength);
    return true;
}

}  // namespace

std::string secureHashHex(std::string_view text) {
    std::vector<unsigned char> input(text.begin(), text.end());
    std::string outHex;
    std::string error;
    if (!sha256Bytes(input, outHex, error)) {
        return "";
    }
    return outHex;
}

std::string secureDigestString(std::string_view text) {
    const std::string hex = secureHashHex(text);
    return hex.empty() ? "" : "sha256:" + hex;
}

bool secureFileDigest(const std::filesystem::path& path,
                      std::string& outDigest,
                      std::string& outError) {
    std::vector<unsigned char> bytes;
    if (!loadFileBytes(path, bytes, outError)) {
        return false;
    }

    std::string outHex;
    if (!sha256Bytes(bytes, outHex, outError)) {
        return false;
    }
    outDigest = "sha256:" + outHex;
    return true;
}

bool secureDirectoryDigest(const std::filesystem::path& root,
                           std::string& outDigest,
                           std::string& outError,
                           std::string_view excludedRelativePath) {
    std::error_code ec;
    if (!std::filesystem::exists(root, ec) || ec) {
        outError = "Could not read directory '" + root.string() + "'.";
        return false;
    }

    std::vector<std::filesystem::path> files;
    for (std::filesystem::recursive_directory_iterator it(root, ec), end;
         !ec && it != end; it.increment(ec)) {
        if (!it->is_regular_file(ec)) {
            continue;
        }
        const std::filesystem::path relative = it->path().lexically_relative(root);
        if (!excludedRelativePath.empty() &&
            relative.lexically_normal().generic_string() == excludedRelativePath) {
            continue;
        }
        files.push_back(it->path());
    }
    if (ec) {
        outError = "Could not enumerate files under '" + root.string() + "'.";
        return false;
    }

    std::sort(files.begin(), files.end());

    std::vector<unsigned char> seed;
    for (const auto& file : files) {
        const std::string relative = file.lexically_relative(root).generic_string();
        seed.insert(seed.end(), relative.begin(), relative.end());
        seed.push_back('\n');

        std::vector<unsigned char> bytes;
        if (!loadFileBytes(file, bytes, outError)) {
            return false;
        }
        seed.insert(seed.end(), bytes.begin(), bytes.end());
        seed.push_back('\n');
    }

    std::string outHex;
    if (!sha256Bytes(seed, outHex, outError)) {
        return false;
    }
    outDigest = "sha256:" + outHex;
    return true;
}

bool base64Encode(const std::vector<unsigned char>& input, std::string& outText) {
    outText.clear();
    if (input.empty()) {
        return true;
    }

    std::vector<unsigned char> encoded(4 * ((input.size() + 2) / 3) + 1, 0);
    const int length = EVP_EncodeBlock(encoded.data(), input.data(),
                                       static_cast<int>(input.size()));
    if (length < 0) {
        return false;
    }

    outText.assign(reinterpret_cast<const char*>(encoded.data()),
                   static_cast<size_t>(length));
    return true;
}

bool base64Decode(std::string_view text,
                  std::vector<unsigned char>& outBytes,
                  std::string& outError) {
    outBytes.clear();
    outError.clear();

    std::string compact;
    compact.reserve(text.size());
    for (unsigned char ch : text) {
        if (ch == '\n' || ch == '\r' || ch == '\t' || ch == ' ') {
            continue;
        }
        compact.push_back(static_cast<char>(ch));
    }

    if (compact.empty()) {
        return true;
    }
    if (compact.size() % 4 != 0) {
        outError = "Base64 input length must be a multiple of 4.";
        return false;
    }

    std::vector<unsigned char> decoded((compact.size() / 4) * 3 + 1, 0);
    const int length = EVP_DecodeBlock(decoded.data(),
                                       reinterpret_cast<const unsigned char*>(compact.data()),
                                       static_cast<int>(compact.size()));
    if (length < 0) {
        outError = "Invalid base64 input.";
        return false;
    }

    size_t outputLength = static_cast<size_t>(length);
    if (!compact.empty() && compact.back() == '=') {
        --outputLength;
    }
    if (compact.size() >= 2 && compact[compact.size() - 2] == '=') {
        --outputLength;
    }
    decoded.resize(outputLength);
    outBytes = std::move(decoded);
    return true;
}

bool signEd25519Message(std::string_view privateKeyDerBase64,
                        std::string_view message,
                        std::string& outSignatureBase64,
                        std::string& outError) {
    std::vector<unsigned char> privateKeyDer;
    if (!base64Decode(privateKeyDerBase64, privateKeyDer, outError)) {
        outError = "Invalid private key encoding: " + outError;
        return false;
    }

    const unsigned char* keyData = privateKeyDer.data();
    EVP_PKEY* rawKey = d2i_AutoPrivateKey(nullptr, &keyData,
                                          static_cast<long>(privateKeyDer.size()));
    if (rawKey == nullptr) {
        outError = "Could not parse Ed25519 private key.";
        return false;
    }
    EvpPkeyPtr key(rawKey, EVP_PKEY_free);
    if (EVP_PKEY_base_id(key.get()) != EVP_PKEY_ED25519) {
        outError = "Signing key must use the Ed25519 algorithm.";
        return false;
    }

    EVP_MD_CTX* rawCtx = EVP_MD_CTX_new();
    if (rawCtx == nullptr) {
        outError = "Could not allocate signing context.";
        return false;
    }
    EvpMdCtxPtr ctx(rawCtx, EVP_MD_CTX_free);

    if (EVP_DigestSignInit(ctx.get(), nullptr, nullptr, nullptr, key.get()) != 1) {
        outError = "Could not initialize Ed25519 signing.";
        return false;
    }

    size_t signatureLength = 0;
    if (EVP_DigestSign(ctx.get(), nullptr, &signatureLength,
                       reinterpret_cast<const unsigned char*>(message.data()),
                       message.size()) != 1) {
        outError = "Could not compute Ed25519 signature length.";
        return false;
    }

    std::vector<unsigned char> signature(signatureLength, 0);
    if (EVP_DigestSign(ctx.get(), signature.data(), &signatureLength,
                       reinterpret_cast<const unsigned char*>(message.data()),
                       message.size()) != 1) {
        outError = "Ed25519 signing failed.";
        return false;
    }
    signature.resize(signatureLength);

    if (!base64Encode(signature, outSignatureBase64)) {
        outError = "Could not base64-encode Ed25519 signature.";
        return false;
    }
    return true;
}

bool verifyEd25519Message(std::string_view publicKeyDerBase64,
                          std::string_view message,
                          std::string_view signatureBase64,
                          std::string& outError) {
    std::vector<unsigned char> publicKeyDer;
    if (!base64Decode(publicKeyDerBase64, publicKeyDer, outError)) {
        outError = "Invalid trusted key encoding: " + outError;
        return false;
    }

    std::vector<unsigned char> signature;
    if (!base64Decode(signatureBase64, signature, outError)) {
        outError = "Invalid signature encoding: " + outError;
        return false;
    }

    const unsigned char* keyData = publicKeyDer.data();
    EVP_PKEY* rawKey = d2i_PUBKEY(nullptr, &keyData,
                                  static_cast<long>(publicKeyDer.size()));
    if (rawKey == nullptr) {
        outError = "Could not parse Ed25519 public key.";
        return false;
    }
    EvpPkeyPtr key(rawKey, EVP_PKEY_free);
    if (EVP_PKEY_base_id(key.get()) != EVP_PKEY_ED25519) {
        outError = "Trusted key must use the Ed25519 algorithm.";
        return false;
    }

    EVP_MD_CTX* rawCtx = EVP_MD_CTX_new();
    if (rawCtx == nullptr) {
        outError = "Could not allocate verification context.";
        return false;
    }
    EvpMdCtxPtr ctx(rawCtx, EVP_MD_CTX_free);

    if (EVP_DigestVerifyInit(ctx.get(), nullptr, nullptr, nullptr, key.get()) != 1) {
        outError = "Could not initialize Ed25519 verification.";
        return false;
    }

    const int verified =
        EVP_DigestVerify(ctx.get(), signature.data(), signature.size(),
                         reinterpret_cast<const unsigned char*>(message.data()),
                         message.size());
    if (verified == 1) {
        return true;
    }

    outError = verified == 0 ? "Signature verification failed."
                             : "Ed25519 verification failed.";
    return false;
}
