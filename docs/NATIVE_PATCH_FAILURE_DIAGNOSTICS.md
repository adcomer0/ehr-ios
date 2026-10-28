# Numeric source failure origin

Build 47 reported `GameStartManager.Start` status 6 with flags 127. Those flags prove dispatcher/original participation and a retained native exception, but cannot distinguish original failure from a source callback's native operation. The target has prefix 87 (`AllMapIconsPatch`), postfix 88 (`AllMapIconsPatch`) and postfix 131 (`GameStartManagerStartPatch`). These are diagnostic candidates, not proven faulty callbacks.

The source dispatcher now tracks the stage and generated callback index of the surviving exception. Finalizers that explicitly replace an exception become its origin; suppressed exception-path finalizer throws do not relabel the original failure. This changes numeric bookkeeping only. Callback order, prefix skip rules, finalizer retries, original participation and exception ownership remain unchanged.

An independent optional C export leaves all existing tables and V2 proof sizes unchanged:

```c
int32_t ehr_source_patch_failure_v1(uint64_t target_id,
    uint32_t *words, size_t word_count); /* exactly 12 aligned words */
```

Read on the same thread immediately after a failed dispatch. The record is published after copyback, exception export and cleanup, so nested calls cannot overwrite the final outer failure. Each new dispatch invalidates older records. Repeated reads are stable; wrong-target/no-current-record returns NOT_FOUND (3), zeroes valid output and does not consume the record. Invalid pointers/count/alignment return BAD_ARGUMENT (4).

| Word | Numeric value |
| --- | --- |
| 0–1 | Version 1, count 12 |
| 2–3 | Sequence low/high |
| 4–5 | Exact generated target ID low/high |
| 6 | Failure stage below |
| 7 | Callback index + 1; zero means none |
| 8 | Argument index + 1; zero means none |
| 9 | Exception category below |
| 10 | Actual returned dispatch status |
| 11 | Source dispatcher selected its original delegate (0/1) |

Stages are 1 readiness, 2 receiver decode, 3 argument decode, 4 default result, 5 prefix, 6 original delegate, 7 postfix, 8 finalizer, 9 ref copyback, 10 result boxing, 11 native-exception export, 12 binding dispatch. Stage 6 may include preparing/invoking/closing the original route; the existing V2 proof establishes whether the real runtime/trampoline was entered.

Exception categories are 1 native-game exception wrapper, 2 other runtime-gateway exception, 3 invalid cast, 4 argument exception, 5 unsupported operation, 6 invalid operation, 7 other CLR exception. These are fixed categories, not native class names or messages. No text, stack, account/player data, object pointer or GC token is copied. The native reader must additionally match target, status and bounds before recording the values; native metadata exception classification is a separate diagnostic.

The owned `tests/patch_outcome_fixture` compiles the production dispatcher with an owned host, including the exact callback ordinals above, original/native-wrapper failures, finalizer replacement/suppression, nested calls, output failures and stale-record rejection. It invokes no game code. Actual device reproduction remains required to identify the black-screen origin.

## Native diagnostic snapshot

The native reader queries this optional export only after establishing the
returned-value, ref-value and exception ownership guards. C++ and Objective-C
observer exceptions are contained. Malformed or stale responses are ignored;
the saved dispatch status, original-call proof and exception are unchanged.
There is no additional original call or source retry.

The existing own-cache numeric snapshot adds `failureDetailLimit` (32),
`failureDetailTotal` and `failureDetails`. This separate bounded ring does not
increment route `failureTotal`. It uses event kind 11. Each record contains only
numbers and is linked to the current route or iterator when one exists:

| Field | Meaning |
| --- | --- |
| `kind` | 1 source dispatcher origin; 2 native invocation exception metadata |
| `sourceSequence` | Source dispatch sequence, zero for native metadata |
| `stage`, `callbackIndexPlusOne`, `argumentIndexPlusOne` | Source origin above |
| `exceptionKind` | Source category above for kind 1; native category below for kind 2 |
| `metadataMethodToken` | Native invoked method's public metadata token |
| `metadataOwnerHash`, `metadataMethodHash` | Bounded metadata-name hashes |
| `originalEntered` | Source selection of its original delegate, not a replacement for the V2 participation proof |

Native metadata is recorded only after the original exception has been rooted.
It reads public class/method metadata without initializing classes, inspecting
exception fields, or copying messages or stacks. Native categories are 0 unknown,
1 null reference, 2 Unity missing reference, 3 argument, 4 invalid operation,
5 index out of range, 6 missing method, 7 unsupported operation, 8 type load,
9 invalid cast, 10 disposed object, 11 null argument, 12 argument out of range,
13 other `System.Exception`. Category ancestry is bounded to eight classes.

Hashes use 64-bit FNV-1a over UTF-8 metadata names: offset
14695981039346656037 and multiplier 1099511628211. The owner input is
`namespace + "." + className` when a namespace exists; the method input is its
name. Each name must terminate within 512 bytes, otherwise its hash is zero.
These values identify operations against the locally pinned metadata without
including object addresses, GC tokens, arguments, account data or free text.
The existing 512 KiB snapshot limit remains in force.
