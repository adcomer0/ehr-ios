// Include after Foundation/dlfcn in an own XCTest harness. Metadata only:
// no singleton storage, account failure handler, login, or SetEnabled call.
static NSDictionary *EHRAuthRetryMetadataProof(void) {
    auto prepare=reinterpret_cast<int32_t(*)(void)>(dlsym(RTLD_DEFAULT,"EHRAuthRetryGuardPrepare"));
    auto copy=reinterpret_cast<NSDictionary *(*)(void)>(dlsym(RTLD_DEFAULT,"EHRAuthRetryGuardCopyStatus"));
    if(!prepare||!copy)return @{@"pass":@NO,@"status":@3,
        @"accountOperationsInitiatedByTest":@0,@"authRequestsInitiatedByTest":@0};
    NSDictionary *before=copy();
    if(!before||!before[@"enabled"])return @{@"pass":@NO,@"status":@1,
        @"accountOperationsInitiatedByTest":@0,@"authRequestsInitiatedByTest":@0};
    if([before[@"enabled"] boolValue])return @{@"pass":@NO,@"status":@7,@"state":before,
        @"accountOperationsInitiatedByTest":@0,@"authRequestsInitiatedByTest":@0};
    const auto status=prepare();NSDictionary *state=copy();
    const bool countersPresent=state[@"failureHandlerEntries"]&&state[@"failureHandlerCompleted"];
    const bool pass=status==0&&state[@"preparedStatus"]&&[state[@"preparedStatus"] intValue]==0&&state[@"enabled"]&&
        ![state[@"enabled"] boolValue]&&countersPresent&&
        [state[@"failureHandlerEntries"] unsignedLongLongValue]==0&&
        [state[@"failureHandlerCompleted"] unsignedLongLongValue]==0;
    return @{@"pass":@(pass),@"status":@(status),@"before":before,@"state":state,
        @"accountOperationsInitiatedByTest":@0,@"authRequestsInitiatedByTest":@0};
}
