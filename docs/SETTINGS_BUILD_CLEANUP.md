# Settings build cleanup

The tested build-47 settings iterator removed its `BuildCoroutines` entry only at normal completion and in its stale-generation branch. An uncaught fault or disposal while suspended could leave a stale handle; stale completion could also remove a replacement generation's handle. Both behaviors are reproduced in an owned fixture. They are separate from the observed native coroutine capacity failure and are not proven to explain the physical black screen.

The current selected `source-app/compiled/157/GameOptionsMenuPatch.cs` wraps only `CreateSettingsPrefix`'s local `CoRoutine(int gen)` in `try/finally`. The `finally` removes the entry only if the stored generation still equals `gen`. It keeps all UI actions, the existing per-option catch, loop/yield sites and Start/Stop calls in their original order. An older iterator cannot remove a newer build's handle. Missing generation evidence prevents removal. Disposing an unstarted CLR iterator remains lazy; no stronger Unity cancellation claim is made.

The preparer accepts only baseline SHA256 `8f0c225439e6b56546b5e6da120d4acc981c7d6bc4f547176ffac1b735e3feee` and rejects drift, duplicate selection and already-adapted input. The adaptation reverses to that baseline exactly. It changes one Compile selection; resource bytes and logical names are unchanged. The manifest selects the revised source, while build 47 remains the last physical test baseline.

From the repository root, with .NET 10 on PATH:

```sh
python3 -m unittest discover -s tests -p 'test_settings_build_cleanup.py' -v
python3 tools/check_settings_build_cleanup.py \
  --source source-app/compiled/157/GameOptionsMenuPatch.cs \
  --output /absolute/path/to/fresh/check-output \
  --dotnet "$(command -v dotnet)"
```

The small checker compiles the exact extracted original/adapted iterator control flow; game/UI work is replaced only with injected owned CLR actions and counts. No Unity or game engine is emulated. Fifty compiled checks cover normal order/yields, faults before/after the first yield, final-action and reporter faults, existing per-option catch behavior, cancellation/repeated Dispose, stale completion, replacement during final UI work, other menus and missing generation evidence. It never invokes a game/native method. There are no native, capacity, forced-GC, account or authentication changes in this adaptation.
