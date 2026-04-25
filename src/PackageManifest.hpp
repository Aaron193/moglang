#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "DependencySpec.hpp"

struct SystemDependencySpec {
    std::string name;
    std::string version;
    bool required = true;
};

struct NativePackageManifestConfig {
    std::string entry;
    std::string build;
    std::vector<std::string> targets;
};

struct PackageManifest {
    std::string kind = "native";
    std::string importName;
    std::string packageNamespace;
    std::string packageName;
    std::string version;
    std::string license;
    bool publish = true;
    uint32_t abiVersion = 0;
    std::string mogRuntime;
    std::string author;
    std::vector<std::string> authors;
    std::string description;
    std::string repository;
    std::string homepage;
    std::string documentation;
    std::vector<std::string> keywords;
    std::string sourceEntry;
    std::string library;
    NativePackageManifestConfig native;
    std::vector<SystemDependencySpec> systemDependencies;
    std::vector<DependencySpec> dependencies;
    std::vector<DependencySpec> devDependencies;
    std::vector<DependencySpec> buildDependencies;
};

bool loadPackageManifest(const std::string& packageDir,
                         PackageManifest& outManifest,
                         std::string& outError);

bool validatePackageManifestForDistribution(const PackageManifest& manifest,
                                            std::string& outError);

bool validatePackageDirectory(const std::string& packageDir,
                              const std::string& repoRoot,
                              std::string& outError);
