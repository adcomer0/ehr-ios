#import "EHRManagedPatchProbe.h"
#include "EHRManagedPatchHostV1.h"
#include "EHRManagedPatchSignatureV1.h"
#include "EHRRuntimeOriginal.h"
#include "EHRHookBinding.generated.h"

namespace {
NSDictionary *outcomeV2(uint64_t versionRva,uint64_t predicateRva,int32_t expectedVersion){
    struct Root {uint64_t token=0;~Root(){if(token)ehr_runtime_object_release(token);}};
    Root version,versionError,predicate,predicateError;EHRManagedPatchDispatchProofV2 v{},p{};
    uint64_t before=EHROriginalInvocationBypassCount();
    auto vs=ehr_source_patch_dispatch_v2(1,0,nullptr,0,&version.token,&versionError.token,nullptr,0,&v,sizeof(v));
    uint64_t vd=EHROriginalInvocationBypassCount()-before;
    auto ps=ehr_source_patch_dispatch_v2(2,0,nullptr,0,&predicate.token,&predicateError.token,nullptr,0,&p,sizeof(p));
    uint64_t pd=EHROriginalInvocationBypassCount()-before-vd;
    int32_t integer=0;uint8_t boolean=0;size_t integerBytes=0,booleanBytes=0;
    auto vc=version.token?ehr_runtime_copy_value(version.token,&integer,sizeof(integer),&integerBytes):EHR_RUNTIME_NOT_FOUND;
    auto pc=predicate.token?ehr_runtime_copy_value(predicate.token,&boolean,sizeof(boolean),&booleanBytes):EHR_RUNTIME_NOT_FOUND;
    const bool versionProof=vs==0&&!versionError.token&&vc==EHR_RUNTIME_OK&&integerBytes==4&&integer==expectedVersion&&vd==1&&v.abi_version==2&&v.byte_size==32&&v.target_found==1&&v.dispatcher_entered==1&&v.original_attempted==1&&v.runtime_entered==1&&v.permit_consumed==1&&v.hook_consumptions==1;
    const bool skipProof=ps==0&&!predicateError.token&&pc==EHR_RUNTIME_OK&&booleanBytes==1&&boolean==1&&pd==0&&p.target_found==1&&p.dispatcher_entered==1&&p.original_attempted==0&&p.runtime_entered==0&&p.permit_consumed==0&&p.hook_consumptions==0;
    alignas(8) uint8_t memory[64],saved[64];memset(memory,0xa5,sizeof(memory));memcpy(saved,memory,sizeof(memory));
    auto *overlapProof=reinterpret_cast<EHRManagedPatchDispatchProofV2 *>(memory+4);
    uint64_t output=UINT64_C(0xaabbccdd),error=UINT64_C(0x11223344);
    auto os=ehr_source_patch_dispatch_v2(1,0,nullptr,0,reinterpret_cast<uint64_t *>(memory+8),&error,nullptr,0,overlapProof,sizeof(*overlapProof));
    const bool overlapRejected=os==EHR_RUNTIME_BAD_ARGUMENT&&memcmp(memory,saved,sizeof(memory))==0&&error==UINT64_C(0x11223344);
    alignas(8) uint8_t aligned[40]{};auto *four=reinterpret_cast<EHRManagedPatchDispatchProofV2 *>(aligned+4);
    auto absent=ehr_source_patch_dispatch_v2(UINT64_MAX,0,nullptr,0,&output,&error,nullptr,0,four,sizeof(*four));
    const bool fourAligned=absent==EHR_RUNTIME_NOT_FOUND&&four->abi_version==2&&four->byte_size==32&&four->target_found==0&&four->dispatcher_entered==0&&!output&&!error;
    auto setup1=ehr_source_patch_fixture_fail_setup(versionRva,predicateRva,1);EHRManagedPatchDispatchProofV2 prefix{};Root prefixResult,prefixError;
    auto first=setup1==0?ehr_source_patch_dispatch_v2(1,0,nullptr,0,&prefixResult.token,&prefixError.token,nullptr,0,&prefix,sizeof(prefix)):setup1;
    const bool beforeProof=first==6&&!prefixResult.token&&!prefixError.token&&prefix.target_found==1&&prefix.dispatcher_entered==1&&prefix.original_attempted==0&&prefix.runtime_entered==0&&prefix.permit_consumed==0&&prefix.hook_consumptions==0;
    auto setup2=ehr_source_patch_fixture_fail_setup(versionRva,predicateRva,2);EHRManagedPatchDispatchProofV2 postfix{};Root postfixResult,postfixError;
    before=EHROriginalInvocationBypassCount();auto second=setup2==0?ehr_source_patch_dispatch_v2(1,0,nullptr,0,&postfixResult.token,&postfixError.token,nullptr,0,&postfix,sizeof(postfix)):setup2;
    const bool afterProof=second==6&&!postfixResult.token&&!postfixError.token&&EHROriginalInvocationBypassCount()-before==1&&postfix.target_found==1&&postfix.dispatcher_entered==1&&postfix.original_attempted==1&&postfix.runtime_entered==1&&postfix.permit_consumed==1&&postfix.hook_consumptions==1;
    auto restore=ehr_source_patch_fixture_setup(versionRva,predicateRva);
    return @{@"success":@(versionProof&&skipProof&&overlapRejected&&fourAligned&&beforeProof&&afterProof&&restore==0),
      @"versionExactlyOneOriginal":@(versionProof),@"skipPrefixZeroOriginal":@(skipProof),@"proofOverlapRejectedBeforeWrites":@(overlapRejected),@"proofFourByteAlignmentAccepted":@(fourAligned),
      @"prefixFailureBeforeOriginalProof":@(beforeProof),@"postfixFailurePreservesOriginalProof":@(afterProof),@"prefixFailureStatus":@(first),@"postfixFailureStatus":@(second),@"restoreStatus":@(restore),
      @"nativeFallbackAfterDispatcherEntryPermitted":@NO,@"clrFailureRequiresNativeExceptionConstruction":@YES};
}
}

NSDictionary<NSString *,id> *EHRManagedPatchFrameSelfTest(void) {
#if EHR_HAS_MANAGED_RULES
    EHRManagedPatchHostV1 table{};EHRManagedPatchMakeTable(&table);
    const auto bind=ehr_source_bind_patch_host(&table,sizeof(table));
    if(bind)return @{@"success":@NO,@"bindStatus":@(bind)};
    const auto setup=ehr_source_patch_fixture_setup(EHRVersionMethodRVA,EHRIsModdedMethodRVA);
    if(setup)return @{@"success":@NO,@"setupStatus":@(setup)};
    struct Clear {~Clear(){ehr_source_patch_fixture_clear();}} clear;
    EHRManagedPatchSignatureV1 versionSignature{},predicateSignature{},missingSignature{};
    const auto versionSignatureStatus=ehr_source_patch_signature_v1(1,&versionSignature,sizeof(versionSignature),nullptr,0);
    const auto predicateSignatureStatus=ehr_source_patch_signature_v1(2,&predicateSignature,sizeof(predicateSignature),nullptr,0);
    const auto missingSignatureStatus=ehr_source_patch_signature_v1(UINT64_MAX,&missingSignature,sizeof(missingSignature),nullptr,0);
    uint64_t constantClass=0,intClass=0,boolClass=0;
    const bool signatureClasses=ehr_runtime_find_class("Assembly-CSharp.dll","","Constants",&constantClass)==EHR_RUNTIME_OK&&
        ehr_runtime_find_class("mscorlib.dll","System","Int32",&intClass)==EHR_RUNTIME_OK&&
        ehr_runtime_find_class("mscorlib.dll","System","Boolean",&boolClass)==EHR_RUNTIME_OK;
    const bool signaturesPassed=versionSignatureStatus==0&&predicateSignatureStatus==0&&missingSignatureStatus==EHR_RUNTIME_NOT_FOUND&&signatureClasses&&
        versionSignature.abi_version==1&&versionSignature.byte_size==48&&versionSignature.parameter_count==0&&versionSignature.flags==6&&
        predicateSignature.abi_version==1&&predicateSignature.byte_size==48&&predicateSignature.parameter_count==0&&predicateSignature.flags==6&&
        versionSignature.owner_class==constantClass&&predicateSignature.owner_class==constantClass&&versionSignature.result_class==intClass&&predicateSignature.result_class==boolClass&&
        versionSignature.expected_rva==EHRVersionMethodRVA&&predicateSignature.expected_rva==EHRIsModdedMethodRVA&&
        versionSignature.method!=0&&predicateSignature.method!=0&&versionSignature.method!=predicateSignature.method;
    struct Root {uint64_t token=0;~Root(){if(token)ehr_runtime_object_release(token);}};
    Root raw,exception;uint64_t method=0,invocation=0;EHROriginalInvocationProofV1 original{};
    auto status=ehr_runtime_original_target_method(1,&method);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_original_begin(1,method,&invocation);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_invoke_original(invocation,1,method,0,nullptr,0,&raw.token,&exception.token,&original,sizeof(original));
    if(invocation)ehr_runtime_original_end(invocation);
    int32_t rawValue=0;size_t copied=0;
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_copy_value(raw.token,&rawValue,sizeof(rawValue),&copied);
    if(status!=EHR_RUNTIME_OK||exception.token||copied!=sizeof(rawValue))return @{@"success":@NO,@"rawStatus":@(status)};
    const uint64_t before=EHROriginalInvocationBypassCount();
    Root version,predicate,versionError,predicateError;
    const auto versionStatus=ehr_source_patch_dispatch(1,0,nullptr,0,&version.token,&versionError.token,nullptr,0);
    const uint64_t versionDelta=EHROriginalInvocationBypassCount()-before;
    const auto predicateStatus=ehr_source_patch_dispatch(2,0,nullptr,0,&predicate.token,&predicateError.token,nullptr,0);
    const uint64_t predicateDelta=EHROriginalInvocationBypassCount()-before-versionDelta;
    int32_t modified=0;uint8_t boolean=0;size_t versionBytes=0,predicateBytes=0;
    const auto versionCopy=version.token?ehr_runtime_copy_value(version.token,&modified,sizeof(modified),&versionBytes):EHR_RUNTIME_NOT_FOUND;
    const auto predicateCopy=predicate.token?ehr_runtime_copy_value(predicate.token,&boolean,sizeof(boolean),&predicateBytes):EHR_RUNTIME_NOT_FOUND;
    Root invalid,invalidError;
    const auto missing=ehr_source_patch_dispatch(UINT64_MAX,0,nullptr,0,&invalid.token,&invalidError.token,nullptr,0);
    uint64_t argument=0,referenceOutput=0;
    const auto wrongCount=ehr_source_patch_dispatch(1,0,&argument,1,&invalid.token,&invalidError.token,&referenceOutput,1);
    // Invalid overlapping inputs are rejected before any caller memory write.
    uint64_t shared=UINT64_C(0xaabbccdd);
    const auto overlap=ehr_source_patch_dispatch(1,0,&shared,1,&shared,&invalidError.token,&referenceOutput,1);
    NSDictionary *v2=outcomeV2(EHRVersionMethodRVA,EHRIsModdedMethodRVA,modified);
    const bool passed=signaturesPassed&&[v2[@"success"] boolValue]&&versionStatus==0&&predicateStatus==0&&!versionError.token&&!predicateError.token&&
        versionCopy==EHR_RUNTIME_OK&&versionBytes==4&&modified==int64_t(rawValue)+7&&versionDelta==1&&
        predicateCopy==EHR_RUNTIME_OK&&predicateBytes==1&&boolean==1&&predicateDelta==0&&
        missing==EHR_RUNTIME_NOT_FOUND&&wrongCount==EHR_RUNTIME_TYPE_MISMATCH&&overlap==EHR_RUNTIME_BAD_ARGUMENT&&shared==UINT64_C(0xaabbccdd)&&
        !invalid.token&&!invalidError.token&&!referenceOutput;
    return @{@"success":@(passed),@"opaqueSignatureMetadata":@{@"success":@(signaturesPassed),@"declarationBytes":@48,@"parameterBytes":@16,@"installedHookAvailabilityEstablished":@NO},@"dispatchOutcomeV2":v2,@"bindStatus":@(bind),@"setupStatus":@(setup),@"versionStatus":@(versionStatus),@"predicateStatus":@(predicateStatus),
        @"rawVersion":@(rawValue),@"postfixVersion":@(modified),@"versionOriginalBypasses":@(versionDelta),@"skippingPrefixOriginalBypasses":@(predicateDelta),
        @"missingTargetStatus":@(missing),@"wrongCountStatus":@(wrongCount),@"overlapStatus":@(overlap),@"overlapInputUnchanged":@(shared==UINT64_C(0xaabbccdd)),
        @"ownedArithmeticCallbacks":@YES,@"fullSourceCatalogLoaded":@NO,@"refCopybackExercised":@NO,@"nativeExceptionsExercised":@NO};
#else
    return @{@"success":@NO,@"enabled":@NO};
#endif
}
