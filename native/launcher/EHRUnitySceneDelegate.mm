#import "EHRUnitySceneDelegate.h"
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <dispatch/dispatch.h>
#include <objc/runtime.h>

// UIKit scene adoption is required for iOS27-linked applications:
// https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle
// Unity owns UIApplicationMain, its app controller and its rendering window:
// https://docs.unity3d.com/6000.0/Documentation/Manual/UnityasaLibrary-iOS.html
// The existing app controller's idempotent initialization selector runs in the
// initial scene foreground phase, before legacy Active can make its view key.
// No engine implementation, private layout or copied code is here.
namespace {
constexpr uint32_t MaximumAttachAttempts=100;
constexpr uint64_t RetryNanoseconds=100*NSEC_PER_MSEC;
enum Status:int32_t {Okay=0,NotReady=1,WrongThread=2,BadArgument=4,TypeMismatch=5,CallbackException=6,AlreadyConfigured=7,Limit=8};
enum Event:uint32_t {Active=1,Resign=2,Foreground=3,Background=4};
struct Metrics {
    std::atomic<int32_t> lastStatus{NotReady},attachStatus{NotReady},initializerStatus{NotReady};
    std::atomic<uint32_t> configured{0},connected{0},attached{0},windowPreserved{0},rootPreserved{0},rootPresent{0},windowVisible{0},windowKey{0},firstActiveCompleted{0};
    std::atomic<uint64_t> connections{0},ignoredScenes{0},attachAttempts{0},retriesScheduled{0},retriesExhausted{0};
    std::atomic<uint64_t> activeForwards{0},resignForwards{0},foregroundForwards{0},backgroundForwards{0},disconnects{0},callbackFailures{0},wrongThreadCalls{0},initialForegroundSkipped{0};
    std::atomic<uint64_t> initializerCalls{0},initializerReturned{0};
} metrics;
id<EHRUnityFrameworkPublicAPI> framework;
id<UIApplicationDelegate> unityDelegate;
UIWindow *unityWindow;
__weak UIWindowScene *currentScene;
__weak UIWindowScene *disconnectedScene;
__weak EHRUnitySceneDelegate *currentOwner;
bool initializerEntered=false;
bool mainThread(){if(NSThread.isMainThread)return true;++metrics.wrongThreadCalls;metrics.lastStatus.store(WrongThread);return false;}
void recordCallbackFailure(bool &recorded){if(recorded)return;recorded=true;++metrics.callbackFailures;metrics.lastStatus.store(CallbackException);}
id<UIApplicationDelegate> delegateForUnity(){
    if(!framework)return nil;
    id candidate=[framework appController];
    if(!candidate)return nil;
    if(candidate!=UIApplication.sharedApplication.delegate||![candidate conformsToProtocol:@protocol(UIApplicationDelegate)]||
       ![candidate respondsToSelector:@selector(window)]||
       (unityDelegate&&candidate!=unityDelegate)){
        metrics.lastStatus.store(TypeMismatch);return nil;
    }
    unityDelegate=(id<UIApplicationDelegate>)candidate;
    return unityDelegate;
}
bool exactType(char *type,const char *expected){
    const bool equal=type&&std::strcmp(type,expected)==0;
    std::free(type);return equal;
}
bool initializeUnity(id<UIApplicationDelegate> delegate){
    if(initializerEntered)return metrics.initializerReturned.load()!=0;
    const SEL selector=sel_registerName("initUnityWithApplication:");
    Method method=class_getInstanceMethod(object_getClass(delegate),selector);
    Method frameworkMethod=class_getInstanceMethod(object_getClass(framework),@selector(appController));
    Dl_info methodImage{},frameworkImage{};
    // This is a selector on the already loaded, signed Unity app controller,
    // not an Apple API. Validate its exact void(self,SEL,object) ABI and that
    // its implementation belongs to the configured framework's loaded image.
    if(!method||!frameworkMethod||method_getNumberOfArguments(method)!=3||
       !exactType(method_copyReturnType(method),"v")||
       !exactType(method_copyArgumentType(method,0),"@")||
       !exactType(method_copyArgumentType(method,1),":")||
       !exactType(method_copyArgumentType(method,2),"@")||
       !dladdr(reinterpret_cast<const void *>(method_getImplementation(method)),&methodImage)||
       !dladdr(reinterpret_cast<const void *>(method_getImplementation(frameworkMethod)),&frameworkImage)||
       !methodImage.dli_fbase||methodImage.dli_fbase!=frameworkImage.dli_fbase){
        metrics.initializerStatus.store(TypeMismatch);metrics.lastStatus.store(TypeMismatch);return false;
    }
    // Mark before entering original code. A reentrant event or exception must
    // never retry an entered initializer; the original has its own idempotence.
    initializerEntered=true;++metrics.initializerCalls;
    using Initialize=void(*)(id,SEL,UIApplication *);
    reinterpret_cast<Initialize>(method_getImplementation(method))(delegate,selector,UIApplication.sharedApplication);
    metrics.initializerReturned.store(1);metrics.initializerStatus.store(Okay);return true;
}
struct ForwardingScope {bool &value;explicit ForwardingScope(bool &flag):value(flag){value=true;}~ForwardingScope(){value=false;}};
}

@interface EHRUnitySceneDelegate () {
    __weak UIWindowScene *_scene;
    NSMutableArray<NSNumber *> *_pendingEvents;
    uint64_t _epoch;
    uint32_t _attempts;
    bool _accepted,_attached,_retryScheduled,_forwarding,_foreground,_active;
}
- (bool)isCurrent:(UIScene *)scene;
- (bool)tryAttach;
- (void)scheduleAttach;
- (void)flushEvents;
- (void)enqueue:(uint32_t)event;
@end

@implementation EHRUnitySceneDelegate
- (bool)isCurrent:(UIScene *)scene {
    return _accepted&&scene&&scene==_scene&&scene==currentScene&&currentOwner==self;
}
- (void)scheduleAttach {
    if(_attached||_retryScheduled||![self isCurrent:_scene])return;
    if(_attempts>=MaximumAttachAttempts){
        ++metrics.retriesExhausted;metrics.attachStatus.store(Limit);metrics.lastStatus.store(Limit);return;
    }
    _retryScheduled=true;++metrics.retriesScheduled;
    const uint64_t epoch=_epoch;
    __weak EHRUnitySceneDelegate *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,RetryNanoseconds),dispatch_get_main_queue(),^{
        EHRUnitySceneDelegate *owner=weakSelf;
        if(!owner||owner->_epoch!=epoch||![owner isCurrent:owner->_scene])return;
        owner->_retryScheduled=false;
        [owner flushEvents];
        [owner tryAttach];
    });
}
- (bool)tryAttach {
    if(!mainThread()||![self isCurrent:_scene])return false;
    if(_attached){
        metrics.rootPresent.store(self.window.rootViewController!=nil);
        metrics.windowVisible.store(!self.window.hidden);
        metrics.windowKey.store(self.window.isKeyWindow);
        return true;
    }
    ++_attempts;++metrics.attachAttempts;
    // Wait for original initialization and the initial Active callback before
    // touching Unity's existing window. No private engine flag/API is read or
    // written. Lifecycle delivery remains independent of attachment.
    if(!metrics.firstActiveCompleted.load()){
        metrics.attachStatus.store(NotReady);metrics.lastStatus.store(NotReady);[self scheduleAttach];return false;
    }
    @try {try {
        id<UIApplicationDelegate> delegate=delegateForUnity();
        if(!delegate){metrics.attachStatus.store(NotReady);[self scheduleAttach];return false;}
        UIWindow *window=delegate.window;
        if(!window){metrics.attachStatus.store(NotReady);metrics.lastStatus.store(NotReady);[self scheduleAttach];return false;}
        if(![window isKindOfClass:UIWindow.class]||(unityWindow&&unityWindow!=window)||
           (window.windowScene&&window.windowScene!=_scene&&window.windowScene!=disconnectedScene)){
            metrics.attachStatus.store(TypeMismatch);metrics.lastStatus.store(TypeMismatch);return false;
        }
        UIViewController *root=window.rootViewController;
        const BOOL wasVisible=!window.hidden;
        if(window.windowScene!=_scene)window.windowScene=_scene;
        // Preserve the current Unity-created root, including a still-lazy nil
        // root. Unity's normal lifecycle callbacks remain responsible for UI.
        if(window.windowScene!=_scene||delegate.window!=window||window.rootViewController!=root){
            metrics.attachStatus.store(TypeMismatch);metrics.lastStatus.store(TypeMismatch);return false;
        }
        unityWindow=window;self.window=window;disconnectedScene=nil;_attached=true;
        // Unity may have shown its legacy window before a scene was connected.
        // Reapply that existing intent after attachment; never show a window
        // Unity deliberately kept hidden/lazy during engine initialization.
        if(wasVisible)[window makeKeyAndVisible];
        metrics.attached.store(1);metrics.windowPreserved.store(1);metrics.rootPreserved.store(1);
        metrics.rootPresent.store(window.rootViewController!=nil);metrics.windowVisible.store(!window.hidden);metrics.windowKey.store(window.isKeyWindow);
        metrics.attachStatus.store(Okay);metrics.lastStatus.store(Okay);
        return true;
    }catch(...){++metrics.callbackFailures;metrics.attachStatus.store(CallbackException);metrics.lastStatus.store(CallbackException);return false;}}
    @catch(__unused NSException *error){++metrics.callbackFailures;metrics.attachStatus.store(CallbackException);metrics.lastStatus.store(CallbackException);return false;}
}
- (void)flushEvents {
    if(_forwarding||![self isCurrent:_scene]||!_pendingEvents.count)return;
    id<UIApplicationDelegate> delegate=nil;
    bool lookupFailureRecorded=false;
    @try {try {delegate=delegateForUnity();}catch(...){recordCallbackFailure(lookupFailureRecorded);throw;}}
    @catch(NSException *error){recordCallbackFailure(lookupFailureRecorded);@throw error;}
    if(!delegate){[self scheduleAttach];return;}
    ForwardingScope scope(_forwarding);
    while(_pendingEvents.count&&[self isCurrent:_scene]){
        const uint32_t event=_pendingEvents.firstObject.unsignedIntValue;
        // Remove before original code: reentry cannot replay an entered event.
        [_pendingEvents removeObjectAtIndex:0];
        bool callbackFailureRecorded=false;
        @try {try {
            switch(event){
                case Active:
                    // UIKit normally supplies Foreground first. Do not enter
                    // Unity's fallback initializer too late from Active if the
                    // earlier initialization contract was unavailable/failed.
                    if(!metrics.initializerReturned.load()){_active=false;metrics.lastStatus.store(NotReady);break;}
                    if([delegate respondsToSelector:@selector(applicationDidBecomeActive:)]){++metrics.activeForwards;[delegate applicationDidBecomeActive:UIApplication.sharedApplication];metrics.firstActiveCompleted.store(1);}break;
                case Resign:if([delegate respondsToSelector:@selector(applicationWillResignActive:)]){++metrics.resignForwards;[delegate applicationWillResignActive:UIApplication.sharedApplication];}break;
                case Foreground:
                    // DDF may skip initialization while UIApplication is in
                    // the background during scene creation. Initialize in the
                    // foreground phase, before Active can trigger key-command
                    // queries, using the original idempotent engine selector.
                    // The legacy Foreground callback itself denotes a resume,
                    // so it is still omitted for the cold scene transition.
                    if(!metrics.firstActiveCompleted.load()){
                        if(!initializeUnity(delegate))break;
                        ++metrics.initialForegroundSkipped;break;
                    }
                    if([delegate respondsToSelector:@selector(applicationWillEnterForeground:)]){++metrics.foregroundForwards;[delegate applicationWillEnterForeground:UIApplication.sharedApplication];}break;
                case Background:if([delegate respondsToSelector:@selector(applicationDidEnterBackground:)]){++metrics.backgroundForwards;[delegate applicationDidEnterBackground:UIApplication.sharedApplication];}break;
                default:metrics.lastStatus.store(BadArgument);break;
            }
        }catch(...){if(initializerEntered&&!metrics.initializerReturned.load())metrics.initializerStatus.store(CallbackException);recordCallbackFailure(callbackFailureRecorded);throw;}}
        @catch(NSException *error){if(initializerEntered&&!metrics.initializerReturned.load())metrics.initializerStatus.store(CallbackException);recordCallbackFailure(callbackFailureRecorded);@throw error;}
    }
}
- (void)enqueue:(uint32_t)event {
    if(_pendingEvents.count>=16){metrics.lastStatus.store(Limit);return;}
    [_pendingEvents addObject:@(event)];[self flushEvents];[self tryAttach];
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(__unused UISceneConnectionOptions *)options {
    if(!mainThread())return;
    if(!framework||![scene isKindOfClass:UIWindowScene.class]||session!=scene.session||
       ![session.role isEqualToString:UIWindowSceneSessionRoleApplication]||
       (currentScene&&currentScene!=scene)||(currentOwner&&currentOwner!=self)){
        ++metrics.ignoredScenes;metrics.lastStatus.store(BadArgument);return;
    }
    if([self isCurrent:scene])return;
    _scene=(UIWindowScene *)scene;currentScene=_scene;currentOwner=self;
    _accepted=true;_attached=false;_retryScheduled=false;_forwarding=false;_foreground=false;_active=false;_attempts=0;++_epoch;
    _pendingEvents=[NSMutableArray new];self.window=nil;
    ++metrics.connections;metrics.connected.store(1);metrics.attached.store(0);metrics.rootPresent.store(0);metrics.windowVisible.store(0);metrics.windowKey.store(0);
    [self tryAttach];
}
- (void)sceneWillEnterForeground:(UIScene *)scene {
    if(!mainThread())return;if(![self isCurrent:scene]){++metrics.ignoredScenes;return;}
    if(_foreground)return;_foreground=true;[self enqueue:Foreground];
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    if(!mainThread())return;if(![self isCurrent:scene]){++metrics.ignoredScenes;return;}
    if(_active)return;_active=true;[self enqueue:Active];
}
- (void)sceneWillResignActive:(UIScene *)scene {
    if(!mainThread())return;if(![self isCurrent:scene]){++metrics.ignoredScenes;return;}
    if(!_active)return;_active=false;[self enqueue:Resign];
}
- (void)sceneDidEnterBackground:(UIScene *)scene {
    if(!mainThread())return;if(![self isCurrent:scene]){++metrics.ignoredScenes;return;}
    if(!_foreground)return;_foreground=false;[self enqueue:Background];
}
- (void)sceneDidDisconnect:(UIScene *)scene {
    if(!mainThread())return;if(![self isCurrent:scene]){++metrics.ignoredScenes;return;}
    _accepted=false;_attached=false;_retryScheduled=false;++_epoch;[_pendingEvents removeAllObjects];
    disconnectedScene=_scene;currentScene=nil;currentOwner=nil;_scene=nil;
    metrics.connected.store(0);metrics.attached.store(0);metrics.rootPresent.store(0);metrics.windowVisible.store(0);metrics.windowKey.store(0);++metrics.disconnects;
    // The Unity-owned window/root stays intact. A later accepted connection
    // can attach this same window, after the former scene has disconnected.
}
@end

extern "C" __attribute__((visibility("default")))
int32_t EHRUnitySceneConfigure(id<EHRUnityFrameworkPublicAPI> value){
    if(!mainThread())return WrongThread;
    if(!value||![value respondsToSelector:@selector(appController)])return BadArgument;
    if(framework&&framework!=value)return AlreadyConfigured;
    framework=value;metrics.configured.store(1);metrics.lastStatus.store(Okay);return Okay;
}
extern "C" __attribute__((visibility("default")))
NSDictionary<NSString *,id> *EHRUnitySceneCopyStatus(void){
    return @{@"schemaVersion":@1,@"configured":@(metrics.configured.load()),@"connected":@(metrics.connected.load()),@"attached":@(metrics.attached.load()),
        @"lastStatus":@(metrics.lastStatus.load()),@"attachStatus":@(metrics.attachStatus.load()),@"connections":@(metrics.connections.load()),
        @"ignoredScenes":@(metrics.ignoredScenes.load()),@"attachAttempts":@(metrics.attachAttempts.load()),@"retriesScheduled":@(metrics.retriesScheduled.load()),
        @"retriesExhausted":@(metrics.retriesExhausted.load()),@"windowPreserved":@(metrics.windowPreserved.load()),@"rootPreserved":@(metrics.rootPreserved.load()),
        @"rootPresent":@(metrics.rootPresent.load()),@"windowVisible":@(metrics.windowVisible.load()),@"windowKey":@(metrics.windowKey.load()),@"firstActiveCompleted":@(metrics.firstActiveCompleted.load()),@"activeForwards":@(metrics.activeForwards.load()),
        @"resignForwards":@(metrics.resignForwards.load()),@"foregroundForwards":@(metrics.foregroundForwards.load()),@"backgroundForwards":@(metrics.backgroundForwards.load()),
        @"disconnects":@(metrics.disconnects.load()),@"callbackFailures":@(metrics.callbackFailures.load()),@"wrongThreadCalls":@(metrics.wrongThreadCalls.load()),@"initialForegroundSkipped":@(metrics.initialForegroundSkipped.load()),
        @"initializerStatus":@(metrics.initializerStatus.load()),@"initializerCalls":@(metrics.initializerCalls.load()),@"initializerReturned":@(metrics.initializerReturned.load())};
}
