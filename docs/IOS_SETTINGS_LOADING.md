# Settings loading and menu lifetime

The role settings build now yields one real frame before its bounds/UI work,
then yields after at most eight selected-tab option attempts. Header, hidden,
missing-setting and per-option error paths count toward that limit. A sparse
global option index can no longer skip the yield. Every selected option keeps
its original order, visibility rules and value callbacks. This is a row budget,
not a measured millisecond limit or viewport virtualization.

The native loading label reads own main-thread state from:

```c
int32_t ehr_source_settings_loading_v1(uint32_t *words, size_t count);
```

`count` is exactly eight. The words are version `1`, count `8`, selected-tab busy
`0/1`, active build count, selected attempted-row count, selected total rows,
selected global tab index plus one, and reserved zero. An idle selected tab has
zero busy/progress/total/tab words. Counts are bounded to 32 active builds and
20,000 rows; tab index plus one is at most 64. The getter reads only CLR fields
and the existing host main-thread predicate, never a Unity object or account.
Returns are `0` success, `2` off-main/unbound host, `4` invalid or ambiguous,
`6` contained diagnostic failure, and `8` exceeded bounds. Rejected reads leave
the caller's words untouched. Reading never finishes or cancels a build.

The label describes the actual selected-tab build. Normal completion, iterator
failure/disposal, tab changes and menu close clear its busy state. Only successful
final UI/navigation construction marks a build complete. Incomplete cached tabs
restart when reopened; their Children collection is rebuilt without duplicate
entries. The initial asynchronous yield also defers the existing controller
navigation call until rows exist. Synchronous/preset-explorer paths retain their
immediate call.

Tab deactivation and close invalidate the build generation and remove its owned
handle before stopping it. A late/disposed old iterator cannot remove a replacement
generation. If stopping fails, the invalid generation prevents another batch from
touching the UI, and close continues retiring other owned builds.

The same adaptation repairs directly visible cache defects: custom headers reuse
their existing collider/button and replace their own collapse listener; game-mode
buttons reuse live cached objects instead of clearing their lookup immediately
before every allocation. Modes no longer relevant are hidden. Close skips absent
or destroyed cached UI, including an input field that was never created. These
changes do not remove the existing settings cache or instantiate only visible
viewport rows.

`tools/source_port/prepare_settings_loading.py` checks the selected pre-change
source hash and applies individually unique, reversible edits. Its exact reverse
recovers the reviewed build-64 source. The older build-cleanup checker first
removes this layer and still verifies its original generation/fault proof.

```sh
EHR_DOTNET=/path/to/dotnet python3 -m unittest discover \
  -s tests -p 'test_settings_loading.py' -v
```

The fixture compiles extracted real scheduling, state-reader, cancellation and
cache allocation control flow with owned identity/action collaborators. It checks
all-continue and foreign-tab paths, first-frame visibility, row ordering, normal
completion, faults, cancellation, stale generations, rejected-read preservation
and repeated cache reopening. It performs no game, device, account or network
operation. This is evidence for these code contracts; it does not establish the
cause of the reported lobby-to-main-menu freeze or replace phone acceptance.
