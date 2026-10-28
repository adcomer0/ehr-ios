#include "EHRRuntimeMetadataPrivate.h"
EHRRuntimeStatus EHRRuntimeBorrowMethod(EHRRuntimeToken token,const void **method,const void **owner) {
    if(!method||!owner||method==owner)return EHR_RUNTIME_BAD_ARGUMENT;
    *method=nullptr;*owner=nullptr;REQUIRE_READY();
    const Metadata *value=lookup(token,MetadataKind::Method);
    if(!value||!value->pointer||!value->owner)return EHR_RUNTIME_INVALID_TOKEN;
    *method=value->pointer;*owner=value->owner;return EHR_RUNTIME_OK;
}
EHRRuntimeStatus EHRRuntimeBorrowClass(EHRRuntimeToken token,const void **result) {
    if(!result)return EHR_RUNTIME_BAD_ARGUMENT;*result=nullptr;REQUIRE_READY();
    RuntimeClass *value=klass(token);if(!value)return EHR_RUNTIME_INVALID_TOKEN;
    *result=value;return EHR_RUNTIME_OK;
}
