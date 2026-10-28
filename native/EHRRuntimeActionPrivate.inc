#include "EHRRuntimeActionPrivate.h"
EHRRuntimeStatus EHRRuntimeActionRootBorrowed(void *value,EHRRuntimeToken *owned) {
    if(!owned)return EHR_RUNTIME_BAD_ARGUMENT;*owned=0;
    REQUIRE_READY();
    try{return root(static_cast<Object *>(value),owned);}
    catch(...){return EHR_RUNTIME_LIMIT;}
}
