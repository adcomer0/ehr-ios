#include "EHRHostCore.h"
#include <cassert>
#include <cstdint>
#include <iostream>
#include <limits>

struct Fixture {
    EHRHostCore *core = ehr_core_create(42);
    Fixture() {
        assert(core);
        assert(ehr_core_configure(core, {1, 0, 0, 0}) != EHR_INVALID_INPUT);
        ehr_core_begin_round(core, 7, 1);
    }
    ~Fixture() { ehr_core_destroy(core); }
    EHRMurderEvent kill(uint8_t victim = 2) { return {1, 7, 1000, 1, victim, 1, 0}; }
};
int main() {
    { Fixture f; EHRAction a{};
      assert(ehr_core_confirmed_murder(f.core, f.kill()) == EHR_SCHEDULED);
      assert(!ehr_core_poll(f.core, 1149, &a));
      assert(ehr_core_poll(f.core, 1150, &a));
      assert(a.kind == EHR_REPORT_BODY && a.reporter_id == 1 && a.victim_id == 2);
      assert(!ehr_core_poll(f.core, 9000, &a));
      assert(ehr_core_confirmed_murder(f.core, f.kill()) == EHR_DUPLICATE); }
    { Fixture f; auto event = f.kill(); event.round_id = 6;
      assert(ehr_core_confirmed_murder(f.core, event) == EHR_IGNORED);
      event = f.kill(); event.killer_is_exempt = 1;
      assert(ehr_core_confirmed_murder(f.core, event) == EHR_IGNORED);
      event = f.kill(); event.victim_is_bait = 0;
      assert(ehr_core_confirmed_murder(f.core, event) == EHR_IGNORED);
      event = f.kill(); event.killer_id = event.victim_id;
      assert(ehr_core_confirmed_murder(f.core, event) == EHR_IGNORED); }
    for (auto phase : {EHR_LOBBY, EHR_MEETING, EHR_ENDED}) {
      Fixture f; EHRAction a{}; ehr_core_confirmed_murder(f.core, f.kill());
      ehr_core_set_phase(f.core, phase); ehr_core_set_phase(f.core, EHR_TASKS);
      assert(!ehr_core_poll(f.core, 9000, &a)); }
    { Fixture f; EHRAction a{}; ehr_core_confirmed_murder(f.core, f.kill());
      ehr_core_set_host(f.core, 0); ehr_core_set_host(f.core, 1);
      assert(!ehr_core_poll(f.core, 9000, &a)); }
    { Fixture f; EHRAction a{}; ehr_core_confirmed_murder(f.core, f.kill());
      ehr_core_begin_round(f.core, 8, 1); assert(!ehr_core_poll(f.core, 9000, &a));
      auto event = f.kill(); event.round_id = 8;
      assert(ehr_core_confirmed_murder(f.core, event) == EHR_SCHEDULED); }
    { Fixture f; EHRAction a{}; ehr_core_configure(f.core, {1, 2, 4, 1});
      for (uint8_t id = 2; id < 30; ++id) {
        assert(ehr_core_confirmed_murder(f.core, f.kill(id)) == EHR_SCHEDULED);
      }
      uint64_t last_due = 0;
      while (ehr_core_poll(f.core, 5000, &a)) {
        assert(a.due_ms >= 3000 && a.due_ms <= 5000);
        assert(a.due_ms >= last_due && a.kind == EHR_FORCE_MEETING); last_due = a.due_ms;
      }
      assert(ehr_core_pending_count(f.core) == 0); }
    { Fixture f; EHRAction a{}; ehr_core_configure(f.core, {1, 4, 2, 0});
      ehr_core_confirmed_murder(f.core, f.kill());
      assert(ehr_core_poll(f.core, 1150, &a) && a.due_ms == 1150); }
    { Fixture f; auto event = f.kill(); event.monotonic_ms = std::numeric_limits<uint64_t>::max();
      assert(ehr_core_confirmed_murder(f.core, event) == EHR_INVALID_INPUT);
      event = f.kill(); event.victim_id = 255;
      assert(ehr_core_confirmed_murder(f.core, event) == EHR_INVALID_INPUT);
      assert(ehr_core_configure(f.core, {1, -1, 4, 0}) == EHR_INVALID_INPUT);
      assert(ehr_core_configure(f.core, {1, 0, 91, 0}) == EHR_INVALID_INPUT);
      assert(ehr_core_configure(f.core, {1, 90, 90, 0}) != EHR_INVALID_INPUT);
      event = f.kill(); event.killer_id = 254;
      assert(ehr_core_confirmed_murder(f.core, event) == EHR_INVALID_INPUT); }
    { Fixture f; EHRAction a{}; ehr_core_configure(f.core, {1, 2, 2, 0});
      ehr_core_confirmed_murder(f.core, f.kill());
      ehr_core_configure(f.core, {1, 2, 2, 0});
      assert(ehr_core_poll(f.core, 3000, &a)); }
    { Fixture f; EHRAction a{}; ehr_core_confirmed_murder(f.core, f.kill());
      ehr_core_configure(f.core, {0, 0, 0, 0});
      assert(!ehr_core_poll(f.core, 9000, &a)); }
    assert(!ehr_core_game_adapter_available());
    assert(ehr_core_confirmed_murder(nullptr, {}) == EHR_INVALID_INPUT);
    std::cout << "Native Bait subset: all behavioral checks passed. Game integration is absent.\n";
}
