#include "EHROriginalInvocationGate.hpp"

#include <atomic>
#include <cassert>
#include <iostream>
#include <stdexcept>
#include <thread>

using ehr::OriginalInvocationPermit;

int main() {
    const int firstMethod = 0, secondMethod = 0;
    assert(!OriginalInvocationPermit::tryConsume(1, &firstMethod));
    {
        OriginalInvocationPermit scope(1, &firstMethod);
        assert(scope.valid() && !scope.consumed());
        assert(!OriginalInvocationPermit::tryConsume(2, &firstMethod));
        assert(!OriginalInvocationPermit::tryConsume(1, &secondMethod));
        assert(OriginalInvocationPermit::tryConsume(1, &firstMethod));
        assert(scope.consumed());
        // Same-target recursion after trampoline entry gets the patch pipeline.
        assert(!OriginalInvocationPermit::tryConsume(1, &firstMethod));
        {
            OriginalInvocationPermit recursiveOriginal(1, &firstMethod);
            assert(OriginalInvocationPermit::tryConsume(1, &firstMethod));
        }
        assert(!OriginalInvocationPermit::tryConsume(1, &firstMethod));
    }
    {
        OriginalInvocationPermit outer(1, &firstMethod);
        {
            OriginalInvocationPermit inner(2, &secondMethod);
            // A nested runtime call cannot consume the enclosing call's permit.
            assert(!OriginalInvocationPermit::tryConsume(1, &firstMethod));
            assert(OriginalInvocationPermit::tryConsume(2, &secondMethod));
        }
        assert(!outer.consumed());
        assert(OriginalInvocationPermit::tryConsume(1, &firstMethod));
    }
    {
        OriginalInvocationPermit outer(1, &firstMethod);
        try {
            OriginalInvocationPermit throwing(2, &secondMethod);
            throw std::runtime_error("original fixture exception");
        } catch (const std::runtime_error &) { }
        assert(OriginalInvocationPermit::tryConsume(1, &firstMethod));
    }
    assert(!OriginalInvocationPermit::tryConsume(1, &firstMethod));
    {
        OriginalInvocationPermit outer(1, &firstMethod);
        OriginalInvocationPermit invalidTarget(0, &firstMethod);
        OriginalInvocationPermit invalidMethod(1, nullptr);
        assert(!invalidTarget.valid() && !invalidMethod.valid());
        assert(OriginalInvocationPermit::tryConsume(1, &firstMethod));
    }
    {
        OriginalInvocationPermit mainThread(1, &firstMethod);
        std::atomic<bool> otherThreadPassed{false};
        std::thread worker([&] {
            assert(!OriginalInvocationPermit::tryConsume(1, &firstMethod));
            OriginalInvocationPermit workerThread(1, &firstMethod);
            assert(OriginalInvocationPermit::tryConsume(1, &firstMethod));
            otherThreadPassed.store(true);
        });
        worker.join();
        assert(otherThreadPassed.load());
        assert(!mainThread.consumed());
        assert(OriginalInvocationPermit::tryConsume(1, &firstMethod));
    }
    // A runtime call may throw or return without reaching the hook. No stale
    // permit survives the native scope even when it was never consumed.
    { OriginalInvocationPermit neverEntered(1, &firstMethod); }
    assert(!OriginalInvocationPermit::tryConsume(1, &firstMethod));
    std::cout << "Original invocation routing: identity, nesting, unwind and thread isolation passed\n";
}
