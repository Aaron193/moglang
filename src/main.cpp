#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "ModuleResolver.hpp"
#include "NativePackageAPI.hpp"
#include "PackageManager.hpp"
#include "PackageManifest.hpp"
#include "PackageRegistry.hpp"
#include "RemoteImportResolver.hpp"
#include "VirtualMachine.hpp"

struct RuntimeOptions {
    bool trace = false;
    bool showReturn = false;
    bool disassemble = false;
    bool frontendTimings = false;
    bool frontendTimingsJson = false;
    InstallOptions installOptions;
    std::string sourceFile;
    std::vector<std::string> packagePaths;
};

struct AddCommandArgs {
    DependencySpec dependency;
    AddDependencyOptions options;
    std::string positional;
    bool explicitSource = false;
};

static std::string normalizePackageSpecifier(std::string rawSpecifier) {
    if (rawSpecifier.find(':') != std::string::npos) {
        return rawSpecifier;
    }
    const size_t slash = rawSpecifier.find('/');
    if (slash == std::string::npos) {
        return rawSpecifier;
    }
    return rawSpecifier.substr(0, slash) + ":" + rawSpecifier.substr(slash + 1);
}

static void splitPackageVersionSpecifier(const std::string& rawSpecifier,
                                         std::string& outPackageId,
                                         std::string& outVersion) {
    outPackageId.clear();
    outVersion.clear();
    const size_t at = rawSpecifier.rfind('@');
    std::string packageText = rawSpecifier;
    if (at != std::string::npos && at > 0) {
        packageText = rawSpecifier.substr(0, at);
        outVersion = rawSpecifier.substr(at + 1);
    }
    outPackageId = normalizePackageSpecifier(packageText);
}

static bool splitRemoteModuleVersionSpecifier(const std::string& rawSpecifier,
                                              std::string& outModule,
                                              std::string& outVersion) {
    outModule.clear();
    outVersion.clear();
    const size_t at = rawSpecifier.rfind('@');
    std::string moduleText = rawSpecifier;
    if (at != std::string::npos && at > 0 && at + 1 < rawSpecifier.size()) {
        moduleText = rawSpecifier.substr(0, at);
        outVersion = rawSpecifier.substr(at + 1);
    }

    RemoteImportSpec remote;
    std::string error;
    if (!resolveRemoteImport(moduleText, remote, error)) {
        return false;
    }
    outModule = remote.importPath;
    return true;
}

static void printUsage(const char* executable) {
    std::cout
        << "Usage: " << executable << " <command> [options]\n"
        << "Commands:\n"
        << "  version                Print runtime and native ABI versions\n"
        << "  init [name]            Create a project kelvra.toml in the current directory\n"
        << "  add <module[@tag]>     Add a package dependency and install it\n"
        << "  remove <alias>         Remove a dependency and install the updated graph\n"
        << "  install [flags]        Install dependencies using kelvra.lock when it is current\n"
        << "  update [flags]         Re-resolve dependencies and rewrite install metadata\n"
        << "  test [flags]           Run the root [scripts].test entry with dev dependencies\n"
        << "  build [flags]          Run the root [scripts].build entry with dev dependencies\n"
        << "  cache <subcommand>     Inspect package-manager cache and store locations\n"
        << "  login <registry> [--token <token>]\n"
        << "                         Store a hosted-registry bearer token\n"
        << "  logout <registry>      Remove a hosted-registry bearer token\n"
        << "  registry <subcommand>  Manage stored registry trust and credentials\n"
        << "  publish [options] [dir] Publish a package to a configured registry\n"
        << "  audit [--offline]      Check locked registry packages against advisories\n"
        << "  run [flags] <file>     Install dependencies if needed, then run a program\n"
        << "  validate-package <dir> Validate a package directory\n"
        << "Registry subcommands:\n"
        << "  list\n"
        << "  status <registry>\n"
        << "  trust <registry> (--key <key_id:base64> | --key-file <path> | --bootstrap | --refresh)\n"
        << "  untrust <registry> --key-id <key_id>\n"
        << "  login <registry> [--token <token>]\n"
        << "  logout <registry>\n"
        << "Cache subcommands:\n"
        << "  status\n"
        << "  path <user|project|registry|git>\n"
        << "  prune [--dry-run]\n"
        << "Flags for install/update/run:\n"
        << "  --locked --offline --prefer-prebuilt --no-native-build\n"
        << "  --target <triple> | --target=<triple>\n"
        << "  --cmake-toolchain <path> | --cmake-toolchain=<path>\n"
        << "Flags for test/build:\n"
        << "  --locked --offline --prefer-prebuilt --no-native-build\n"
        << "  --target <triple> | --target=<triple>\n"
        << "  --cmake-toolchain <path> | --cmake-toolchain=<path>\n"
        << "  --trace --show-return --disassemble --frontend-timings --frontend-timings-json\n"
        << "  --package-path <dir> | --package-path=<dir>\n"
        << "Flags for publish:\n"
        << "  --registry <alias> | --registry=<alias>\n"
        << "  --signing-key <path> | --signing-key=<path>\n"
        << "  --require-clean-git\n"
        << "  --tag <tag> | --tag=<tag>\n"
        << "  --target <triple> | --target=<triple>\n"
        << "  --native-artifact-dir <dir> | --native-artifact-dir=<dir>\n"
        << "Flags for add:\n"
        << "  kelvra add github.com/acme/math@v1.0.0\n"
        << "  --path <dir> | --git <url> | --workspace | --registry <alias>\n"
        << "  --alias <name> --package <namespace:name> --version <requirement>\n"
        << "  --rev <rev> | --tag <tag> | --branch <branch>\n"
        << "  --dev | --build\n"
        << "Additional flags for run:\n"
        << "  --trace --show-return --disassemble --frontend-timings --frontend-timings-json\n"
        << "  --package-path <dir> | --package-path=<dir>\n"
        << "Legacy mode is still supported: " << executable << " [flags] <file>\n";
}

static bool parseAddArgs(int argc, char** argv, int startIndex,
                         AddCommandArgs& args, std::string& outError) {
    outError.clear();
    args = AddCommandArgs{};

    for (int index = startIndex; index < argc; ++index) {
        const std::string arg = argv[index];
        auto requireValue =
            [&](const char* optionName, std::string& destination) -> bool {
                if (index + 1 >= argc) {
                    outError = std::string("Missing value for ") + optionName + ".";
                    return false;
                }
                destination = argv[++index];
                return true;
            };

        if (arg == "--path") {
            args.explicitSource = true;
            if (!requireValue("--path", args.dependency.path)) {
                return false;
            }
        } else if (arg.rfind("--path=", 0) == 0) {
            args.explicitSource = true;
            args.dependency.path = arg.substr(7);
        } else if (arg == "--git") {
            args.explicitSource = true;
            if (!requireValue("--git", args.dependency.git)) {
                return false;
            }
        } else if (arg.rfind("--git=", 0) == 0) {
            args.explicitSource = true;
            args.dependency.git = arg.substr(6);
        } else if (arg == "--registry") {
            args.explicitSource = true;
            if (!requireValue("--registry", args.dependency.registry)) {
                return false;
            }
        } else if (arg.rfind("--registry=", 0) == 0) {
            args.explicitSource = true;
            args.dependency.registry = arg.substr(11);
        } else if (arg == "--workspace") {
            args.explicitSource = true;
            args.dependency.workspace = true;
        } else if (arg == "--alias") {
            args.explicitSource = true;
            if (!requireValue("--alias", args.dependency.alias)) {
                return false;
            }
        } else if (arg.rfind("--alias=", 0) == 0) {
            args.explicitSource = true;
            args.dependency.alias = arg.substr(8);
        } else if (arg == "--package") {
            args.explicitSource = true;
            if (!requireValue("--package", args.dependency.packageId)) {
                return false;
            }
            args.dependency.packageId =
                normalizePackageSpecifier(args.dependency.packageId);
        } else if (arg.rfind("--package=", 0) == 0) {
            args.explicitSource = true;
            args.dependency.packageId = normalizePackageSpecifier(arg.substr(10));
        } else if (arg == "--version") {
            args.explicitSource = true;
            if (!requireValue("--version", args.dependency.version)) {
                return false;
            }
        } else if (arg.rfind("--version=", 0) == 0) {
            args.explicitSource = true;
            args.dependency.version = arg.substr(10);
        } else if (arg == "--rev") {
            args.explicitSource = true;
            if (!requireValue("--rev", args.dependency.gitRev)) {
                return false;
            }
        } else if (arg.rfind("--rev=", 0) == 0) {
            args.explicitSource = true;
            args.dependency.gitRev = arg.substr(6);
        } else if (arg == "--tag") {
            args.explicitSource = true;
            if (!requireValue("--tag", args.dependency.gitTag)) {
                return false;
            }
        } else if (arg.rfind("--tag=", 0) == 0) {
            args.explicitSource = true;
            args.dependency.gitTag = arg.substr(6);
        } else if (arg == "--branch") {
            args.explicitSource = true;
            if (!requireValue("--branch", args.dependency.gitBranch)) {
                return false;
            }
        } else if (arg.rfind("--branch=", 0) == 0) {
            args.explicitSource = true;
            args.dependency.gitBranch = arg.substr(9);
        } else if (arg == "--dev") {
            if (args.options.group == "build") {
                outError = "add accepts only one of --dev or --build.";
                return false;
            }
            args.options.group = "dev";
        } else if (arg == "--build") {
            if (args.options.group == "dev") {
                outError = "add accepts only one of --dev or --build.";
                return false;
            }
            args.options.group = "build";
        } else if (arg == "--help" || arg == "-h") {
            outError = "help";
            return false;
        } else if (!arg.empty() && arg[0] == '-') {
            outError = "Unknown option: " + arg;
            return false;
        } else if (args.positional.empty()) {
            args.positional = arg;
        } else {
            outError = "add accepts at most one package specifier.";
            return false;
        }
    }

    if (args.explicitSource && !args.positional.empty() &&
        args.dependency.packageId.empty() && args.dependency.module.empty()) {
        std::string module;
        std::string version;
        if (!args.dependency.path.empty()) {
            // The local manifest is authoritative for path dependencies.
            // Keep the positional specifier only as a user-facing label.
        } else if (args.dependency.workspace) {
            splitPackageVersionSpecifier(args.positional, args.dependency.packageId,
                                         args.dependency.version);
        } else if (splitRemoteModuleVersionSpecifier(args.positional, module, version)) {
            args.dependency.module = module;
            if (args.dependency.alias.empty()) {
                args.dependency.alias = module;
            }
            if (args.dependency.version.empty()) {
                args.dependency.version = version;
            }
        } else {
            splitPackageVersionSpecifier(args.positional, args.dependency.packageId,
                                         args.dependency.version);
        }
    }

    return true;
}

static bool parseRuntimeArgs(int argc, char** argv, int startIndex,
                             RuntimeOptions& options, std::string& outError) {
    outError.clear();
    std::vector<std::string> positional;

    for (int index = startIndex; index < argc; ++index) {
        std::string arg = argv[index];
        if (arg == "--trace") {
            options.trace = true;
        } else if (arg == "--show-return") {
            options.showReturn = true;
        } else if (arg == "--disassemble") {
            options.disassemble = true;
        } else if (arg == "--frontend-timings") {
            options.frontendTimings = true;
        } else if (arg == "--frontend-timings-json") {
            options.frontendTimingsJson = true;
        } else if (arg == "--locked") {
            options.installOptions.locked = true;
        } else if (arg == "--offline") {
            options.installOptions.offline = true;
        } else if (arg == "--prefer-prebuilt") {
            options.installOptions.preferPrebuilt = true;
        } else if (arg == "--no-native-build") {
            options.installOptions.noNativeBuild = true;
        } else if (arg == "--target") {
            if (index + 1 >= argc) {
                outError = "Missing value for --target.";
                return false;
            }
            options.installOptions.target = argv[++index];
        } else if (arg.rfind("--target=", 0) == 0) {
            options.installOptions.target = arg.substr(9);
        } else if (arg == "--cmake-toolchain") {
            if (index + 1 >= argc) {
                outError = "Missing value for --cmake-toolchain.";
                return false;
            }
            options.installOptions.cmakeToolchainFile = argv[++index];
        } else if (arg.rfind("--cmake-toolchain=", 0) == 0) {
            options.installOptions.cmakeToolchainFile = arg.substr(19);
        } else if (arg == "--package-path") {
            if (index + 1 >= argc) {
                outError = "Missing value for --package-path.";
                return false;
            }
            options.packagePaths.push_back(argv[++index]);
        } else if (arg.rfind("--package-path=", 0) == 0) {
            options.packagePaths.push_back(arg.substr(15));
        } else if (arg == "--help" || arg == "-h") {
            outError = "help";
            return false;
        } else if (!arg.empty() && arg[0] == '-') {
            outError = "Unknown option: " + arg;
            return false;
        } else {
            positional.push_back(arg);
        }
    }

    if (positional.size() > 1) {
        outError = "Expected at most one source file.";
        return false;
    }

    if (!positional.empty()) {
        options.sourceFile = positional[0];
    }

    return true;
}

static bool parseInstallArgs(int argc, char** argv, int startIndex,
                             InstallOptions& options, std::string& outError) {
    outError.clear();
    options = InstallOptions{};
    for (int index = startIndex; index < argc; ++index) {
        const std::string arg = argv[index];
        if (arg == "--locked") {
            options.locked = true;
        } else if (arg == "--offline") {
            options.offline = true;
        } else if (arg == "--prefer-prebuilt") {
            options.preferPrebuilt = true;
        } else if (arg == "--no-native-build") {
            options.noNativeBuild = true;
        } else if (arg == "--target") {
            if (index + 1 >= argc) {
                outError = "Missing value for --target.";
                return false;
            }
            options.target = argv[++index];
        } else if (arg.rfind("--target=", 0) == 0) {
            options.target = arg.substr(9);
        } else if (arg == "--cmake-toolchain") {
            if (index + 1 >= argc) {
                outError = "Missing value for --cmake-toolchain.";
                return false;
            }
            options.cmakeToolchainFile = argv[++index];
        } else if (arg.rfind("--cmake-toolchain=", 0) == 0) {
            options.cmakeToolchainFile = arg.substr(19);
        } else if (arg == "--help" || arg == "-h") {
            outError = "help";
            return false;
        } else {
            outError = "Unknown option: " + arg;
            return false;
        }
    }

    return true;
}

static bool parsePublishArgs(int argc, char** argv, int startIndex,
                             PublishOptions& options,
                             std::string& outPackageDir,
                             std::string& outError) {
    outError.clear();
    outPackageDir.clear();
    options = PublishOptions{};

    for (int index = startIndex; index < argc; ++index) {
        const std::string arg = argv[index];
        if (arg == "--registry") {
            if (index + 1 >= argc) {
                outError = "Missing value for --registry.";
                return false;
            }
            options.registryAlias = argv[++index];
        } else if (arg.rfind("--registry=", 0) == 0) {
            options.registryAlias = arg.substr(11);
        } else if (arg == "--signing-key") {
            if (index + 1 >= argc) {
                outError = "Missing value for --signing-key.";
                return false;
            }
            options.signingKeyPath = argv[++index];
        } else if (arg.rfind("--signing-key=", 0) == 0) {
            options.signingKeyPath = arg.substr(14);
        } else if (arg == "--require-clean-git") {
            options.requireCleanGit = true;
        } else if (arg == "--tag") {
            if (index + 1 >= argc) {
                outError = "Missing value for --tag.";
                return false;
            }
            options.expectedTag = argv[++index];
        } else if (arg.rfind("--tag=", 0) == 0) {
            options.expectedTag = arg.substr(6);
        } else if (arg == "--target") {
            if (index + 1 >= argc) {
                outError = "Missing value for --target.";
                return false;
            }
            options.target = argv[++index];
        } else if (arg.rfind("--target=", 0) == 0) {
            options.target = arg.substr(9);
        } else if (arg == "--native-artifact-dir") {
            if (index + 1 >= argc) {
                outError = "Missing value for --native-artifact-dir.";
                return false;
            }
            options.nativeArtifactDir = argv[++index];
        } else if (arg.rfind("--native-artifact-dir=", 0) == 0) {
            options.nativeArtifactDir = arg.substr(22);
        } else if (arg == "--help" || arg == "-h") {
            outError = "help";
            return false;
        } else if (!arg.empty() && arg[0] == '-') {
            outError = "Unknown option: " + arg;
            return false;
        } else if (outPackageDir.empty()) {
            outPackageDir = arg;
        } else {
            outError = "publish accepts at most one package directory.";
            return false;
        }
    }

    return true;
}

static bool parseAuditArgs(int argc, char** argv, int startIndex,
                           AuditOptions& options, std::string& outError) {
    outError.clear();
    options = AuditOptions{};
    for (int index = startIndex; index < argc; ++index) {
        const std::string arg = argv[index];
        if (arg == "--offline") {
            options.offline = true;
        } else if (arg == "--help" || arg == "-h") {
            outError = "help";
            return false;
        } else {
            outError = "Unknown option: " + arg;
            return false;
        }
    }
    return true;
}

static bool parseLoginArgs(int argc, char** argv, int startIndex,
                           std::string& outRegistryAlias,
                           std::string& outToken,
                           std::string& outError) {
    outError.clear();
    outRegistryAlias.clear();
    outToken.clear();

    for (int index = startIndex; index < argc; ++index) {
        const std::string arg = argv[index];
        if (arg == "--token") {
            if (index + 1 >= argc) {
                outError = "Missing value for --token.";
                return false;
            }
            outToken = argv[++index];
        } else if (arg.rfind("--token=", 0) == 0) {
            outToken = arg.substr(8);
        } else if (arg == "--help" || arg == "-h") {
            outError = "help";
            return false;
        } else if (!arg.empty() && arg[0] == '-') {
            outError = "Unknown option: " + arg;
            return false;
        } else if (outRegistryAlias.empty()) {
            outRegistryAlias = arg;
        } else {
            outError = "login accepts exactly one registry alias.";
            return false;
        }
    }

    if (outRegistryAlias.empty()) {
        outError = "login requires a registry alias.";
        return false;
    }

    return true;
}

static std::string currentProjectRoot() {
    try {
        return std::filesystem::current_path().string();
    } catch (const std::exception&) {
        return ".";
    }
}

static std::string currentManagedProjectRoot() {
    std::string projectRoot;
    if (findProjectRootForPackages(currentProjectRoot(), projectRoot)) {
        return projectRoot;
    }
    return currentProjectRoot();
}

static std::string canonicalOrAbsolutePath(const std::filesystem::path& path) {
    std::error_code ec;
    const std::filesystem::path resolved =
        std::filesystem::weakly_canonical(path, ec);
    if (!ec) {
        return resolved.string();
    }

    const std::filesystem::path absolute = std::filesystem::absolute(path, ec);
    if (!ec) {
        return absolute.lexically_normal().string();
    }

    return path.lexically_normal().string();
}

static bool pathEscapesRoot(const std::filesystem::path& root,
                            const std::filesystem::path& candidate) {
    const std::filesystem::path relative = candidate.lexically_relative(root);
    if (relative.empty()) {
        return candidate != root;
    }
    const std::string relativeText = relative.generic_string();
    return relative.is_absolute() || relativeText == ".." ||
           relativeText.rfind("../", 0) == 0;
}

static bool resolveProjectScriptPath(const std::string& projectRoot,
                                     const std::string& rawScriptPath,
                                     std::filesystem::path& outScriptPath,
                                     std::string& outError) {
    outError.clear();
    outScriptPath.clear();

    if (rawScriptPath.empty()) {
        outError = "Project script path cannot be empty.";
        return false;
    }
    if (!hasSourceModuleExtension(rawScriptPath)) {
        outError = "Project script path must use the .kel extension.";
        return false;
    }

    const std::filesystem::path rootPath =
        canonicalOrAbsolutePath(projectRoot);
    const std::filesystem::path scriptPath =
        std::filesystem::path(rootPath) / std::filesystem::path(rawScriptPath);
    const std::filesystem::path resolvedPath =
        canonicalOrAbsolutePath(scriptPath);
    if (pathEscapesRoot(rootPath, resolvedPath)) {
        outError = "Project script must stay within the project root.";
        return false;
    }
    if (!std::filesystem::exists(resolvedPath)) {
        outError = "Configured script does not exist: " + rawScriptPath;
        return false;
    }
    if (!std::filesystem::is_regular_file(resolvedPath)) {
        outError = "Configured script is not a file: " + rawScriptPath;
        return false;
    }

    outScriptPath = resolvedPath;
    return true;
}

static size_t countFilesystemEntries(const std::filesystem::path& root) {
    std::error_code ec;
    if (!std::filesystem::exists(root, ec) || ec) {
        return 0;
    }

    size_t count = 0;
    std::filesystem::recursive_directory_iterator it(
        root, std::filesystem::directory_options::skip_permission_denied, ec);
    if (ec) {
        return 0;
    }

    for (const auto& entry : it) {
        (void)entry;
        ++count;
    }
    return count;
}

static void printCacheSummaryLine(const char* label,
                                  const std::string& pathText) {
    const std::filesystem::path path(pathText);
    const bool exists = std::filesystem::exists(path);
    std::cout << label << " = " << pathText << "\n";
    std::cout << label << "_exists = " << (exists ? "yes" : "no") << "\n";
    std::cout << label << "_entries = "
              << (exists ? countFilesystemEntries(path) : 0) << std::endl;
}

static std::string inferValidationRootForPackage(const std::string& packageDir) {
    PackageManifest manifest;
    std::string error;
    if (!loadPackageManifest(packageDir, manifest, error)) {
        return currentProjectRoot();
    }

    std::filesystem::path current;
    try {
        current = std::filesystem::weakly_canonical(packageDir);
    } catch (const std::exception&) {
        current = std::filesystem::path(packageDir);
    }

    while (!current.empty()) {
        const std::filesystem::path candidateLibrary =
            current / "build" / "packages" / manifest.packageNamespace /
            manifest.packageName /
#if defined(__APPLE__)
            "package.dylib";
#else
            "package.so";
#endif
        if (std::filesystem::exists(candidateLibrary)) {
            return current.string();
        }
        if (current == current.root_path()) {
            break;
        }
        current = current.parent_path();
    }

    return currentProjectRoot();
}

static int runValidatePackageDir(const std::string& packageDir) {
    std::string error;
    if (!validatePackageDirectory(packageDir,
                                  inferValidationRootForPackage(packageDir),
                                  error)) {
        std::cerr << "Package validation failed: " << error << std::endl;
        return 1;
    }

    std::cout << "Package validation passed: " << packageDir << std::endl;
    return 0;
}

static int runFile(const RuntimeOptions& options) {
    if (options.sourceFile.empty()) {
        std::cerr << "run requires a source file." << std::endl;
        return 1;
    }

    if (!hasSourceModuleExtension(options.sourceFile)) {
        std::cerr << "Error: Source files must use the " << kSourceModuleExtension
                  << " extension: " << options.sourceFile << std::endl;
        return 1;
    }

    std::ifstream file(options.sourceFile);
    if (!file) {
        std::cerr << "Error: Could not open source file " << options.sourceFile
                  << std::endl;
        return 1;
    }

    auto source =
        std::make_unique<std::string>((std::istreambuf_iterator<char>(file)),
                                      std::istreambuf_iterator<char>());
    file.close();

    std::string absolutePath;
    try {
        absolutePath =
            std::filesystem::weakly_canonical(options.sourceFile).string();
    } catch (const std::exception&) {
        absolutePath = options.sourceFile;
    }

    std::string projectRoot;
    if (findProjectRootForPackages(absolutePath, projectRoot)) {
        std::string installError;
        if (!ensureProjectPackagesInstalled(projectRoot, options.installOptions,
                                           installError)) {
            std::cerr << "Package install failed: " << installError << std::endl;
            return 1;
        }
    }

    VirtualMachine vm;
    vm.setPackageSearchPaths(options.packagePaths);
    Status status =
        vm.interpret(*source, options.showReturn, options.trace,
                     options.disassemble, absolutePath,
                     options.frontendTimings,
                     options.frontendTimingsJson);

    if (status == Status::COMPILATION_ERROR) {
        std::cerr << "Compilation error in source file: " << options.sourceFile
                  << std::endl;
        return 1;
    }
    if (status == Status::RUNTIME_ERROR) {
        std::cerr << "Runtime error in source file: " << options.sourceFile
                  << std::endl;
        return 1;
    }

    return 0;
}

static int runProjectScriptCommand(int argc, char** argv,
                                   const char* commandName) {
    RuntimeOptions options;
    try {
        std::filesystem::path executablePath = std::filesystem::weakly_canonical(argv[0]);
        options.packagePaths.push_back(
            (executablePath.parent_path() / "packages").string());
    } catch (const std::exception&) {
    }

    std::string parseError;
    if (!parseRuntimeArgs(argc, argv, 2, options, parseError)) {
        if (parseError == "help") {
            printUsage(argv[0]);
            return 0;
        }
        std::cerr << parseError << std::endl;
        printUsage(argv[0]);
        return 1;
    }
    if (!options.sourceFile.empty()) {
        std::cerr << commandName << " does not accept a source file." << std::endl;
        return 1;
    }

    const std::string projectRoot = currentManagedProjectRoot();
    ProjectManifestData manifest;
    if (!loadProjectManifestData(projectRoot, manifest, parseError)) {
        std::cerr << commandName << " failed: " << parseError << std::endl;
        return 1;
    }

    const std::string scriptPath =
        std::string(commandName) == "test" ? manifest.scripts.test
                                            : manifest.scripts.build;
    if (scriptPath.empty()) {
        std::cerr << commandName << " failed: kelvra.toml is missing [scripts]."
                  << commandName << std::endl;
        return 1;
    }

    std::filesystem::path resolvedScriptPath;
    if (!resolveProjectScriptPath(projectRoot, scriptPath, resolvedScriptPath,
                                  parseError)) {
        std::cerr << commandName << " failed: " << parseError << std::endl;
        return 1;
    }

    options.sourceFile = resolvedScriptPath.string();
    options.installOptions.includeDevDependencies = true;
    options.installOptions.includeBuildDependencies =
        std::string(commandName) == "build";
    return runFile(options);
}

static int runCacheCommand(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "cache requires a subcommand." << std::endl;
        return 1;
    }

    ProjectCachePaths paths;
    std::string error;
    if (!describeProjectCachePaths(currentManagedProjectRoot(), paths, error)) {
        std::cerr << "Cache command failed: " << error << std::endl;
        return 1;
    }

    const std::string subcommand = argv[2];
    if (subcommand == "status") {
        if (argc != 3) {
            std::cerr << "cache status does not accept extra arguments."
                      << std::endl;
            return 1;
        }

        printCacheSummaryLine("user_packages", paths.userPackages);
        printCacheSummaryLine("project_fallback_packages",
                              paths.projectFallbackPackages);
        printCacheSummaryLine("registry", paths.registry);
        printCacheSummaryLine("git", paths.git);
        return 0;
    }

    if (subcommand == "path") {
        if (argc != 4) {
            std::cerr << "cache path requires exactly one cache kind."
                      << std::endl;
            return 1;
        }

        const std::string kind = argv[3];
        if (kind == "user") {
            std::cout << paths.userPackages << std::endl;
            return 0;
        }
        if (kind == "project") {
            std::cout << paths.projectFallbackPackages << std::endl;
            return 0;
        }
        if (kind == "registry") {
            std::cout << paths.registry << std::endl;
            return 0;
        }
        if (kind == "git") {
            std::cout << paths.git << std::endl;
            return 0;
        }

        std::cerr << "Unknown cache path kind: " << kind << std::endl;
        return 1;
    }

    if (subcommand == "prune") {
        CachePruneOptions options;
        for (int index = 3; index < argc; ++index) {
            const std::string arg = argv[index];
            if (arg == "--dry-run") {
                options.dryRun = true;
                continue;
            }
            std::cerr << "Unknown cache prune option: " << arg << std::endl;
            return 1;
        }

        std::string report;
        if (!pruneProjectCaches(currentManagedProjectRoot(), options, report,
                                error)) {
            std::cerr << "Cache prune failed: " << error << std::endl;
            return 1;
        }
        std::cout << report << std::endl;
        return 0;
    }

    std::cerr << "Unknown cache subcommand: " << subcommand << std::endl;
    return 1;
}

static int runRepl(const RuntimeOptions& options) {
    VirtualMachine vm;
    vm.setPackageSearchPaths(options.packagePaths);
    std::string line;

    while (true) {
        std::cout << ">> " << std::flush;
        if (!std::getline(std::cin, line)) {
            std::cout << std::endl;
            break;
        }

        if (line == "exit" || line == "quit") {
            break;
        }

        if (line.empty()) {
            continue;
        }

        Status status = vm.interpret(line, options.showReturn, options.trace,
                                     options.disassemble, "",
                                     options.frontendTimings,
                                     options.frontendTimingsJson);
        if (status == Status::COMPILATION_ERROR) {
            std::cerr << "Compilation error." << std::endl;
            continue;
        }
        if (status == Status::RUNTIME_ERROR) {
            std::cerr << "Runtime error." << std::endl;
        }
    }

    return 0;
}

static int runInstallCommand(const std::string& projectRoot,
                             const InstallOptions& options) {
    std::vector<PackageRegistryEntry> entries;
    std::string error;
    if (!installProjectPackages(projectRoot, entries, options, error)) {
        std::cerr << "Install failed: " << error << std::endl;
        return 1;
    }

    std::cout << "Installed " << entries.size() << " package";
    if (entries.size() != 1) {
        std::cout << "s";
    }
    std::cout << " into " << (std::filesystem::path(projectRoot) / ".kelvra/install")
              << std::endl;
    return 0;
}

static int runInitCommand(int argc, char** argv) {
    std::string projectRoot = currentProjectRoot();
    std::filesystem::path manifestPath = std::filesystem::path(projectRoot) / "kelvra.toml";
    if (std::filesystem::exists(manifestPath)) {
        std::cerr << "kelvra.toml already exists in " << projectRoot << std::endl;
        return 1;
    }

    const std::string projectName =
        argc >= 3 ? argv[2] : std::filesystem::path(projectRoot).filename().string();
    std::string error;
    if (!initializeProjectManifest(projectRoot, projectName, error)) {
        std::cerr << "Init failed: " << error << std::endl;
        return 1;
    }

    std::cout << "Created " << manifestPath << std::endl;
    return 0;
}

static int runAddCommand(int argc, char** argv) {
    AddCommandArgs args;
    std::string parseError;
    if (!parseAddArgs(argc, argv, 2, args, parseError)) {
        if (parseError == "help") {
            printUsage(argv[0]);
            return 0;
        }
        std::cerr << "Add failed: " << parseError << std::endl;
        printUsage(argv[0]);
        return 1;
    }
    if (args.positional.empty() && !args.explicitSource) {
        std::cerr << "add requires a package specifier." << std::endl;
        return 1;
    }

    const std::string projectRoot = currentManagedProjectRoot();
    DependencySpec dependency;
    std::string error;
    if (args.explicitSource) {
        dependency = args.dependency;
        if (!completeExplicitDependencySpec(projectRoot, dependency, error)) {
            std::cerr << "Add failed: " << error << std::endl;
            return 1;
        }
        if (!args.dependency.path.empty() && !args.positional.empty()) {
            std::string requestedModule;
            std::string ignoredVersion;
            bool matches = splitRemoteModuleVersionSpecifier(args.positional, requestedModule, ignoredVersion) &&
                           requestedModule == dependency.module;
            if (!matches) {
                std::string requestedPackageId;
                splitPackageVersionSpecifier(args.positional, requestedPackageId, ignoredVersion);
                matches = requestedPackageId == dependency.packageId ||
                          args.positional == dependency.packageId ||
                          args.positional == dependency.alias;
            }
            if (!matches) {
                std::cerr << "Add failed: Local path dependency '" << args.dependency.path
                          << "' resolves to '" << dependency.packageId
                          << "' (module '" << dependency.module
                          << "'), not positional specifier '" << args.positional << "'." << std::endl;
                return 1;
            }
        }
    } else {
        if (!discoverDependencySpec(projectRoot, args.positional, dependency,
                                    error)) {
            std::cerr << "Add failed: " << error << std::endl;
            return 1;
        }
    }

    if (!addProjectDependency(projectRoot, dependency, args.options, error)) {
        std::cerr << "Add failed: " << error << std::endl;
        return 1;
    }

    std::vector<PackageRegistryEntry> installedEntries;
    InstallOptions installOptions;
    installOptions.includeDevDependencies = true;
    installOptions.includeBuildDependencies = true;
    if (!installProjectPackages(projectRoot, installedEntries, installOptions,
                                error)) {
        std::cerr << "Add failed during install: " << error << std::endl;
        return 1;
    }

    if (!dependency.path.empty()) {
        std::cout << "Added dependency '" << dependency.alias << "' from "
                  << dependency.path << std::endl;
    } else if (!dependency.git.empty()) {
        std::cout << "Added dependency '" << dependency.alias << "' from "
                  << dependency.git << std::endl;
    } else {
        std::cout << "Added dependency '" << dependency.alias << "' as "
                  << dependency.packageId;
        if (!dependency.version.empty()) {
            std::cout << "@" << dependency.version;
        }
        std::cout << std::endl;
    }
    return 0;
}

static int runRemoveCommand(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "remove requires a dependency alias." << std::endl;
        return 1;
    }
    if (argc > 3) {
        std::cerr << "remove accepts exactly one dependency alias." << std::endl;
        return 1;
    }

    const std::string projectRoot = currentManagedProjectRoot();
    std::string error;
    if (!removeProjectDependency(projectRoot, argv[2], error)) {
        std::cerr << "Remove failed: " << error << std::endl;
        return 1;
    }

    InstallOptions installOptions;
    installOptions.includeDevDependencies = true;
    installOptions.includeBuildDependencies = true;
    installOptions.update = true;
    std::vector<PackageRegistryEntry> installedEntries;
    if (!installProjectPackages(projectRoot, installedEntries, installOptions,
                                error)) {
        std::cerr << "Remove failed during install: " << error << std::endl;
        return 1;
    }

    std::cout << "Removed dependency '" << argv[2] << "'" << std::endl;
    return 0;
}

static int runPublishCommand(int argc, char** argv) {
    PublishOptions options;
    std::string packageDir;
    std::string parseError;
    if (!parsePublishArgs(argc, argv, 2, options, packageDir, parseError)) {
        if (parseError == "help") {
            printUsage(argv[0]);
            return 0;
        }
        std::cerr << parseError << std::endl;
        printUsage(argv[0]);
        return 1;
    }

    if (packageDir.empty()) {
        packageDir = currentProjectRoot();
    }

    std::string error;
    if (!publishProjectPackage(currentManagedProjectRoot(), packageDir, options,
                               error)) {
        std::cerr << "Publish failed: " << error << std::endl;
        return 1;
    }

    std::cout << "Published package from " << packageDir << std::endl;
    return 0;
}

static int runAuditCommand(int argc, char** argv) {
    AuditOptions options;
    std::string parseError;
    if (!parseAuditArgs(argc, argv, 2, options, parseError)) {
        if (parseError == "help") {
            printUsage(argv[0]);
            return 0;
        }
        std::cerr << parseError << std::endl;
        printUsage(argv[0]);
        return 1;
    }

    std::string report;
    bool hasFindings = false;
    std::string error;
    if (!auditProjectPackages(currentManagedProjectRoot(), options, report,
                              hasFindings, error)) {
        std::cerr << "Audit failed: " << error << std::endl;
        return 1;
    }

    if (!report.empty()) {
        std::cout << report << std::endl;
    }
    return hasFindings ? 1 : 0;
}

static int runLoginCommand(int argc, char** argv) {
    std::string registryAlias;
    std::string token;
    std::string parseError;
    if (!parseLoginArgs(argc, argv, 2, registryAlias, token, parseError)) {
        if (parseError == "help") {
            printUsage(argv[0]);
            return 0;
        }
        std::cerr << parseError << std::endl;
        printUsage(argv[0]);
        return 1;
    }

    if (token.empty()) {
        if (!std::getline(std::cin, token)) {
            std::cerr << "login requires a token via --token or stdin." << std::endl;
            return 1;
        }
    }

    std::string error;
    if (!loginProjectRegistry(currentManagedProjectRoot(), registryAlias, token,
                              error)) {
        std::cerr << "Login failed: " << error << std::endl;
        return 1;
    }

    std::cout << "Stored token for registry '" << registryAlias << "'" << std::endl;
    return 0;
}

static int runLogoutCommand(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "logout requires a registry alias." << std::endl;
        return 1;
    }

    std::string error;
    if (!logoutProjectRegistry(currentManagedProjectRoot(), argv[2], error)) {
        std::cerr << "Logout failed: " << error << std::endl;
        return 1;
    }

    std::cout << "Removed token for registry '" << argv[2] << "'" << std::endl;
    return 0;
}

static std::string joinStrings(const std::vector<std::string>& values) {
    std::ostringstream out;
    for (size_t index = 0; index < values.size(); ++index) {
        if (index > 0) {
            out << ", ";
        }
        out << values[index];
    }
    return out.str();
}

static int runRegistryCommand(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "registry requires a subcommand." << std::endl;
        return 1;
    }

    const std::string subcommand = argv[2];
    if (subcommand == "list") {
        if (argc != 3) {
            std::cerr << "registry list does not accept extra arguments." << std::endl;
            return 1;
        }

        std::vector<StoredRegistryProfile> profiles;
        std::string error;
        if (!listStoredRegistries(profiles, error)) {
            std::cerr << "Registry list failed: " << error << std::endl;
            return 1;
        }
        if (profiles.empty()) {
            std::cout << "No stored registries." << std::endl;
            return 0;
        }

        for (size_t index = 0; index < profiles.size(); ++index) {
            const auto& profile = profiles[index];
            if (index > 0) {
                std::cout << std::endl;
            }
            std::cout << "index = " << profile.index << std::endl;
            std::cout << "kind = " << (profile.isRemote ? "hosted" : "local")
                      << std::endl;
            std::cout << "trusted_key_ids = "
                      << (profile.trustedKeyIds.empty()
                              ? "(none)"
                              : joinStrings(profile.trustedKeyIds))
                      << std::endl;
            std::cout << "token = " << (profile.hasToken ? "yes" : "no")
                      << std::endl;
        }
        return 0;
    }

    if (subcommand == "status") {
        if (argc != 4) {
            std::cerr << "registry status requires exactly one registry alias."
                      << std::endl;
            return 1;
        }

        ProjectRegistryStatus status;
        std::string error;
        if (!describeProjectRegistry(currentManagedProjectRoot(), argv[3], status,
                                     error)) {
            std::cerr << "Registry status failed: " << error << std::endl;
            return 1;
        }

        std::string trust = "none";
        if (status.trustFromProject && status.trustFromUser) {
            trust = "project+user";
        } else if (status.trustFromProject) {
            trust = "project";
        } else if (status.trustFromUser) {
            trust = "user";
        }

        std::cout << "alias = " << status.alias << std::endl;
        std::cout << "index = " << status.index << std::endl;
        std::cout << "kind = " << (status.isRemote ? "hosted" : "local")
                  << std::endl;
        std::cout << "trust = " << trust << std::endl;
        std::cout << "trusted_key_ids = "
                  << (status.trustedKeyIds.empty()
                          ? "(none)"
                          : joinStrings(status.trustedKeyIds))
                  << std::endl;
        std::cout << "token = " << (status.hasToken ? "yes" : "no") << std::endl;
        return 0;
    }

    if (subcommand == "trust") {
        std::string registryAlias;
        std::string keySpec;
        std::string keyFilePath;
        bool bootstrap = false;
        bool refresh = false;
        for (int index = 3; index < argc; ++index) {
            const std::string arg = argv[index];
            if (arg == "--key") {
                if (index + 1 >= argc) {
                    std::cerr << "Missing value for --key." << std::endl;
                    return 1;
                }
                keySpec = argv[++index];
            } else if (arg.rfind("--key=", 0) == 0) {
                keySpec = arg.substr(6);
            } else if (arg == "--key-file") {
                if (index + 1 >= argc) {
                    std::cerr << "Missing value for --key-file." << std::endl;
                    return 1;
                }
                keyFilePath = argv[++index];
            } else if (arg.rfind("--key-file=", 0) == 0) {
                keyFilePath = arg.substr(11);
            } else if (arg == "--bootstrap") {
                bootstrap = true;
            } else if (arg == "--refresh") {
                refresh = true;
            } else if (!arg.empty() && arg[0] == '-') {
                std::cerr << "Unknown option: " << arg << std::endl;
                return 1;
            } else if (registryAlias.empty()) {
                registryAlias = arg;
            } else {
                std::cerr << "registry trust accepts exactly one registry alias."
                          << std::endl;
                return 1;
            }
        }

        RegistryTrustResult result;
        std::string error;
        if (!trustProjectRegistry(currentManagedProjectRoot(), registryAlias, keySpec,
                                  keyFilePath, bootstrap, refresh, result,
                                  error)) {
            std::cerr << "Registry trust failed: " << error << std::endl;
            return 1;
        }

        if (refresh) {
            std::cout << "Refreshed trust for registry '" << registryAlias << "'"
                      << std::endl;
            std::cout << "trusted_key_ids = "
                      << (result.trustedKeyIds.empty()
                              ? std::string("none")
                              : joinStrings(result.trustedKeyIds))
                      << std::endl;
            std::cout << "added_key_ids = "
                      << (result.addedKeyIds.empty()
                              ? std::string("none")
                              : joinStrings(result.addedKeyIds))
                      << std::endl;
            std::cout << "removed_key_ids = "
                      << (result.removedKeyIds.empty()
                              ? std::string("none")
                              : joinStrings(result.removedKeyIds))
                      << std::endl;
            std::cout << "revoked_key_ids = "
                      << (result.revokedKeyIds.empty()
                              ? std::string("none")
                              : joinStrings(result.revokedKeyIds))
                      << std::endl;
        } else {
            const std::string trustedKeyId =
                !result.addedKeyIds.empty()
                    ? result.addedKeyIds.front()
                    : (!result.trustedKeyIds.empty() ? result.trustedKeyIds.back()
                                                     : std::string("unknown"));
            std::cout << "Trusted key '" << trustedKeyId
                      << "' for registry '" << registryAlias << "'"
                      << std::endl;
        }
        return 0;
    }

    if (subcommand == "untrust") {
        std::string registryAlias;
        std::string keyId;
        for (int index = 3; index < argc; ++index) {
            const std::string arg = argv[index];
            if (arg == "--key-id") {
                if (index + 1 >= argc) {
                    std::cerr << "Missing value for --key-id." << std::endl;
                    return 1;
                }
                keyId = argv[++index];
            } else if (arg.rfind("--key-id=", 0) == 0) {
                keyId = arg.substr(9);
            } else if (!arg.empty() && arg[0] == '-') {
                std::cerr << "Unknown option: " << arg << std::endl;
                return 1;
            } else if (registryAlias.empty()) {
                registryAlias = arg;
            } else {
                std::cerr << "registry untrust accepts exactly one registry alias."
                          << std::endl;
                return 1;
            }
        }

        bool removed = false;
        std::string error;
        if (!untrustProjectRegistry(currentManagedProjectRoot(), registryAlias,
                                    keyId, removed, error)) {
            std::cerr << "Registry untrust failed: " << error << std::endl;
            return 1;
        }

        if (removed) {
            std::cout << "Removed key '" << keyId << "' from registry '"
                      << registryAlias << "'" << std::endl;
        } else {
            std::cout << "Registry '" << registryAlias
                      << "' did not have stored key '" << keyId << "'"
                      << std::endl;
        }
        return 0;
    }

    if (subcommand == "login") {
        std::string registryAlias;
        std::string token;
        std::string parseError;
        if (!parseLoginArgs(argc, argv, 3, registryAlias, token, parseError)) {
            std::cerr << parseError << std::endl;
            return 1;
        }
        if (token.empty()) {
            if (!std::getline(std::cin, token)) {
                std::cerr << "registry login requires a token via --token or stdin."
                          << std::endl;
                return 1;
            }
        }

        std::string error;
        if (!loginProjectRegistry(currentManagedProjectRoot(), registryAlias, token,
                                  error)) {
            std::cerr << "Registry login failed: " << error << std::endl;
            return 1;
        }

        std::cout << "Stored token for registry '" << registryAlias << "'"
                  << std::endl;
        return 0;
    }

    if (subcommand == "logout") {
        if (argc != 4) {
            std::cerr << "registry logout requires exactly one registry alias."
                      << std::endl;
            return 1;
        }
        std::string error;
        if (!logoutProjectRegistry(currentManagedProjectRoot(), argv[3], error)) {
            std::cerr << "Registry logout failed: " << error << std::endl;
            return 1;
        }

        std::cout << "Removed token for registry '" << argv[3] << "'" << std::endl;
        return 0;
    }

    std::cerr << "Unknown registry subcommand: " << subcommand << std::endl;
    return 1;
}

int main(int argc, char** argv) {
    RuntimeOptions runtimeOptions;
    try {
        std::filesystem::path executablePath = std::filesystem::weakly_canonical(argv[0]);
        runtimeOptions.packagePaths.push_back(
            (executablePath.parent_path() / "packages").string());
    } catch (const std::exception&) {
    }

    if (argc <= 1) {
        return runRepl(runtimeOptions);
    }

    const std::string command = argv[1];

    if (command == "--version" || command == "-V" || command == "version") {
        if (argc != 2) {
            std::cerr << command << " does not accept arguments." << std::endl;
            return 1;
        }
        std::cout << "kelvra " << KELVRA_RUNTIME_VERSION << " (native ABI "
                  << EXPR_NATIVE_PACKAGE_ABI_VERSION << ")" << std::endl;
        return 0;
    }
    if (command == "--validate-package") {
        if (argc < 3) {
            std::cerr << "Missing value for --validate-package." << std::endl;
            return 1;
        }
        return runValidatePackageDir(argv[2]);
    }
    if (command.rfind("--validate-package=", 0) == 0) {
        return runValidatePackageDir(command.substr(19));
    }
    if (command == "--help" || command == "-h") {
        printUsage(argv[0]);
        return 0;
    }
    if (command == "init") {
        return runInitCommand(argc, argv);
    }
    if (command == "add") {
        return runAddCommand(argc, argv);
    }
    if (command == "remove") {
        return runRemoveCommand(argc, argv);
    }
    if (command == "install" || command == "update") {
        InstallOptions installOptions;
        std::string parseError;
        if (!parseInstallArgs(argc, argv, 2, installOptions, parseError)) {
            if (parseError == "help") {
                printUsage(argv[0]);
                return 0;
            }
            std::cerr << parseError << std::endl;
            printUsage(argv[0]);
            return 1;
        }
        installOptions.update = command == "update";
        installOptions.includeDevDependencies = true;
        installOptions.includeBuildDependencies = true;
        return runInstallCommand(currentManagedProjectRoot(), installOptions);
    }
    if (command == "test" || command == "build") {
        return runProjectScriptCommand(argc, argv, command.c_str());
    }
    if (command == "cache") {
        return runCacheCommand(argc, argv);
    }
    if (command == "publish") {
        return runPublishCommand(argc, argv);
    }
    if (command == "registry") {
        return runRegistryCommand(argc, argv);
    }
    if (command == "audit") {
        return runAuditCommand(argc, argv);
    }
    if (command == "login") {
        return runLoginCommand(argc, argv);
    }
    if (command == "logout") {
        return runLogoutCommand(argc, argv);
    }
    if (command == "validate-package") {
        if (argc < 3) {
            std::cerr << "validate-package requires a directory." << std::endl;
            return 1;
        }
        return runValidatePackageDir(argv[2]);
    }
    if (command == "run") {
        std::string parseError;
        if (!parseRuntimeArgs(argc, argv, 2, runtimeOptions, parseError)) {
            if (parseError == "help") {
                printUsage(argv[0]);
                return 0;
            }
            std::cerr << parseError << std::endl;
            printUsage(argv[0]);
            return 1;
        }
        runtimeOptions.installOptions.includeDevDependencies = false;
        runtimeOptions.installOptions.includeBuildDependencies = false;
        return runtimeOptions.sourceFile.empty() ? runRepl(runtimeOptions)
                                                 : runFile(runtimeOptions);
    }

    std::string parseError;
    if (!parseRuntimeArgs(argc, argv, 1, runtimeOptions, parseError)) {
        if (parseError == "help") {
            printUsage(argv[0]);
            return 0;
        }
        std::cerr << parseError << std::endl;
        printUsage(argv[0]);
        return 1;
    }

    return runtimeOptions.sourceFile.empty() ? runRepl(runtimeOptions)
                                             : runFile(runtimeOptions);
}
