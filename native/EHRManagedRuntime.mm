#import "EHRManagedRuntime.h"
#import "EHRManagedActionProbe.h"
#import "EHRManagedUnityActionProbe.h"
#import "EHRManagedPatchProbe.h"
#import "EHRManagedTypedActionProbe.h"
#import "EHRManagedComplexDelegateProbe.h"
#import "EHRManagedActionIdentityProbe.h"
#import "EHRNativeHooks.h"
#include "EHRRuntimeGateway.h"
#include "EHRRuntimeOriginal.h"
#import "EHRManagedIteratorProbe.h"
#include "EHRHookBinding.generated.h"
#ifndef EHR_HAS_ITERATOR_HOOKS
#define EHR_HAS_ITERATOR_HOOKS 0
#endif
#import "EHRManagedOriginalProbe.h"
#include "EHRRuntimeCollections.h"
#include "EHRRuntimeReflection.h"
#include "EHRRuntimeEngineColor.h"
#if EHR_HAS_MANAGED_RULES
#include "EHRManagedBridgeV1.h"
#include "EHRManagedFacadeTables.h"
#include "EHRManagedFacadeExtensionsV1.h"
#include "EHRManagedReflectionV1.h"
#include "EHRManagedLifetimeV1.h"
#include "EHRManagedTypeNamesV1.h"
#include "EHRManagedMethodsV1.h"
#include "EHRManagedConstructors.h"
#include "EHRManagedUnityGeneric.h"
#include "EHRManagedEngineColorV1.h"
#include "EHRManagedParams.h"
#include "EHRManagedSets.h"
#include "EHRManagedAsyncHandles.h"
#include "EHRManagedSystemTypesV1.h"
#include "EHRManagedReferenceOutV1.h"
#include "EHRManagedStateMachineV1.h"
#include "EHRManagedGenericGameMethodsV1.h"
#include "EHRTouchUI.h"
#include "EHRSourceHostRuntime.h"
#include <dlfcn.h>
#include "EHRManagedActionCombination.h"

namespace {
int32_t sourceHostMainThread() { return [NSThread isMainThread] ? 1 : 0; }
void sourceHostLog(int32_t level, const uint8_t *utf8, size_t length) {
    if (!utf8 || length > 1024 * 1024) return;
    NSString *message = [[NSString alloc] initWithBytes:utf8 length:length encoding:NSUTF8StringEncoding];
    if (message) NSLog(@"[EHR source %d] %@",level,message);
}
NSDictionary *sourceHostSelfTest() {
    const EHRSourceHostV1 host={1,sizeof(EHRSourceHostV1),sourceHostMainThread,sourceHostLog};
    const int32_t bound=ehr_source_host_bind_v1(&host,sizeof(host));
    if(bound) return @{@"success":@NO,@"bindStatus":@(bound)};
    NSError *error=nil;
    NSURL *support=[[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
    NSURL *root=[support URLByAppendingPathComponent:@"EHRSource" isDirectory:YES];
    if(!root || ![[NSFileManager defaultManager] createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&error])
        return @{@"success":@NO,@"writableRootAvailable":@NO};
    Dl_info info{};
    if(!dladdr(reinterpret_cast<const void *>(&ehr_source_host_self_test),&info)||!info.dli_fname)
        return @{@"success":@NO,@"nativeModuleLocated":@NO};
    NSData *rootBytes=[root.path dataUsingEncoding:NSUTF8StringEncoding];
    NSString *module=[NSString stringWithUTF8String:info.dli_fname];
    NSData *moduleBytes=[module dataUsingEncoding:NSUTF8StringEncoding];
    int32_t proof[16]{};
    const int32_t status=ehr_source_host_self_test(static_cast<const uint8_t *>(rootBytes.bytes),rootBytes.length,
        static_cast<const uint8_t *>(moduleBytes.bytes),moduleBytes.length,proof,16);
    return @{@"success":@(status==0 && proof[0]==1 && proof[13]==0),@"status":@(status),@"stage":@(proof[2]),
        @"realCoreConfigTypes":@(proof[3]),@"loadCount":@(proof[4]),@"finishedCount":@(proof[5]),@"logEvents":@(proof[6]),
        @"pluginInfo":@(proof[7]),@"selfOnly":@(proof[8]),@"failedNoRetry":@(proof[9]),@"reentrancy":@(proof[10]),
        @"workerRejected":@(proof[11]),@"missingComponentBridgeRejected":@(proof[12]),@"dynamicCodeFlags":@(proof[13]),
        @"unloadFalse":@(proof[14]),@"realCorePaths":@(proof[15]),@"fullMainLoadInvoked":@NO};
}

NSDictionary *touchRendererSelfTest() {
    const int32_t bound=ehr_touch_ui_bind_v1(EHRTouchUIGetV1(),sizeof(EHRTouchUIV1));
    if(bound) return @{@"success":@NO,@"bindStatus":@(bound)};
    int32_t native[12]{},managed[8]{};
    const int32_t nativeStatus=EHRTouchUISelfTest(native,12);
    const int32_t managedStatus=ehr_touch_ui_managed_contract_test(managed,8);
    return @{@"success":@(nativeStatus==0 && native[0]==1 && managedStatus==0 && managed[0]==1 && managed[5]==0),
        @"nativeStatus":@(nativeStatus),@"managedStatus":@(managedStatus),
        @"viewportScaling":@(native[2]),@"buttonCreation":@(native[3]),@"queuedPress":@(native[4]),
        @"duplicateKeyRejected":@(native[5]),@"pressConsumedOnce":@(native[6]),@"staleActionDropped":@(native[7]),
        @"richText":@(native[8]),@"sliderValue":@(native[9]),@"hiddenInputAndScroll":@(native[10]),
        @"invalidInputRejected":@(native[11]),@"mainThreadBound":@(managed[1]),@"table72":@(managed[2]),
        @"frame48":@(managed[3]),@"itemAndStyleLayout":@(managed[4]),@"dynamicCodeFlags":@(managed[5]),
        @"actionKeySeparation":@(managed[6]),@"noActiveFrame":@(managed[7]),
        @"scope":@"Original offscreen UIKit controls and own managed function table; no source game actions"};
}

NSDictionary *facadeSelfTest(const EHRManagedGatewayV1 &gateway) {
    EHRManagedFacadeTables tables{};EHRManagedFacadeMakeTables(&tables);
    const auto &extensions=tables.extensions;const auto &reflection=tables.reflection;
    const auto &lifetime=tables.lifetime;const auto &typeNames=tables.typeNames;
    const auto &methods=tables.methods;const auto &engineColors=tables.engineColors;
    const int32_t coreStatus = ehr_generated_bind_gateway(&gateway,sizeof(gateway));
    const int32_t extensionStatus = ehr_generated_bind_extensions(&extensions,sizeof(extensions));
    const int32_t reflectionStatus = ehr_generated_bind_reflection(&reflection,sizeof(reflection));
    const int32_t lifetimeStatus = ehr_generated_bind_lifetime(&lifetime,sizeof(lifetime));
    const int32_t typeNamesStatus = ehr_generated_bind_type_names(&typeNames,sizeof(typeNames));
    const int32_t methodsStatus = ehr_generated_bind_methods(&methods,sizeof(methods));
    const int32_t engineColorBindStatus = ehr_generated_bind_engine_colors(&engineColors,sizeof(engineColors));
    if (coreStatus || extensionStatus || reflectionStatus || lifetimeStatus || typeNamesStatus || methodsStatus || engineColorBindStatus) {
        return @{ @"success": @NO, @"coreBindStatus": @(coreStatus), @"arrayBindStatus": @(extensionStatus),
            @"reflectionBindStatus": @(reflectionStatus), @"lifetimeBindStatus": @(lifetimeStatus), @"typeNamesBindStatus": @(typeNamesStatus), @"methodsBindStatus": @(methodsStatus), @"engineColorBindStatus": @(engineColorBindStatus) };
    }
    int32_t arrays[4]{}, lists[4]{}, lifetimes[6]{}, settings[4]{}, values[6]{}, objects[6]{}, dictionaries[5]{}, predicates[5]{}, singletons[6]{}, constructors[6]{}, unityGeneric[8]{}, getter = 0;
    const int32_t arrayStatus = ehr_generated_array_self_test(arrays,4);
    const int32_t listStatus = ehr_generated_list_self_test(lists,4);
    const int32_t lifetimeTestStatus = ehr_generated_lifetime_self_test(lifetimes,6);
    const int32_t settingsStatus = ehr_generated_settings_self_test(settings,4);
    const int32_t valueStatus = ehr_generated_value_self_test(values,6);
    const int32_t objectStatus = ehr_generated_object_self_test(objects,6);
    const int32_t dictionaryStatus = ehr_generated_dictionary_self_test(dictionaries,5);
    const int32_t predicateStatus = ehr_generated_predicate_self_test(predicates,5);
    const int32_t singletonStatus = ehr_generated_singleton_self_test(singletons,6);
    const int32_t constructorStatus = ehr_generated_constructor_self_test(constructors,6);
    const int32_t unityGenericStatus = ehr_generated_unity_generic_self_test(unityGeneric,8);
    int32_t engineColorsResult[6]{}, params[4]{};
    const int32_t engineColorStatus = ehr_generated_engine_color_self_test(engineColorsResult,6);
    const int32_t paramsStatus = ehr_generated_params_self_test(params,4);
    int32_t sets[6]{},asyncHandle[5]{},systemTypes[7]{},referenceOut[7]{},stateMachines[7]{},genericGame[6]{};
    const int32_t genericGameStatus=ehr_generated_generic_game_methods_self_test(genericGame,6);
    const int32_t referenceOutStatus=ehr_generated_reference_out_self_test(referenceOut,7);
    const int32_t stateMachineStatus=ehr_generated_state_machine_self_test(stateMachines,7);
    const int32_t systemTypesStatus=ehr_generated_system_types_self_test(systemTypes,7);
    const int32_t setStatus=ehr_generated_set_self_test(sets,6);
    const int32_t asyncStatus=ehr_generated_async_handle_self_test(asyncHandle,5);
    const int32_t getterStatus = ehr_generated_get_broadcast_version(&getter);
    // Read-only API audit. A resolved declaration is not an executed method or
    // completed role. Keep every mismatch visible for source/iOS reconciliation.
    const uint32_t count = ehr_generated_binding_count();
    uint32_t resolved = 0;
    NSMutableArray *failures = [NSMutableArray array];
    if (count <= 10000) {
        for (uint32_t i=0; i<count; ++i) {
            const int32_t status = ehr_generated_validate_binding(i);
            if (!status) ++resolved;
            else [failures addObject:@{@"bindingIndex":@(i),@"status":@(status)}];
        }
    }
    const bool passed = arrayStatus == 0 && arrays[0] == 1 && listStatus == 0 && lists[0] == 1 &&
        lifetimeTestStatus == 0 && lifetimes[0] == 1 && settingsStatus == 0 && settings[0] == 1 && valueStatus == 0 && values[0] == 1 && objectStatus == 0 && objects[0] == 1 && dictionaryStatus == 0 && dictionaries[0] == 1 && predicateStatus == 0 && predicates[0] == 1 && singletonStatus == 0 && singletons[0] == 1 && constructorStatus == 0 && constructors[0] == 1 && unityGenericStatus == 0 && unityGeneric[0] == 1 && getterStatus == 0 && getter >= 0;
    return @{ @"success": @(passed && engineColorStatus == 0 && engineColorsResult[0] == 1 && paramsStatus == 0 && params[0] == 1 && setStatus==0 && sets[0]==1 && asyncStatus==0 && asyncHandle[0]==1 && systemTypesStatus==0 && systemTypes[0]==1 && referenceOutStatus==0 && referenceOut[0]==1 && stateMachineStatus==0 && stateMachines[0]==1 && genericGameStatus==0 && genericGame[0]==1),
        @"genericGameMethods":@{@"status":@(genericGameStatus),@"pass":@(genericGame[0]),@"connectingMetadata":@(genericGame[2]),@"taskTypeMetadata":@(genericGame[3]),@"poolGetMetadata":@(genericGame[4]),@"nativeStringAndNull":@(genericGame[5]),@"gameMethodsExecuted":@NO},
        @"nativeStateMachines":@{@"status":@(stateMachineStatus),@"pass":@(stateMachines[0]),@"realInitialStates":@(stateMachines[2]),@"independentFieldWrites":@(stateMachines[3]),@"nullNativeOwners":@(stateMachines[4]),@"wrongIteratorRejected":@(stateMachines[5]),@"unmappedOwnerRejected":@(stateMachines[6]),@"factoriesOrMoveNextInvoked":@NO},
        @"referenceOut":@{@"status":@(referenceOutStatus),@"pass":@(referenceOut[0]),@"parsed":@(referenceOut[2]),@"major":@(referenceOut[3]),@"minor":@(referenceOut[4]),@"build":@(referenceOut[5]),@"invalidResultAndNull":@(referenceOut[6])},
        @"systemTypes":@{@"status":@(systemTypesStatus),@"pass":@(systemTypes[0]),@"unicodeBuilderIdentity":@(systemTypes[2]),@"vectorQueueFifo":@(systemTypes[3]),@"queueClear":@(systemTypes[4]),@"originalEmptyException":@(systemTypes[5]),@"existingFuncMetadata":@(systemTypes[6]),@"funcCallbackConstructionTested":@NO},
        @"sets":@{@"status":@(setStatus),@"pass":@(sets[0]),@"unicodeDuplicates":@(sets[2]),@"nativeIntegerEnumeration":@(sets[3]),@"removeClear":@(sets[4]),@"listRemoveRange":@(sets[5])},
        @"asyncHandle":@{@"status":@(asyncStatus),@"pass":@(asyncHandle[0]),@"defaultIsValidFalse":@(asyncHandle[2]),@"exactPropertyMetadata":@(asyncHandle[3]),@"cloneInvalid":@(asyncHandle[4]),@"actualAssetLoadingTested":@NO},
        @"engineColors": @{@"status":@(engineColorStatus),@"pass":@(engineColorsResult[0]),@"named":@(engineColorsResult[2]),@"hex":@(engineColorsResult[3]),@"invalid":@(engineColorsResult[4]),@"null":@(engineColorsResult[5]),@"implementation":@(ehr_generated_engine_color_implementation()),@"implementationName":ehr_generated_engine_color_implementation()==2?@"documented_compatibility":ehr_generated_engine_color_implementation()==1?@"native_engine":@"unattempted"},
        @"nativeParams": @{@"status":@(paramsStatus),@"pass":@(params[0]),@"mixedNativeFormatArray":@(params[2]),@"nullBoolSingleBoxing":@(params[3])},
        @"arrays": @{@"status":@(arrayStatus),@"pass":@(arrays[0]),@"liveByteArray":@(arrays[2]),@"unicodeAndNull":@(arrays[3])},
        @"lists": @{@"status":@(listStatus),@"pass":@(lists[0]),@"liveMutationAndNativeArray":@(lists[2]),@"enumeratorVersionGuard":@(lists[3])},
        @"lifetime": @{@"status":@(lifetimeTestStatus),@"pass":@(lifetimes[0]),@"sameObjectHashAndEquality":@(lifetimes[2]),
            @"distinctObjectIdentity":@(lifetimes[3]),@"idempotentDispose":@(lifetimes[4]),@"workerAndFinalizerReclamation":@(lifetimes[5])},
        @"settings": @{@"status":@(settingsStatus),@"pass":@(settings[0]),@"scalarRoundtrips":@(settings[2]),@"outCallCount":@(settings[3]),@"activeLobbyOptionsChanged":@NO},
        @"values": @{@"status":@(valueStatus),@"pass":@(values[0]),@"fieldCopyIsolation":@(values[2]),@"instanceCopyIsolation":@(values[3]),@"defaultValueEqualityAndHash":@(values[4]),@"nativeDistance":@(values[5])},
        @"objects": @{@"status":@(objectStatus),@"pass":@(objects[0]),@"nativeIteratorCurrent":@(objects[2]),@"nativeIteratorReset":@(objects[3]),@"validatedCasts":@(objects[4]),@"retainedNativeException":@(objects[5]),@"managedSourceCoroutineCarrier":@NO},
        @"dictionaries": @{@"status":@(dictionaryStatus),@"pass":@(dictionaries[0]),@"unicodeAndTypedAccess":@(dictionaries[2]),@"nativeEnumerationAndKeys":@(dictionaries[3]),@"nativeRemovalAndClear":@(dictionaries[4])},
        @"predicates": @{@"status":@(predicateStatus),@"pass":@(predicates[0]),@"managedSourceFind":@(predicates[2]),@"nativeFindAllResult":@(predicates[3]),@"mutationGuard":@(predicates[4]),@"nativeDelegateBridge":@NO},
        @"singletons": @{@"status":@(singletonStatus),@"pass":@(singletons[0]),@"exactGetterMetadata":@(singletons[2]),@"instanceExists":@(singletons[3]),@"instanceInvoked":@(singletons[4]),@"existingInstanceValidOrSkipped":@(singletons[5])},
        @"constructors": @{@"status":@(constructorStatus),@"pass":@(constructors[0]),@"realWaitTime":@(constructors[2]),@"exactCreatedClass":@(constructors[3]),@"wrongParameterRejected":@(constructors[4]),@"originalInnerException":@(constructors[5])},
        @"unityGenericMethods": @{@"status":@(unityGenericStatus),@"pass":@(unityGeneric[0]),@"stage":@(unityGeneric[2]),@"ownTransform":@(unityGeneric[3]),@"componentTransform":@(unityGeneric[4]),@"typedNativeChildren":@(unityGeneric[5]),@"cloneDistinct":@(unityGeneric[6]),@"cloneTransform":@(unityGeneric[7]),@"playerOrLobbyObjectsTouched":@NO},
        @"generatedGetter": @{@"status":@(getterStatus),@"value":@(getter)},
        @"metadataAudit": @{@"declaredBindings":@(count),@"resolved":@(resolved),@"unresolved":failures,
            @"gameMethodsInvokedByAudit":@NO,@"runtimeTypeReflectionOnly":@YES,@"roleCoverageEstablished":@NO},
        @"fullEHRAvailable":@NO };
}
}
#endif

NSDictionary<NSString *, id> *EHRManagedRuntimeSelfTest(void) {
#if EHR_HAS_MANAGED_RULES
    if (![NSThread isMainThread]) return @{ @"success": @NO, @"status": @(EHR_RUNTIME_WRONG_THREAD) };
    EHRManagedFacadeTables tables{};EHRManagedFacadeMakeTables(&tables);
    const auto &gateway=tables.gateway;
    const int32_t bound = ehr_managed_bind_gateway(&gateway, sizeof(gateway));
    if (bound != 0) return @{ @"success": @NO, @"bindStatus": @(bound) };
    EHRManagedSelfTestV1 result{};
    const int32_t status = ehr_managed_gateway_self_test(&result, sizeof(result));
    NSDictionary *facades = facadeSelfTest(gateway);
    NSDictionary *touchRenderer = touchRendererSelfTest();
    NSDictionary *sourceHost = sourceHostSelfTest();
    NSDictionary *actions = EHRManagedActionSelfTest();
    NSDictionary *unityActions = EHRManagedUnityActionSelfTest();
    NSDictionary *typedActions = EHRManagedTypedActionSelfTest();
    NSDictionary *complexDelegates = EHRManagedComplexDelegateSelfTest();
    NSDictionary *actionIdentity = EHRManagedActionIdentitySelfTest();
    NSDictionary *originals = EHRRuntimeOriginalSelfTest();
#if EHR_HAS_ITERATOR_HOOKS
    NSDictionary *iterators = EHRManagedIteratorSelfTest();
    const bool iteratorPassed = [iterators[@"success"] boolValue];
#else
    NSDictionary *iterators = @{ @"enabled": @NO, @"unityStartCoroutineTested": @NO };
    const bool iteratorPassed = true;
#endif
    NSDictionary *aotOriginals = EHRManagedOriginalAotSelfTest();
    NSDictionary *registeredOriginals = EHRRuntimeOriginalRegisteredSelfTest();
    NSDictionary *patchFrames = EHRManagedPatchFrameSelfTest();
    int32_t actionCombination[6]{};
    const int32_t actionCombinationStatus=ehr_action_combination_self_test(actionCombination,6);
    const bool actionCombinationPassed=actionCombinationStatus==0&&actionCombination[0]==1;
    const int32_t integerOption = ehr_source_integer_option(0,90,1,99);
    const float floatOption = ehr_source_float_option(0.5f,5.0f,0.5f,7);
    const bool numericPassed = integerOption == 8 && floatOption == 4.0f;
    return @{ @"success": @(status == 0 && result.pass == 1 && numericPassed && [actions[@"success"] boolValue] && [unityActions[@"success"] boolValue] && [typedActions[@"success"] boolValue] && [complexDelegates[@"success"] boolValue] && [actionIdentity[@"success"] boolValue] && [facades[@"success"] boolValue] && [touchRenderer[@"success"] boolValue] && [sourceHost[@"success"] boolValue] && [originals[@"success"] boolValue] && iteratorPassed && [aotOriginals[@"success"] boolValue] && [registeredOriginals[@"success"] boolValue] && [patchFrames[@"success"] boolValue] && actionCombinationPassed), @"status": @(status),
        @"abiVersion": @(result.abi_version), @"dynamicCodeFlags": @(result.dynamic_code_flags),
        @"actualGetterValue": @(result.actual_getter_value), @"offlineValue": @(result.offline_value),
        @"onlineValue": @(result.online_value), @"expectedOnlineValue": @(result.expected_online_value),
        @"pinnedImageObserved": @(result.pinned_image_observed),
        @"callbacksBefore": @(result.callbacks_before), @"callbacksAfter": @(result.callbacks_after),
        @"rootedResultsReleased": @(result.rooted_results_released),
        @"liveFacades": facades,
        @"nativeTouchRenderer": touchRenderer,
        @"nativeSourceHost": sourceHost,
        @"nativeAotActions": actions,
        @"nativeAotUnityActions": unityActions,
        @"nativeAotTypedActions": typedActions,
        @"nativeAotComplexDelegates": complexDelegates,
        @"nativeDelegateSourceIdentity": actionIdentity,
        @"caughtOriginalRoute": originals,
        @"nativeAotIteratorCarrier": iterators,
        @"nativeAotOriginalRoundTrip": aotOriginals,
        @"registeredOriginalRoutes": registeredOriginals,
        @"nativeAotStaticPatchFrames": patchFrames,
        @"nativeAotActionCombination":@{@"success":@(actionCombinationPassed),@"status":@(actionCombinationStatus),@"combinedEffects":@(actionCombination[2]),@"removeExisting":@(actionCombination[3]),@"nullIdentity":@(actionCombination[4]),@"ownedRootsReleased":@(actionCombination[5]),@"freshMethodGroupIdentityTested":@NO},
        @"numericOptionRules": @{@"success":@(numericPassed),@"integerValue":@(integerOption),@"floatValue":@(floatOption)},
        @"source": @"Unchanged EHR v8.0.3 ServerUpdatePatch.Postfix + ValueRule.cs in NativeAOT",
        @"fullEHRAvailable": @NO, @"gameplayMutationPerformed": @NO };
#else
    return @{ @"success": @NO, @"status": @"managed_rules_not_built", @"fullEHRAvailable": @NO };
#endif
}
