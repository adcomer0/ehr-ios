#include "EHRHostCore.h"
#include <algorithm>
#include <array>
#include <limits>
#include <new>

struct EHRHostCore {
    EHRBaitConfig config{0, 0, 0, 0};
    uint64_t round_id = 0;
    bool host = false;
    EHRPhase phase = EHR_LOBBY;
    uint32_t random_state;
    std::array<EHRAction, 255> pending{};
    uint32_t count = 0;
    // Each body may trigger only once per round, including after a timer fires.
    std::array<bool, 255> seen_victims{};
    explicit EHRHostCore(uint32_t seed) : random_state(seed ? seed : 0xE4A17u) {}
};

static uint32_t next_random(EHRHostCore *core) {
    uint32_t x = core->random_state;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    core->random_state = x;
    return x;
}

extern "C" {
EHRHostCore *ehr_core_create(uint32_t seed) { return new (std::nothrow) EHRHostCore(seed); }
void ehr_core_destroy(EHRHostCore *core) { delete core; }
EHRStatus ehr_core_configure(EHRHostCore *core, EHRBaitConfig config) {
    if (!core || config.delay_min_seconds < 0 || config.delay_max_seconds < 0 ||
        config.delay_min_seconds > 90 || config.delay_max_seconds > 90)
        return EHR_INVALID_INPUT;
    const bool changed = core->config.enabled != config.enabled ||
        core->config.delay_min_seconds != config.delay_min_seconds ||
        core->config.delay_max_seconds != config.delay_max_seconds ||
        core->config.force_meeting != config.force_meeting;
    core->config = config;
    if (changed) core->count = 0;
    return EHR_IGNORED;
}
void ehr_core_begin_round(EHRHostCore *core, uint64_t round_id, int is_host) {
    if (!core) return;
    core->round_id = round_id;
    core->host = is_host != 0;
    core->phase = EHR_TASKS;
    core->count = 0;
    core->seen_victims.fill(false);
}
void ehr_core_set_phase(EHRHostCore *core, EHRPhase phase) {
    if (!core) return;
    core->phase = phase;
    if (phase != EHR_TASKS) core->count = 0;
}
void ehr_core_set_host(EHRHostCore *core, int is_host) {
    if (!core) return;
    core->host = is_host != 0;
    if (!core->host) core->count = 0;
}
EHRStatus ehr_core_confirmed_murder(EHRHostCore *core, EHRMurderEvent event) {
    if (!core || event.killer_id >= 254 || event.victim_id >= 254)
        return EHR_INVALID_INPUT;
    if (!core->config.enabled || !core->host || core->phase != EHR_TASKS ||
        core->round_id != event.round_id || !event.victim_is_bait ||
        event.killer_is_exempt || event.killer_id == event.victim_id)
        return EHR_IGNORED;
    if (core->seen_victims[event.victim_id]) return EHR_DUPLICATE;
    if (core->count == core->pending.size()) return EHR_QUEUE_FULL;
    uint64_t delay_ms = 150;
    const int minimum = core->config.delay_min_seconds;
    const int maximum = core->config.delay_max_seconds;
    if (maximum >= minimum) {
        const uint32_t span = static_cast<uint32_t>(maximum - minimum + 1);
        const uint64_t seconds = minimum + (next_random(core) % span);
        delay_ms = std::max<uint64_t>(150, seconds * 1000);
    }
    if (event.monotonic_ms > std::numeric_limits<uint64_t>::max() - delay_ms)
        return EHR_INVALID_INPUT;
    EHRAction action{};
    action.kind = core->config.force_meeting ? EHR_FORCE_MEETING : EHR_REPORT_BODY;
    action.event_id = event.event_id;
    action.round_id = core->round_id;
    action.due_ms = event.monotonic_ms + delay_ms;
    action.reporter_id = event.killer_id;
    action.victim_id = event.victim_id;
    core->pending[core->count++] = action;
    core->seen_victims[event.victim_id] = true;
    return EHR_SCHEDULED;
}
int ehr_core_poll(EHRHostCore *core, uint64_t now, EHRAction *action) {
    if (!core || !action || !core->host || core->phase != EHR_TASKS || !core->count) return 0;
    uint32_t first = 0;
    for (uint32_t i = 1; i < core->count; ++i)
        if (core->pending[i].due_ms < core->pending[first].due_ms) first = i;
    if (core->pending[first].due_ms > now) return 0;
    *action = core->pending[first];
    for (uint32_t i = first + 1; i < core->count; ++i) core->pending[i - 1] = core->pending[i];
    --core->count;
    return 1;
}
uint32_t ehr_core_pending_count(const EHRHostCore *core) { return core ? core->count : 0; }
const char *ehr_core_reference_version(void) { return "EHR v8.0.3"; }
int ehr_core_game_adapter_available(void) { return 0; }
}
