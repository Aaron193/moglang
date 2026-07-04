#include "ModuleResolver.hpp"

#include <cctype>
#include <filesystem>

#include "RemoteImportResolver.hpp"

namespace {

bool startsWith(std::string_view text, std::string_view prefix) {
    return text.size() >= prefix.size() && text.substr(0, prefix.size()) == prefix;
}

bool isValidBareAlias(std::string_view text) {
    if (text.empty()) {
        return false;
    }
    for (char ch : text) {
        if (!(std::islower(static_cast<unsigned char>(ch)) ||
              std::isdigit(static_cast<unsigned char>(ch)) || ch == '_' ||
              ch == '-')) {
            return false;
        }
    }
    return true;
}

}  // namespace

bool hasSourceModuleExtension(const std::string& pathText) {
    if (pathText.empty()) {
        return false;
    }

    return std::filesystem::path(pathText).extension().string() ==
           kSourceModuleExtension;
}

ImportSpecifierKind classifyImportSpecifier(std::string_view rawImportPath) {
    if (rawImportPath.empty()) {
        return ImportSpecifierKind::Invalid;
    }

    if (startsWith(rawImportPath, "./") || startsWith(rawImportPath, "../") ||
        startsWith(rawImportPath, "/")) {
        return ImportSpecifierKind::LocalSource;
    }
    if (startsWith(rawImportPath, "std/")) {
        return ImportSpecifierKind::StandardPackage;
    }

    RemoteImportSpec remoteSpec;
    std::string remoteError;
    if (resolveRemoteImport(rawImportPath, remoteSpec, remoteError)) {
        return ImportSpecifierKind::RemoteModule;
    }

    if (isValidBareAlias(rawImportPath)) {
        return ImportSpecifierKind::InstalledAlias;
    }
    return ImportSpecifierKind::Invalid;
}

std::string resolveImportPath(const std::string& importerPath,
                              const std::string& rawImportPath) {
    if (rawImportPath.empty() || !hasSourceModuleExtension(rawImportPath)) {
        return "";
    }

    std::error_code ec;
    std::filesystem::path importPath(rawImportPath);
    std::filesystem::path candidate;

    if (importPath.is_absolute()) {
        candidate = importPath;
    } else {
        if (importerPath.empty()) {
            return "";
        }

        std::filesystem::path importer(importerPath);
        candidate = importer.parent_path() / importPath;
    }

    std::filesystem::path resolved =
        std::filesystem::weakly_canonical(candidate, ec);
    if (ec) {
        return "";
    }

    if (!std::filesystem::exists(resolved, ec) || ec) {
        return "";
    }

    std::string resolvedPath = resolved.string();
    if (!hasSourceModuleExtension(resolvedPath)) {
        return "";
    }

    return resolvedPath;
}
