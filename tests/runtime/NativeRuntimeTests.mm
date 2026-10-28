#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <cstring>
#include <cstdint>
#include <vector>
#include <thread>
#include <mach-o/dyld.h>
#include "native/EHRRuntimeGateway.h"
#include "native/EHRRuntimeCollections.h"
#include "native/EHRRuntimeReflection.h"

#ifndef EHR_XCTEST_WRAPPER_HOLD_SECONDS
#define EHR_XCTEST_WRAPPER_HOLD_SECONDS 0
#endif

#import <XCTest/XCTest.h>
// Add this own helper to the app-hosted test target; lookup is existing
// bridgeExport. Calling XCTest wait runs the main runloop and allows Unity to
// drive frames. No manual source MoveNext is used in this test.
NSDictionary *EHRExerciseIteratorScheduling(XCTestCase *test, void *(*lookup)(const char *)) {
    using Operation = NSDictionary *(*)(void);
    auto begin = reinterpret_cast<Operation>(lookup("EHRManagedIteratorSchedulingBegin"));
    auto sample = reinterpret_cast<Operation>(lookup("EHRManagedIteratorSchedulingCopyStatus"));
    auto cancel = reinterpret_cast<Operation>(lookup("EHRManagedIteratorSchedulingCancel"));
    if (!begin || !sample || !cancel) return @{ @"success": @NO, @"complete": @YES, @"state": @"scheduling_exports_missing" };
    __block NSDictionary *status = begin();
    if ([status[@"complete"] boolValue]) return status;
    XCTestExpectation *ready = [test expectationWithDescription:@"real Unity coroutine drives source iterator"];
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    __block bool fulfilled = false;
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 25000000, 1000000);
    dispatch_source_set_event_handler(timer, ^{
        status = sample();
        if ([status[@"complete"] boolValue] && !fulfilled) {
            fulfilled = true; dispatch_source_cancel(timer); [ready fulfill];
        }
    });
    dispatch_resume(timer);
    [test waitForExpectations:@[ready] timeout:20];
    dispatch_source_cancel(timer);
    if (!fulfilled) status = cancel();
    return status;
}

namespace {
void *bridgeExport(const char *symbol) {
    if (void *value = dlsym(RTLD_DEFAULT, symbol)) return value;
    for (uint32_t i=0; i<_dyld_image_count(); ++i) {
        const char *path = _dyld_get_image_name(i);
        if (!path || (!strstr(path, "/EHRNativeHooks.dylib") &&
                      !strstr(path, "/UnityFramework.framework/UnityFramework"))) continue;
        void *handle = dlopen(path, RTLD_LAZY | RTLD_NOLOAD);
        if (!handle) continue;
        void *value = dlsym(handle, symbol);
        dlclose(handle);
        if (value) return value;
    }
    return nullptr;
}

NSDictionary *exerciseVersionGetter(void) {
    // Opaque IL2CPP handles only; all layout/type information comes from its
    // exported metadata API. No object field offset or method address guessed.
    auto domainGet = reinterpret_cast<void *(*)(void)>(bridgeExport("il2cpp_domain_get"));
    auto assembliesGet = reinterpret_cast<const void **(*)(void *, size_t *)>(bridgeExport("il2cpp_domain_get_assemblies"));
    auto imageGet = reinterpret_cast<const void *(*)(const void *)>(bridgeExport("il2cpp_assembly_get_image"));
    auto imageName = reinterpret_cast<const char *(*)(const void *)>(bridgeExport("il2cpp_image_get_name"));
    auto classGet = reinterpret_cast<void *(*)(const void *, const char *, const char *)>(bridgeExport("il2cpp_class_from_name"));
    auto methodsGet = reinterpret_cast<const void *(*)(void *, void **)>(bridgeExport("il2cpp_class_get_methods"));
    auto methodName = reinterpret_cast<const char *(*)(const void *)>(bridgeExport("il2cpp_method_get_name"));
    auto paramCount = reinterpret_cast<uint32_t (*)(const void *)>(bridgeExport("il2cpp_method_get_param_count"));
    auto methodFlags = reinterpret_cast<uint32_t (*)(const void *, uint32_t *)>(bridgeExport("il2cpp_method_get_flags"));
    auto returnType = reinterpret_cast<const void *(*)(const void *)>(bridgeExport("il2cpp_method_get_return_type"));
    auto typeKind = reinterpret_cast<int (*)(const void *)>(bridgeExport("il2cpp_type_get_type"));
    auto invoke = reinterpret_cast<void *(*)(const void *, void *, void **, void **)>(bridgeExport("il2cpp_runtime_invoke"));
    auto unbox = reinterpret_cast<void *(*)(void *)>(bridgeExport("il2cpp_object_unbox"));
    auto handleNew = reinterpret_cast<uint32_t (*)(void *, bool)>(bridgeExport("il2cpp_gchandle_new"));
    auto handleTarget = reinterpret_cast<void *(*)(uint32_t)>(bridgeExport("il2cpp_gchandle_get_target"));
    auto handleFree = reinterpret_cast<void (*)(uint32_t)>(bridgeExport("il2cpp_gchandle_free"));
    if (!domainGet || !assembliesGet || !imageGet || !imageName || !classGet || !methodsGet ||
        !methodName || !paramCount || !methodFlags || !returnType || !typeKind || !invoke || !unbox ||
        !handleNew || !handleTarget || !handleFree)
        return @{ @"success": @NO, @"error": @"A required IL2CPP metadata export is unavailable" };
    void *domain = domainGet();
    if (!domain) return @{ @"success": @NO, @"error": @"IL2CPP domain is unavailable" };
    size_t count = 0;
    const void **assemblies = assembliesGet(domain, &count);
    if (!assemblies || count > 4096)
        return @{ @"success": @NO, @"error": @"Assembly array is unavailable or exceeds bound" };
    const void *gameImage = nullptr;
    for (size_t i = 0; i < count; ++i) {
        const void *image = imageGet(assemblies[i]);
        const char *name = image ? imageName(image) : nullptr;
        if (name && (!strcmp(name, "Assembly-CSharp.dll") || !strcmp(name, "Assembly-CSharp"))) gameImage = image;
    }
    void *constants = gameImage ? classGet(gameImage, "", "Constants") : nullptr;
    if (!constants) return @{ @"success": @NO, @"error": @"Constants class was not found" };
    void *iterator = nullptr;
    const void *method = nullptr;
    unsigned matches = 0;
    for (unsigned i = 0; i < 4096; ++i) {
        const void *candidate = methodsGet(constants, &iterator);
        if (!candidate) break;
        const char *name = methodName(candidate);
        if (name && !strcmp(name, "GetBroadcastVersion") && paramCount(candidate) == 0) {
            method = candidate;
            ++matches;
        }
    }
    uint32_t implementationFlags = 0;
    const void *returns = method ? returnType(method) : nullptr;
    // METHOD_ATTRIBUTE_STATIC=0x10, IL2CPP_TYPE_I4=0x08.
    if (matches != 1 || !(methodFlags(method, &implementationFlags) & 0x10) ||
        !returns || typeKind(returns) != 0x08)
        return @{ @"success": @NO, @"error": @"Getter metadata does not match static Int32 GetBroadcastVersion()" };
    void *exception = nullptr;
    void *boxed = invoke(method, nullptr, nullptr, &exception);
    if (exception || !boxed)
        return @{ @"success": @NO, @"error": @"Getter raised a managed exception or returned no boxed value" };
    void *value = unbox(boxed);
    if (!value) return @{ @"success": @NO, @"error": @"Int32 unbox returned no payload" };
    int32_t result = 0;
    memcpy(&result, value, sizeof(result));
    // This pinned runtime uses UInt32 GC handles. Treat them as opaque IDs.
    uint32_t handle = handleNew(boxed, false);
    void *target = handle ? handleTarget(handle) : nullptr;
    void *targetValue = target ? unbox(target) : nullptr;
    int32_t heldResult = 0;
    if (targetValue) memcpy(&heldResult, targetValue, sizeof(heldResult));
    const bool targetMatches = target == boxed;
    const bool valueUnchanged = targetValue && heldResult == result;
    if (handle) handleFree(handle);
    return @{ @"success": @(result >= 0 && handle && targetMatches && valueUnchanged), @"method": @"Constants.GetBroadcastVersion",
        @"static": @YES, @"parameterCount": @0, @"returnType": @"System.Int32",
        @"boxedInt32Result": @(result), @"managedException": @NO,
        @"gcHandleNonzero": @(handle != 0), @"gcTargetMatchesBoxedObject": @(targetMatches),
        @"gcBoxedValueUnchanged": @(valueUnchanged), @"gcHandleFreedOnce": @(handle != 0) };
}

NSDictionary *exerciseGateway(void) {
    // Resolve the gateway from the normally signed helper. The test bundle
    // itself is not linked to the game or the helper's implementation.
#define GATEWAY(name) auto name = reinterpret_cast<decltype(&ehr_runtime_##name)>(bridgeExport("ehr_runtime_" #name)); if (!name) return @{ @"success": @NO, @"missingExport": @#name }
    GATEWAY(initialize); GATEWAY(initialize_class); GATEWAY(find_class); GATEWAY(find_method);
    GATEWAY(class_type_object); GATEWAY(object_class);
    GATEWAY(find_field); GATEWAY(read_field); GATEWAY(write_field);
    GATEWAY(invoke); GATEWAY(invoke_with_refs); GATEWAY(copy_value); GATEWAY(value_size); GATEWAY(box);
    GATEWAY(string_create); GATEWAY(string_copy);
    GATEWAY(object_retain); GATEWAY(object_release);
    GATEWAY(object_same); GATEWAY(object_identity_hash);
    GATEWAY(array_create); GATEWAY(array_length); GATEWAY(array_get); GATEWAY(array_set);
    GATEWAY(class_from_type_object); GATEWAY(make_generic_class); GATEWAY(construct);
#undef GATEWAY
    NSMutableDictionary *proof = [NSMutableDictionary dictionary];
    std::vector<EHRRuntimeToken> roots;
    bool passed = true;
    auto check = [&](NSString *key, bool condition) { proof[key] = @(condition); passed = passed && condition; };
    auto keep = [&](EHRRuntimeToken token) { if (token) roots.push_back(token); return token; };
    check(@"mainThread", [NSThread isMainThread]);
    EHRRuntimeStatus status = initialize();
    proof[@"initializationStatus"] = @(status);
    if (status != EHR_RUNTIME_OK) { proof[@"success"] = @NO; return proof; }
    EHRRuntimeToken constants = 0, intClass = 0, stringClass = 0, method = 0;
    check(@"actualGameClass", find_class("Assembly-CSharp.dll", "", "Constants", &constants) == EHR_RUNTIME_OK);
    check(@"intClass", find_class("mscorlib.dll", "System", "Int32", &intClass) == EHR_RUNTIME_OK);
    check(@"stringClass", find_class("mscorlib.dll", "System", "String", &stringClass) == EHR_RUNTIME_OK);
    check(@"exactVersionSignature", find_method(constants, "GetBroadcastVersion", nullptr, 0, "System.Int32", 1, &method) == EHR_RUNTIME_OK);
    EHRRuntimeToken returned = 0, exception = 0;
    status = invoke(method, 0, nullptr, 0, &returned, &exception);
    keep(returned); keep(exception);
    int32_t version = 0;
    size_t bytes = 0;
    check(@"actualVersionInvocation", status == EHR_RUNTIME_OK && !exception && returned &&
          copy_value(returned, &version, sizeof(version), &bytes) == EHR_RUNTIME_OK && bytes == sizeof(version) && version >= 0);
    proof[@"version"] = @(version);
    EHRRuntimeToken predicate = 0, predicateResult = 0;
    check(@"exactModdedPredicateSignature", find_method(constants, "IsVersionModded", nullptr, 0, "System.Boolean", 1, &predicate) == EHR_RUNTIME_OK);
    exception = 0;
    status = invoke(predicate, 0, nullptr, 0, &predicateResult, &exception);
    keep(predicateResult); keep(exception);
    uint8_t modded = 0;
    check(@"unchangedSourceModdedPrefix", status == EHR_RUNTIME_OK && !exception &&
          copy_value(predicateResult, &modded, sizeof(modded), &bytes) == EHR_RUNTIME_OK && bytes == 1 && modded == 1);
    EHRRuntimeToken wrongMethod = 0;
    check(@"wrongStaticRejected", find_method(constants, "GetBroadcastVersion", nullptr, 0, "System.Int32", 0, &wrongMethod) == EHR_RUNTIME_NOT_FOUND && !wrongMethod);
    check(@"wrongReturnRejected", find_method(constants, "GetBroadcastVersion", nullptr, 0, "System.String", 1, &wrongMethod) == EHR_RUNTIME_NOT_FOUND && !wrongMethod);
    const uint16_t sample[] = { 'A', 0, 0xd83d, 0xde80, 0x03a9 };
    EHRRuntimeToken text = 0;
    check(@"createUnicodeString", string_create(sample, 5, &text) == EHR_RUNTIME_OK && text);
    keep(text);
    uint16_t copied[10] = {};
    size_t length = 0;
    check(@"unicodeIncludingNulRoundTrip", string_copy(text, copied, 10, &length) == EHR_RUNTIME_OK && length == 5 && !memcmp(sample, copied, sizeof(sample)));
    check(@"boundedStringCopy", string_copy(text, copied, 1, &length) == EHR_RUNTIME_LIMIT && length == 5);
    EHRRuntimeToken concat = 0, concatenated = 0;
    const char *concatTypes[] = { "System.String", "System.String" };
    EHRRuntimeArgument concatArgs[] = { {EHR_RUNTIME_REFERENCE, 0, text, nullptr, 0}, {EHR_RUNTIME_REFERENCE, 0, text, nullptr, 0} };
    check(@"exactReferenceOverload", find_method(stringClass, "Concat", concatTypes, 2, "System.String", 1, &concat) == EHR_RUNTIME_OK);
    exception = 0;
    status = invoke(concat, 0, concatArgs, 2, &concatenated, &exception);
    keep(concatenated); keep(exception);
    check(@"referenceArguments", status == EHR_RUNTIME_OK && !exception &&
          string_copy(concatenated, copied, 10, &length) == EHR_RUNTIME_OK && length == 10 &&
          !memcmp(sample, copied, sizeof(sample)) && !memcmp(sample, copied + 5, sizeof(sample)));
    EHRRuntimeToken retained = 0;
    status = object_retain(text, &retained);
    check(@"newOwnedStrongRoot", status == EHR_RUNTIME_OK && retained && retained != text);
    check(@"releaseOwnedRoot", object_release(retained) == EHR_RUNTIME_OK);
    check(@"doubleReleaseRejected", object_release(retained) == EHR_RUNTIME_INVALID_TOKEN);
    check(@"staleTokenRejected", string_copy(retained, copied, 10, &length) == EHR_RUNTIME_INVALID_TOKEN);
    const char *tryParseTypes[] = { "System.String", "System.Int32&" };
    EHRRuntimeToken tryParse = 0;
    check(@"byrefSignatureCanBeResolved", find_method(intClass, "TryParse", tryParseTypes, 2, "System.Boolean", 1, &tryParse) == EHR_RUNTIME_OK);
    int32_t output = 0;
    EHRRuntimeArgument parseArgs[] = { {EHR_RUNTIME_REFERENCE, 0, text, nullptr, 0}, {EHR_RUNTIME_VALUE, 0, intClass, &output, sizeof(output)} };
    returned = exception = 0;
    check(@"byrefInvocationExplicitlyRejected", invoke(tryParse, 0, parseArgs, 2, &returned, &exception) == EHR_RUNTIME_UNSUPPORTED && !returned && !exception);
    // Mutable outputs are supplied explicitly. The ordinary input bytes remain
    // immutable and are copied into private, runtime-aligned argument storage.
    const uint16_t numericUnits[] = {'4', '2'};
    EHRRuntimeToken numericText = 0, byteClass = 0;
    check(@"createRefParseString", string_create(numericUnits, 2, &numericText) == EHR_RUNTIME_OK && numericText);
    keep(numericText);
    check(@"byteClassForRefMismatch", find_class("mscorlib.dll", "System", "Byte", &byteClass) == EHR_RUNTIME_OK);
    const int32_t initialOut = 99;
    int32_t parsedOut = -123;
    EHRRuntimeArgument refArgs[] = {{EHR_RUNTIME_REFERENCE, 0, numericText, nullptr, 0},
        {EHR_RUNTIME_VALUE, 0, intClass, &initialOut, sizeof(initialOut)}};
    EHRRuntimeByRefOutput outDescriptor{1, 0, intClass, &parsedOut, sizeof(parsedOut)};
    returned = exception = 0;
    status = invoke_with_refs(tryParse, 0, refArgs, 2, &outDescriptor, 1, &returned, &exception);
    keep(returned); keep(exception);
    uint8_t parsed = 0;
    check(@"scalarOutTryParseSuccess", status == EHR_RUNTIME_OK && !exception && returned && parsedOut == 42 &&
          copy_value(returned, &parsed, sizeof(parsed), &bytes) == EHR_RUNTIME_OK && bytes == 1 && parsed == 1);
    check(@"refInputBytesRemainImmutable", initialOut == 99);
    parsedOut = -123;
    refArgs[0].token = text;
    returned = exception = 0;
    status = invoke_with_refs(tryParse, 0, refArgs, 2, &outDescriptor, 1, &returned, &exception);
    keep(returned); keep(exception);
    parsed = 1;
    check(@"scalarOutTryParseFalseResetsOutput", status == EHR_RUNTIME_OK && !exception && returned && parsedOut == 0 &&
          copy_value(returned, &parsed, sizeof(parsed), &bytes) == EHR_RUNTIME_OK && bytes == 1 && parsed == 0);
    parsedOut = 777;
    refArgs[0].token = numericText;
    EHRRuntimeByRefOutput shortDescriptor = outDescriptor;
    shortDescriptor.byte_count = sizeof(parsedOut) - 1;
    returned = exception = 0;
    check(@"wrongRefOutputSizeRejected", invoke_with_refs(tryParse, 0, refArgs, 2, &shortDescriptor, 1, &returned, &exception) == EHR_RUNTIME_TYPE_MISMATCH &&
          parsedOut == 777 && !returned && !exception);
    EHRRuntimeByRefOutput wrongClassDescriptor = outDescriptor;
    wrongClassDescriptor.value_class = byteClass;
    check(@"wrongRefValueClassRejected", invoke_with_refs(tryParse, 0, refArgs, 2, &wrongClassDescriptor, 1, &returned, &exception) == EHR_RUNTIME_TYPE_MISMATCH &&
          parsedOut == 777 && !returned && !exception);
    EHRRuntimeArgument shortArgs[] = {refArgs[0], refArgs[1]};
    shortArgs[1].byte_count = sizeof(initialOut) - 1;
    check(@"wrongRefInputSizeRejected", invoke_with_refs(tryParse, 0, shortArgs, 2, &outDescriptor, 1, &returned, &exception) == EHR_RUNTIME_TYPE_MISMATCH &&
          parsedOut == 777 && !returned && !exception);
    check(@"missingRefOutputRejected", invoke_with_refs(tryParse, 0, refArgs, 2, nullptr, 0, &returned, &exception) == EHR_RUNTIME_BAD_ARGUMENT &&
          parsedOut == 777 && !returned && !exception);
    EHRRuntimeByRefOutput duplicates[] = {outDescriptor, outDescriptor};
    check(@"duplicateRefOutputRejected", invoke_with_refs(tryParse, 0, refArgs, 2, duplicates, 2, &returned, &exception) == EHR_RUNTIME_BAD_ARGUMENT &&
          parsedOut == 777 && !returned && !exception);
    EHRRuntimeByRefOutput ordinaryDescriptor = outDescriptor;
    ordinaryDescriptor.argument_index = 0;
    check(@"ordinaryParameterOutputRejected", invoke_with_refs(tryParse, 0, refArgs, 2, &ordinaryDescriptor, 1, &returned, &exception) == EHR_RUNTIME_BAD_ARGUMENT &&
          parsedOut == 777 && !returned && !exception);
    EHRRuntimeToken openList = 0, openConstructor = 0;
    check(@"openGenericClass", find_class("mscorlib.dll", "System.Collections.Generic", "List`1", &openList) == EHR_RUNTIME_OK);
    check(@"openGenericMethod", find_method(openList, ".cctor", nullptr, 0, "System.Void", 1, &openConstructor) == EHR_RUNTIME_OK);
    returned = exception = 0;
    check(@"openGenericInvocationRejected", invoke(openConstructor, 0, nullptr, 0, &returned, &exception) == EHR_RUNTIME_UNSUPPORTED && !returned && !exception);
    EHRRuntimeToken vectorClass = 0, floatClass = 0, xField = 0, vector = 0;
    check(@"vectorClass", find_class("UnityEngine.CoreModule.dll", "UnityEngine", "Vector2", &vectorClass) == EHR_RUNTIME_OK);
    check(@"floatClass", find_class("mscorlib.dll", "System", "Single", &floatClass) == EHR_RUNTIME_OK);
    struct Vector { float x, y; } v{3, 4};
    check(@"runtimeStructSize", value_size(vectorClass, &bytes) == EHR_RUNTIME_OK && bytes == sizeof(v));
    check(@"boxIsolatedStruct", box(vectorClass, &v, sizeof(v), &vector) == EHR_RUNTIME_OK && vector);
    keep(vector);
    check(@"exactFieldSignature", find_field(vectorClass, "x", "System.Single", 0, &xField) == EHR_RUNTIME_OK);
    float newX = 8;
    EHRRuntimeArgument xValue{EHR_RUNTIME_VALUE, 0, floatClass, &newX, sizeof(newX)};
    check(@"writeIsolatedBoxedField", write_field(xField, vector, &xValue) == EHR_RUNTIME_OK);
    EHRRuntimeToken boxedX = 0;
    status = read_field(xField, vector, &boxedX);
    keep(boxedX);
    float actualX = 0;
    check(@"readIsolatedBoxedField", status == EHR_RUNTIME_OK && copy_value(boxedX, &actualX, sizeof(actualX), &bytes) == EHR_RUNTIME_OK && actualX == newX);
    Vector actualVector{};
    check(@"isolatedStructPayload", copy_value(vector, &actualVector, sizeof(actualVector), &bytes) == EHR_RUNTIME_OK && actualVector.x == 8 && actualVector.y == 4);
    EHRRuntimeToken distance = 0, origin = 0;
    const char *distanceTypes[] = {"UnityEngine.Vector2", "UnityEngine.Vector2"};
    check(@"structOverload", find_method(vectorClass, "Distance", distanceTypes, 2, "System.Single", 1, &distance) == EHR_RUNTIME_OK);
    Vector zero{0, 0};
    EHRRuntimeArgument vectorArgs[] = {{EHR_RUNTIME_VALUE, 0, vectorClass, &v, sizeof(v)}, {EHR_RUNTIME_VALUE, 0, vectorClass, &zero, sizeof(zero)}};
    exception = 0;
    status = invoke(distance, 0, vectorArgs, 2, &origin, &exception);
    keep(origin); keep(exception);
    float magnitude = 0;
    check(@"structArguments", status == EHR_RUNTIME_OK && !exception && copy_value(origin, &magnitude, sizeof(magnitude), &bytes) == EHR_RUNTIME_OK && magnitude == 5);
    EHRRuntimeToken boxedVector = 0, boxedZero = 0, boxedDistance = 0;
    check(@"boxPinnedStructArgument", box(vectorClass, &v, sizeof(v), &boxedVector) == EHR_RUNTIME_OK && boxedVector);
    check(@"boxPinnedStructOrigin", box(vectorClass, &zero, sizeof(zero), &boxedZero) == EHR_RUNTIME_OK && boxedZero);
    keep(boxedVector); keep(boxedZero);
    EHRRuntimeArgument boxedArgs[] = {{EHR_RUNTIME_BOXED_VALUE, 0, boxedVector, nullptr, 0},
        {EHR_RUNTIME_BOXED_VALUE, 0, boxedZero, nullptr, 0}};
    exception = 0;
    status = invoke(distance, 0, boxedArgs, 2, &boxedDistance, &exception);
    keep(boxedDistance); keep(exception);
    magnitude = 0;
    check(@"pinnedBoxedStructArguments", status == EHR_RUNTIME_OK && !exception &&
          copy_value(boxedDistance, &magnitude, sizeof(magnitude), &bytes) == EHR_RUNTIME_OK && magnitude == 5);
    Vector preservedVector{};
    check(@"boxedArgumentRootPreserved", copy_value(boxedVector, &preservedVector, sizeof(preservedVector), &bytes) == EHR_RUNTIME_OK &&
          preservedVector.x == v.x && preservedVector.y == v.y);
    EHRRuntimeArgument mismatchedBoxes[] = {boxedArgs[0], {EHR_RUNTIME_BOXED_VALUE, 0, text, nullptr, 0}};
    returned = exception = 0;
    check(@"boxedExactClassMismatchRejected", invoke(distance, 0, mismatchedBoxes, 2, &returned, &exception) == EHR_RUNTIME_TYPE_MISMATCH && !returned && !exception);

    // Only harmless mscorlib initialization is exercised. No game-global
    // initializer is invoked, and no IL2CPP class layout is inspected.
    EHRRuntimeToken boolClass = 0, trueStringField = 0, typeObject = 0, typeObjectClass = 0;
    EHRRuntimeToken typeHandleGetter = 0, typeHandle = 0, helpers = 0, runConstructor = 0;
    check(@"classInitBooleanClass", find_class("mscorlib.dll", "System", "Boolean", &boolClass) == EHR_RUNTIME_OK);
    check(@"classInitStaticStringField", find_field(boolClass, "TrueString", "System.String", 1, &trueStringField) == EHR_RUNTIME_OK);
    returned = 0;
    check(@"uncaughtStaticInitializerStillRejected", read_field(trueStringField, 0, &returned) == EHR_RUNTIME_UNSUPPORTED && !returned);
    check(@"realManagedTypeObject", class_type_object(boolClass, &typeObject) == EHR_RUNTIME_OK && typeObject);
    keep(typeObject);
    check(@"realManagedTypeClass", object_class(typeObject, &typeObjectClass) == EHR_RUNTIME_OK);
    check(@"typeHandleGetterSignature", find_method(typeObjectClass, "get_TypeHandle", nullptr, 0, "System.RuntimeTypeHandle", 0, &typeHandleGetter) == EHR_RUNTIME_OK);
    exception = 0;
    status = invoke(typeHandleGetter, typeObject, nullptr, 0, &typeHandle, &exception);
    keep(typeHandle); keep(exception);
    check(@"boxedRuntimeTypeHandle", status == EHR_RUNTIME_OK && typeHandle && !exception);
    check(@"runtimeHelpersClass", find_class("mscorlib.dll", "System.Runtime.CompilerServices", "RuntimeHelpers", &helpers) == EHR_RUNTIME_OK);
    const char *constructorTypes[] = {"System.RuntimeTypeHandle"};
    check(@"caughtClassConstructorSignature", find_method(helpers, "RunClassConstructor", constructorTypes, 1, "System.Void", 1, &runConstructor) == EHR_RUNTIME_OK);
    EHRRuntimeArgument handleArgument{EHR_RUNTIME_BOXED_VALUE, 0, typeHandle, nullptr, 0};
    returned = exception = 0;
    status = invoke(runConstructor, 0, &handleArgument, 1, &returned, &exception);
    keep(returned); keep(exception);
    check(@"managedRunClassConstructorWithBoxedHandle", status == EHR_RUNTIME_OK && !returned && !exception);
    returned = 0;
    check(@"staticAccessRequiresRecordedSuccess", read_field(trueStringField, 0, &returned) == EHR_RUNTIME_UNSUPPORTED && !returned);
    exception = 0;
    status = initialize_class(boolClass, &exception);
    keep(exception);
    check(@"caughtClassInitializationGateway", status == EHR_RUNTIME_OK && !exception);
    EHRRuntimeToken trueString = 0;
    status = read_field(trueStringField, 0, &trueString);
    keep(trueString);
    const uint16_t expectedTrue[] = {'T', 'r', 'u', 'e'};
    check(@"recordedInitializationUnlocksStaticRead", status == EHR_RUNTIME_OK && trueString &&
          string_copy(trueString, copied, 10, &length) == EHR_RUNTIME_OK && length == 4 && !memcmp(copied, expectedTrue, sizeof(expectedTrue)));
    exception = 0;
    check(@"classInitializationSuccessIsCached", initialize_class(boolClass, &exception) == EHR_RUNTIME_OK && !exception);
    check(@"classInitializationRejectsOpenGeneric", initialize_class(openList, &exception) == EHR_RUNTIME_UNSUPPORTED && !exception);
    check(@"classInitializationRejectsObjectToken", initialize_class(text, &exception) == EHR_RUNTIME_INVALID_TOKEN && !exception);
    // Use a local immutable string to provoke and contain a managed exception.
    EHRRuntimeToken substring = 0;
    const char *substringTypes[] = {"System.Int32"};
    check(@"instanceSignature", find_method(stringClass, "Substring", substringTypes, 1, "System.String", 0, &substring) == EHR_RUNTIME_OK);
    const int32_t negative = -1;
    EHRRuntimeArgument negativeArg{EHR_RUNTIME_VALUE, 0, intClass, &negative, sizeof(negative)};
    returned = exception = 0;
    status = invoke(substring, text, &negativeArg, 1, &returned, &exception);
    keep(returned); keep(exception);
    check(@"managedExceptionContained", status == EHR_RUNTIME_MANAGED_EXCEPTION && !returned && exception);
    EHRRuntimeToken exceptionClass = 0, messageField = 0, message = 0;
    check(@"exceptionClass", find_class("mscorlib.dll", "System", "Exception", &exceptionClass) == EHR_RUNTIME_OK);
    check(@"referenceFieldSignature", find_field(exceptionClass, "_message", "System.String", 0, &messageField) == EHR_RUNTIME_OK);
    EHRRuntimeArgument messageValue{EHR_RUNTIME_REFERENCE, 0, text, nullptr, 0};
    check(@"writeIsolatedReferenceField", write_field(messageField, exception, &messageValue) == EHR_RUNTIME_OK);
    status = read_field(messageField, exception, &message);
    keep(message);
    check(@"referenceFieldWriteBarrierRoundTrip", status == EHR_RUNTIME_OK && message &&
          string_copy(message, copied, 10, &length) == EHR_RUNTIME_OK && length == 5 && !memcmp(sample, copied, sizeof(sample)));
    EHRRuntimeArgument nullValue{EHR_RUNTIME_REFERENCE, 0, 0, nullptr, 0};
    check(@"writeNullReferenceField", write_field(messageField, exception, &nullValue) == EHR_RUNTIME_OK);
    message = 0;
    check(@"readNullReferenceField", read_field(messageField, exception, &message) == EHR_RUNTIME_OK && !message);
    EHRRuntimeToken integerArray = 0, stringArray = 0, boxedNumber = 0, element = 0;
    exception = 0;
    status = array_create(intClass, 3, &integerArray, &exception);
    keep(integerArray); keep(exception);
    check(@"createLiveIntegerArray", status == EHR_RUNTIME_OK && integerArray && !exception);
    int32_t arrayLength = -1;
    exception = 0;
    check(@"liveArrayLength", array_length(integerArray, &arrayLength, &exception) == EHR_RUNTIME_OK && arrayLength == 3 && !exception);
    keep(exception);
    const int32_t number = 123456;
    check(@"boxArrayElement", box(intClass, &number, sizeof(number), &boxedNumber) == EHR_RUNTIME_OK && boxedNumber);
    keep(boxedNumber);
    exception = 0;
    check(@"setLiveIntegerArray", array_set(integerArray, 1, boxedNumber, &exception) == EHR_RUNTIME_OK && !exception);
    keep(exception);
    exception = 0;
    status = array_get(integerArray, 1, &element, &exception);
    keep(element); keep(exception);
    int32_t actualNumber = 0;
    check(@"getLiveIntegerArray", status == EHR_RUNTIME_OK && !exception && copy_value(element, &actualNumber, sizeof(actualNumber), &bytes) == EHR_RUNTIME_OK && actualNumber == number);
    exception = 0; element = 0;
    check(@"negativeArrayIndexRejected", array_get(integerArray, -1, &element, &exception) == EHR_RUNTIME_BAD_ARGUMENT && !element && !exception);
    check(@"pastEndArrayIndexRejected", array_set(integerArray, 3, boxedNumber, &exception) == EHR_RUNTIME_BAD_ARGUMENT && !exception);
    status = array_set(integerArray, 0, text, &exception);
    keep(exception);
    check(@"arrayTypeExceptionContained", status == EHR_RUNTIME_MANAGED_EXCEPTION && exception);
    exception = 0;
    status = array_create(stringClass, 2, &stringArray, &exception);
    keep(stringArray); keep(exception);
    check(@"createLiveReferenceArray", status == EHR_RUNTIME_OK && stringArray && !exception);
    exception = 0;
    check(@"setLiveReferenceArray", array_set(stringArray, 1, text, &exception) == EHR_RUNTIME_OK && !exception);
    keep(exception);
    exception = 0; element = 0;
    status = array_get(stringArray, 1, &element, &exception);
    keep(element); keep(exception);
    check(@"referenceArrayRoundTrip", status == EHR_RUNTIME_OK && !exception &&
          string_copy(element, copied, 10, &length) == EHR_RUNTIME_OK && length == 5 && !memcmp(sample, copied, sizeof(sample)));
    exception = 0;
    check(@"setNullReferenceArray", array_set(stringArray, 1, 0, &exception) == EHR_RUNTIME_OK && !exception);
    keep(exception);
    exception = 0; element = 0;
    check(@"getNullReferenceArray", array_get(stringArray, 1, &element, &exception) == EHR_RUNTIME_OK && !element && !exception);
    EHRRuntimeToken integerType = 0, roundTripClass = 0;
    check(@"reflectionIntegerType", class_type_object(intClass, &integerType) == EHR_RUNTIME_OK && integerType);
    keep(integerType);
    check(@"realTypeConvertsBackToMetadata", class_from_type_object(integerType, &roundTripClass) == EHR_RUNTIME_OK && roundTripClass == intClass);
    roundTripClass = 0;
    check(@"arbitraryObjectRejectedAsRuntimeType", class_from_type_object(text, &roundTripClass) == EHR_RUNTIME_TYPE_MISMATCH && !roundTripClass);
    EHRRuntimeToken closedList = 0, liveList = 0, constructedClass = 0;
    const EHRRuntimeToken genericArguments[] = {intClass};
    exception = 0;
    status = make_generic_class(openList, genericArguments, 1, &closedList, &exception);
    keep(exception);
    check(@"realClosedGenericListClass", status == EHR_RUNTIME_OK && closedList && !exception && closedList != openList);
    exception = 0;
    status = construct(closedList, nullptr, 0, &liveList, &exception);
    keep(liveList); keep(exception);
    check(@"realManagedListConstructor", status == EHR_RUNTIME_OK && liveList && !exception);
    check(@"constructedClosedClassMatches", object_class(liveList, &constructedClass) == EHR_RUNTIME_OK && constructedClass == closedList);
    EHRRuntimeToken listInterface = 0, collectionInterface = 0, add = 0, countGetter = 0, itemGetter = 0, itemSetter = 0;
    check(@"nonGenericListInterface", find_class("mscorlib.dll", "System.Collections", "IList", &listInterface) == EHR_RUNTIME_OK);
    check(@"collectionInterface", find_class("mscorlib.dll", "System.Collections", "ICollection", &collectionInterface) == EHR_RUNTIME_OK);
    const char *addTypes[] = {"System.Object"};
    const char *getItemTypes[] = {"System.Int32"};
    const char *setItemTypes[] = {"System.Int32", "System.Object"};
    check(@"liveListAddSignature", find_method(listInterface, "Add", addTypes, 1, "System.Int32", 0, &add) == EHR_RUNTIME_OK);
    check(@"liveListCountSignature", find_method(collectionInterface, "get_Count", nullptr, 0, "System.Int32", 0, &countGetter) == EHR_RUNTIME_OK);
    check(@"liveListItemGetterSignature", find_method(listInterface, "get_Item", getItemTypes, 1, "System.Object", 0, &itemGetter) == EHR_RUNTIME_OK);
    check(@"liveListItemSetterSignature", find_method(listInterface, "set_Item", setItemTypes, 2, "System.Void", 0, &itemSetter) == EHR_RUNTIME_OK);
    const EHRRuntimeArgument addArgument{EHR_RUNTIME_REFERENCE, 0, boxedNumber, nullptr, 0};
    returned = exception = 0;
    status = invoke(add, liveList, &addArgument, 1, &returned, &exception);
    keep(returned); keep(exception);
    int32_t addedIndex = -1;
    check(@"liveGenericListAdd", status == EHR_RUNTIME_OK && !exception &&
          copy_value(returned, &addedIndex, sizeof(addedIndex), &bytes) == EHR_RUNTIME_OK && addedIndex == 0);
    returned = exception = 0;
    status = invoke(countGetter, liveList, nullptr, 0, &returned, &exception);
    keep(returned); keep(exception);
    int32_t liveCount = -1;
    check(@"liveGenericListCount", status == EHR_RUNTIME_OK && !exception &&
          copy_value(returned, &liveCount, sizeof(liveCount), &bytes) == EHR_RUNTIME_OK && liveCount == 1);
    const int32_t firstIndex = 0;
    const EHRRuntimeArgument indexArgument{EHR_RUNTIME_VALUE, 0, intClass, &firstIndex, sizeof(firstIndex)};
    returned = exception = 0;
    status = invoke(itemGetter, liveList, &indexArgument, 1, &returned, &exception);
    keep(returned); keep(exception);
    int32_t firstValue = 0;
    check(@"liveGenericListItemRead", status == EHR_RUNTIME_OK && !exception &&
          copy_value(returned, &firstValue, sizeof(firstValue), &bytes) == EHR_RUNTIME_OK && firstValue == number);
    const int32_t replacementValue = -7;
    EHRRuntimeToken replacement = 0;
    check(@"boxLiveListReplacement", box(intClass, &replacementValue, sizeof(replacementValue), &replacement) == EHR_RUNTIME_OK && replacement);
    keep(replacement);
    const EHRRuntimeArgument setArguments[] = {indexArgument, {EHR_RUNTIME_REFERENCE, 0, replacement, nullptr, 0}};
    returned = exception = 0;
    status = invoke(itemSetter, liveList, setArguments, 2, &returned, &exception);
    keep(returned); keep(exception);
    check(@"liveGenericListItemWrite", status == EHR_RUNTIME_OK && !returned && !exception);
    returned = exception = 0;
    status = invoke(itemGetter, liveList, &indexArgument, 1, &returned, &exception);
    keep(returned); keep(exception);
    firstValue = 0;
    check(@"liveGenericListWriteVisible", status == EHR_RUNTIME_OK && !exception &&
          copy_value(returned, &firstValue, sizeof(firstValue), &bytes) == EHR_RUNTIME_OK && firstValue == replacementValue);
    EHRRuntimeToken invalidClosedClass = 0;
    exception = 0;
    status = make_generic_class(openList, nullptr, 0, &invalidClosedClass, &exception);
    keep(exception);
    check(@"genericWrongArityExceptionContained", status == EHR_RUNTIME_MANAGED_EXCEPTION && !invalidClosedClass && exception);
    const int32_t negativeCapacity = -1;
    EHRRuntimeToken badCapacity = 0, failedConstruction = 0;
    check(@"boxInvalidConstructorArgument", box(intClass, &negativeCapacity, sizeof(negativeCapacity), &badCapacity) == EHR_RUNTIME_OK && badCapacity);
    keep(badCapacity);
    exception = 0;
    status = construct(closedList, &badCapacity, 1, &failedConstruction, &exception);
    keep(failedConstruction); keep(exception);
    check(@"constructorExceptionContained", status == EHR_RUNTIME_MANAGED_EXCEPTION && !failedConstruction && exception);
    EHRRuntimeToken sameObjectRoot = 0, equalString = 0;
    check(@"identityRetainedRoot", object_retain(text, &sameObjectRoot) == EHR_RUNTIME_OK && sameObjectRoot);
    check(@"identityDistinctEqualString", string_create(sample, 5, &equalString) == EHR_RUNTIME_OK && equalString);
    keep(equalString);
    int32_t same = -1;
    check(@"sameManagedObjectAcrossRoots", object_same(text, sameObjectRoot, &same) == EHR_RUNTIME_OK && same == 1);
    check(@"equalValuesKeepDistinctIdentity", object_same(text, equalString, &same) == EHR_RUNTIME_OK && same == 0);
    check(@"nullIdentity", object_same(0, 0, &same) == EHR_RUNTIME_OK && same == 1);
    check(@"nullVersusObjectIdentity", object_same(0, text, &same) == EHR_RUNTIME_OK && same == 0);
    int32_t firstHash = 0, retainedHash = 0, equalValueHash = 0;
    exception = 0;
    status = object_identity_hash(text, &firstHash, &exception);
    keep(exception);
    check(@"managedIdentityHash", status == EHR_RUNTIME_OK && !exception);
    exception = 0;
    status = object_identity_hash(sameObjectRoot, &retainedHash, &exception);
    keep(exception);
    check(@"sameObjectIdentityHashStable", status == EHR_RUNTIME_OK && !exception && retainedHash == firstHash);
    exception = 0;
    status = object_identity_hash(equalString, &equalValueHash, &exception);
    keep(exception);
    check(@"distinctEqualValueIdentityHashAvailable", status == EHR_RUNTIME_OK && !exception);
    proof[@"identityHash"] = @(firstHash);
    proof[@"distinctEqualValueIdentityHash"] = @(equalValueHash);
    check(@"identityRootRelease", object_release(sameObjectRoot) == EHR_RUNTIME_OK);
    check(@"identityStaleTokenRejected", object_same(text, sameObjectRoot, &same) == EHR_RUNTIME_INVALID_TOKEN && same == 0);
    exception = 0;
    check(@"identityHashStaleTokenRejected", object_identity_hash(sameObjectRoot, &retainedHash, &exception) == EHR_RUNTIME_INVALID_TOKEN && !exception);
    check(@"nullIdentityHash", object_identity_hash(0, &retainedHash, &exception) == EHR_RUNTIME_OK && retainedHash == 0 && !exception);
    bool released = true;
    for (auto token : roots) released = (object_release(token) == EHR_RUNTIME_OK) && released;
    check(@"allTestRootsReleasedOnce", released);
    proof[@"gameplayMutationPerformed"] = @NO;
    proof[@"success"] = @(passed);
    return proof;
}
NSDictionary *exerciseMethodReflection(void) {
#define METHOD_API(name) auto name = reinterpret_cast<decltype(&ehr_runtime_##name)>(bridgeExport("ehr_runtime_" #name)); if (!name) return @{ @"success": @NO, @"missingExport": @#name }
    METHOD_API(find_class); METHOD_API(find_method); METHOD_API(method_object);
    METHOD_API(method_from_object); METHOD_API(method_function_pointer);
    METHOD_API(make_generic_method); METHOD_API(class_type_object);
    METHOD_API(validate_native_method);
    METHOD_API(invoke); METHOD_API(copy_value); METHOD_API(array_length);
    METHOD_API(object_class); METHOD_API(class_type_name); METHOD_API(string_copy);
    METHOD_API(object_release);
#undef METHOD_API
    NSMutableDictionary *proof = [NSMutableDictionary dictionary];
    std::vector<EHRRuntimeToken> roots;
    bool passed = true;
    auto check = [&](NSString *key, bool condition) { proof[key] = @(condition); passed = passed && condition; };
    auto keep = [&](EHRRuntimeToken value) { if (value) roots.push_back(value); };
    EHRRuntimeToken constants = 0, version = 0, reflection = 0, converted = 0;
    check(@"methodReflectionDeclaringClass", find_class("Assembly-CSharp.dll", "", "Constants", &constants) == EHR_RUNTIME_OK);
    check(@"methodReflectionExactMethod", find_method(constants, "GetBroadcastVersion", nullptr, 0, "System.Int32", 1, &version) == EHR_RUNTIME_OK);
    check(@"realMethodInfoObject", method_object(version, &reflection) == EHR_RUNTIME_OK && reflection);
    keep(reflection);
    check(@"realMethodInfoRoundTrip", method_from_object(reflection, &converted) == EHR_RUNTIME_OK && converted == version);
    EHRRuntimeToken wrongObject = 0;
    check(@"methodReflectionWrongObjectCreated", class_type_object(constants, &wrongObject) == EHR_RUNTIME_OK && wrongObject);
    keep(wrongObject);
    converted = 99;
    check(@"arbitraryReflectionObjectRejected", method_from_object(wrongObject, &converted) == EHR_RUNTIME_TYPE_MISMATCH && !converted);
    converted = 99;
    check(@"methodReflectionMetadataAsObjectRejected", method_from_object(version, &converted) == EHR_RUNTIME_INVALID_TOKEN && !converted);
    EHRRuntimeToken boxedPointer = 0, exception = 0;
    auto status = method_function_pointer(version, &boxedPointer, &exception);
    keep(boxedPointer); keep(exception);
    proof[@"functionPointerStatus"] = @(status);
    uintptr_t pointer = 0;
    size_t bytes = 0;
    const bool copiedPointer = status == EHR_RUNTIME_OK && !exception && boxedPointer &&
        copy_value(boxedPointer, &pointer, sizeof(pointer), &bytes) == EHR_RUNTIME_OK && pointer;
    proof[@"realRuntimeMethodHandleFunctionPointer"] = @(copiedPointer);
    check(@"publicFunctionPointerCapabilityOutcomeExplicit", copiedPointer ||
          (status == EHR_RUNTIME_NOT_FOUND && !boxedPointer && !exception));
    if (!copiedPointer) {
        NSMutableDictionary *steps = [NSMutableDictionary dictionary];
        EHRRuntimeToken methodBase = 0, handleClass = 0, getter = 0, getPointer = 0;
        steps[@"methodBaseClass"] = @(find_class("mscorlib.dll", "System.Reflection", "MethodBase", &methodBase));
        steps[@"handleClass"] = @(find_class("mscorlib.dll", "System", "RuntimeMethodHandle", &handleClass));
        steps[@"handleGetter"] = @(find_method(methodBase, "get_MethodHandle", nullptr, 0, "System.RuntimeMethodHandle", 0, &getter));
        EHRRuntimeToken handle = 0, raised = 0;
        steps[@"handleInvoke"] = @(invoke(getter, reflection, nullptr, 0, &handle, &raised));
        keep(handle); keep(raised);
        steps[@"functionPointerMethod"] = @(find_method(handleClass, "GetFunctionPointer", nullptr, 0, "System.IntPtr", 0, &getPointer));
        EHRRuntimeToken address = 0, pointerException = 0;
        steps[@"functionPointerInvoke"] = @(invoke(getPointer, handle, nullptr, 0, &address, &pointerException));
        keep(address); keep(pointerException);
        uintptr_t returnedAddress = 0;
        size_t returnedBytes = 0;
        steps[@"copyPointerValue"] = @(copy_value(address, &returnedAddress, sizeof(returnedAddress), &returnedBytes));
        steps[@"pointerIsNonzero"] = @(returnedAddress != 0);
        if (pointerException) {
            EHRRuntimeToken exceptionClass = 0, getMessage = 0, message = 0, messageException = 0;
            if (find_class("mscorlib.dll", "System", "Exception", &exceptionClass) == EHR_RUNTIME_OK &&
                find_method(exceptionClass, "get_Message", nullptr, 0, "System.String", 0, &getMessage) == EHR_RUNTIME_OK &&
                invoke(getMessage, pointerException, nullptr, 0, &message, &messageException) == EHR_RUNTIME_OK) {
                uint16_t text[2048]{}; size_t count = 0;
                if (string_copy(message, text, 2048, &count) == EHR_RUNTIME_OK)
                    steps[@"runtimeExceptionMessage"] = [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar *>(text) length:count];
            }
            keep(message); keep(messageException);
        }
        proof[@"functionPointerDiagnostic"] = steps;
    }
    using Hooks = NSDictionary *(*)(void);
    auto hooks = reinterpret_cast<Hooks>(bridgeExport("EHRNativeHooksCopyStatus"));
    Dl_info image{};
    const bool mapped = copiedPointer && dladdr(reinterpret_cast<void *>(pointer), &image) && image.dli_fbase && image.dli_fname &&
        strstr(image.dli_fname, "/UnityFramework.framework/UnityFramework");
    NSDictionary *hookState = hooks ? hooks() : @{};
    const uintptr_t expected = [hookState[@"broadcastVersionOriginalRVA"] unsignedLongLongValue];
    const uintptr_t actual = mapped ? pointer - reinterpret_cast<uintptr_t>(image.dli_fbase) : 0;
    proof[@"independentRuntimeNativeAssociation"] = @(mapped && expected && actual == expected);
    if (copiedPointer) check(@"availablePublicPointerMatchesPinnedTarget", mapped && expected && actual == expected);
    else proof[@"publicMethodPointerCapability"] = @"Unavailable: this runtime has no RuntimeMethodHandle.GetFunctionPointer declaration";
    proof[@"runtimeNativeRVA"] = @(actual);
    proof[@"expectedPinnedNativeRVA"] = @(expected);
    uint64_t independentlyObserved = 0;
    const auto associationStatus = validate_native_method(version, expected, &independentlyObserved);
    check(@"versionPinnedNativeAssociation", associationStatus == EHR_RUNTIME_OK && independentlyObserved == expected);
    proof[@"versionPinnedNativeAssociationStatus"] = @(associationStatus);
    proof[@"versionPinnedNativeRVA"] = @(independentlyObserved);
    independentlyObserved = 99;
    check(@"wrongNativeRvaIsRejectedWithActualObserved", validate_native_method(version, expected + 4, &independentlyObserved) == EHR_RUNTIME_TYPE_MISMATCH && independentlyObserved == expected);
    independentlyObserved = 99;
    check(@"nativeAssociationRejectsNonMethodToken", validate_native_method(constants, expected, &independentlyObserved) == EHR_RUNTIME_INVALID_TOKEN && !independentlyObserved);
    independentlyObserved = 99;
    check(@"nativeAssociationRejectsUnalignedExpectedRva", validate_native_method(version, expected + 1, &independentlyObserved) == EHR_RUNTIME_BAD_ARGUMENT && !independentlyObserved);
    // A generic method may be inflated only through the actual runtime's
    // reflection path. Missing precompiled implementations remain exceptions.
    EHRRuntimeToken arrayClass = 0, empty = 0;
    check(@"genericArrayClass", find_class("mscorlib.dll", "System", "Array", &arrayClass) == EHR_RUNTIME_OK);
    const auto emptyStatus = find_method(arrayClass, "Empty", nullptr, 0, "T[]", 1, &empty);
    proof[@"genericEmptyDefinitionLookupStatus"] = @(emptyStatus);
    check(@"genericEmptyDefinitionFound", emptyStatus == EHR_RUNTIME_OK && empty);
    NSMutableArray *genericCases = [NSMutableArray array];
    size_t genericSuccesses = 0;
    for (const char *typeName : {"Byte", "Int32", "Object"}) {
        EHRRuntimeToken type = 0, closed = 0;
        const auto typeStatus = find_class("mscorlib.dll", "System", typeName, &type);
        exception = 0;
        const auto inflationStatus = typeStatus == EHR_RUNTIME_OK ? make_generic_method(empty, &type, 1, &closed, &exception) : typeStatus;
        keep(exception);
        exception = 0;
        EHRRuntimeToken returned = 0, invokeException = 0;
        const auto invokeStatus = inflationStatus == EHR_RUNTIME_OK ? invoke(closed, 0, nullptr, 0, &returned, &invokeException) : inflationStatus;
        keep(returned); keep(invokeException);
        int32_t length = -1;
        const bool executed = invokeStatus == EHR_RUNTIME_OK && !invokeException && returned &&
            array_length(returned, &length, &exception) == EHR_RUNTIME_OK && !exception && length == 0;
        keep(exception);
        if (executed) ++genericSuccesses;
        [genericCases addObject:@{@"type": [NSString stringWithUTF8String:typeName], @"inflationStatus": @(inflationStatus),
            @"invocationStatus": @(invokeStatus), @"emptyArrayObserved": @(executed)}];
    }
    check(@"closedGenericMethodExecutedWithAotBody", genericSuccesses > 0);
    proof[@"genericCases"] = genericCases;
    exception = 0; converted = 0;
    const auto invalidGeneric = make_generic_method(version, nullptr, 0, &converted, &exception);
    keep(exception);
    check(@"nonGenericInflationExceptionContained", invalidGeneric == EHR_RUNTIME_MANAGED_EXCEPTION && exception && !converted);
    bool released = true;
    for (const auto root : roots) released = object_release(root) == EHR_RUNTIME_OK && released;
    check(@"allMethodReflectionRootsReleased", released);
    converted = 99;
    check(@"staleMethodReflectionRootRejected", method_from_object(reflection, &converted) == EHR_RUNTIME_INVALID_TOKEN && !converted);
    proof[@"gameplayMutationPerformed"] = @NO;
    proof[@"success"] = @(passed);
    return proof;
}
NSDictionary *exerciseVectorClasses(void) {
#define VECTOR_API(name) auto name = reinterpret_cast<decltype(&ehr_runtime_##name)>(bridgeExport("ehr_runtime_" #name)); if (!name) return @{ @"success": @NO, @"missingExport": @#name }
    VECTOR_API(find_class); VECTOR_API(vector_class); VECTOR_API(array_create);
    VECTOR_API(object_class); VECTOR_API(class_type_name); VECTOR_API(object_release);
#undef VECTOR_API
    NSMutableDictionary *proof = [NSMutableDictionary dictionary];
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    bool passed = true;
    auto check = [&](NSString *key, bool condition) { proof[key] = @(condition); passed = passed && condition; };
    struct Case { const char *image, *space, *name; NSString *key; };
    const Case cases[] = {
        {"mscorlib.dll", "System", "Byte", @"byteVector"},
        {"Assembly-CSharp.dll", "", "PlayerControl", @"playerVector"},
        {"Assembly-CSharp.dll", "", "NetworkedPlayerInfo+PlayerOutfit", @"nestedOutfitVector"}
    };
    std::vector<EHRRuntimeToken> roots;
    for (const auto &item : cases) {
        EHRRuntimeToken element = 0, vector = 0, repeated = 0, array = 0, exception = 0, actual = 0;
        check([item.key stringByAppendingString:@"ElementClass"], find_class(item.image, item.space, item.name, &element) == EHR_RUNTIME_OK);
        check([item.key stringByAppendingString:@"MetadataOnlyClass"], vector_class(element, &vector) == EHR_RUNTIME_OK && vector);
        check([item.key stringByAppendingString:@"StableClassIdentity"], vector_class(element, &repeated) == EHR_RUNTIME_OK && repeated == vector);
        const auto status = array_create(element, 0, &array, &exception);
        if (array) roots.push_back(array);
        if (exception) roots.push_back(exception);
        check([item.key stringByAppendingString:@"ActualArrayClassMatches"], status == EHR_RUNTIME_OK && !exception && array &&
              object_class(array, &actual) == EHR_RUNTIME_OK && actual == vector);
        char name[4096]{}; size_t required = 0;
        const auto nameStatus = class_type_name(vector, name, sizeof(name), &required);
        check([item.key stringByAppendingString:@"ExactRuntimeName"], nameStatus == EHR_RUNTIME_OK && required > 3 && required <= sizeof(name));
        if (nameStatus == EHR_RUNTIME_OK) names[item.key] = @(name);
    }
    EHRRuntimeToken invalid = 99, voidClass = 0, openList = 0;
    check(@"vectorRejectsInvalidMetadataToken", vector_class(UINT64_MAX, &invalid) == EHR_RUNTIME_INVALID_TOKEN && !invalid);
    check(@"voidClassResolved", find_class("mscorlib.dll", "System", "Void", &voidClass) == EHR_RUNTIME_OK);
    invalid = 99;
    check(@"vectorRejectsVoidElement", vector_class(voidClass, &invalid) == EHR_RUNTIME_UNSUPPORTED && !invalid);
    check(@"openListClassResolvedForVectorRejection", find_class("mscorlib.dll", "System.Collections.Generic", "List`1", &openList) == EHR_RUNTIME_OK);
    invalid = 99;
    check(@"vectorRejectsOpenGenericElement", vector_class(openList, &invalid) == EHR_RUNTIME_UNSUPPORTED && !invalid);
    bool released = true;
    for (const auto root : roots) released = object_release(root) == EHR_RUNTIME_OK && released;
    check(@"allVectorArrayRootsReleased", released);
    proof[@"runtimeVectorTypeNames"] = names;
    proof[@"gameplayMutationPerformed"] = @NO;
    proof[@"success"] = @(passed);
    return proof;
}
NSDictionary *exerciseTypeNames(void) {
#define NAME_API(name) auto name = reinterpret_cast<decltype(&ehr_runtime_##name)>(bridgeExport("ehr_runtime_" #name)); if (!name) return @{ @"success": @NO, @"missingExport": @#name }
    NAME_API(find_class); NAME_API(find_field); NAME_API(find_method);
    NAME_API(class_type_name); NAME_API(field_type_name);
    NAME_API(make_generic_class); NAME_API(object_release);
#undef NAME_API
    NSMutableDictionary *proof = [NSMutableDictionary dictionary];
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    bool passed = true;
    auto check = [&](NSString *key, bool condition) { proof[key] = @(condition); passed = passed && condition; };
    using CopyName = EHRRuntimeStatus (*)(EHRRuntimeToken, char *, size_t, size_t *);
    auto read = [&](CopyName copy, EHRRuntimeToken token, NSString *key) -> NSString * {
        size_t required = 999;
        const auto queried = copy(token, nullptr, 0, &required);
        const bool bounded = queried == EHR_RUNTIME_LIMIT && required > 1 && required <= 4096;
        check([key stringByAppendingString:@"SizeQuery"], bounded);
        if (!bounded) return nil;
        std::vector<char> buffer(required + 1, 0x5a);
        size_t copied = 0;
        const auto status = copy(token, buffer.data(), required, &copied);
        const bool complete = status == EHR_RUNTIME_OK && copied == required &&
            buffer[required - 1] == 0 && buffer[required] == 0x5a && strlen(buffer.data()) + 1 == required;
        check([key stringByAppendingString:@"ExactCapacityAndNul"], complete);
        if (!complete) return nil;
        NSString *value = [NSString stringWithUTF8String:buffer.data()];
        check([key stringByAppendingString:@"ValidUtf8"], value != nil);
        if (value) names[key] = value;
        return value;
    };
    EHRRuntimeToken integer = 0, vector = 0, xField = 0, openList = 0, player = 0;
    check(@"typeNameIntClass", find_class("mscorlib.dll", "System", "Int32", &integer) == EHR_RUNTIME_OK);
    check(@"typeNameVectorClass", find_class("UnityEngine.CoreModule.dll", "UnityEngine", "Vector2", &vector) == EHR_RUNTIME_OK);
    check(@"typeNameField", find_field(vector, "x", "System.Single", 0, &xField) == EHR_RUNTIME_OK);
    NSString *integerName = read(class_type_name, integer, @"int32");
    NSString *fieldName = read(field_type_name, xField, @"vectorXField");
    check(@"primitiveTypeSpelling", [integerName isEqualToString:@"System.Int32"]);
    check(@"fieldTypeSpelling", [fieldName isEqualToString:@"System.Single"]);
    char bounded[2] = {'x', 'z'};
    size_t required = 99;
    check(@"insufficientNameBufferEmpty", class_type_name(integer, bounded, 1, &required) == EHR_RUNTIME_LIMIT &&
          bounded[0] == 0 && bounded[1] == 'z' && required == strlen("System.Int32") + 1);
    bounded[0] = 'x'; required = 99;
    check(@"invalidClassNameTokenEmpty", class_type_name(xField, bounded, sizeof(bounded), &required) == EHR_RUNTIME_INVALID_TOKEN &&
          bounded[0] == 0 && required == 0);
    bounded[0] = 'x'; required = 99;
    check(@"invalidFieldNameTokenEmpty", field_type_name(integer, bounded, sizeof(bounded), &required) == EHR_RUNTIME_INVALID_TOKEN &&
          bounded[0] == 0 && required == 0);
    required = 99;
    check(@"nullPositiveCapacityRejected", class_type_name(integer, nullptr, 1, &required) == EHR_RUNTIME_BAD_ARGUMENT && required == 0);
    check(@"nullRequiredRejected", class_type_name(integer, bounded, sizeof(bounded), nullptr) == EHR_RUNTIME_BAD_ARGUMENT);
    check(@"typeNameOpenListClass", find_class("mscorlib.dll", "System.Collections.Generic", "List`1", &openList) == EHR_RUNTIME_OK);
    check(@"typeNamePlayerMetadataClass", find_class("Assembly-CSharp.dll", "", "PlayerControl", &player) == EHR_RUNTIME_OK);
    read(class_type_name, openList, @"openList");
    const EHRRuntimeToken arguments[] = {integer, player};
    NSString *keys[] = {@"closedInt32List", @"closedPlayerList"};
    for (size_t i = 0; i < 2; ++i) {
        EHRRuntimeToken closed = 0, exception = 0;
        const auto status = make_generic_class(openList, &arguments[i], 1, &closed, &exception);
        check([keys[i] stringByAppendingString:@"RealClosedClass"], status == EHR_RUNTIME_OK && closed && !exception);
        if (exception) check([keys[i] stringByAppendingString:@"ExceptionReleased"], object_release(exception) == EHR_RUNTIME_OK);
        NSString *name = read(class_type_name, closed, keys[i]);
        check([keys[i] stringByAppendingString:@"RuntimeGenericSpelling"],
              [name containsString:@"System.Collections.Generic.List"] &&
              [name containsString:i ? @"PlayerControl" : @"System.Int32"]);
    }
    // The copied runtime spelling can be fed directly into exact signature
    // lookup, without substituting a C# facade's own generic-name formatter.
    EHRRuntimeToken constants = 0, method = 0;
    check(@"typeNameConstantsClass", find_class("Assembly-CSharp.dll", "", "Constants", &constants) == EHR_RUNTIME_OK);
    check(@"runtimeSpellingAcceptedForExactLookup", integerName &&
          find_method(constants, "GetBroadcastVersion", nullptr, 0, integerName.UTF8String, 1, &method) == EHR_RUNTIME_OK && method);
    proof[@"runtimeNames"] = names;
    proof[@"gameplayMutationPerformed"] = @NO;
    proof[@"success"] = @(passed);
    return proof;
}
NSDictionary *exerciseNestedClasses(void) {
#define NESTED_API(name) auto name = reinterpret_cast<decltype(&ehr_runtime_##name)>(bridgeExport("ehr_runtime_" #name)); if (!name) return @{ @"success": @NO, @"missingExport": @#name }
    NESTED_API(find_class); NESTED_API(class_type_name); NESTED_API(class_type_object);
    NESTED_API(class_from_type_object); NESTED_API(object_release);
#undef NESTED_API
    struct Case { const char *image, *space, *name; NSString *key; };
    const Case cases[] = {
        {"Assembly-CSharp.dll", "", "NetworkedPlayerInfo+PlayerOutfit", @"playerOutfit"},
        {"Assembly-CSharp.dll", "", "MeetingHud+VoterState", @"voterState"},
        {"Assembly-CSharp.dll", "", "ExileController+InitProperties", @"exileInitProperties"},
        {"Assembly-CSharp.dll", "InnerNet", "InnerNetClient+TotalGameData", @"namespacedGameNestedType"},
        {"mscorlib.dll", "System", "Environment+SpecialFolder", @"namespacedRuntimeNestedEnum"},
        {"mscorlib.dll", "System.Collections.Generic", "Dictionary`2+KeyCollection+Enumerator", @"twoLevelOpenGenericNestedType"}
    };
    NSMutableDictionary *proof = [NSMutableDictionary dictionary];
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    bool passed = true;
    auto check = [&](NSString *key, bool condition) { proof[key] = @(condition); passed = passed && condition; };
    std::vector<EHRRuntimeToken> roots;
    for (const auto &item : cases) {
        EHRRuntimeToken klass = 0, repeated = 0, typeObject = 0, roundTrip = 0;
        check([item.key stringByAppendingString:@"ResolvedByTraversal"],
              find_class(item.image, item.space, item.name, &klass) == EHR_RUNTIME_OK && klass);
        check([item.key stringByAppendingString:@"StableMetadataIdentity"],
              find_class(item.image, item.space, item.name, &repeated) == EHR_RUNTIME_OK && repeated == klass);
        auto status = class_type_object(klass, &typeObject);
        if (typeObject) roots.push_back(typeObject);
        check([item.key stringByAppendingString:@"ActualTypeIdentityRoundTrip"], status == EHR_RUNTIME_OK && typeObject &&
              class_from_type_object(typeObject, &roundTrip) == EHR_RUNTIME_OK && roundTrip == klass);
        size_t required = 0;
        status = class_type_name(klass, nullptr, 0, &required);
        const bool bounded = status == EHR_RUNTIME_LIMIT && required > 1 && required <= 4096;
        check([item.key stringByAppendingString:@"RuntimeNameSize"], bounded);
        if (bounded) {
            std::vector<char> utf8(required);
            status = class_type_name(klass, utf8.data(), utf8.size(), &required);
            NSString *name = status == EHR_RUNTIME_OK ? [NSString stringWithUTF8String:utf8.data()] : nil;
            check([item.key stringByAppendingString:@"RuntimeNameCopied"], name.length > 0);
            if (name) names[item.key] = name;
        }
    }
    EHRRuntimeToken absent = 123;
    check(@"wrongNestedOwnerRejected", find_class("Assembly-CSharp.dll", "", "NetworkedPlayerInfo+VoterState", &absent) == EHR_RUNTIME_NOT_FOUND && !absent);
    absent = 123;
    check(@"wrongOuterNamespaceRejected", find_class("Assembly-CSharp.dll", "", "InnerNetClient+TotalGameData", &absent) == EHR_RUNTIME_NOT_FOUND && !absent);
    absent = 123;
    check(@"nestedNamesRemainCaseSensitive", find_class("Assembly-CSharp.dll", "", "NetworkedPlayerInfo+playerOutfit", &absent) == EHR_RUNTIME_NOT_FOUND && !absent);
    for (const char *invalid : {"+PlayerOutfit", "NetworkedPlayerInfo+", "NetworkedPlayerInfo++PlayerOutfit", "NetworkedPlayerInfo/PlayerOutfit"}) {
        absent = 123;
        check([@"malformedNestedNameRejected:" stringByAppendingString:@(invalid)],
              find_class("Assembly-CSharp.dll", "", invalid, &absent) == EHR_RUNTIME_BAD_ARGUMENT && !absent);
    }
    NSMutableString *deep = [NSMutableString stringWithString:@"X"];
    for (unsigned i = 0; i < 32; ++i) [deep appendString:@"+X"];
    absent = 123;
    check(@"nestedDepthBounded", find_class("Assembly-CSharp.dll", "", deep.UTF8String, &absent) == EHR_RUNTIME_LIMIT && !absent);
    EHRRuntimeStatus workerStatus = EHR_RUNTIME_OK;
    EHRRuntimeToken workerResult = 123;
    std::thread worker([&] {
        workerStatus = find_class("Assembly-CSharp.dll", "", "NetworkedPlayerInfo+PlayerOutfit", &workerResult);
    });
    worker.join();
    check(@"nestedLookupRequiresMainThread", workerStatus == EHR_RUNTIME_WRONG_THREAD && !workerResult);
    bool released = true;
    for (const auto token : roots) released = object_release(token) == EHR_RUNTIME_OK && released;
    check(@"allNestedTypeObjectRootsReleased", released);
    proof[@"runtimeNestedTypeNames"] = names;
    proof[@"gameObjectsCreated"] = @NO;
    proof[@"gameplayMutationPerformed"] = @NO;
    proof[@"success"] = @(passed);
    return proof;
}
NSDictionary *exerciseIteratorCarrierBaseline(void) {
#define ITERATOR_API(name) auto name = reinterpret_cast<decltype(&ehr_runtime_##name)>(bridgeExport("ehr_runtime_" #name)); if (!name) return @{ @"success": @NO, @"missingExport": @#name }
    ITERATOR_API(find_class); ITERATOR_API(find_method); ITERATOR_API(construct);
    ITERATOR_API(invoke); ITERATOR_API(copy_value); ITERATOR_API(object_class);
    ITERATOR_API(object_retain); ITERATOR_API(object_release); ITERATOR_API(object_same);
    ITERATOR_API(object_identity_hash); ITERATOR_API(class_type_name);
    ITERATOR_API(string_create); ITERATOR_API(box);
#undef ITERATOR_API
    NSMutableDictionary *proof = [NSMutableDictionary dictionary];
    bool passed = true;
    auto check = [&](NSString *key, bool condition) { proof[key] = @(condition); passed = passed && condition; };
    std::vector<EHRRuntimeToken> roots;
    auto keep = [&](EHRRuntimeToken token) { if (token) roots.push_back(token); };
    struct Invocation { EHRRuntimeStatus status; EHRRuntimeToken value, exception; };
    auto call = [&](EHRRuntimeToken method, EHRRuntimeToken instance, const EHRRuntimeArgument *arguments = nullptr, size_t count = 0) {
        Invocation answer{EHR_RUNTIME_NOT_READY, 0, 0};
        answer.status = invoke(method, instance, arguments, count, &answer.value, &answer.exception);
        keep(answer.value); keep(answer.exception);
        return answer;
    };
    auto boolean = [&](Invocation answer, bool expected) {
        uint8_t value = 9;
        size_t size = 0;
        return answer.status == EHR_RUNTIME_OK && !answer.exception && answer.value &&
            copy_value(answer.value, &value, sizeof(value), &size) == EHR_RUNTIME_OK && size == 1 && value == (expected ? 1 : 0);
    };
    EHRRuntimeToken arrayList = 0, enumerable = 0, enumerator = 0, listInterface = 0, simple = 0, intClass = 0;
    check(@"arrayListCarrierClass", find_class("mscorlib.dll", "System.Collections", "ArrayList", &arrayList) == EHR_RUNTIME_OK);
    check(@"enumerableInterface", find_class("mscorlib.dll", "System.Collections", "IEnumerable", &enumerable) == EHR_RUNTIME_OK);
    check(@"enumeratorInterface", find_class("mscorlib.dll", "System.Collections", "IEnumerator", &enumerator) == EHR_RUNTIME_OK);
    check(@"listInterface", find_class("mscorlib.dll", "System.Collections", "IList", &listInterface) == EHR_RUNTIME_OK);
    check(@"nestedEnumeratorCandidateClass", find_class("mscorlib.dll", "System.Collections", "ArrayList+ArrayListEnumeratorSimple", &simple) == EHR_RUNTIME_OK);
    check(@"carrierIntClass", find_class("mscorlib.dll", "System", "Int32", &intClass) == EHR_RUNTIME_OK);
    EHRRuntimeToken getEnumerator = 0, moveNext = 0, current = 0, reset = 0, add = 0;
    check(@"getEnumeratorSignature", find_method(enumerable, "GetEnumerator", nullptr, 0, "System.Collections.IEnumerator", 0, &getEnumerator) == EHR_RUNTIME_OK);
    check(@"moveNextSignature", find_method(enumerator, "MoveNext", nullptr, 0, "System.Boolean", 0, &moveNext) == EHR_RUNTIME_OK);
    check(@"currentSignature", find_method(enumerator, "get_Current", nullptr, 0, "System.Object", 0, &current) == EHR_RUNTIME_OK);
    check(@"resetSignature", find_method(enumerator, "Reset", nullptr, 0, "System.Void", 0, &reset) == EHR_RUNTIME_OK);
    const char *addTypes[] = {"System.Object"};
    check(@"carrierListAddSignature", find_method(listInterface, "Add", addTypes, 1, "System.Int32", 0, &add) == EHR_RUNTIME_OK);
    EHRRuntimeToken dispose = 123;
    check(@"concreteEnumeratorHasNoDisposeMethod", find_method(simple, "Dispose", nullptr, 0, "System.Void", 0, &dispose) == EHR_RUNTIME_NOT_FOUND && !dispose);
    EHRRuntimeToken list = 0, exception = 0;
    auto status = construct(arrayList, nullptr, 0, &list, &exception);
    keep(list); keep(exception);
    check(@"constructIndependentList", status == EHR_RUNTIME_OK && list && !exception);
    const uint16_t text[] = {'c','a','r','r','i','e','r'};
    EHRRuntimeToken yieldedString = 0, yieldedInteger = 0;
    const int32_t number = 73;
    check(@"ownCarrierString", string_create(text, sizeof(text) / sizeof(text[0]), &yieldedString) == EHR_RUNTIME_OK && yieldedString);
    check(@"ownCarrierBoxedInteger", box(intClass, &number, sizeof(number), &yieldedInteger) == EHR_RUNTIME_OK && yieldedInteger);
    keep(yieldedString); keep(yieldedInteger);
    const EHRRuntimeToken values[] = {yieldedString, yieldedInteger, 0};
    for (size_t i = 0; i < 3; ++i) {
        const EHRRuntimeArgument value{EHR_RUNTIME_REFERENCE, 0, values[i], nullptr, 0};
        const auto added = call(add, list, &value, 1);
        int32_t index = -1; size_t size = 0;
        check([NSString stringWithFormat:@"carrierValueAdded%zu", i], added.status == EHR_RUNTIME_OK && !added.exception &&
              copy_value(added.value, &index, sizeof(index), &size) == EHR_RUNTIME_OK && size == sizeof(index) && index == static_cast<int32_t>(i));
    }
    const auto first = call(getEnumerator, list);
    const auto second = call(getEnumerator, list);
    check(@"constructSeparateEnumerators", first.status == EHR_RUNTIME_OK && second.status == EHR_RUNTIME_OK && first.value && second.value && !first.exception && !second.exception);
    EHRRuntimeToken actual = 0;
    check(@"actualFactoryReturnsClassifiedConcreteType", object_class(first.value, &actual) == EHR_RUNTIME_OK && actual == simple);
    size_t required = 0;
    status = class_type_name(actual, nullptr, 0, &required);
    if (status == EHR_RUNTIME_LIMIT && required > 1 && required <= 4096) {
        std::vector<char> spelling(required);
        if (class_type_name(actual, spelling.data(), spelling.size(), &required) == EHR_RUNTIME_OK)
            proof[@"actualEnumeratorTypeName"] = [NSString stringWithUTF8String:spelling.data()];
    }
    EHRRuntimeToken retained = 0;
    check(@"retainCarrierIdentity", object_retain(first.value, &retained) == EHR_RUNTIME_OK && retained);
    keep(retained);
    int32_t same = -1;
    check(@"separateEnumeratorsHaveSeparateIdentity", object_same(first.value, second.value, &same) == EHR_RUNTIME_OK && same == 0);
    check(@"retainedCarrierHasSameIdentity", object_same(first.value, retained, &same) == EHR_RUNTIME_OK && same == 1);
    int32_t hash = 0, retainedHash = 1;
    exception = 0; status = object_identity_hash(first.value, &hash, &exception); keep(exception);
    check(@"carrierIdentityHash", status == EHR_RUNTIME_OK && !exception);
    exception = 0; status = object_identity_hash(retained, &retainedHash, &exception); keep(exception);
    check(@"carrierIdentityHashStableAcrossOwners", status == EHR_RUNTIME_OK && !exception && retainedHash == hash);
    const auto before = call(current, first.value);
    check(@"currentBeforeFirstMoveThrows", before.status == EHR_RUNTIME_MANAGED_EXCEPTION && before.exception && !before.value);
    check(@"normalFirstMoveNext", boolean(call(moveNext, first.value), true));
    const auto yielded = call(current, first.value);
    check(@"currentReturnsActualYieldObject", yielded.status == EHR_RUNTIME_OK && !yielded.exception && yielded.value &&
          object_same(yielded.value, yieldedString, &same) == EHR_RUNTIME_OK && same == 1);
    const auto repeated = call(current, retained);
    check(@"currentRepeatedGetterHasIndependentOwnedRoot", repeated.status == EHR_RUNTIME_OK && !repeated.exception && repeated.value && repeated.value != yielded.value &&
          object_same(repeated.value, yielded.value, &same) == EHR_RUNTIME_OK && same == 1);
    const auto resetResult = call(reset, retained);
    check(@"normalReset", resetResult.status == EHR_RUNTIME_OK && !resetResult.value && !resetResult.exception);
    const auto afterReset = call(current, first.value);
    check(@"resetRestoresInvalidCurrent", afterReset.status == EHR_RUNTIME_MANAGED_EXCEPTION && afterReset.exception && !afterReset.value);
    check(@"separateEnumeratorPositionIndependent", boolean(call(moveNext, second.value), true));
    for (size_t i = 0; i < 3; ++i) {
        check([NSString stringWithFormat:@"normalIterationMove%zu", i], boolean(call(moveNext, first.value), true));
        const auto item = call(current, first.value);
        check([NSString stringWithFormat:@"normalIterationCurrent%zu", i], item.status == EHR_RUNTIME_OK && !item.exception &&
              object_same(item.value, values[i], &same) == EHR_RUNTIME_OK && same == 1);
    }
    check(@"normalIterationCompletes", boolean(call(moveNext, first.value), false));
    check(@"completedMoveNextRemainsFalse", boolean(call(moveNext, first.value), false));
    const auto ended = call(current, first.value);
    check(@"currentAfterCompletionThrows", ended.status == EHR_RUNTIME_MANAGED_EXCEPTION && ended.exception && !ended.value);
    const EHRRuntimeArgument extra{EHR_RUNTIME_REFERENCE, 0, 0, nullptr, 0};
    const auto mutated = call(add, list, &extra, 1);
    check(@"independentListMutationForVersionGuard", mutated.status == EHR_RUNTIME_OK && !mutated.exception);
    const auto invalidated = call(moveNext, second.value);
    check(@"normalEnumeratorVersionGuard", invalidated.status == EHR_RUNTIME_MANAGED_EXCEPTION && invalidated.exception && !invalidated.value);
    bool released = true;
    for (const auto token : roots) released = object_release(token) == EHR_RUNTIME_OK && released;
    check(@"allCarrierBaselineRootsReleasedOnce", released);
    proof[@"adapterHooksInstalled"] = @NO;
    proof[@"managedToIl2CppAdapterImplemented"] = @NO;
    proof[@"gameplayMutationPerformed"] = @NO;
    proof[@"success"] = @(passed);
    return proof;
}
NSDictionary *exerciseDeferredRelease(XCTestCase *test) {
#define RELEASE_API(name) auto name = reinterpret_cast<decltype(&ehr_runtime_##name)>(bridgeExport("ehr_runtime_" #name)); if (!name) return @{ @"success": @NO, @"missingExport": @#name }
    RELEASE_API(string_create); RELEASE_API(string_copy); RELEASE_API(object_retain);
    RELEASE_API(object_release); RELEASE_API(object_release_deferred);
    RELEASE_API(object_same); RELEASE_API(object_identity_hash);
    RELEASE_API(drain_deferred_releases);
#undef RELEASE_API
    NSMutableDictionary *proof = [NSMutableDictionary dictionary];
    static const uint16_t units[] = {'d', 'e', 'f', 'e', 'r'};
    EHRRuntimeToken owner = 0, queued = 0;
    if (string_create(units, 5, &owner) != EHR_RUNTIME_OK || !owner)
        return @{ @"success": @NO, @"setup": @"string" };
    if (object_retain(owner, &queued) != EHR_RUNTIME_OK || !queued) {
        object_release(owner);
        return @{ @"success": @NO, @"setup": @"retained root" };
    }
    XCTestExpectation *finished = [test expectationWithDescription:@"Background deferred release automatically drains on main"];
    __block bool completed = false;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        const bool background = ![NSThread isMainThread];
        const auto enqueued = object_release_deferred(queued);
        // Both main-queue submissions originate on this worker in order: the
        // gateway's automatic drain precedes this verification block. No later
        // facade operation is needed to release the queued root.
        dispatch_async(dispatch_get_main_queue(), ^{
            uint16_t copied[5] = {};
            size_t length = 0;
            int32_t same = -1, hash = 0;
            EHRRuntimeToken exception = 0;
            const auto stale = string_copy(queued, copied, 5, &length);
            const bool sameRejected = object_same(owner, queued, &same) == EHR_RUNTIME_INVALID_TOKEN;
            const bool hashRejected = object_identity_hash(queued, &hash, &exception) == EHR_RUNTIME_INVALID_TOKEN && !exception;
            const bool ownerAlive = string_copy(owner, copied, 5, &length) == EHR_RUNTIME_OK && length == 5 &&
                !memcmp(copied, units, sizeof(units));
            const auto duplicateEnqueued = object_release_deferred(queued);
            size_t freed = 999;
            const bool duplicateIgnored = drain_deferred_releases(&freed) == EHR_RUNTIME_OK && freed == 0;
            if (stale != EHR_RUNTIME_INVALID_TOKEN) object_release(queued);
            const bool ownerReleased = object_release(owner) == EHR_RUNTIME_OK;
            proof[@"enqueuedFromBackground"] = @(background && enqueued == EHR_RUNTIME_OK);
            proof[@"automaticMainQueueDrain"] = @(stale == EHR_RUNTIME_INVALID_TOKEN);
            proof[@"staleIdentityRejected"] = @(sameRejected);
            proof[@"staleIdentityHashRejected"] = @(hashRejected);
            proof[@"separateOwnedRootRemainsAlive"] = @(ownerAlive);
            proof[@"duplicateDeferredReleaseIgnored"] = @(duplicateEnqueued == EHR_RUNTIME_OK && duplicateIgnored);
            proof[@"remainingRootReleasedOnce"] = @(ownerReleased);
            proof[@"success"] = @(background && enqueued == EHR_RUNTIME_OK && stale == EHR_RUNTIME_INVALID_TOKEN &&
                sameRejected && hashRejected && ownerAlive && duplicateEnqueued == EHR_RUNTIME_OK && duplicateIgnored && ownerReleased);
            completed = true;
            [finished fulfill];
        });
    });
    [test waitForExpectations:@[finished] timeout:5];
    if (!completed) {
        object_release(queued); object_release(owner);
        return @{ @"success": @NO, @"timeout": @YES };
    }
    return proof;
}
NSDictionary *exerciseValueReceivers(void) {
#define VALUE_API(name) auto name = reinterpret_cast<decltype(&ehr_runtime_##name)>(bridgeExport("ehr_runtime_" #name)); if (!name) return @{ @"success": @NO, @"missingExport": @#name }
    VALUE_API(find_class); VALUE_API(find_method); VALUE_API(box); VALUE_API(invoke);
    VALUE_API(invoke_with_refs); VALUE_API(copy_value); VALUE_API(string_copy);
    VALUE_API(class_from_type_object); VALUE_API(object_release);
#undef VALUE_API
    NSMutableDictionary *proof = [NSMutableDictionary dictionary];
    std::vector<EHRRuntimeToken> roots;
    bool passed = true;
    auto check = [&](NSString *key, bool condition) { proof[key] = @(condition); passed = passed && condition; };
    auto keep = [&](EHRRuntimeToken value) { if (value) roots.push_back(value); };
    EHRRuntimeToken intClass = 0, vectorClass = 0, objectClass = 0;
    check(@"scalarReceiverClass", find_class("mscorlib.dll", "System", "Int32", &intClass) == EHR_RUNTIME_OK);
    check(@"vectorReceiverClass", find_class("UnityEngine.CoreModule.dll", "UnityEngine", "Vector2", &vectorClass) == EHR_RUNTIME_OK);
    check(@"referenceBaseClass", find_class("mscorlib.dll", "System", "Object", &objectClass) == EHR_RUNTIME_OK);
    const int32_t number = 42;
    EHRRuntimeToken integer = 0, toString = 0;
    check(@"boxScalarReceiver", box(intClass, &number, sizeof(number), &integer) == EHR_RUNTIME_OK && integer);
    keep(integer);
    check(@"scalarInstanceMethod", find_method(intClass, "ToString", nullptr, 0, "System.String", 0, &toString) == EHR_RUNTIME_OK);
    EHRRuntimeToken returned = 0, exception = 0;
    auto status = invoke(toString, integer, nullptr, 0, &returned, &exception);
    keep(returned); keep(exception);
    uint16_t characters[16] = {};
    size_t length = 0, bytes = 0;
    check(@"unboxedInt32ReceiverToString", status == EHR_RUNTIME_OK && !exception &&
          string_copy(returned, characters, 16, &length) == EHR_RUNTIME_OK && length == 2 && characters[0] == '4' && characters[1] == '2');
    EHRRuntimeToken virtualToString = 0;
    check(@"referenceBaseVirtualSignature", find_method(objectClass, "ToString", nullptr, 0, "System.String", 0, &virtualToString) == EHR_RUNTIME_OK);
    returned = exception = 0;
    status = invoke(virtualToString, integer, nullptr, 0, &returned, &exception);
    keep(returned); keep(exception);
    check(@"resolvedValueOverrideUsesUnboxedThis", status == EHR_RUNTIME_OK && !exception &&
          string_copy(returned, characters, 16, &length) == EHR_RUNTIME_OK && length == 2 && characters[0] == '4' && characters[1] == '2');
    EHRRuntimeToken getType = 0;
    check(@"boxedBaseMethodSignature", find_method(objectClass, "GetType", nullptr, 0, "System.Type", 0, &getType) == EHR_RUNTIME_OK);
    returned = exception = 0;
    status = invoke(getType, integer, nullptr, 0, &returned, &exception);
    keep(returned); keep(exception);
    EHRRuntimeToken actualType = 0;
    check(@"referenceBaseMethodKeepsBoxedThis", status == EHR_RUNTIME_OK && !exception &&
          class_from_type_object(returned, &actualType) == EHR_RUNTIME_OK && actualType == intClass);
    struct Vector { float x, y; };
    const Vector initial{3, 4};
    EHRRuntimeToken vector = 0, control = 0, magnitudeGetter = 0, normalize = 0;
    check(@"boxMutableVectorReceiver", box(vectorClass, &initial, sizeof(initial), &vector) == EHR_RUNTIME_OK && vector);
    check(@"boxIndependentVectorControl", box(vectorClass, &initial, sizeof(initial), &control) == EHR_RUNTIME_OK && control);
    keep(vector); keep(control);
    check(@"magnitudeReceiverSignature", find_method(vectorClass, "get_magnitude", nullptr, 0, "System.Single", 0, &magnitudeGetter) == EHR_RUNTIME_OK);
    check(@"mutatingReceiverSignature", find_method(vectorClass, "Normalize", nullptr, 0, "System.Void", 0, &normalize) == EHR_RUNTIME_OK);
    returned = exception = 0;
    status = invoke(magnitudeGetter, vector, nullptr, 0, &returned, &exception);
    keep(returned); keep(exception);
    float magnitude = 0;
    check(@"boxedVectorMagnitude", status == EHR_RUNTIME_OK && !exception &&
          copy_value(returned, &magnitude, sizeof(magnitude), &bytes) == EHR_RUNTIME_OK && magnitude == 5);
    returned = exception = 0;
    status = invoke(normalize, vector, nullptr, 0, &returned, &exception);
    keep(returned); keep(exception);
    check(@"boxedVectorNormalizeCompleted", status == EHR_RUNTIME_OK && !returned && !exception);
    Vector changed{}, unchanged{};
    check(@"mutationTargetsOnlyBoxedReceiver", copy_value(vector, &changed, sizeof(changed), &bytes) == EHR_RUNTIME_OK &&
          changed.x > 0.59999f && changed.x < 0.60001f && changed.y > 0.79999f && changed.y < 0.80001f &&
          copy_value(control, &unchanged, sizeof(unchanged), &bytes) == EHR_RUNTIME_OK && unchanged.x == 3 && unchanged.y == 4);
    returned = exception = 0;
    status = invoke_with_refs(magnitudeGetter, vector, nullptr, 0, nullptr, 0, &returned, &exception);
    keep(returned); keep(exception);
    magnitude = 0;
    check(@"valueReceiverInExplicitRefEntryPoint", status == EHR_RUNTIME_OK && !exception &&
          copy_value(returned, &magnitude, sizeof(magnitude), &bytes) == EHR_RUNTIME_OK && magnitude > 0.99999f && magnitude < 1.00001f);
    returned = exception = 0;
    check(@"wrongReceiverClassRejected", invoke(normalize, integer, nullptr, 0, &returned, &exception) == EHR_RUNTIME_TYPE_MISMATCH && !returned && !exception);
    bool released = true;
    for (const auto root : roots) released = object_release(root) == EHR_RUNTIME_OK && released;
    check(@"allValueReceiverTestRootsReleased", released);
    proof[@"gameplayMutationPerformed"] = @NO;
    proof[@"success"] = @(passed);
    return proof;
}
}

@interface NativeRuntimeTests : XCTestCase
@end
@implementation NativeRuntimeTests
- (void)testSignedCandidateLoadsActualRuntime {
    XCTAssertEqualObjects(NSBundle.mainBundle.bundleIdentifier, @"__EHR_TEST_APP_BUNDLE_ID__");
    XCTestExpectation *ready = [self expectationWithDescription:@"Actual Unity game assembly becomes available"];
    __block NSDictionary *lastSnapshot = nil;
    __block NSDictionary *lastHooks = nil;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), 250 * NSEC_PER_MSEC, 25 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        using Snapshot = NSDictionary *(*)(void);
        auto snapshot = reinterpret_cast<Snapshot>(bridgeExport("EHRLiveBridgeCopySnapshot"));
        auto hooks = reinterpret_cast<Snapshot>(bridgeExport("EHRNativeHooksCopyStatus"));
        if (!snapshot || !hooks) return;
        lastSnapshot = snapshot(); lastHooks = hooks();
        NSDictionary *runtime = lastSnapshot[@"runtime"];
        if ([lastSnapshot[@"status"] isEqual:@"live_sample"] && [runtime[@"gameAssemblyFound"] boolValue]) {
            dispatch_source_cancel(timer);
            [ready fulfill];
        }
    });
    dispatch_resume(timer);
    [self waitForExpectations:@[ready] timeout:45];
    dispatch_source_cancel(timer);
    XCTAssertEqualObjects(lastSnapshot[@"status"], @"live_sample");
    XCTAssertTrue([lastSnapshot[@"runtime"][@"gameAssemblyFound"] boolValue]);
    XCTAssertTrue([lastHooks[@"entryInterceptorsBuilt"] boolValue]);
    using HookStatus = NSDictionary *(*)(void);
    auto hooks = reinterpret_cast<HookStatus>(bridgeExport("EHRNativeHooksCopyStatus"));
    NSDictionary *beforeGetter = hooks ? hooks() : @{};
    NSDictionary *getter = exerciseVersionGetter();
    NSDictionary *gateway = exerciseGateway();
    NSDictionary *methodReflection = exerciseMethodReflection();
    NSDictionary *typeNames = exerciseTypeNames();
    NSDictionary *iteratorCarrier = exerciseIteratorCarrierBaseline();
    NSDictionary *vectorClasses = exerciseVectorClasses();
    NSDictionary *nestedClasses = exerciseNestedClasses();
    NSDictionary *deferredRelease = exerciseDeferredRelease(self);
    NSDictionary *valueReceivers = exerciseValueReceivers();
    using ManagedTest = NSDictionary *(*)(void);
    auto managedTest = reinterpret_cast<ManagedTest>(bridgeExport("EHRManagedRuntimeSelfTest"));
    NSDictionary *managed = managedTest ? managedTest() : @{ @"success": @NO, @"missingExport": @YES };
    NSDictionary *unityScheduling = EHRExerciseIteratorScheduling(self, bridgeExport);
    lastHooks = hooks ? hooks() : @{};
    XCTAssertTrue([getter[@"success"] boolValue], @"%@", getter);
    XCTAssertTrue([gateway[@"success"] boolValue], @"%@", gateway);
    XCTAssertTrue([methodReflection[@"success"] boolValue], @"%@", methodReflection);
    XCTAssertTrue([typeNames[@"success"] boolValue], @"%@", typeNames);
    XCTAssertTrue([iteratorCarrier[@"success"] boolValue], @"%@", iteratorCarrier);
    XCTAssertTrue([vectorClasses[@"success"] boolValue], @"%@", vectorClasses);
    XCTAssertTrue([nestedClasses[@"success"] boolValue], @"%@", nestedClasses);
    XCTAssertTrue([deferredRelease[@"success"] boolValue], @"%@", deferredRelease);
    XCTAssertTrue([valueReceivers[@"success"] boolValue], @"%@", valueReceivers);
    XCTAssertTrue([managed[@"success"] boolValue], @"%@", managed);
    XCTAssertTrue([unityScheduling[@"success"] boolValue], @"%@", unityScheduling);
    XCTAssertGreaterThan([lastHooks[@"broadcastVersionCallbacks"] unsignedLongLongValue],
                         [beforeGetter[@"broadcastVersionCallbacks"] unsignedLongLongValue]);
    XCTAssertTrue([lastHooks[@"pinnedImageObserved"] boolValue]);
    XCTAssertGreaterThan([lastHooks[@"managedIsVersionModdedPrefixes"] unsignedLongLongValue], 0ULL);
    XCTAssertEqual([lastHooks[@"isVersionModdedOriginalCalls"] unsignedLongLongValue], 0ULL);
    XCTAssertEqual([lastHooks[@"managedIsVersionModdedPrefixErrors"] unsignedLongLongValue], 0ULL);
    // No UI action, game agreement, account login, role assignment, kill or
    // reporting is performed by this runtime startup check.
    NSDictionary *proof = @{
        @"scope": @"Actual game runtime startup under normal XCTest host launch",
        @"gameAssemblyFound": @([lastSnapshot[@"runtime"][@"gameAssemblyFound"] boolValue]),
        @"status": lastSnapshot[@"status"] ?: @"unavailable",
        @"nativeHooks": lastHooks ?: @{},
        @"versionGetter": getter,
        @"runtimeGateway": gateway,
        @"methodReflection": methodReflection,
        @"runtimeTypeNames": typeNames,
        @"iteratorCarrierBaseline": iteratorCarrier,
        @"vectorClasses": vectorClasses,
        @"nestedClasses": nestedClasses,
        @"deferredRelease": deferredRelease,
        @"valueReceivers": valueReceivers,
        @"managedSourceReuse": managed,
        @"unityIteratorScheduling": unityScheduling,
        @"nativeHooksBeforeGetter": beforeGetter,
        @"multiplayerVerified": @NO,
        @"termsAcceptedByTest": @NO
    };
    NSLog(@"EHR_XCTEST_RUNTIME_PREDICATE_CONFIRMED status=%@ gameAssemblyFound=%d", lastSnapshot[@"status"], [lastSnapshot[@"runtime"][@"gameAssemblyFound"] boolValue]);
    // The normal XCTest stdout stream is captured in the result bundle. Avoid
    // cache/file writes here; the result bundle keeps these diagnostics.
    NSData *data = [NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingPrettyPrinted error:nil];
    NSData *snapshotData = [NSJSONSerialization dataWithJSONObject:lastSnapshot ?: @{} options:NSJSONWritingPrettyPrinted error:nil];
    NSLog(@"EHR_NATIVE_RUNTIME_TEST %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    NSLog(@"EHR_NATIVE_RUNTIME_SNAPSHOT %@", [[NSString alloc] initWithData:snapshotData encoding:NSUTF8StringEncoding]);
    NSLog(@"EHR_NATIVE_RUNTIME_DERIVED_CACHES_PATH %@", [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"]);
    XCTAttachment *proofAttachment = [XCTAttachment attachmentWithData:data uniformTypeIdentifier:@"public.json"];
    proofAttachment.name = @"EHRNativeXCTestProof.json";
    proofAttachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:proofAttachment];
    XCTAttachment *snapshotAttachment = [XCTAttachment attachmentWithData:snapshotData uniformTypeIdentifier:@"public.json"];
    snapshotAttachment.name = @"EHRNativeXCTestSnapshot.json";
    snapshotAttachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:snapshotAttachment];
    if (EHR_XCTEST_WRAPPER_HOLD_SECONDS > 0) {
        NSLog(@"EHR_XCTEST_WRAPPER_READY %@", NSBundle.mainBundle.bundlePath);
        XCTestExpectation *preservationWindow = [self expectationWithDescription:@"Normal Xcode wrapper preservation window"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, EHR_XCTEST_WRAPPER_HOLD_SECONDS * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [preservationWindow fulfill];
        });
        [self waitForExpectations:@[preservationWindow] timeout:EHR_XCTEST_WRAPPER_HOLD_SECONDS + 5];
    }
}
@end
