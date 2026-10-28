// Own generic audit implementation. Exact game declarations/RVAs are supplied
// only by a PRIVATE generated JSON literal outside Git. No audited target is
// invoked: only metadata discovery, reflection declaring-type properties and
// real closed-generic type construction are used.
NSDictionary *exerciseAllHarmonyRuntimeBindings(const char *factsJSON) {
#define BIND_AUDIT_API(name) auto name = reinterpret_cast<decltype(&ehr_runtime_##name)>(bridgeExport("ehr_runtime_" #name)); if (!name) return @{ @"success": @NO, @"missingExport": @#name }
    BIND_AUDIT_API(initialize); BIND_AUDIT_API(find_class); BIND_AUDIT_API(find_method);
    BIND_AUDIT_API(class_type_name); BIND_AUDIT_API(vector_class); BIND_AUDIT_API(make_generic_class);
    BIND_AUDIT_API(validate_native_method); BIND_AUDIT_API(method_object); BIND_AUDIT_API(object_class);
    BIND_AUDIT_API(invoke); BIND_AUDIT_API(class_from_type_object); BIND_AUDIT_API(object_release);
#undef BIND_AUDIT_API
    NSMutableDictionary *proof = [NSMutableDictionary dictionary];
    proof[@"auditedTargetInvocations"] = @0;
    proof[@"scope"] = @"Actual runtime metadata and exact native-RVA association; no audited target invocation";
    if (!factsJSON || strnlen(factsJSON,16*1024*1024)==16*1024*1024)
        return @{ @"success": @NO, @"error": @"invalid private audit facts" };
    NSError *jsonError = nil;
    id decoded = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:factsJSON length:strlen(factsJSON)] options:0 error:&jsonError];
    if (jsonError || ![decoded isKindOfClass:NSDictionary.class] || ![decoded[@"schema"] isEqual:@"ehr.runtime-binding-audit-facts.v1"])
        return @{ @"success": @NO, @"error": @"private audit facts schema/JSON rejected" };
    NSDictionary *facts = decoded;
    NSArray *types = facts[@"types"], *methods = facts[@"methods"];
    if (![types isKindOfClass:NSArray.class] || ![methods isKindOfClass:NSArray.class] ||
        types.count>4096 || !methods.count || methods.count>4096 || [facts[@"expected_method_count"] unsignedIntegerValue]!=methods.count)
        return @{ @"success": @NO, @"error": @"private audit facts bounds rejected" };
    const auto readyStatus = initialize();
    if (readyStatus!=EHR_RUNTIME_OK) return @{ @"success": @NO, @"initializationStatus": @(readyStatus) };
    bool cleanup = true;
    auto releaseOwned = [&](EHRRuntimeToken token) { if (token && object_release(token)!=EHR_RUNTIME_OK) cleanup=false; };
    std::vector<EHRRuntimeToken> classes(types.count,0);
    std::vector<std::string> names(types.count);
    auto readName = [&](EHRRuntimeToken klass, std::string &name) {
        size_t required=0;
        auto status=class_type_name(klass,nullptr,0,&required);
        if (status!=EHR_RUNTIME_LIMIT) return status;
        if (!required || required>65536) return EHR_RUNTIME_LIMIT;
        std::vector<char> bytes(required);
        status=class_type_name(klass,bytes.data(),bytes.size(),&required);
        if (status==EHR_RUNTIME_OK) name.assign(bytes.data(),required-1);
        return status;
    };
    NSMutableArray *typeProof=[NSMutableArray array], *methodProof=[NSMutableArray array], *failures=[NSMutableArray array];
    size_t resolvedTypes=0, genericRequests=0, vectorRequests=0, byrefMarkers=0, propertyInvocations=0;
    for (NSUInteger index=0; index<types.count; ++index) {
        NSDictionary *spec=types[index];
        EHRRuntimeStatus status=EHR_RUNTIME_BAD_ARGUMENT;
        NSString *kind=spec[@"kind"];
        if (![spec isKindOfClass:NSDictionary.class] || [spec[@"id"] unsignedIntegerValue]!=index) {
            [failures addObject:@{ @"typeIndex":@(index), @"reason":@"invalid type descriptor order" }];
            [typeProof addObject:@{ @"id":@(index), @"status":@(status) }];
            continue;
        }
        if ([kind isEqual:@"named"]) {
            NSString *image=spec[@"image"], *space=spec[@"namespace"], *name=spec[@"name"];
            if ([image isKindOfClass:NSString.class] && [space isKindOfClass:NSString.class] && [name isKindOfClass:NSString.class])
                status=find_class(image.UTF8String,space.UTF8String,name.UTF8String,&classes[index]);
        } else if ([kind isEqual:@"generic"]) {
            const NSUInteger definition=[spec[@"definition"] unsignedIntegerValue];
            NSArray *arguments=spec[@"arguments"];
            if (definition<index && classes[definition] && [arguments isKindOfClass:NSArray.class] && arguments.count && arguments.count<=128) {
                std::vector<EHRRuntimeToken> tokens;
                bool valid=true;
                for (NSNumber *argument in arguments) {
                    const NSUInteger dependency=argument.unsignedIntegerValue;
                    if (dependency>=index || !classes[dependency]) { valid=false; break; }
                    tokens.push_back(classes[dependency]);
                }
                if (valid) {
                    EHRRuntimeToken exception=0;
                    ++genericRequests;
                    status=make_generic_class(classes[definition],tokens.data(),tokens.size(),&classes[index],&exception);
                    if (exception && status==EHR_RUNTIME_OK) status=EHR_RUNTIME_MANAGED_EXCEPTION;
                    releaseOwned(exception);
                }
            }
        } else if ([kind isEqual:@"vector"]) {
            const NSUInteger dependency=[spec[@"element"] unsignedIntegerValue];
            if (dependency<index && classes[dependency]) {
                ++vectorRequests;
                status=vector_class(classes[dependency],&classes[index]);
            }
        } else if ([kind isEqual:@"byref"]) {
            const NSUInteger dependency=[spec[@"element"] unsignedIntegerValue];
            if (dependency<index && classes[dependency] && !names[dependency].empty()) {
                // The ABI's explicit IL2CPP byref suffix is appended to the
                // actual base spelling. Nested/generic text is never replaced.
                names[index]=names[dependency]+"&";
                ++byrefMarkers;status=EHR_RUNTIME_OK;
            }
        }
        if (status==EHR_RUNTIME_OK && ![kind isEqual:@"byref"]) status=readName(classes[index],names[index]);
        const bool success=status==EHR_RUNTIME_OK && !names[index].empty();
        if (success) ++resolvedTypes;
        else [failures addObject:@{ @"typeIndex":@(index), @"canonical":spec[@"canonical"] ?: @"", @"status":@(status) }];
        [typeProof addObject:@{ @"id":@(index), @"canonical":spec[@"canonical"] ?: @"", @"kind":kind ?: @"", @"status":@(status),
            @"runtimeName":success ? [NSString stringWithUTF8String:names[index].c_str()] : @"", @"success":@(success) }];
    }
    std::vector<std::pair<EHRRuntimeToken,EHRRuntimeToken>> declaringGetters;
    size_t passed=0;
    for (NSDictionary *spec in methods) {
        NSMutableDictionary *item=[NSMutableDictionary dictionary];
        item[@"selectorId"]=spec[@"selector_id"] ?: @"";
        item[@"canonicalSignature"]=spec[@"canonical_signature"] ?: @"";
        item[@"expectedRva"]=spec[@"expected_rva"] ?: @"";
        EHRRuntimeStatus resolution=EHR_RUNTIME_BAD_ARGUMENT, association=EHR_RUNTIME_NOT_READY, ownerStatus=EHR_RUNTIME_NOT_READY;
        bool ownerMatches=false;
        uint64_t observed=0;
        const NSUInteger owner=[spec[@"declaring_type"] unsignedIntegerValue], returns=[spec[@"return_type"] unsignedIntegerValue];
        NSArray *parameterIDs=spec[@"parameter_types"];
        NSMutableArray *runtimeParams=[NSMutableArray array];
        std::vector<const char *> parameters;
        bool valid=owner<classes.size() && classes[owner] && returns<names.size() && !names[returns].empty() &&
            [parameterIDs isKindOfClass:NSArray.class] && parameterIDs.count<=128;
        if (valid) {
            for (NSNumber *number in parameterIDs) {
                const NSUInteger parameter=number.unsignedIntegerValue;
                if (parameter>=names.size() || names[parameter].empty()) { valid=false; break; }
                parameters.push_back(names[parameter].c_str());
                [runtimeParams addObject:[NSString stringWithUTF8String:names[parameter].c_str()]];
            }
        }
        EHRRuntimeToken method=0;
        NSString *methodName=spec[@"method_name"];
        if (valid && [methodName isKindOfClass:NSString.class]) {
            item[@"runtimeDeclaringType"]=[NSString stringWithUTF8String:names[owner].c_str()];
            item[@"runtimeReturnType"]=[NSString stringWithUTF8String:names[returns].c_str()];
            item[@"runtimeParameterTypes"]=runtimeParams;
            resolution=find_method(classes[owner],methodName.UTF8String,parameters.data(),parameters.size(),names[returns].c_str(),[spec[@"is_static"] boolValue],&method);
            if (resolution==EHR_RUNTIME_OK && method) {
                // find_method intentionally walks bases. Independently verify
                // the actual reflection DeclaringType so inherited matches
                // cannot silently satisfy an exact declaring-owner selector.
                EHRRuntimeToken reflection=0, reflectionClass=0, getter=0, declaredType=0, exception=0, declaredClass=0;
                ownerStatus=method_object(method,&reflection);
                if (ownerStatus==EHR_RUNTIME_OK) ownerStatus=object_class(reflection,&reflectionClass);
                if (ownerStatus==EHR_RUNTIME_OK) {
                    for (const auto &entry:declaringGetters) if (entry.first==reflectionClass) getter=entry.second;
                    if (!getter) {
                        ownerStatus=find_method(reflectionClass,"get_DeclaringType",nullptr,0,"System.Type",0,&getter);
                        if (ownerStatus==EHR_RUNTIME_OK) declaringGetters.push_back({reflectionClass,getter});
                    }
                }
                if (ownerStatus==EHR_RUNTIME_OK) {
                    ++propertyInvocations;
                    ownerStatus=invoke(getter,reflection,nullptr,0,&declaredType,&exception);
                    if (exception && ownerStatus==EHR_RUNTIME_OK) ownerStatus=EHR_RUNTIME_MANAGED_EXCEPTION;
                }
                if (ownerStatus==EHR_RUNTIME_OK) ownerStatus=class_from_type_object(declaredType,&declaredClass);
                ownerMatches=ownerStatus==EHR_RUNTIME_OK && declaredClass==classes[owner];
                if (ownerStatus==EHR_RUNTIME_OK && !ownerMatches) {
                    std::string actualName;
                    if (readName(declaredClass,actualName)==EHR_RUNTIME_OK) item[@"observedDeclaringType"]=[NSString stringWithUTF8String:actualName.c_str()];
                }
                releaseOwned(reflection);releaseOwned(declaredType);releaseOwned(exception);
                const char *expected=[spec[@"expected_rva"] UTF8String];
                char *end=nullptr;
                const uint64_t rva=expected ? strtoull(expected,&end,16) : 0;
                if (ownerMatches && expected && end && !*end && rva && !(rva%4))
                    association=validate_native_method(method,rva,&observed);
            }
        }
        const bool success=resolution==EHR_RUNTIME_OK && ownerMatches && association==EHR_RUNTIME_OK;
        item[@"methodResolutionStatus"]=@(resolution);item[@"declaringOwnerStatus"]=@(ownerStatus);
        item[@"declaringOwnerMatches"]=@(ownerMatches);item[@"associationStatus"]=@(association);
        item[@"observedRva"]=[NSString stringWithFormat:@"0x%llx",static_cast<unsigned long long>(observed)];
        item[@"success"]=@(success);
        if (success) ++passed; else [failures addObject:item];
        [methodProof addObject:item];
    }
    proof[@"types"]=typeProof;proof[@"methods"]=methodProof;proof[@"failures"]=failures;
    proof[@"frameworkUuid"]=facts[@"framework_uuid"] ?: @"";
    proof[@"expectedMethodCount"]=@(methods.count);proof[@"matchedMethodCount"]=@(passed);
    proof[@"typeShapeCount"]=@(types.count);proof[@"resolvedTypeShapeCount"]=@(resolvedTypes);
    proof[@"closedGenericTypeShapeRequests"]=@(genericRequests);proof[@"vectorClassRequests"]=@(vectorRequests);
    proof[@"explicitByrefMarkersOnRuntimeBaseNames"]=@(byrefMarkers);proof[@"reflectionDeclaringTypePropertyInvocations"]=@(propertyInvocations);
    proof[@"allTemporaryRootsReleased"]=@(cleanup);
    proof[@"excludedUnboundSelectors"]=facts[@"excluded_unbound_selectors"] ?: @[];
    proof[@"success"]=@(cleanup && resolvedTypes==types.count && passed==methods.count && !failures.count);
    return proof;
}
