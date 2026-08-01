#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define EXPR_HOST_API_ABI_VERSION 1u
#define EXPR_NATIVE_PACKAGE_ABI_VERSION 3u
#define EXPR_NATIVE_PACKAGE_NAMESPACED_ABI_VERSION 2u

typedef enum ExprPackageValueKind {
    EXPR_PACKAGE_VALUE_NULL = 0,
    EXPR_PACKAGE_VALUE_BOOL = 1,
    EXPR_PACKAGE_VALUE_I64 = 2,
    EXPR_PACKAGE_VALUE_U64 = 3,
    EXPR_PACKAGE_VALUE_F64 = 4,
    EXPR_PACKAGE_VALUE_STR = 5,
    EXPR_PACKAGE_VALUE_HANDLE = 6,
    EXPR_PACKAGE_VALUE_BYTES = 7,
} ExprPackageValueKind;

typedef struct ExprPackageStringView {
    const char* data;
    size_t length;
} ExprPackageStringView;

// Byte views are borrowed for the duration of a native call. The VM copies a
// returned byte view into a GC-owned Array<u8> before the callback returns to
// interpreted code.
typedef struct ExprPackageByteView {
    const uint8_t* data;
    size_t length;
} ExprPackageByteView;

typedef void (*ExprPackageHandleFinalizer)(void* handle_data);

typedef struct ExprPackageHandleValue {
    const char* package_namespace;
    const char* package_name;
    const char* type_name;
    void* handle_data;
    ExprPackageHandleFinalizer finalizer;
} ExprPackageHandleValue;

typedef struct ExprPackageValue {
    ExprPackageValueKind kind;
    union {
        bool boolean_value;
        int64_t i64_value;
        uint64_t u64_value;
        double f64_value;
        ExprPackageStringView string_value;
        ExprPackageByteView bytes_value;
        ExprPackageHandleValue handle_value;
    } as;
} ExprPackageValue;

typedef struct ExprHostApi {
    uint32_t abi_version;
} ExprHostApi;

typedef bool (*ExprNativePackageFn)(const ExprHostApi* host_api,
                                    const ExprPackageValue* args, size_t argc,
                                    ExprPackageValue* out_result,
                                    ExprPackageStringView* out_error);

typedef struct ExprPackageFunctionExport {
    const char* name;
    const char* signature;
    int arity;
    ExprNativePackageFn callback;
} ExprPackageFunctionExport;

typedef struct ExprPackageConstantExport {
    const char* name;
    const char* type_name;
    ExprPackageValue value;
} ExprPackageConstantExport;

typedef struct ExprPackageRegistrationHeader {
    uint32_t abi_version;
} ExprPackageRegistrationHeader;

typedef struct ExprPackageRegistration {
    uint32_t abi_version;
    const char* package_namespace;
    const char* package_name;
    const ExprPackageFunctionExport* functions;
    size_t function_count;
    const ExprPackageConstantExport* constants;
    size_t constant_count;
} ExprPackageRegistration;

typedef const ExprPackageRegistration* (*ExprRegisterPackageFn)(void);
