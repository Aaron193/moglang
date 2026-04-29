#pragma once

#include <string>
#include <utility>
#include <vector>

#include "DependencySpec.hpp"
#include "PackageRegistry.hpp"

struct ProjectRegistryConfig {
    std::string alias;
    std::string index;
    std::vector<std::string> trustedKeys;
    bool allowInsecure = false;
};

struct ProjectNativeToolchainConfig {
    std::string target;
    std::string cmakeToolchain;
    std::string generator;
    std::string buildType;
    std::vector<std::string> configureArgs;
    std::vector<std::string> buildArgs;
    std::vector<std::pair<std::string, std::string>> env;
};

struct ProjectPolicyConfig {
    std::vector<std::string> allowedRegistries;
    std::vector<std::string> allowedNativeNamespaces;
    bool requireLockedInCi = false;
    bool requireSignedArtifacts = false;
};

struct ProjectScriptConfig {
    std::string test;
    std::string build;
};

struct ProjectManifestData {
    std::string kind = "project";
    std::string name;
    std::string version = "0.1.0";
    std::string description;
    ProjectScriptConfig scripts;
    std::vector<std::string> workspaceMembers;
    ProjectPolicyConfig policy;
    std::vector<ProjectRegistryConfig> registries;
    std::vector<ProjectNativeToolchainConfig> nativeToolchains;
    std::vector<DependencySpec> dependencies;
    std::vector<DependencySpec> devDependencies;
    std::vector<DependencySpec> buildDependencies;
};

struct InstallOptions {
    bool locked = false;
    bool offline = false;
    bool preferPrebuilt = true;
    bool noNativeBuild = false;
    bool includeDevDependencies = false;
    bool includeBuildDependencies = false;
    bool update = false;
    std::string target;
    std::string cmakeToolchainFile;
};

struct AuditOptions {
    bool offline = false;
};

struct RegistryTrustResult {
    std::vector<std::string> trustedKeyIds;
    std::vector<std::string> revokedKeyIds;
    std::vector<std::string> addedKeyIds;
    std::vector<std::string> removedKeyIds;
};

struct PublishOptions {
    std::string registryAlias;
    std::string signingKeyPath;
    std::string target;
    std::string nativeArtifactDir;
    bool requireCleanGit = false;
    std::string expectedTag;
};

struct StoredRegistryProfile {
    std::string index;
    bool isRemote = false;
    bool hasToken = false;
    std::vector<std::string> trustedKeyIds;
};

struct ProjectRegistryStatus {
    std::string alias;
    std::string index;
    bool isRemote = false;
    bool hasToken = false;
    bool trustFromProject = false;
    bool trustFromUser = false;
    std::vector<std::string> trustedKeyIds;
};

struct ProjectCachePaths {
    std::string userPackages;
    std::string projectFallbackPackages;
    std::string registry;
    std::string git;
};

struct CachePruneOptions {
    bool dryRun = false;
};

bool loadProjectManifestData(const std::string& projectRoot,
                             ProjectManifestData& outManifest,
                             std::string& outError);

bool writeProjectManifestData(const std::string& projectRoot,
                              const ProjectManifestData& manifest,
                              std::string& outError);

bool initializeProjectManifest(const std::string& projectRoot,
                               const std::string& projectName,
                               std::string& outError);

bool discoverDependencySpec(const std::string& projectRoot,
                            const std::string& rawSpecifier,
                            DependencySpec& outDependency,
                            std::string& outError);

bool addProjectDependency(const std::string& projectRoot,
                          const DependencySpec& dependency,
                          std::string& outError);

bool removeProjectDependency(const std::string& projectRoot,
                             const std::string& alias,
                             std::string& outError);

bool publishProjectPackage(const std::string& projectRoot,
                           const std::string& packageDir,
                           const PublishOptions& options,
                           std::string& outError);

bool loginProjectRegistry(const std::string& projectRoot,
                          const std::string& registryAlias,
                          const std::string& token,
                          std::string& outError);

bool logoutProjectRegistry(const std::string& projectRoot,
                           const std::string& registryAlias,
                           std::string& outError);

bool listStoredRegistries(std::vector<StoredRegistryProfile>& outProfiles,
                          std::string& outError);

bool describeProjectRegistry(const std::string& projectRoot,
                             const std::string& registryAlias,
                             ProjectRegistryStatus& outStatus,
                             std::string& outError);

bool trustProjectRegistry(const std::string& projectRoot,
                          const std::string& registryAlias,
                          const std::string& keySpec,
                          const std::string& keyFilePath,
                          bool bootstrap,
                          bool refresh,
                          RegistryTrustResult& outResult,
                          std::string& outError);

bool untrustProjectRegistry(const std::string& projectRoot,
                            const std::string& registryAlias,
                            const std::string& keyId,
                            bool& outRemoved,
                            std::string& outError);

bool installProjectPackages(const std::string& projectRoot,
                            std::vector<PackageRegistryEntry>& outEntries,
                            const InstallOptions& options,
                            std::string& outError);

bool ensureProjectPackagesInstalled(const std::string& projectRoot,
                                    const InstallOptions& options,
                                    std::string& outError);

bool auditProjectPackages(const std::string& projectRoot,
                          const AuditOptions& options,
                          std::string& outReport,
                          bool& outHasFindings,
                          std::string& outError);

bool describeProjectCachePaths(const std::string& projectRoot,
                               ProjectCachePaths& outPaths,
                               std::string& outError);

bool pruneProjectCaches(const std::string& projectRoot,
                        const CachePruneOptions& options,
                        std::string& outReport,
                        std::string& outError);
