#include <cstdint>
#include <new>
#include <thread>

#include "NativePackageAPI.hpp"

namespace {

struct PersistentHandle {
    ExprHostApi host{};
    ExprPersistentValue* value = nullptr;
};

ExprPersistentValue* crossVmValue = nullptr;

void finalizePersistent(void* data) {
    auto* handle = static_cast<PersistentHandle*>(data);
    if (handle != nullptr) {
        if (handle->value != nullptr && handle->host.releaseValue != nullptr) {
            handle->host.releaseValue(handle->host.context, handle->value);
        }
        delete handle;
    }
}

void setError(ExprPackageStringView* outError, const char* text,
              size_t length) {
    if (outError != nullptr) *outError = {text, length};
}

bool requireHost(const ExprHostApi* host, ExprPackageStringView* outError) {
    if (host != nullptr && host->abi_version >= 2 &&
        host->struct_size >= sizeof(ExprHostApi) && host->context != nullptr &&
        host->retainValue != nullptr && host->releaseValue != nullptr &&
        host->getValue != nullptr && host->invokeValue != nullptr) {
        return true;
    }
    static const char message[] = "Host API v2 is required";
    setError(outError, message, sizeof(message) - 1);
    return false;
}

bool requireHandle(const ExprPackageValue& value, PersistentHandle*& out,
                   ExprPackageStringView* outError) {
    if (value.kind == EXPR_PACKAGE_VALUE_HANDLE &&
        value.as.handle_value.handle_data != nullptr) {
        out = static_cast<PersistentHandle*>(value.as.handle_value.handle_data);
        return true;
    }
    static const char message[] = "expected Persistent handle";
    setError(outError, message, sizeof(message) - 1);
    return false;
}

bool retain(const ExprHostApi* host, const ExprPackageValue* args, size_t argc,
            ExprPackageValue* outResult, ExprPackageStringView* outError) {
    if (!requireHost(host, outError) || args == nullptr || argc != 1 ||
        outResult == nullptr)
        return false;
    auto* handle = new (std::nothrow) PersistentHandle();
    if (handle == nullptr) return false;
    handle->host = *host;
    if (!host->retainValue(host->context, &args[0], &handle->value, outError)) {
        delete handle;
        return false;
    }
    outResult->kind = EXPR_PACKAGE_VALUE_HANDLE;
    outResult->as.handle_value = {"examples", "host_api", "PersistentHandle",
                                  handle, finalizePersistent};
    return true;
}

bool getAny(const ExprHostApi*, const ExprPackageValue* args, size_t argc,
            ExprPackageValue* outResult, ExprPackageStringView* outError) {
    PersistentHandle* handle = nullptr;
    if (args == nullptr || argc != 1 || outResult == nullptr ||
        !requireHandle(args[0], handle, outError))
        return false;
    return handle->host.getValue(handle->host.context, handle->value, outResult,
                                 outError);
}

bool invokeImpl(const ExprPackageValue* args, size_t argc,
                ExprPackageValue* outResult, ExprPackageStringView* outError,
                bool swallowError) {
    PersistentHandle* handle = nullptr;
    if (args == nullptr || argc != 2 || outResult == nullptr ||
        !requireHandle(args[0], handle, outError))
        return false;
    ExprPackageValue callbackResult{};
    ExprPackageStringView callbackError{};
    bool ok =
        handle->host.invokeValue(handle->host.context, handle->value, &args[1],
                                 1, &callbackResult, &callbackError);
    if (swallowError) {
        outResult->kind = EXPR_PACKAGE_VALUE_BOOL;
        outResult->as.boolean_value = ok;
        return true;
    }
    if (!ok) {
        if (outError != nullptr) *outError = callbackError;
        return false;
    }
    *outResult = callbackResult;
    return true;
}

bool invoke(const ExprHostApi*, const ExprPackageValue* args, size_t argc,
            ExprPackageValue* outResult, ExprPackageStringView* outError) {
    return invokeImpl(args, argc, outResult, outError, false);
}

bool tryInvoke(const ExprHostApi*, const ExprPackageValue* args, size_t argc,
               ExprPackageValue* outResult, ExprPackageStringView* outError) {
    return invokeImpl(args, argc, outResult, outError, true);
}

bool invokeBytes(const ExprHostApi* host, const ExprPackageValue* args,
                 size_t argc, ExprPackageValue* outResult,
                 ExprPackageStringView* outError) {
    if (!requireHost(host, outError) || args == nullptr || argc != 2 ||
        outResult == nullptr)
        return false;
    ExprPersistentValue* callback = nullptr;
    if (!host->retainValue(host->context, &args[0], &callback, outError)) {
        return false;
    }
    bool ok = host->invokeValue(host->context, callback, &args[1], 1, outResult,
                                outError);
    host->releaseValue(host->context, callback);
    return ok;
}

bool invokeHandle(const ExprHostApi* host, const ExprPackageValue* args,
                  size_t argc, ExprPackageValue* outResult,
                  ExprPackageStringView* outError) {
    return invokeBytes(host, args, argc, outResult, outError);
}

bool foreignThreadRejected(const ExprHostApi* host,
                           const ExprPackageValue* args, size_t argc,
                           ExprPackageValue* outResult,
                           ExprPackageStringView* outError) {
    if (!requireHost(host, outError) || args == nullptr || argc != 1 ||
        outResult == nullptr)
        return false;
    ExprHostApi copied = *host;
    ExprPackageValue value = args[0];
    bool retained = false;
    std::thread worker([&]() {
        ExprPersistentValue* persistent = nullptr;
        ExprPackageStringView error{};
        retained =
            copied.retainValue(copied.context, &value, &persistent, &error);
        if (retained) copied.releaseValue(copied.context, persistent);
    });
    worker.join();
    outResult->kind = EXPR_PACKAGE_VALUE_BOOL;
    outResult->as.boolean_value = !retained;
    return true;
}

bool stashForCrossVm(const ExprHostApi* host, const ExprPackageValue* args,
                     size_t argc, ExprPackageValue* outResult,
                     ExprPackageStringView* outError) {
    if (!requireHost(host, outError) || args == nullptr || argc != 1 ||
        outResult == nullptr)
        return false;
    if (!host->retainValue(host->context, &args[0], &crossVmValue, outError)) {
        return false;
    }
    outResult->kind = EXPR_PACKAGE_VALUE_BOOL;
    outResult->as.boolean_value = true;
    return true;
}

bool crossVmRejected(const ExprHostApi* host, const ExprPackageValue*,
                     size_t argc, ExprPackageValue* outResult,
                     ExprPackageStringView* outError) {
    if (!requireHost(host, outError) || argc != 0 || outResult == nullptr ||
        crossVmValue == nullptr)
        return false;
    ExprPackageValue borrowed{};
    ExprPackageStringView error{};
    bool retrieved =
        host->getValue(host->context, crossVmValue, &borrowed, &error);
    outResult->kind = EXPR_PACKAGE_VALUE_BOOL;
    outResult->as.boolean_value = !retrieved;
    return true;
}

bool release(const ExprHostApi*, const ExprPackageValue* args, size_t argc,
             ExprPackageValue* outResult, ExprPackageStringView* outError) {
    PersistentHandle* handle = nullptr;
    if (args == nullptr || argc != 1 || outResult == nullptr ||
        !requireHandle(args[0], handle, outError))
        return false;
    if (handle->value != nullptr) {
        handle->host.releaseValue(handle->host.context, handle->value);
        handle->value = nullptr;
    }
    outResult->kind = EXPR_PACKAGE_VALUE_NULL;
    return true;
}

constexpr ExprPackageFunctionExport functions[] = {
    {"retainCallable",
     "fn(fn(i64) -> i64) -> handle<examples:host_api:PersistentHandle>", 1,
     retain},
    {"retainAny", "fn(any) -> handle<examples:host_api:PersistentHandle>", 1,
     retain},
    {"getAny", "fn(handle<examples:host_api:PersistentHandle>) -> any", 1,
     getAny},
    {"invoke", "fn(handle<examples:host_api:PersistentHandle>, i64) -> i64", 2,
     invoke},
    {"tryInvoke", "fn(handle<examples:host_api:PersistentHandle>, i64) -> bool",
     2, tryInvoke},
    {"invokeBytes", "fn(fn(Array<u8>) -> Array<u8>, Array<u8>) -> Array<u8>", 2,
     invokeBytes},
    {"invokeHandle",
     "fn(fn(handle<examples:host_api:PersistentHandle>) -> "
     "handle<examples:host_api:PersistentHandle>, "
     "handle<examples:host_api:PersistentHandle>) -> "
     "handle<examples:host_api:PersistentHandle>",
     2, invokeHandle},
    {"foreignThreadRejected", "fn(any) -> bool", 1, foreignThreadRejected},
    {"stashForCrossVm", "fn(any) -> bool", 1, stashForCrossVm},
    {"crossVmRejected", "fn() -> bool", 0, crossVmRejected},
    {"release", "fn(handle<examples:host_api:PersistentHandle>) -> void", 1,
     release},
};

constexpr ExprPackageRegistration registration = {
    EXPR_NATIVE_PACKAGE_ABI_VERSION,          "examples", "host_api", functions,
    sizeof(functions) / sizeof(functions[0]), nullptr,    0};

}  // namespace

extern "C" const ExprPackageRegistration* exprRegisterPackage(void) {
    return &registration;
}
