#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <os/log.h>

// Benign load capability probe. Never alters game state, code or protection flags.
static void writeProbeMarker(void) {
    @autoreleasepool {
        void *domainAPI = dlsym(RTLD_DEFAULT, "il2cpp_domain_get");
        NSDictionary *marker = @{
            @"probe_loaded": @YES,
            @"bundle_id": NSBundle.mainBundle.bundleIdentifier ?: @"unavailable",
            @"il2cpp_domain_api_present": @(domainAPI != nullptr),
            @"gameplay_modified": @NO,
            @"timestamp": @([NSDate date].timeIntervalSince1970)
        };
        NSURL *cache = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory
            inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
        if (cache) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:marker options:NSJSONWritingPrettyPrinted error:nil];
            [data writeToURL:[cache URLByAppendingPathComponent:@"EHRNativeProbe.json"] atomically:YES];
        }
        os_log(OS_LOG_DEFAULT, "EHR_NATIVE_PROBE_LOADED domain_api=%{public}d", domainAPI != nullptr);
        fprintf(stderr, "EHR_NATIVE_PROBE_LOADED domain_api=%d\n", domainAPI != nullptr);
    }
}

__attribute__((constructor)) static void EHRNativeProbeLoad(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        writeProbeMarker();
    });
}
