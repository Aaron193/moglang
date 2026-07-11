#pragma once

#include <string>

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#ifdef OPTIONAL
#undef OPTIONAL
#endif
#ifdef ERROR
#undef ERROR
#endif
#else
#include <dlfcn.h>
#endif

inline std::string dynamicLibraryError() {
#if defined(_WIN32)
    return "Windows error " + std::to_string(GetLastError());
#else
    const char* error = dlerror();
    return error == nullptr ? "unknown dynamic library error" : error;
#endif
}

inline void* openDynamicLibrary(const std::string& path) {
#if defined(_WIN32)
    return reinterpret_cast<void*>(LoadLibraryA(path.c_str()));
#else
    dlerror();
    return dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
#endif
}

inline void* findDynamicLibrarySymbol(void* handle, const char* symbol) {
#if defined(_WIN32)
    return reinterpret_cast<void*>(
        GetProcAddress(reinterpret_cast<HMODULE>(handle), symbol));
#else
    dlerror();
    return dlsym(handle, symbol);
#endif
}

inline void closeDynamicLibrary(void* handle) {
    if (handle == nullptr) {
        return;
    }

#if defined(_WIN32)
    FreeLibrary(reinterpret_cast<HMODULE>(handle));
#else
    dlclose(handle);
#endif
}
