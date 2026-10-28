// Original ARM64 compiler-ABI fixture, not a game delegate execution proof.
#include <cassert>
#include <climits>
#include <cstdint>
struct ScenePayload{int32_t handle;};static_assert(sizeof(ScenePayload)==4);
struct OwnContext{int32_t value=0,kind=0;void *reference=nullptr;const void *metadata=nullptr;};
__attribute__((noinline))void action3(void *self,void *reference,int32_t value,int32_t kind,const void *metadata){auto &s=*static_cast<OwnContext *>(self);s={value,kind,reference,metadata};}
__attribute__((noinline))bool function(void *self,void *reference,const void *metadata){auto &s=*static_cast<OwnContext *>(self);assert(metadata==s.metadata);return reference==s.reference;}
__attribute__((noinline))void scene2(void *self,ScenePayload scene,int32_t kind,const void *metadata){auto &s=*static_cast<OwnContext *>(self);s={scene.handle,kind,nullptr,metadata};}
int main(){
 OwnContext own;int reference=0,method=0;
 void(*volatile triple)(void *,void *,int32_t,int32_t,const void *)=action3;
 bool(*volatile predicate)(void *,void *,const void *)=function;
 void(*volatile scene)(void *,ScenePayload,int32_t,const void *)=scene2;
 const int32_t inputs[]={INT32_MIN,-1234567,-1,0,1,231,1234567,INT32_MAX};
 for(int32_t value:inputs)for(int32_t kind:inputs){triple(&own,&reference,value,kind,&method);assert(own.value==value&&own.kind==kind&&own.reference==&reference&&own.metadata==&method);
  assert(predicate(&own,&reference,&method)&&!predicate(&own,nullptr,&method));scene(&own,{value},kind,&method);assert(own.value==value&&own.kind==kind&&own.metadata==&method);}
}
