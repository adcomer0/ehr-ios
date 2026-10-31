# Source coroutine failure diagnostics

The production coroutine callback still returns its original status and uses
the original completion/disposal path. A separate read-only export records one
bounded numeric failure; it does not swallow a fault or widen the 72-byte host
and 32-byte callback tables.

```c
int32_t ehr_source_coroutine_failure_v1(uint64_t source_id,
                                      uint64_t *words, size_t count);
```

The native caller queries immediately after a failed `Step`, before terminal
cleanup cancels/removes the source. `count` must be 12. Returns are `0` for a
matching record, `1` unbound, `2` off-main, `3` unknown/stale/different source,
and `4` invalid arguments. Rejected reads leave the output untouched. A source
must remain registered and its failure sequence must match the latest record.

| Word | Meaning |
| --- | --- |
| 0, 1 | Version `1`, word count `12` |
| 2 | Exact managed source ID, not a pointer |
| 3 | FNV-1a 64-bit hash of UTF-8 `IEnumerator.GetType().FullName`; `0` if unavailable |
| 4 | Phase: 1 Ready, 2 CloseChild, 3 MoveNext, 4 Current, 5 encode yield, 6 Finish |
| 5 | Primary fixed exception kind |
| 6 | Primary status |
| 7 | Actual returned callback status |
| 8 | Monotonic failure sequence |
| 9, 10 | Cleanup exception kind/status; zero if none |
| 11 | Reserved zero |

Exception kinds are 1 native-game exception, 2 gateway, 3 null reference,
4 index, 5 unsupported, 6 cast, 7 disposed, 8 argument, 9 invalid operation,
10 overflow, 11 memory and 12 other. Cleanup may change the returned status;
the record preserves both the original failure and cleanup outcome. It emits
no exception text, stack, user payload, room, account identifier or token.
Successful callbacks do not replace the last failure.

Map hashes against the exact built mod assembly without executing it:

```sh
dotnet run --project tools/coroutine_type_map/CoroutineTypeMap.csproj \
  -c Release --artifacts-path /path/to/local-map-tools -- \
  /path/to/actual-built/EHR.dll > /path/to/private-type-map.json
```

The helper reads type/interface metadata only. It includes direct nongeneric
CLR IEnumerator implementations and compiler-generated iterators, rejecting
hash collisions. Constructed generic names require actual runtime arguments;
generic definitions are explicitly omitted. No game assembly is needed and no
method body/resource is read. Use the map for the same mod assembly hash as the
diagnostic build, rather than assuming compiler-generated names across builds.

The owned fixture compiles the actual production source, captures its real
unmanaged callback pointers through registration, and injects phase faults.
It checks primary versus cleanup status, exact source/sequence validation,
no-record success, stale output preservation, disposal, and offline hash mapping.
It makes no game, account, device or network calls.

```sh
EHR_DOTNET=/path/to/dotnet python3 -m unittest discover -s tests -p 'test_coroutine_failure.py' -v
```

These diagnostics do not establish which source operation caused a player's
failure. In the build-63 settings investigation, the OS report reaches the
native coroutine error path; cached UI churn and role scrolling alone are not
proof of the initiating managed exception.
