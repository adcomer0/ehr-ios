# iOS game-start iterator adaptation

The pinned iOS AOT build allocates the native host-start iterator directly inside
`AmongUsClient.CoStartGame`'s `MoveNext`. These inlined products bypass the
`CoStartGameHost` method-entry patch. The host-start source replacement therefore
needs one additional, optional native interception boundary.

The adapter calls the original parent `MoveNext` exactly once. After a successful
`true` result, it recognizes only the exact parent/host iterator classes, parent
yield state 5 or 7, untouched host state 0, and identical non-null captured
`AmongUsClient` owners. It invokes the existing patched host factory once, keeping
its source callbacks and role-assignment ordering. The replacement must be an
active production-owned native iterator. Before committing, it checks activation
and all captured parent/child facts again, then writes `Current` through the
public field API and verifies identity. Other yielded objects stay unchanged.

Preparation resolves metadata, rejects class constructors on the generated
iterator classes, checks exact declared field owners/types/writability, and
validates native methods against the signed framework association. It does not
construct objects or invoke the host factory. Activation belongs after successful
full source startup; disable it before failure cleanup. Counters and failure
stages are fixed numeric values and can be copied by the diagnostics worker.
Failed adaptation raises the original retained native exception when available,
or the existing bounded native failure. It never retries the original or factory.

## Generate and select the optional adapter

Use the exact locally installed game that matches the reviewed framework and
metadata fingerprints. Choose fresh output files outside every Git checkout.
`EHR_GAME_APP` below is the local game `.app`; `EHR_OUTPUT` is your private build
output directory. These commands inspect the source read-only:

```sh
: "${EHR_GAME_APP:?Set the matching local game .app path}"
: "${EHR_OUTPUT:?Set a fresh output directory outside Git}"

python3 tools/map_native_methods.py \
  --framework "$EHR_GAME_APP/Frameworks/UnityFramework.framework/UnityFramework" \
  --metadata "$EHR_GAME_APP/Data/Managed/Metadata/global-metadata.dat" \
  --output "$EHR_OUTPUT/native-method-map.json"

python3 tools/prepare_game_start_iterator_map.py \
  --framework "$EHR_GAME_APP/Frameworks/UnityFramework.framework/UnityFramework" \
  --metadata "$EHR_GAME_APP/Data/Managed/Metadata/global-metadata.dat" \
  --pins "$EHR_OUTPUT/native-method-map.json" \
  --output "$EHR_OUTPUT/game-start-iterator-map.json"
```

Add `--game-start-iterator-map "$EHR_OUTPUT/game-start-iterator-map.json"` to the
existing reviewed `tools/build_game_probe.py` full-profile invocation. It still
requires the original hook map, managed library, full native catalog/target map,
compiled thunk inputs, iterator map, static-class plan and your normal signing
inputs. Retain any other optional inputs selected for that candidate; this
argument does not replace them or regenerate the full native pipeline. See
[building](BUILDING.md#native-generation-and-signing).

The builder verifies reviewed source identity, metadata declarations and the
installed entry/trampoline, then compiles this adapter only for the full source
profile. The signed `EHRGameStartIteratorCompiled` flag is false when omitted.
When true, runtime delivery checks require actual `preparedStatus: 0` and
`enabled: true`, plus the matching `EHRGameStartIteratorProof.json` attachment.
The installer checks its success, counts, root accounting and explicit absence
of real game actions, alongside the existing startup and binary/signing checks.
Generated maps and game binaries remain outside Git. No managed function-table
ABI changes.

## Validation and its limits

`python3 -m unittest discover -s tests -p test_game_start_iterator.py -v` runs
self-contained mapping/builder checks and an owned synthetic native runtime. The
compiled fixture exercises the actual adapter's owner checks, original/factory
counts, reentrant mutations, inactive/worker behavior and exception/root cleanup.
The exported `EHRGameStartIteratorSelfTest` separately constructs only owned native
iterator and ArrayList objects, with no game owner, real host factory, original
`MoveNext`, Unity scene, account or network operation. Its internal factory seam
alone permits matching null owners; production always rejects them. This probe
must pass on the actual signed runtime before delivery.

Build 49 passed that probe on the signed iOS-on-Mac candidate: 46 checks, six
factory-seam calls, and the same owned-root count before and after. Preparation
returned zero and activation was enabled; the retained-carrier and failure-cleanup
checks also passed. No real owner, original `MoveNext`, real host factory, Unity
object creation or executable memory write was used by this probe.

The separate physical build-49 observation recorded one real-owner replacement
and one factory call, with zero adapter failures. Its host replacement, custom
intro, allowed ship initialization, game-start and game-end routes completed;
the user reported entering a game and winning immediately. The earlier build-48
black screen did not recur in that attempt. This does not establish every role,
player combination or a normal multiplayer round. See
[the validation scope](BUILD49_VALIDATION.md) and [known issues](KNOWN_ISSUES.md).
