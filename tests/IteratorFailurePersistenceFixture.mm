// Exact production writer, isolated to the command-line temporary directory.
// No production flags, user cache lookup, runtime, game or account are used.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <atomic>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>

static NSURL *ownedCache=nil;
static char writerKey;
static std::atomic<unsigned> cacheLookups{0},queueLookups{0},unexpectedLookups{0};
static NSURL *OwnedCache(id,SEL,NSSearchPathDirectory directory,NSSearchPathDomainMask domain,NSURL *appropriate,BOOL create,NSError *__autoreleasing *error){
    ++cacheLookups;queueLookups+=dispatch_get_specific(&writerKey)==&writerKey;
    if(directory!=NSCachesDirectory||domain!=NSUserDomainMask||appropriate||!create){++unexpectedLookups;if(error)*error=nil;return nil;}
    if(error)*error=nil;return ownedCache;
}

#include EHR_DIAGNOSTICS_SOURCE

namespace {
unsigned checks=0;
void Check(bool okay){++checks;if(!okay){fprintf(stderr,"Owned persistence check %u failed\n",checks);abort();}}
struct FD{int value=-1;~FD(){if(value>=0)close(value);}};
struct CacheOverride {
    Method method=nullptr;IMP original=nullptr;
    CacheOverride(){method=class_getInstanceMethod(NSFileManager.class,@selector(URLForDirectory:inDomain:appropriateForURL:create:error:));Check(method!=nullptr);original=method_setImplementation(method,reinterpret_cast<IMP>(&OwnedCache));}
    ~CacheOverride(){method_setImplementation(method,original);}
};
NSData *Read(NSString *path){FD file;file.value=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);Check(file.value>=0);NSMutableData *data=[NSMutableData new];uint8_t buffer[4096];while(true){ssize_t n=read(file.value,buffer,sizeof(buffer));Check(n>=0);if(!n)break;[data appendBytes:buffer length:NSUInteger(n)];Check(data.length<=512*1024);}return data;}
void Write(NSString *path,NSData *data){FD file;file.value=open(path.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);Check(file.value>=0);Check(write(file.value,data.bytes,data.length)==ssize_t(data.length));}
struct stat Stat(NSString *path){struct stat result{};Check(lstat(path.fileSystemRepresentation,&result)==0);return result;}
void NoPartials(NSString *folder){DIR *directory=opendir(folder.fileSystemRepresentation);Check(directory!=nullptr);while(auto *entry=readdir(directory))Check(strncmp(entry->d_name,".snapshot-",10)!=0);closedir(directory);}
void NumericTree(id value,bool schema=false){
    if([value isKindOfClass:NSDictionary.class]){for(id key in value){Check([key isKindOfClass:NSString.class]);NumericTree(value[key],[key isEqual:@"schema"]);}}
    else if([value isKindOfClass:NSArray.class]){for(id item in value)NumericTree(item);}
    else if([value isKindOfClass:NSNumber.class])Check(true);
    else Check(schema&&[value isEqual:@"ehr.numeric-runtime-diagnostics.v1"]);
}
}
int main(int argc,const char **argv){@autoreleasepool{
    Check(argc==2);NSString *root=[[NSString alloc]initWithUTF8String:argv[1]];Check(root.isAbsolutePath);
    struct stat rootFacts{};Check(lstat(root.fileSystemRepresentation,&rootFacts)==0&&S_ISDIR(rootFacts.st_mode)&&rootFacts.st_uid==geteuid());
    NSString *cache=[root stringByAppendingPathComponent:@"cache"];Check(mkdir(cache.fileSystemRepresentation,0700)==0);
    NSString *folder=[cache stringByAppendingPathComponent:@"EHRDiagnostics"];Check(mkdir(folder.fileSystemRepresentation,0700)==0);
    NSString *last=[folder stringByAppendingPathComponent:@"last-iterator-failure-v1.json"],*periodic=[folder stringByAppendingPathComponent:@"runtime-native-v1.json"];
    NSString *other=[root stringByAppendingPathComponent:@"other-owned-file"];
    NSData *prior=[@"OWN-PREVIOUS-ITERATOR-FAILURE" dataUsingEncoding:NSUTF8StringEncoding],*sentinel=[@"OWN-OTHER-FILE" dataUsingEncoding:NSUTF8StringEncoding];
    Write(last,prior);Write(other,sentinel);ownedCache=[NSURL fileURLWithPath:cache isDirectory:YES];
    Method selector=class_getInstanceMethod(NSFileManager.class,@selector(URLForDirectory:inDomain:appropriateForURL:create:error:));IMP original=method_getImplementation(selector);
    {
        CacheOverride replacement;
        Check(method_getImplementation(class_getInstanceMethod(object_getClass(NSFileManager.defaultManager),@selector(URLForDirectory:inDomain:appropriateForURL:create:error:)))==reinterpret_cast<IMP>(&OwnedCache));
        // dispatch_sync may execute inline on its calling thread. Assert the
        // actual private queue context rather than assuming a worker pthread.
        dispatch_queue_set_specific(writerQueue(),&writerKey,&writerKey,nullptr);
        Check(EHRRuntimeDiagnosticsFlushIteratorFailure()==4);Check(cacheLookups==0);Check([Read(last)isEqualToData:prior]);
        FD previous;previous.value=open(last.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);Check(previous.value>=0);auto before=Stat(last);
        ehr_diagnostics::Iterators failure;failure.callback_failures=1;failure.created=1;failure.closed=1;ehr_diagnostics::state().iterators(failure);
        uint64_t words[12]={1,12,77,12345,3,3,6,6,1,0,0,0};ehr_diagnostics::context={0,0,55,0,0};Check(EHRDiagnosticCoroutineFailure(77,6,words,12));
        Check(EHRRuntimeDiagnosticsFlushIteratorFailure()==0);NSData *saved=Read(last);Check(saved.length<=512*1024);NSDictionary *json=[NSJSONSerialization JSONObjectWithData:saved options:0 error:nil];Check(json!=nil);NumericTree(json);
        Check([json[@"productionIterators"][@"callbackFailures"] unsignedLongLongValue]==1);NSDictionary *detail=[json[@"failureDetails"] lastObject];
        Check([detail[@"kind"] unsignedIntValue]==3&&[detail[@"sourceId"] unsignedLongLongValue]==77&&[detail[@"iteratorTypeHash"] unsignedLongLongValue]==12345);
        Check([detail[@"registrationId"] unsignedLongLongValue]==55&&[detail[@"stage"] unsignedIntValue]==3&&[detail[@"status"] intValue]==6);
        auto after=Stat(last);Check(S_ISREG(after.st_mode)&&after.st_nlink==1&&(after.st_mode&0777)==0600&&after.st_ino!=before.st_ino);
        uint8_t oldBytes[64]{};ssize_t oldCount=read(previous.value,oldBytes,sizeof(oldBytes));Check(oldCount==ssize_t(prior.length)&&memcmp(oldBytes,prior.bytes,prior.length)==0);
        Check(access(periodic.fileSystemRepresentation,F_OK)!=0);NoPartials(folder);

        // Periodic startup state may be written, but it cannot replace the
        // separate durable failure file or turn a zero-failure flush into one.
        ehr_diagnostics::state().iterators({});dispatch_sync(writerQueue(),^{writeSnapshot(false);});
        Check([Read(last)isEqualToData:saved]);Check(Stat(last).st_ino==after.st_ino);Check(access(periodic.fileSystemRepresentation,F_OK)==0);
        NSDictionary *normal=[NSJSONSerialization JSONObjectWithData:Read(periodic) options:0 error:nil];Check([normal[@"productionIterators"][@"callbackFailures"] unsignedLongLongValue]==0);
        Check(EHRRuntimeDiagnosticsFlushIteratorFailure()==4);Check([Read(last)isEqualToData:saved]);
        ehr_diagnostics::state().iterators(failure);unsigned lookupsBefore=cacheLookups.load();int32_t workerStatus=0;
        std::thread worker([&]{@autoreleasepool{workerStatus=EHRRuntimeDiagnosticsFlushIteratorFailure();}});worker.join();Check(workerStatus==2&&cacheLookups==lookupsBefore);Check([Read(last)isEqualToData:saved]);

        Check(unlink(last.fileSystemRepresentation)==0);Check(symlink(other.fileSystemRepresentation,last.fileSystemRepresentation)==0);auto otherBefore=Stat(other);
        Check(EHRRuntimeDiagnosticsFlushIteratorFailure()==7);Check(S_ISLNK(Stat(last).st_mode));Check([Read(other)isEqualToData:sentinel]);Check(Stat(other).st_ino==otherBefore.st_ino);NoPartials(folder);
        Check(unlink(last.fileSystemRepresentation)==0);Check(link(other.fileSystemRepresentation,last.fileSystemRepresentation)==0);
        Check(EHRRuntimeDiagnosticsFlushIteratorFailure()==7);Check(Stat(last).st_nlink==2);Check([Read(other)isEqualToData:sentinel]);NoPartials(folder);
        Check(unlink(last.fileSystemRepresentation)==0);Write(last,saved);Check(EHRRuntimeDiagnosticsFlushIteratorFailure()==0);Check([Read(other)isEqualToData:sentinel]);
        Check(cacheLookups>0&&cacheLookups==queueLookups&&unexpectedLookups==0);
    }
    Check(method_getImplementation(selector)==original);ownedCache=nil;
    printf("{\"schema\":\"ehr.iterator-failure-persistence-owned-proof.v1\",\"pass\":true,\"checks\":%u,\"temporaryCacheOnly\":true,\"selectorRestored\":true,\"actualGameCalls\":0,\"actualNetworkRequests\":0}\n",checks);
}return 0;}
