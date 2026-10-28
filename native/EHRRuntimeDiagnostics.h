#pragma once
#include "EHRDiagnosticState.hpp"
#include <time.h>
inline uint64_t EHRDiagnosticTick() noexcept {timespec value{};clock_gettime(CLOCK_MONOTONIC,&value);return uint64_t(value.tv_sec)*UINT64_C(1000000000)+uint64_t(value.tv_nsec);}
inline void EHRDiagnosticLimit(uint32_t category,uint64_t count,uint64_t limit) noexcept {
 ehr_diagnostics::state().guard(EHRDiagnosticTick(),category,count,limit,ehr_diagnostics::context);
}
// Flags: entered1, native exception2, original attempted4, runtime entered8,
// original permit consumed16, original hook consumed32, target found64.
struct EHRDiagnosticRouteScope {
 uint64_t id,rva;int32_t status=1;uint32_t flags=0,phase=0,argument=0;ehr_diagnostics::Context prior;
 EHRDiagnosticRouteScope(uint64_t target,uint64_t address) noexcept:id(target),rva(address),prior(ehr_diagnostics::context){ehr_diagnostics::context.target=id;ehr_diagnostics::context.rva=rva;ehr_diagnostics::context.phase=0;ehr_diagnostics::context.argument=0;ehr_diagnostics::state().begin(EHRDiagnosticTick(),id,rva);}
 void at(uint32_t p,uint32_t a=0) noexcept {phase=p;argument=a;ehr_diagnostics::context.phase=p;ehr_diagnostics::context.argument=a;}
 ~EHRDiagnosticRouteScope(){ehr_diagnostics::state().end(EHRDiagnosticTick(),id,rva,status,flags,phase,argument);ehr_diagnostics::context=prior;}
};
struct EHRDiagnosticComponentScope {
 uint32_t type,message;int32_t status=1;
 EHRDiagnosticComponentScope(uint32_t t,uint32_t m) noexcept:type(t),message(m){ehr_diagnostics::state().component(EHRDiagnosticTick(),true,type,message,0);}
 ~EHRDiagnosticComponentScope(){ehr_diagnostics::state().component(EHRDiagnosticTick(),false,type,message,status);}
};
struct EHRDiagnosticIteratorScope {
 uint64_t registration;uint32_t operation;int32_t status=6;ehr_diagnostics::Context prior;
 EHRDiagnosticIteratorScope(uint64_t r,uint32_t o) noexcept:registration(r),operation(o),prior(ehr_diagnostics::context){ehr_diagnostics::context.iterator=r;ehr_diagnostics::state().iterator(EHRDiagnosticTick(),true,registration,operation,0);}
 ~EHRDiagnosticIteratorScope(){ehr_diagnostics::state().iterator(EHRDiagnosticTick(),false,registration,operation,status);ehr_diagnostics::context=prior;}
};
// Main-thread-only copy of numeric gateway state. Never initializes, invokes,
// collects, drains, reads objects or runs on the diagnostics writer thread.
void EHRRuntimeGatewayPublishDiagnosticSnapshot(void) noexcept;
void EHRRuntimeDiagnosticsStart(void);
void EHRRuntimeDiagnosticsRecordAuth(uint32_t domain,int32_t code,uint64_t observedCount);
void EHRRuntimeDiagnosticsRecordAuthInstall(int32_t status);
void EHRRuntimeDiagnosticsRecordAuthCounters(uint64_t requests,uint64_t successes,uint64_t errors,uint64_t overlaps);
// Phase1 normal,2 silent; observerStatus!=0 means resultCode unavailable.
void EHRRuntimeDiagnosticsRecordEOSLogin(uint32_t phase,int32_t resultCode,int32_t observerStatus,uint64_t observedCount);
#ifdef __OBJC__
@class NSDictionary;
NSDictionary *EHRRuntimeDiagnosticsCopyStatus(void);
#endif
