#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// Posted on the main queue after a sample. The notification object is its
/// immutable NSDictionary snapshot. No managed game objects escape the bridge.
FOUNDATION_EXPORT NSString *const EHRLiveBridgeSnapshotNotification;

/// Starts an idempotent 500 ms, main-queue runtime sampler. Calling from a
/// background thread is allowed. The default build also calls this after the
/// dylib loads; define EHR_LIVE_BRIDGE_AUTOSTART=0 to opt out.
FOUNDATION_EXPORT void EHRLiveBridgeStart(void);
FOUNDATION_EXPORT void EHRLiveBridgeStop(void);

/// Thread-safe access to the last JSON-compatible snapshot. Before the first
/// sample this reports status "not_sampled"; availability is never inferred.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EHRLiveBridgeCopySnapshot(void);

/// Samples synchronously on the main queue. A caller must not hold a lock that
/// the main queue needs. The diagnostic sample reads getters/fields only. A
/// separate Bait timer can invoke reporting only after configuration AND an
/// actual validated post-MurderPlayer callback; the default is disabled.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EHRLiveBridgeSampleNow(void);

/// Manual assignment for the limited Bait rule, NOT full EHR role assignment.
/// Returns 1 for accepted settings, 0 for invalid inputs. Player IDs are 0...253;
/// -1 means unselected and is accepted only when disabled. Delays are 0...90 s.
/// An actual callback is still required; configuring does not claim a live hook.
FOUNDATION_EXPORT int EHRLiveBridgeConfigureBait(int enabled, int selectedPlayerId,
                                                int delayMinSeconds, int delayMaxSeconds);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EHRLiveBridgeCopyBaitStatus(void);

/// Exact helper callback ABI. The separately installed interceptor MUST call
/// the original PlayerControl.MurderPlayer(target, flags) first, then call this
/// on Unity's main thread with its real __this/target/flags. Off-main callbacks
/// are rejected without retaining or asynchronously dereferencing raw pointers.
/// This bridge installs no hook and modifies no executable instructions.
FOUNDATION_EXPORT void EHRLiveBridgeOnConfirmedMurder(void *_Nullable killer,
                                                     void *_Nullable victim,
                                                     uint32_t flags);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
