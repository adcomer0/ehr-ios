#ifndef EHR_HOST_CORE_H
#define EHR_HOST_CORE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

// A portable first-rule experiment. These are adapter inputs, not game hooks.
typedef struct EHRHostCore EHRHostCore;
typedef enum EHRPhase { EHR_LOBBY = 0, EHR_TASKS = 1, EHR_MEETING = 2, EHR_ENDED = 3 } EHRPhase;
typedef enum EHRActionKind { EHR_REPORT_BODY = 1, EHR_FORCE_MEETING = 2 } EHRActionKind;
typedef enum EHRStatus {
    EHR_IGNORED = 0, EHR_SCHEDULED = 1, EHR_INVALID_INPUT = 2,
    EHR_DUPLICATE = 3, EHR_QUEUE_FULL = 4
} EHRStatus;
typedef struct EHRBaitConfig {
    int enabled;
    int delay_min_seconds;
    int delay_max_seconds;
    int force_meeting;
} EHRBaitConfig;
typedef struct EHRMurderEvent {
    uint64_t event_id;
    uint64_t round_id;
    uint64_t monotonic_ms;
    uint8_t killer_id; // Adapter resolves EHR's real-killer identity first.
    uint8_t victim_id;
    int victim_is_bait;
    int killer_is_exempt; // Adapter supplies KillingMachine / Focused exclusions.
} EHRMurderEvent;
typedef struct EHRAction {
    EHRActionKind kind;
    uint64_t event_id;
    uint64_t round_id;
    uint64_t due_ms;
    uint8_t reporter_id;
    uint8_t victim_id;
} EHRAction;

EHRHostCore *ehr_core_create(uint32_t random_seed);
void ehr_core_destroy(EHRHostCore *core);
// Changing configuration discards pending actions to avoid stale callbacks.
EHRStatus ehr_core_configure(EHRHostCore *core, EHRBaitConfig config);
void ehr_core_begin_round(EHRHostCore *core, uint64_t round_id, int is_host);
// Meeting/lobby/end transitions discard timers; returning to tasks never revives them.
void ehr_core_set_phase(EHRHostCore *core, EHRPhase phase);
void ehr_core_set_host(EHRHostCore *core, int is_host);
EHRStatus ehr_core_confirmed_murder(EHRHostCore *core, EHRMurderEvent event);
// The actual game adapter must call this on Unity's main thread and revalidate
// player objects before dispatch. This library does not send network packets.
int ehr_core_poll(EHRHostCore *core, uint64_t monotonic_ms, EHRAction *action);
uint32_t ehr_core_pending_count(const EHRHostCore *core);
const char *ehr_core_reference_version(void);
int ehr_core_game_adapter_available(void);

#ifdef __cplusplus
}
#endif
#endif
