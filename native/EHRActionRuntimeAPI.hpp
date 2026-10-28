#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>
namespace ehr_action {
void *actionSymbol(const char *name);
struct alignas(8) PinnedMethodInfo2022 {
    void *methodPointer;
    void *virtualMethodPointer;
    void *invokerMethod;
    const char *name;
    void *klass;
    const void *returnType;
    const void *parameters;
    void *runtimeData;
    void *genericData;
    uint32_t token;
    uint16_t flags;
    uint16_t implementationFlags;
    uint16_t slot;
    uint8_t parameterCount;
    uint8_t bitfield;
};
static_assert(sizeof(PinnedMethodInfo2022)==88);
static_assert(offsetof(PinnedMethodInfo2022,slot)==80);
static_assert(offsetof(PinnedMethodInfo2022,parameterCount)==82);
struct API {
    void *(*domain_get)();
    const void **(*domain_get_assemblies)(void *,size_t *);
    const void *(*assembly_get_image)(const void *);
    const char *(*image_get_name)(const void *);
    void *(*class_from_name)(const void *,const char *,const char *);
    const void *(*class_get_methods)(void *,void **);
    const char *(*method_get_name)(const void *);
    uint32_t (*method_get_param_count)(const void *);
    const void *(*method_get_param)(const void *,uint32_t);
    const void *(*method_get_return_type)(const void *);
    uint32_t (*method_get_flags)(const void *,uint32_t *);
    void *(*method_get_class)(const void *);
    char *(*type_get_name)(const void *);
    void (*free)(void *);
    void *(*object_new)(void *);
    void *(*runtime_invoke)(const void *,void *,void **,void **);
    void *(*method_get_object)(const void *,void *);
    void *(*class_get_field_from_name)(void *,const char *);
    const void *(*field_get_type)(void *);
    uint32_t (*field_get_flags)(void *);
    void (*field_set_value)(void *,void *,void *);
    void (*field_set_value_object)(void *,void *,void *);
    void (*field_get_value)(void *,void *,void *);
    uint32_t (*gchandle_new)(void *,bool);
    uint32_t (*gchandle_new_weakref)(void *,bool);
    void *(*gchandle_get_target)(uint32_t);
    void (*gchandle_free)(uint32_t);
    bool load() {
#define ACTION_API(name) name=reinterpret_cast<decltype(name)>(actionSymbol("il2cpp_" #name)); if(!name) return false
        ACTION_API(domain_get);ACTION_API(domain_get_assemblies);ACTION_API(assembly_get_image);
        ACTION_API(image_get_name);ACTION_API(class_from_name);ACTION_API(class_get_methods);
        ACTION_API(method_get_name);ACTION_API(method_get_param_count);ACTION_API(method_get_param);
        ACTION_API(method_get_return_type);ACTION_API(method_get_flags);ACTION_API(method_get_class);
        ACTION_API(type_get_name);ACTION_API(free);ACTION_API(object_new);ACTION_API(runtime_invoke);
        ACTION_API(method_get_object);ACTION_API(class_get_field_from_name);ACTION_API(field_get_type);
        ACTION_API(field_get_flags);ACTION_API(field_set_value);ACTION_API(field_set_value_object);
        ACTION_API(field_get_value);ACTION_API(gchandle_new);ACTION_API(gchandle_new_weakref);ACTION_API(gchandle_get_target);ACTION_API(gchandle_free);
#undef ACTION_API
        return true;
    }
    bool typeEquals(const void *type,const char *expected) {
        if(!type) return false;
        char *name=type_get_name(type);
        const bool same=name && !strcmp(name,expected);
        if(name) free(name);
        return same;
    }
    const void *method(void *klass,const char *name,const std::vector<const char *> &parameters,const char *returns) {
        void *iterator=nullptr;
        const void *match=nullptr;
        for(size_t i=0;i<4096;++i) {
            const void *candidate=class_get_methods(klass,&iterator);
            if(!candidate) return match;
            const char *candidateName=method_get_name(candidate);
            uint32_t impl=0;
            if(!candidateName || strcmp(candidateName,name) || method_get_class(candidate)!=klass ||
               method_get_param_count(candidate)!=parameters.size() || (method_get_flags(candidate,&impl)&0x10) ||
               !typeEquals(method_get_return_type(candidate),returns)) continue;
            bool exact=true;
            for(size_t p=0;p<parameters.size();++p)
                exact=exact && typeEquals(method_get_param(candidate,static_cast<uint32_t>(p)),parameters[p]);
            if(exact) { if(match) return nullptr; match=candidate; }
        }
        return nullptr;
    }
    void *field(void *klass,const char *name,const char *type) {
        void *result=class_get_field_from_name(klass,name);
        return result && !(field_get_flags(result)&0x10) && typeEquals(field_get_type(result),type) ? result : nullptr;
    }
};
}
