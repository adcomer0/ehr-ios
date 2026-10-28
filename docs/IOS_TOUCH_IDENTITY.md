> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

Legacy43-only overlay. For fresh canonical regeneration, use `prepare_touch_shortcuts.py` directly and SKIP `prepare_touch_identity.py`: current preparation already selects all four identity/failure helpers. This tool intentionally accepts only the old pinned43 helper SHA, so it rejects a current helper instead of silently reapplying the overlay. No change to the frozen44 delivery manifest or its C# sources.

Fresh identity/failure containment overlay after the frozen touch+paste+updater43 join. Preparation replaces only own IOSTouchShortcuts.cs and adds own IOSTouchControlFailureGate.cs. Original context guards and execution effect bodies are retained. No hook or native function-table changes.

Production policy: one failure seals all newly added shortcut controls until process restart. Reconcile, visibility checks, requests, selectors, confirmation and numeric-step lookups contain exceptions; queued scalar chat requests/meeting selection clear and option steps fall back to one. Cleanup marks the gate failed before running, so reentry cannot issue an action. NativeGameException roots are disposed. The failure gate never retries an effect that may have partially completed. The original desktop callbacks remain outside this own shortcut gate.

The optional export in native/IOSTouchIdentityProbe.h requires the already-bound source host/native gateway on its main thread. Exactly eight int32 words, return zero success: [1,1,id,id,id,1,1,0]; id must be signed nonzero and equal in words2/3/4. It uses the same private Id implementation as production. The probe constructs only its own GameObject through the already-proved native constructor route; repeats Id, acquires a separate owned root and repeats Id through that wrapper. Every path requests Object.Destroy for the created object, independently releases both object roots, and contains/disposes managed-game exceptions. Destroy is deferred: word5 proves request return only. Caller must compare native root counts before/after and yield Unity a frame. The probe never accesses production scalar state or game/account/global source state. Failed construction is explicitly unsuccessful; cleanup does not invent creation/identity success.

Validation: six source/project tests; 212 compiled owned failure/reentry/cleanup checks; full pinned IL2CPP-profile source compile zero errors. Root's actual signed Mac iOS RuntimeFullFeatures44 additionally passed the native probe with three equal signed nonzero IDs, successful own Destroy request, both wrappers disposed and gateway owned-object count6957 before/after. The test then yielded the main queue for100ms. Deferred native destruction and collection were not measured; physical interaction remains unverified.

Replay:
python3 tools/prepare_touch_identity.py --project INPUT/EHR.csproj --output FRESH
python3 -m unittest discover -s tests -p 'test_*.py'
dotnet run --project tests/FailureGateFixture.csproj -c Release

The preparation tool requires the exact prior own helper hash, fails before creating output if it differs, and rebases unrelated relative explicit source/resource/reference paths when relocating the input project. It preserves LogicalName and unrelated metadata. No implicit globs are supported by the full pinned input project.
