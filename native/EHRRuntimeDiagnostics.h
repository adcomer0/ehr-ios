#pragma once
#include "EHRDiagnosticState.hpp"
#include <time.h>
inline uint64_t EHRDiagnosticTick() noexcept {timespec value{};clock_gettime(CLOCK_MONOTONIC,&value);return uint64_t(value.tv_sec)*UINT64_C(1000000000)+uint64_t(value.tv_nsec);}
inline void EHRDiagnosticLimit(uint32_t category,uint64_t count,uint64_t limit) noexcept {
 ehr_diagnostics::state().guard(EHRDiagnosticTick(),category,count,limit,ehr_diagnostics::context);
}
// Validate the independent owned numeric export before retaining any fields.
inline bool EHRDiagnosticSourceFailure(uint64_t target,int32_t status,const uint32_t *words,size_t count) noexcept {
 if(!target||!words||count!=12||words[0]!=1||words[1]!=12||!status||
    (uint64_t(words[4])|(uint64_t(words[5])<<32))!=target||
    words[6]>12||words[7]>4096||words[8]>128||words[9]<1||words[9]>7||words[10]!=uint32_t(status)||words[11]>1)return false;
 ehr_diagnostics::FailureDetail value;value.kind=1;value.source_sequence=uint64_t(words[2])|(uint64_t(words[3])<<32);
 if(!value.source_sequence)return false;
 value.stage=words[6];value.callback=words[7];value.argument=words[8];value.exception_kind=words[9];value.status=status;value.original_entered=words[11];
 auto origin=ehr_diagnostics::context;origin.target=target;ehr_diagnostics::state().failureDetail(EHRDiagnosticTick(),value,origin);return true;
}
// The independent coroutine export is sampled before its source is cancelled.
// Only a matching registered source and bounded fixed numeric ABI are retained.
inline bool EHRDiagnosticCoroutineFailure(uint64_t source,int32_t status,const uint64_t *words,size_t count) noexcept {
 if(!source||!words||count!=12||words[0]!=1||words[1]!=12||words[2]!=source||
    status<1||status>10||words[4]<1||words[4]>6||words[5]<1||words[5]>12||
    words[6]>10||words[7]!=uint64_t(status)||!words[8]||words[9]>12||words[10]>10||words[11]||
    ((words[9]==0)!=(words[10]==0)))return false;
 ehr_diagnostics::FailureDetail value;value.kind=3;value.source_id=source;value.iterator_type_hash=words[3];
 value.stage=uint32_t(words[4]);value.exception_kind=uint32_t(words[5]);value.primary_status=int32_t(words[6]);
 value.status=status;value.source_sequence=words[8];value.cleanup_exception_kind=uint32_t(words[9]);value.cleanup_status=int32_t(words[10]);
 ehr_diagnostics::state().failureDetail(EHRDiagnosticTick(),value,ehr_diagnostics::context);return true;
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
// Failure-only durable numeric snapshot; main-thread caller, filesystem work
// stays on the private writer queue. No game/runtime/account calls on worker.
int32_t EHRRuntimeDiagnosticsFlushIteratorFailure(void);
void EHRRuntimeDiagnosticsRecordAuth(uint32_t domain,int32_t code,uint64_t observedCount);
void EHRRuntimeDiagnosticsRecordAuthInstall(int32_t status);
void EHRRuntimeDiagnosticsRecordAuthCounters(uint64_t requests,uint64_t successes,uint64_t errors,uint64_t overlaps);
// Phase1 normal,2 silent; observerStatus!=0 means resultCode unavailable.
void EHRRuntimeDiagnosticsRecordEOSLogin(uint32_t phase,int32_t resultCode,int32_t observerStatus,uint64_t observedCount);
#ifdef __OBJC__
@class NSDictionary;
NSDictionary *EHRRuntimeDiagnosticsCopyStatus(void);
#endif
