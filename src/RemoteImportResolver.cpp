#include "RemoteImportResolver.hpp"

#include <cctype>
#include <string>
#include <string_view>
#include <vector>

namespace {

std::string trim(std::string_view text) {
    size_t start = 0;
    while (start < text.size() &&
           std::isspace(static_cast<unsigned char>(text[start]))) {
        ++start;
    }

    size_t end = text.size();
    while (end > start &&
           std::isspace(static_cast<unsigned char>(text[end - 1]))) {
        --end;
    }

    return std::string(text.substr(start, end - start));
}

bool startsWith(std::string_view text, std::string_view prefix) {
    return text.size() >= prefix.size() && text.substr(0, prefix.size()) == prefix;
}

bool isKnownHost(std::string_view host) {
    return host == "github.com" || host == "gitlab.com" ||
           host == "codeberg.org" || host == "bitbucket.org";
}

std::vector<std::string> splitPath(std::string_view text) {
    std::vector<std::string> parts;
    size_t start = 0;
    while (start <= text.size()) {
        const size_t slash = text.find('/', start);
        const size_t end = slash == std::string_view::npos ? text.size() : slash;
        parts.emplace_back(text.substr(start, end - start));
        if (slash == std::string_view::npos) {
            break;
        }
        start = slash + 1;
    }
    return parts;
}

std::string joinParts(const std::vector<std::string>& parts, size_t begin,
                      size_t end) {
    std::string joined;
    for (size_t index = begin; index < end; ++index) {
        if (!joined.empty()) {
            joined.push_back('/');
        }
        joined += parts[index];
    }
    return joined;
}

bool hasUnsafeText(std::string_view text) {
    if (text.empty()) {
        return true;
    }
    for (char ch : text) {
        if (std::isspace(static_cast<unsigned char>(ch)) || ch == '\\' ||
            ch == '?' || ch == '#') {
            return true;
        }
    }
    return false;
}

bool validateParts(const std::vector<std::string>& parts, std::string& outError) {
    for (const auto& part : parts) {
        if (part.empty() || part == "." || part == "..") {
            outError = "Remote import paths must not contain empty, '.', or '..' segments.";
            return false;
        }
    }
    return true;
}

bool resolveKnownHostPath(const std::string& importPath,
                          RemoteImportSpec& outSpec,
                          std::string& outError) {
    std::vector<std::string> parts = splitPath(importPath);
    if (parts.size() < 3 || !isKnownHost(parts[0])) {
        return false;
    }
    if (!validateParts(parts, outError)) {
        return false;
    }

    outSpec.importPath = importPath;
    if (parts[2].size() > 4 &&
        parts[2].substr(parts[2].size() - 4) == ".git") {
        parts[2].resize(parts[2].size() - 4);
    }
    outSpec.repoRoot = joinParts(parts, 0, 3);
    outSpec.subdir = parts.size() > 3 ? joinParts(parts, 3, parts.size()) : "";
    outSpec.gitUrl = "https://" + outSpec.repoRoot + ".git";
    return true;
}

bool splitExplicitGitUrl(const std::string& importPath,
                         std::string_view prefix,
                         RemoteImportSpec& outSpec,
                         std::string& outError) {
    const size_t rootEnd = importPath.find(".git", prefix.size());
    if (rootEnd == std::string::npos) {
        outError = "Self-hosted remote imports must include a .git repository path.";
        return false;
    }

    const size_t gitEnd = rootEnd + 4;
    if (gitEnd < importPath.size() && importPath[gitEnd] != '/') {
        outError = "Remote import .git suffix must end the repository path.";
        return false;
    }

    const std::string gitUrl = importPath.substr(0, gitEnd);
    const std::string subdir =
        gitEnd < importPath.size() ? importPath.substr(gitEnd + 1) : "";
    if (!subdir.empty()) {
        const std::vector<std::string> subdirParts = splitPath(subdir);
        if (!validateParts(subdirParts, outError)) {
            return false;
        }
    }

    outSpec.importPath = importPath;
    outSpec.repoRoot = gitUrl;
    outSpec.subdir = subdir;
    outSpec.gitUrl = gitUrl;
    return true;
}

bool resolveHttpsOrSshUrl(const std::string& importPath,
                          RemoteImportSpec& outSpec,
                          std::string& outError) {
    const std::string_view httpsPrefix = "https://";
    const std::string_view sshPrefix = "ssh://";
    const std::string_view prefix =
        startsWith(importPath, httpsPrefix) ? httpsPrefix : sshPrefix;
    const size_t hostStart = prefix.size();
    const size_t hostEnd = importPath.find('/', hostStart);
    if (hostEnd == std::string::npos || hostEnd == hostStart) {
        outError = "Remote import URLs must include a host and repository path.";
        return false;
    }

    std::string host = importPath.substr(hostStart, hostEnd - hostStart);
    if (startsWith(host, "git@")) {
        host = host.substr(4);
    }
    if (isKnownHost(host)) {
        return resolveKnownHostPath(host + "/" + importPath.substr(hostEnd + 1),
                                    outSpec, outError);
    }

    return splitExplicitGitUrl(importPath, prefix, outSpec, outError);
}

bool resolveScpLikeUrl(const std::string& importPath,
                       RemoteImportSpec& outSpec,
                       std::string& outError) {
    const std::string_view prefix = "git@";
    const size_t colon = importPath.find(':', prefix.size());
    if (colon == std::string::npos || colon == prefix.size()) {
        outError = "SCP-style remote imports must use git@host:path/repo.git.";
        return false;
    }

    const std::string host = importPath.substr(prefix.size(), colon - prefix.size());
    if (isKnownHost(host)) {
        return resolveKnownHostPath(host + "/" + importPath.substr(colon + 1),
                                    outSpec, outError);
    }

    return splitExplicitGitUrl(importPath, prefix, outSpec, outError);
}

}  // namespace

bool resolveRemoteImport(std::string_view rawImportPath,
                         RemoteImportSpec& outSpec,
                         std::string& outError) {
    outSpec = RemoteImportSpec{};
    outError.clear();

    std::string importPath = trim(rawImportPath);
    while (!importPath.empty() && importPath.back() == '/') {
        importPath.pop_back();
    }
    if (hasUnsafeText(importPath)) {
        outError = "Remote import path contains unsupported characters.";
        return false;
    }

    if (startsWith(importPath, "https://") || startsWith(importPath, "ssh://")) {
        return resolveHttpsOrSshUrl(importPath, outSpec, outError);
    }
    if (startsWith(importPath, "git@")) {
        return resolveScpLikeUrl(importPath, outSpec, outError);
    }
    if (resolveKnownHostPath(importPath, outSpec, outError)) {
        return true;
    }
    if (outError.empty()) {
        outError = "Unsupported remote import host or URL form.";
    }
    return false;
}
