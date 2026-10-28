// Run only after the managed Action self-test has returned and released its
// proxy/retained roots. Later main-queue turns avoid retaining constructing
// frames during this conservative-GC lifetime check.
NSDictionary *exerciseActionAutomaticWeakCollection(XCTestCase *test) {
    using Count=uint64_t (*)(void);
    using Sweep=EHRRuntimeStatus (*)(size_t *);
    using Collect=void (*)(int);
    auto count=reinterpret_cast<Count>(bridgeExport("EHRManagedActionRegistrationCount"));
    auto active=reinterpret_cast<Count>(bridgeExport("EHRManagedActionActiveCount"));
    auto sweep=reinterpret_cast<Sweep>(bridgeExport("EHRManagedActionSweep"));
    auto collect=reinterpret_cast<Collect>(bridgeExport("il2cpp_gc_collect"));
    if(!test || !NSThread.isMainThread)
        return @{ @"success":@NO,@"error":@"XCTest owner and Unity main thread required" };
    NSMutableArray *missing=[NSMutableArray array];
    if(!count) [missing addObject:@"EHRManagedActionRegistrationCount"];
    if(!active) [missing addObject:@"EHRManagedActionActiveCount"];
    if(!sweep) [missing addObject:@"EHRManagedActionSweep"];
    if(!collect) [missing addObject:@"il2cpp_gc_collect"];
    if(missing.count) return @{ @"success":@NO,@"missingExports":missing,@"gcExportAvailable":@(collect!=nullptr) };
    const uint64_t before=count(),activeBefore=active();
    if(before>256 || activeBefore!=0)
        return @{ @"success":@NO,@"error":@"Unexpected live callback scope",@"weakBefore":@(before),@"activeBefore":@(activeBefore) };
    XCTestExpectation *done=[test expectationWithDescription:@"Automatic Action weak registry cleanup after source frames return"];
    __block NSUInteger polls=0,collections=0;
    __block bool completed=false,clean=false;
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),100*NSEC_PER_MSEC,10*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{
        if(completed) return;
        ++polls;
        // Request normal runtime collection only while our weak tombstones
        // remain. Cleanup itself must come from the adapter's scheduled sweep.
        if(count() && collections<3) {collect(0);++collections;}
        clean=count()==0 && active()==0;
        if(clean || polls>=30) {completed=true;dispatch_source_cancel(timer);[done fulfill];}
    });
    dispatch_resume(timer);
    [test waitForExpectations:@[done] timeout:4];
    dispatch_source_cancel(timer);dispatch_source_set_event_handler(timer,nil);
    size_t additionallyRemoved=0;const auto status=sweep(&additionallyRemoved);
    return @{ @"success":@(completed && clean && status==EHR_RUNTIME_OK && !additionallyRemoved && !count() && !active()),
        @"weakBefore":@(before),@"activeBefore":@(activeBefore),@"weakAfter":@(count()),@"activeAfter":@(active()),
        @"automaticMainQueueSweepObserved":@(clean),@"normalRuntimeCollectionRequests":@(collections),@"polls":@(polls),
        @"explicitFinalSweepStatus":@(status),@"explicitFinalSweepRemoved":@(additionallyRemoved),
        @"gameplayMutationPerformed":@NO };
}
