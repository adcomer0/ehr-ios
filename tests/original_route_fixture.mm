// Original owned fixture. Executes the real staged gateway against explicitly
// installed test API callbacks, never an EHR/game assembly or game image.
#include "EHRRuntimeGateway.mm"
#import "EHRNativeHooks.h"
#include <cassert>
#include <iostream>
#include <stdexcept>
#include <thread>

namespace {
struct Domain {};
struct Image { const char *name; };
struct Assembly { const Image *image; };
struct Type { const char *name; int kind; RuntimeClass *klass; };
struct RuntimeClass { const char *name; Type *type; bool value; };
struct Method { const char *name; Type *returns; RuntimeClass *owner; };
struct Object { RuntimeClass *klass; int32_t value; };
Domain fixtureDomain;
Image fixtureImage{"Assembly-CSharp.dll"};
Assembly fixtureAssembly{&fixtureImage};
const Assembly *fixtureAssemblies[]{&fixtureAssembly};
RuntimeClass constants{}, intClass{}, boolClass{};
Type intType{"System.Int32", 0x08, &intClass}, boolType{"System.Boolean", 0x02, &boolClass};
Method version{"GetBroadcastVersion", &intType, &constants}, foreign{"IsVersionModded", &boolType, &constants};
Object boxed{&intClass, 100}, exceptionObject{&constants, 0};
std::unordered_map<uint32_t, Object *> fixtureRoots;
uint32_t nextHandle = 1;
uint64_t runtimeEntries = 0, normalPatches = 0, originalBodies = 0, foreignInvocations = 0;
bool noHook = false, throwOriginal = false, throwNative = false, recurseOnce = false;
int32_t fakeHook(const Method *method);
int32_t fakeOriginal(const Method *method) {
    ++originalBodies;
    if (throwOriginal) throw std::runtime_error("owned caught original exception");
    if (recurseOnce) { recurseOnce = false; (void)fakeHook(method); }
    return 100;
}
int32_t fakeHook(const Method *method) {
    if (EHRTryConsumeOriginalInvocation(EHR_ORIGINAL_TARGET_BROADCAST_VERSION, method))
        return fakeOriginal(method);
    ++normalPatches;
    return fakeOriginal(method) + 25;
}
Object *fakeRuntimeInvoke(const Method *method, void *, void **, Exception **raised) {
    ++runtimeEntries;
    *raised = nullptr;
    if (throwNative) throw std::logic_error("owned unexpected native exception");
    try {
        if (method != &version) { ++foreignInvocations; return nullptr; }
        boxed.value = noHook ? fakeOriginal(method) : fakeHook(method);
        return &boxed;
    } catch (const std::runtime_error &) {
        *raised = reinterpret_cast<Exception *>(&exceptionObject);
        return nullptr;
    }
}
void installFixtureAPI() {
    constants = {"Constants", nullptr, false};
    intClass = {"Int32", &intType, true}; boolClass = {"Boolean", &boolType, true};
    auto &s = state(); s.loaded = true;
    auto &a = s.api;
    a.domain_get = [] { return &fixtureDomain; };
    a.domain_get_assemblies = [](const Domain *, size_t *count) { *count = 1; return fixtureAssemblies; };
    a.assembly_get_image = [](const Assembly *assembly) { return assembly->image; };
    a.image_get_name = [](const Image *image) { return image->name; };
    a.class_from_name = [](const Image *, const char *space, const char *name) -> RuntimeClass * {
        return !strcmp(space, "") && !strcmp(name, "Constants") ? &constants : nullptr;
    };
    a.class_get_parent = [](RuntimeClass *) -> RuntimeClass * { return nullptr; };
    a.class_get_name = [](RuntimeClass *c) { return c->name; };
    a.class_get_namespace = [](RuntimeClass *) { return ""; };
    a.class_get_nested_types = [](RuntimeClass *, void **) -> RuntimeClass * { return nullptr; };
    a.class_get_type = [](RuntimeClass *c) -> const Type * { return c->type; };
    a.class_is_generic = [](const RuntimeClass *) { return false; };
    a.class_is_inflated = [](const RuntimeClass *) { return false; };
    a.class_is_valuetype = [](const RuntimeClass *c) { return c->value; };
    a.class_has_references = [](RuntimeClass *) { return false; };
    a.class_is_blittable = [](const RuntimeClass *) { return true; };
    a.class_value_size = [](RuntimeClass *c, uint32_t *align) { *align = 4; return c == &boolClass ? 1 : 4; };
    a.class_get_methods = [](RuntimeClass *c, void **iter) -> const Method * {
        if (c != &constants) return nullptr;
        const auto index = reinterpret_cast<uintptr_t>(*iter);
        *iter = reinterpret_cast<void *>(index + 1);
        return index == 0 ? &version : index == 1 ? &foreign : nullptr;
    };
    a.method_get_name = [](const Method *method) { return method->name; };
    a.method_get_flags = [](const Method *, uint32_t *impl) { *impl = 0; return kStatic; };
    a.method_get_param_count = [](const Method *) -> uint32_t { return 0; };
    a.method_get_return_type = [](const Method *method) -> const Type * { return method->returns; };
    a.method_get_declaring_type = [](const Method *method) { return method->owner; };
    a.method_is_generic = [](const Method *) { return false; };
    a.type_get_name = [](const Type *type) { return strdup(type->name); };
    a.type_get_type = [](const Type *type) { return type->kind; };
    a.type_is_byref = [](const Type *) { return false; };
    a.runtime_free = free;
    a.runtime_invoke = fakeRuntimeInvoke;
    a.thread_current = []() -> void * { return &fixtureDomain; };
    a.thread_attach = [](Domain *) -> void * { return &fixtureDomain; };
    a.gchandle_new = [](Object *value, bool) { const auto handle = nextHandle++; fixtureRoots[handle] = value; return handle; };
    a.gchandle_get_target = [](uint32_t handle) -> Object * {
        const auto found = fixtureRoots.find(handle); return found == fixtureRoots.end() ? nullptr : found->second;
    };
    a.gchandle_free = [](uint32_t handle) { fixtureRoots.erase(handle); };
    a.object_get_class = [](Object *object) { return object->klass; };
    a.object_unbox = [](Object *object) -> void * { return &object->value; };
}
EHROriginalInvocationToken open(EHRRuntimeToken method) {
    EHROriginalInvocationToken call = 0;
    assert(ehr_runtime_original_begin(EHR_ORIGINAL_TARGET_BROADCAST_VERSION, method, &call) == EHR_RUNTIME_OK && call);
    return call;
}
EHRRuntimeStatus invoke(EHROriginalInvocationToken call, EHRRuntimeToken method,
    EHRRuntimeToken *result, EHRRuntimeToken *exception, EHROriginalInvocationProofV1 *proof) {
    return ehr_runtime_invoke_original(call, EHR_ORIGINAL_TARGET_BROADCAST_VERSION, method, 0, nullptr, 0,
        result, exception, proof, sizeof(*proof));
}
}

extern "C" NSDictionary<NSString *, id> *EHRNativeHooksCopyStatus(void) {
    return @{ @"broadcastVersionCallbacks": @(normalPatches), @"managedVersionPostfixCalls": @(normalPatches),
        @"moddedBroadcastVersions": @(normalPatches), @"broadcastOriginalBypasses": @(EHROriginalInvocationBypassCount()) };
}

int main() { @autoreleasepool {
    installFixtureAPI();
    NSDictionary *report = EHRRuntimeOriginalSelfTest();
    if (![report[@"success"] boolValue]) { NSLog(@"%@", report); return 1; }
    assert(fixtureRoots.empty() && state().roots.empty() && originalRoutes().calls.empty());
    assert(runtimeEntries == 2 && originalBodies == 2 && normalPatches == 1 && foreignInvocations == 0);
    EHRRuntimeToken method = 0;
    assert(ehr_runtime_original_target_method(EHR_ORIGINAL_TARGET_BROADCAST_VERSION, &method) == EHR_RUNTIME_OK);
    assert(ehr_runtime_original_register(0,method,4)==EHR_RUNTIME_BAD_ARGUMENT);
    assert(ehr_runtime_original_register(1,method,4)==EHR_RUNTIME_BAD_ARGUMENT);
    assert(ehr_runtime_original_register(2,method,3)==EHR_RUNTIME_BAD_ARGUMENT);
    assert(ehr_runtime_original_register(2,UINT64_MAX,4)==EHR_RUNTIME_INVALID_TOKEN);
    assert(ehr_runtime_original_register(2,method,4)==EHR_RUNTIME_TYPE_MISMATCH);
    EHRRuntimeToken result = 0, exception = 0;
    EHROriginalInvocationProofV1 proof{};

    auto call = open(method); recurseOnce = true;
    assert(invoke(call, method, &result, &exception, &proof) == EHR_RUNTIME_OK);
    assert(proof.permit_consumed == 1 && proof.hook_consumptions == 1 && normalPatches == 2 && originalBodies == 4);
    assert(ehr_runtime_object_release(result) == EHR_RUNTIME_OK); result = 0;
    assert(ehr_runtime_original_end(call) == EHR_RUNTIME_OK);
    assert(ehr_runtime_original_end(call) == EHR_RUNTIME_INVALID_TOKEN);

    call = open(method); noHook = true;
    assert(invoke(call, method, &result, &exception, &proof) == EHR_RUNTIME_UNSUPPORTED);
    assert(proof.runtime_invoke_entered == 1 && !proof.permit_consumed && !result && !exception);
    noHook = false; assert(ehr_runtime_original_end(call) == EHR_RUNTIME_OK);
    assert(!EHRTryConsumeOriginalInvocation(EHR_ORIGINAL_TARGET_BROADCAST_VERSION, &version));

    call = open(method); throwOriginal = true;
    assert(invoke(call, method, &result, &exception, &proof) == EHR_RUNTIME_MANAGED_EXCEPTION);
    assert(proof.permit_consumed == 1 && proof.hook_consumptions == 1 && exception && !result);
    Object *raised = nullptr; assert(object(exception, &raised) == EHR_RUNTIME_OK && raised == &exceptionObject);
    assert(ehr_runtime_object_release(exception) == EHR_RUNTIME_OK); exception = 0;
    throwOriginal = false; assert(ehr_runtime_original_end(call) == EHR_RUNTIME_OK);

    call = open(method); throwNative = true;
    assert(invoke(call, method, &result, &exception, &proof) == EHR_RUNTIME_UNSUPPORTED);
    assert(proof.runtime_invoke_entered == 1 && !proof.permit_consumed && activeOriginalCall == nullptr);
    throwNative = false; assert(ehr_runtime_original_end(call) == EHR_RUNTIME_OK);
    assert(!EHRTryConsumeOriginalInvocation(EHR_ORIGINAL_TARGET_BROADCAST_VERSION, &version));

    call = open(method);
    const uint64_t before = runtimeEntries;
    EHRRuntimeArgument extra{};
    assert(ehr_runtime_invoke_original(call, EHR_ORIGINAL_TARGET_BROADCAST_VERSION, method, 0, &extra, 1,
        &result, &exception, &proof, sizeof(proof)) == EHR_RUNTIME_BAD_ARGUMENT);
    assert(proof.original_request_accepted == 1 && !proof.runtime_invoke_entered && runtimeEntries == before);
    assert(invoke(call, method, &result, &exception, &proof) == EHR_RUNTIME_BAD_ARGUMENT);
    assert(runtimeEntries == before && ehr_runtime_original_end(call) == EHR_RUNTIME_OK);

    call = open(method);
    EHRRuntimeStatus workerStatus = EHR_RUNTIME_OK;
    std::thread worker([&] { EHROriginalInvocationProofV1 workerProof{}; EHRRuntimeToken r = 0, e = 0;
        workerStatus = invoke(call, method, &r, &e, &workerProof); }); worker.join();
    assert(workerStatus == EHR_RUNTIME_WRONG_THREAD);
    assert(invoke(call, method, &result, &exception, &proof) == EHR_RUNTIME_OK);
    assert(ehr_runtime_object_release(result) == EHR_RUNTIME_OK); result = 0;
    assert(ehr_runtime_original_end(call) == EHR_RUNTIME_OK);
    assert(fixtureRoots.empty() && state().roots.empty() && originalRoutes().calls.empty());
    call=open(method);
    assert(ehr_runtime_invoke_original_with_refs(call,EHR_ORIGINAL_TARGET_BROADCAST_VERSION,method,0,
        nullptr,0,nullptr,0,&result,&exception,&proof,sizeof(proof))==EHR_RUNTIME_OK);
    assert(proof.permit_consumed==1 && proof.hook_consumptions==1 && result && !exception);
    assert(ehr_runtime_object_release(result)==EHR_RUNTIME_OK);result=0;
    assert(ehr_runtime_original_end(call)==EHR_RUNTIME_OK);
    assert(fixtureRoots.empty() && state().roots.empty() && originalRoutes().calls.empty());
    std::cout << "PASS: real staged gateway + original owned API fixture; exact identity, one-shot/repeat rejection, nested recursion, no-hook failure, caught native-object exception root, C++ unwind, failed preflight, worker rejection, and zero leaked roots/capabilities. No game image executed.\n";
    return 0;
} }
