// Actual private gateway helpers, synthetic exported-runtime implementation.
// No framework is loaded, no game methods execute, and no collection is forced.
#include "EHRRuntimeGateway.mm"
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <thread>
#include <unordered_map>
#define CHECK(x) do { ++checks; if (!(x)) { std::fprintf(stderr,"line %d\n",__LINE__); return 1; } } while (0)
namespace fixture {
struct alignas(8) Class { const char *name, *space; };
Class list{"ArrayList","System.Collections"}, carrierClass{"ArrayListEnumeratorSimple",""},
      objectClass{"Object","System"}, otherClass{"Other","Owned"};
struct ObjectData { RuntimeClass *klass; void *monitor=nullptr, *list=nullptr; int32_t index=0,version=0; void *current=nullptr; bool isArrayList=true; };
ObjectData marker{reinterpret_cast<RuntimeClass *>(&objectClass)};
struct Handle { ObjectData *value; bool pinned; };
std::unordered_map<uint32_t,Handle> handles;
uint32_t next=1;size_t calls=0,barriers=0,constructs=0,pinChecks=0;
size_t offset=offsetof(ObjectData,current);uint32_t size=sizeof(ObjectData),header=2*sizeof(void *);
bool wrongFieldType=false,throwBarrier=false,dropBarrier=false;
char field;
void touch() { if(!NSThread.isMainThread)abort();++calls; }
ObjectData *raw(Object *object) { return reinterpret_cast<ObjectData *>(object); }
RuntimeClass *as(Class &klass) { return reinterpret_cast<RuntimeClass *>(&klass); }
bool pinned(ObjectData *object) { for(auto &item:handles)if(item.second.value==object&&item.second.pinned)return true;return false; }
Object *target(uint32_t handle) { touch();auto i=handles.find(handle);return i==handles.end()?nullptr:reinterpret_cast<Object *>(i->second.value); }
uint32_t newHandle(Object *object,bool pin) { touch();auto id=next++;handles.emplace(id,Handle{raw(object),pin});return id; }
void freeHandle(uint32_t handle) { touch();if(!handles.erase(handle))abort(); }
Domain *domain() { touch();return reinterpret_cast<Domain *>(1); }
void *thread() { touch();return reinterpret_cast<void *>(1); }
const Assembly **assemblies(const Domain *,size_t *count) { touch();static const Assembly *items[]{reinterpret_cast<Assembly *>(1)};*count=1;return items; }
const Image *image(const Assembly *) { touch();return reinterpret_cast<Image *>(1); }
const char *imageName(const Image *) { touch();return "mscorlib.dll"; }
RuntimeClass *findClass(const Image *,const char *space,const char *name) { touch();if(!strcmp(space,"System.Collections")&&!strcmp(name,"ArrayList"))return as(list);if(!strcmp(space,"System")&&!strcmp(name,"Object"))return as(objectClass);return nullptr; }
const char *name(RuntimeClass *klass) { touch();return reinterpret_cast<Class *>(klass)->name; }
const char *space(RuntimeClass *klass) { touch();return reinterpret_cast<Class *>(klass)->space; }
RuntimeClass *nested(RuntimeClass *klass,void **iterator) { touch();if(klass==as(list)&&!*iterator){*iterator=reinterpret_cast<void *>(1);return as(carrierClass);}return nullptr; }
RuntimeClass *parent(RuntimeClass *) { touch();return nullptr; }
Field *fields(RuntimeClass *klass,void **iterator) { touch();if(klass==as(carrierClass)&&!*iterator){*iterator=reinterpret_cast<void *>(1);return reinterpret_cast<Field *>(&field);}return nullptr; }
const char *fieldName(Field *) { touch();return "_currentElement"; }
int flags(Field *) { touch();return 0; }
const Type *fieldType(Field *) { touch();return reinterpret_cast<Type *>(1); }
char *typeName(const Type *) { touch();return strdup(wrongFieldType?"System.Int32":"System.Object"); }
RuntimeClass *getClass(Object *object) { touch();return raw(object)->klass; }
Object *getField(Field *,Object *object) { touch();return static_cast<Object *>(raw(object)->current); }
void setField(Object *object,Field *which,Object *value) {
    touch();if(which!=reinterpret_cast<Field *>(&field)||raw(object)->klass!=as(carrierClass)||!pinned(raw(object))||!pinned(raw(value)))abort();
    ++pinChecks;if(throwBarrier)throw std::runtime_error("owned barrier failure");++barriers;
    if(!dropBarrier)raw(object)->current=value;
}
void freeMemory(void *value) { touch();free(value); }
}
extern "C" __attribute__((visibility("default"))) uint32_t il2cpp_class_instance_size(RuntimeClass *) { fixture::touch();return fixture::size; }
extern "C" __attribute__((visibility("default"))) size_t il2cpp_field_get_offset(Field *) { fixture::touch();return fixture::offset; }
extern "C" __attribute__((visibility("default"))) uint32_t il2cpp_object_header_size() { fixture::touch();return fixture::header; }
namespace ehr_pinned {
EHRRuntimeStatus validate_engine_entry(const void *entry) {
    fixture::touch();return entry==reinterpret_cast<void *>(il2cpp_class_instance_size)||entry==reinterpret_cast<void *>(il2cpp_field_get_offset)||entry==reinterpret_cast<void *>(il2cpp_object_header_size)?EHR_RUNTIME_OK:EHR_RUNTIME_TYPE_MISMATCH;
}
}
extern "C" EHRRuntimeStatus ehr_runtime_construct(EHRRuntimeToken klass,const EHRRuntimeToken *,size_t count,EHRRuntimeToken *result,EHRRuntimeToken *exception) {
    fixture::touch();*result=*exception=0;if(::klass(klass)!=fixture::as(fixture::objectClass)||count)abort();++fixture::constructs;return root(reinterpret_cast<Object *>(&fixture::marker),result);
}
int main() { @autoreleasepool { using namespace fixture;size_t checks=0;auto&s=state();s.loaded=true;
    s.api.domain_get=domain;s.api.thread_current=thread;s.api.domain_get_assemblies=assemblies;s.api.assembly_get_image=image;s.api.image_get_name=imageName;
    s.api.class_from_name=findClass;s.api.class_get_name=name;s.api.class_get_namespace=space;s.api.class_get_nested_types=nested;s.api.class_get_parent=parent;
    s.api.class_get_fields=fields;s.api.field_get_name=fieldName;s.api.field_get_flags=flags;s.api.field_get_type=fieldType;s.api.type_get_name=typeName;s.api.runtime_free=freeMemory;
    s.api.object_get_class=getClass;s.api.field_get_value_object=getField;s.api.field_set_value_object=setField;s.api.gchandle_new=newHandle;s.api.gchandle_get_target=target;s.api.gchandle_free=freeHandle;
    ObjectData carrier{as(carrierClass)},ordinary{as(carrierClass)},foreign{as(otherClass)};
    EHRRuntimeToken owned=0,pin=0;void *identity=nullptr;
    CHECK(root(reinterpret_cast<Object *>(&carrier),&owned)==0&&EHRRuntimeIteratorPin(owned,&pin,&identity)==0&&identity==&carrier);
    CHECK(!EHRRuntimeIteratorIsTerminal(&carrier)&&EHRRuntimeIteratorMarkTerminal(pin)==EHR_RUNTIME_NOT_READY);
    const auto baseline=s.roots.size();wrongFieldType=true;
    CHECK(EHRRuntimeIteratorTerminalPrepare(pin)==EHR_RUNTIME_NOT_FOUND&&s.roots.size()==baseline&&barriers==0);wrongFieldType=false;
    offset=sizeof(ObjectData);CHECK(EHRRuntimeIteratorTerminalPrepare(pin)==EHR_RUNTIME_TYPE_MISMATCH&&s.roots.size()==baseline&&barriers==0);
    offset=offsetof(ObjectData,current)+1;CHECK(EHRRuntimeIteratorTerminalPrepare(pin)==EHR_RUNTIME_TYPE_MISMATCH&&s.roots.size()==baseline);
    offset=offsetof(ObjectData,current);header=offset+sizeof(void *);CHECK(EHRRuntimeIteratorTerminalPrepare(pin)==EHR_RUNTIME_TYPE_MISMATCH&&s.roots.size()==baseline);
    header=2*sizeof(void *);CHECK(EHRRuntimeIteratorTerminalPrepare(pin)==0&&s.roots.size()==baseline+1&&pinned(&marker)&&barriers==0);
    const auto prepared=constructs;CHECK(EHRRuntimeIteratorTerminalPrepare(pin)==0&&constructs==prepared&&s.roots.size()==baseline+1);
    throwBarrier=true;CHECK(EHRRuntimeIteratorMarkTerminal(pin)==EHR_RUNTIME_MANAGED_EXCEPTION&&!EHRRuntimeIteratorIsTerminal(&carrier));throwBarrier=false;
    dropBarrier=true;CHECK(EHRRuntimeIteratorMarkTerminal(pin)==EHR_RUNTIME_TYPE_MISMATCH&&!EHRRuntimeIteratorIsTerminal(&carrier));dropBarrier=false;
    CHECK(EHRRuntimeIteratorMarkTerminal(pin)==0&&carrier.current==&marker&&EHRRuntimeIteratorIsTerminal(&carrier)&&pinChecks==3);
    CHECK(!EHRRuntimeIteratorIsTerminal(&ordinary)&&!EHRRuntimeIteratorIsTerminal(&foreign)&&!EHRRuntimeIteratorIsTerminal(nullptr));
    // Wrong-class receiver has only a header-sized allocation: the field is
    // not read. Misalignment also rejects before dereferencing its header.
    uintptr_t shortForeign=reinterpret_cast<uintptr_t>(as(otherClass));CHECK(!EHRRuntimeIteratorIsTerminal(&shortForeign));
    CHECK(!EHRRuntimeIteratorIsTerminal(reinterpret_cast<char *>(&carrier)+1));
    size_t before=calls;bool workerPass=false;
    std::thread worker([&]{workerPass=EHRRuntimeIteratorIsTerminal(&carrier)&&!EHRRuntimeIteratorIsTerminal(&ordinary)&&!EHRRuntimeIteratorIsTerminal(&shortForeign);});worker.join();CHECK(workerPass&&calls==before);
    CHECK(ehr_runtime_object_release(pin)==0&&ehr_runtime_object_release(owned)==0&&s.roots.size()==1&&handles.size()==1);
    // Actual terminal marker is a fixed lifetime root; completed carriers add
    // no roots. Repeated cache queries cannot allocate/pin or call the runtime.
    before=calls;for(size_t n=0;n<10000;++n)CHECK(EHRRuntimeIteratorIsTerminal(&carrier));CHECK(calls==before&&s.roots.size()==1);
    std::printf("{\"pass\":true,\"checks\":%zu,\"gameLoaded\":false,\"markerRoots\":1,\"barriers\":%zu}\n",checks,barriers);return 0;
} }
