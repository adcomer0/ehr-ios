#pragma once
#include "EHRRuntimeGateway.h"
// Native-only immortal metadata borrows from gateway-created opaque tokens.
// No pointer enters C# or a function table. The game image must remain loaded.
EHRRuntimeStatus EHRRuntimeBorrowMethod(EHRRuntimeToken,const void **method,const void **declaringClass);
EHRRuntimeStatus EHRRuntimeBorrowClass(EHRRuntimeToken,const void **klass);
