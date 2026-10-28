// Original metadata-only observation helper. No target invocation/value boxing,
// object payload read/copy, field write, lobby or account operation occurs.
NSDictionary *exercisePublicValueABIFacts(const char *specText) {
    struct API {
        void *(*domain_get)();const void **(*domain_get_assemblies)(void *,size_t *);
        const void *(*assembly_get_image)(const void *);const char *(*image_get_name)(const void *);
        void *(*class_from_name)(const void *,const char *,const char *);
        void *(*class_get_nested_types)(void *,void **);void *(*class_get_declaring_type)(void *);
        const void *(*class_get_image)(void *);const char *(*class_get_name)(void *);const char *(*class_get_namespace)(void *);
        const void *(*class_get_type)(void *);void *(*class_from_type)(const void *);
        bool (*class_is_valuetype)(void *);bool (*class_is_enum)(void *);bool (*class_is_blittable)(void *);bool (*class_has_references)(void *);
        int32_t (*class_value_size)(void *,uint32_t *);int32_t (*class_instance_size)(void *);int32_t (*class_get_flags)(void *);
        void *(*class_get_fields)(void *,void **);const char *(*field_get_name)(void *);const void *(*field_get_type)(void *);
        uint32_t (*field_get_offset)(void *);uint32_t (*field_get_flags)(void *);
        const void *(*class_enum_basetype)(void *);int (*type_get_type)(const void *);bool (*type_is_byref)(const void *);
        char *(*type_get_name)(const void *);void (*free)(void *);uint32_t (*object_header_size)();
    } api{};
    NSMutableArray *failures=[NSMutableArray array],*missing=[NSMutableArray array];
#define VALUE_API(name) api.name=reinterpret_cast<decltype(api.name)>(bridgeExport("il2cpp_" #name));if(!api.name)[missing addObject:@#name]
    VALUE_API(domain_get);VALUE_API(domain_get_assemblies);VALUE_API(assembly_get_image);VALUE_API(image_get_name);VALUE_API(class_from_name);
    VALUE_API(class_get_nested_types);VALUE_API(class_get_declaring_type);VALUE_API(class_get_image);VALUE_API(class_get_name);VALUE_API(class_get_namespace);
    VALUE_API(class_get_type);VALUE_API(class_from_type);VALUE_API(class_is_valuetype);VALUE_API(class_is_enum);VALUE_API(class_is_blittable);VALUE_API(class_has_references);
    VALUE_API(class_value_size);VALUE_API(class_instance_size);VALUE_API(class_get_flags);VALUE_API(class_get_fields);VALUE_API(field_get_name);VALUE_API(field_get_type);
    VALUE_API(field_get_offset);VALUE_API(field_get_flags);VALUE_API(class_enum_basetype);VALUE_API(type_get_type);VALUE_API(type_is_byref);VALUE_API(type_get_name);VALUE_API(free);VALUE_API(object_header_size);
#undef VALUE_API
    if(missing.count)return @{@"success":@NO,@"missingExports":missing};
    if(!NSThread.isMainThread)return @{@"success":@NO,@"failure":@"not_main_thread"};
    auto string=[](const char *text)->NSString *{if(!text||strnlen(text,4097)>4096)return nil;return [NSString stringWithUTF8String:text];};
    auto typeName=[&](const void *type)->NSString *{if(!type)return nil;char *value=api.type_get_name(type);NSString *name=string(value);if(value)api.free(value);return name;};
    auto canonical=[&](void *klass)->NSString *{
        NSMutableArray *chain=[NSMutableArray array];void *current=klass;NSString *space=nil;
        for(size_t depth=0;current&&depth<32;++depth){NSString *name=string(api.class_get_name(current));if(!name)return nil;[chain insertObject:name atIndex:0];
            void *parent=api.class_get_declaring_type(current);if(!parent)space=string(api.class_get_namespace(current));current=parent;}
        if(current||!space)return nil;NSString *name=[chain componentsJoinedByString:@"+"];return space.length?[space stringByAppendingFormat:@".%@",name]:name;
    };
    NSDictionary *spec=[NSJSONSerialization JSONObjectWithData:[[NSString stringWithUTF8String:specText] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if(![spec isKindOfClass:NSDictionary.class]||![spec[@"requestedTypes"] isKindOfClass:NSArray.class])return @{@"success":@NO,@"failure":@"invalid_own_spec"};
    // This verifies the loaded image identity before interpreting public facts.
    bool uuidMatched=false;uint32_t loadedFrameworkCount=0;NSString *expected=spec[@"framework_uuid"];
    for(uint32_t i=0;i<_dyld_image_count();++i){const char *path=_dyld_get_image_name(i);if(!path||!strstr(path,"/UnityFramework.framework/UnityFramework"))continue;
        ++loadedFrameworkCount;
        auto *header=reinterpret_cast<const mach_header_64 *>(_dyld_get_image_header(i));if(!header||header->magic!=MH_MAGIC_64||header->ncmds>16384||header->sizeofcmds>16*1024*1024)continue;
        const uint8_t *cursor=reinterpret_cast<const uint8_t *>(header+1),*end=cursor+header->sizeofcmds;
        for(uint32_t c=0;c<header->ncmds;++c){if(size_t(end-cursor)<sizeof(load_command))break;auto *command=reinterpret_cast<const load_command *>(cursor);if(command->cmdsize<sizeof(load_command)||command->cmdsize>size_t(end-cursor))break;
            if(command->cmd==LC_UUID&&command->cmdsize==sizeof(uuid_command)){auto *u=reinterpret_cast<const uuid_command *>(cursor);NSUUID *value=[[NSUUID alloc]initWithUUIDBytes:u->uuid];uuidMatched=[value.UUIDString.lowercaseString isEqual:expected];}cursor+=command->cmdsize;}
    }
    if(!uuidMatched||loadedFrameworkCount!=1)return @{@"success":@NO,@"failure":@"loaded_framework_uuid_missing_different_or_ambiguous"};
    size_t assemblyCount=0;const void **assemblies=api.domain_get_assemblies(api.domain_get(),&assemblyCount);
    if(!assemblies||assemblyCount>4096)return @{@"success":@NO,@"failure":@"domain_or_assemblies_unavailable"};
    const uint32_t header=api.object_header_size();if(header==0||header>256||header%sizeof(void *))return @{@"success":@NO,@"failure":@"invalid_public_object_header_size"};
    NSMutableDictionary *types=[NSMutableDictionary dictionary];NSMutableArray *requested=[NSMutableArray array];std::set<void *> seen;
    std::function<void(void *,unsigned)> observe;
    observe=[&](void *klass,unsigned depth){
        if(!klass||depth>16){[failures addObject:@"value_field_recursion_or_class_missing"];return;}
        if(!seen.insert(klass).second)return;
        NSString *name=canonical(klass),*runtimeName=typeName(api.class_get_type(klass)),*image=string(api.image_get_name(api.class_get_image(klass)));
        if(!name||!runtimeName||!image){[failures addObject:@"public_type_name_unavailable"];return;}
        bool value=api.class_is_valuetype(klass);NSMutableDictionary *row=[@{@"canonical":name,@"runtime_type_name":runtimeName,@"image":image,@"is_value_type":@(value),@"is_enum":@(api.class_is_enum(klass)),@"flags":@(uint32_t(api.class_get_flags(klass))),@"instance_size":@(api.class_instance_size(klass)),@"evidence_kind":@"observed_public_api"}mutableCopy];
        row[@"layout_mask"]=@([row[@"flags"]unsignedIntValue]&0x18);
        types[name]=row;if(!value)return;
        uint32_t alignment=0;int32_t size=api.class_value_size(klass,&alignment);
        if(size<=0||size>1024*1024||!alignment||alignment>256||(alignment&(alignment-1))){[failures addObject:[name stringByAppendingString:@":invalid_public_value_size_alignment"]];return;}
        row[@"value_size"]=@(size);row[@"alignment"]=@(alignment);row[@"contains_references"]=@(api.class_has_references(klass));row[@"blittable"]=@(api.class_is_blittable(klass));
        if(api.class_is_enum(klass))row[@"enum_underlying"]=typeName(api.class_enum_basetype(klass))?:@"unavailable";
        NSMutableArray *fields=[NSMutableArray array];row[@"fields"]=fields;void *iterator=nullptr;bool complete=false;
        for(size_t n=0;n<4096;++n){void *field=api.class_get_fields(klass,&iterator);if(!field){complete=true;break;}
            NSString *fieldName=string(api.field_get_name(field));const void *fieldType=api.field_get_type(field);NSString *fieldTypeName=typeName(fieldType);void *fieldClass=fieldType?api.class_from_type(fieldType):nullptr;
            if(!fieldName||!fieldTypeName||!fieldClass){[failures addObject:[name stringByAppendingString:@":field_metadata_missing"]];continue;}
            uint32_t flags=api.field_get_flags(field),offset=api.field_get_offset(field);bool isStatic=(flags&0x10)!=0;bool fieldValue=api.class_is_valuetype(fieldClass);
            NSMutableDictionary *item=[@{@"name":fieldName,@"type":canonical(fieldClass)?:fieldTypeName,@"runtime_type_name":fieldTypeName,@"type_kind":@(api.type_get_type(fieldType)),@"is_byref":@(api.type_is_byref(fieldType)),@"is_static":@(isStatic),@"flags":@(flags),@"boxed_field_offset":@(offset),@"is_value_type":@(fieldValue)}mutableCopy];
            if(!isStatic){uint32_t fieldAlign=0;int32_t width=fieldValue?api.class_value_size(fieldClass,&fieldAlign):int32_t(sizeof(void *));
                item[@"field_size"]=@(width);item[@"field_alignment"]=@(fieldValue?fieldAlign:uint32_t(alignof(void *)));
                if(offset>=header&&width>0&&uint64_t(offset-header)+uint64_t(width)<=uint64_t(size))item[@"value_offset"]=@(offset-header);
                else [failures addObject:[NSString stringWithFormat:@"%@:field_offset_outside_public_value_size:%@",name,fieldName]];
                if(fieldValue)observe(fieldClass,depth+1);
            }
            [fields addObject:item];
        }
        if(!complete)[failures addObject:[name stringByAppendingString:@":field_iteration_not_terminated"]];
        NSDictionary *declared=spec[@"metadataDeclaredTypes"][name];NSMutableArray *observedDeclarations=[NSMutableArray array];
        for(NSDictionary *field in fields)[observedDeclarations addObject:@{@"name":field[@"name"],@"type":field[@"type"]}];
        bool declarationMatches=[declared isKindOfClass:NSDictionary.class]&&[declared[@"flags"]isEqual:row[@"flags"]]&&[declared[@"image"]isEqual:image]&&[declared[@"fields"]isEqual:observedDeclarations];
        row[@"metadata_declaration"]=declared?:@{};row[@"metadata_declaration_matches"]=@(declarationMatches);
        if(!declarationMatches)[failures addObject:[name stringByAppendingString:@":runtime_metadata_declarations_differ"]];
    };
    for(NSDictionary *wanted in spec[@"requestedTypes"]){NSString *imageName=wanted[@"image"],*space=wanted[@"namespace"],*className=wanted[@"name"],*expectedName=wanted[@"canonical"];
        const void *image=nullptr;for(size_t i=0;i<assemblyCount;++i){const void *candidate=api.assembly_get_image(assemblies[i]);NSString *name=string(api.image_get_name(candidate));if([name isEqual:imageName]){if(image){[failures addObject:@"requested_image_ambiguous"];image=nullptr;break;}image=candidate;}}
        NSArray<NSString *> *parts=[className componentsSeparatedByString:@"+"];void *klass=image?api.class_from_name(image,space.UTF8String,parts.firstObject.UTF8String):nullptr;
        for(NSUInteger part=1;klass&&part<parts.count;++part){void *it=nullptr,*found=nullptr;for(size_t n=0;n<4096;++n){void *nested=api.class_get_nested_types(klass,&it);if(!nested)break;if([string(api.class_get_name(nested))isEqual:parts[part]]){if(found){found=nullptr;break;}found=nested;}}klass=found;}
        if(!klass||![canonical(klass)isEqual:expectedName]){[failures addObject:[expectedName stringByAppendingString:@":exact_requested_class_missing"]];continue;}
        [requested addObject:expectedName];observe(klass,0);
    }
    return @{@"success":@(failures.count==0&&requested.count==[spec[@"requestedTypes"]count]),@"schema":@"ehr.native-abi-layout-facts.v1",
        @"framework_sha256":spec[@"framework_sha256"],@"metadata_sha256":spec[@"metadata_sha256"],@"framework_uuid":expected,
        @"requested_types":requested,@"types":types,@"failures":failures,@"object_header_size":@(header),@"offset_basis":@"public_field_get_offset_minus_public_object_header_size",
        @"value_box_calls":@0,@"object_payload_bytes_read_or_copied":@0,@"target_invocations":@0,@"runtime_thunk_availability_claimed":@NO};
}
