#pragma once

#include <string>
#include <string_view>

inline constexpr std::string_view kSourceModuleExtension = ".kel";

enum class ImportSpecifierKind {
    LocalSource,
    StandardPackage,
    InstalledAlias,
    RemoteModule,
    Invalid,
};

bool hasSourceModuleExtension(const std::string& pathText);

ImportSpecifierKind classifyImportSpecifier(std::string_view rawImportPath);

std::string resolveImportPath(const std::string& importerPath,
                              const std::string& rawImportPath);
