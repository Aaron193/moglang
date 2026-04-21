#pragma once

#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

std::string secureHashHex(std::string_view text);
std::string secureDigestString(std::string_view text);

bool secureFileDigest(const std::filesystem::path& path,
                      std::string& outDigest,
                      std::string& outError);

bool secureDirectoryDigest(const std::filesystem::path& root,
                           std::string& outDigest,
                           std::string& outError,
                           std::string_view excludedRelativePath = "");

bool base64Encode(const std::vector<unsigned char>& input, std::string& outText);

bool base64Decode(std::string_view text,
                  std::vector<unsigned char>& outBytes,
                  std::string& outError);

bool signEd25519Message(std::string_view privateKeyDerBase64,
                        std::string_view message,
                        std::string& outSignatureBase64,
                        std::string& outError);

bool verifyEd25519Message(std::string_view publicKeyDerBase64,
                          std::string_view message,
                          std::string_view signatureBase64,
                          std::string& outError);
