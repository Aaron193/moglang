#pragma once

#include <string>
#include <string_view>

struct RemoteImportSpec {
    std::string importPath;
    std::string repoRoot;
    std::string subdir;
    std::string gitUrl;
};

bool resolveRemoteImport(std::string_view rawImportPath,
                         RemoteImportSpec& outSpec,
                         std::string& outError);
