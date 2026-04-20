#pragma once

#include <string>

struct DependencySpec {
    std::string alias;
    std::string packageId;
    std::string path;
    std::string version;
    std::string git;
    std::string gitRev;
    std::string gitTag;
    std::string gitBranch;
    std::string registry;
    bool workspace = false;
};
