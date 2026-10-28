> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# iOS touch shortcuts

This source-only overlay composes after the current protected full-source project, including sizing, audio names, and the separate iOS Ctrl+V correction. It adds no native hook, ABI table, account write, forced chat permission, vote selection, or duplicate lobby-code copy button.

The client controls menu gains:

- **Chat editing:** Previous, Next and Complete command. They appear only while the existing free-chat field is open and focused. Tapping closes the client panel and queues one action for the existing ControllerManager handler, which retains all its original focus/history/command guards. The request belongs to the same native chat instance, expires after two seconds, and is consumed once. Native TextBoxTMP.SetText already writes accepted text to the existing TouchScreenKeyboard buffer; the adapter adds no second keyboard write. Actual keyboard/IME interaction remains a phone playtest.
- **Number-option steps:** ×1, ×5 and ×10. Choose a step, then use the existing numeric plus/minus controls. The selector is limited to the host's active lobby settings menu, outside countdown/started phases. Leaving that menu resets the mode. Original Shift/Control priority, numeric range/wrap behavior, save, callbacks and sync remain unchanged. The multiplier applies to the option's increment, rather than an absolute numeric value.
- **Host meeting execution:** Rows explicitly select a currently alive player from this meeting. A separate red confirmation runs the pinned original seven-effect execution sequence; Cancel or losing the host/meeting/member/alive context clears the pending selection. This touch selector replaces only desktop mouse-hover hit selection. It never writes HighlightedFX or invokes vanilla PlayerVoteArea.Select/MeetingHud.Select/Confirm, so selecting a row does not cast a vote. Native instance IDs and player IDs are scalar context keys; no native object/root is retained in static state. Original external-keyboard execution remains untouched.

Read-only actual iOS metadata confirms the existing vanilla `LobbyInfoPane.CopyCodeButton`, CopyGameCode (RVA 0x1c0fd64), CoCopyGameCode and DisableCopyCodeText; no duplicate is added. The actual PlayerVoteArea.Select body directly calls MeetingHud.Select, with a separate MeetingHud.Confirm; these are deliberately not reused to synthesize a touch execution target. Metadata/API presence does not establish visibility of a particular lobby scene. Private evidence is `evidence/vanilla-touch.local.json`, pinned to framework SHA 42e47c2e676fd5389385d12ddefc45bdcb88a9c3db54285381521abb762ba84f and metadata SHA 22dd824b108490c49962b7e31c30eae0055ce0b72e39aac3fa159324d6dd529c; it contains declarations/addresses, no game bytes.

Generate against a CURRENT project:

```sh
python3 tools/prepare_touch_shortcuts.py --project /absolute/current/EHR.csproj --output /absolute/fresh/join
```

The generator preserves the current GUI, ControlPatch and numeric-options adaptations, rebases explicit relative input paths, and adds all four current own helpers (including the failure gate and same-Id optional native probe). It verifies the exact current original execution effect block before emitting anything usable. An input must precede this touch overlay: a selected helper is rejected before output creation, preventing duplicate definitions. Compose after the current keyboard-paste/sizing/audio adaptations, preserving their selected inputs. The manifest reports `failureGateIncluded: true`, `identityProbeIncluded: true` and `separateLegacyIdentityOverlayRequired: false`. Fresh canonical regeneration must skip `prepare_touch_identity.py`; it already includes that helper revision. The frozen43/44 delivery projects and manifests are historical pins and are unchanged.

`tools/check_touch_shortcuts.py --project CURRENT --output FRESH --nativeaot --full-compile` verifies exact original body/guard preservation, then runs owned scalar policy checks under both .NET and an actual osx-arm64 NativeAOT binary. Its inputs contain no Unity/game objects. Full-source compilation passes with zero errors; warnings remain. New controls reuse the already tested client Btn geometry (at least 44 pt hit areas/readable 14 pt text); this package does not claim a rendered meeting/chat/settings playtest.

For the full iOS NativeAOT image, optional export `ehr_ios_touch_shortcuts_self_test_v1(int32_t*proof,size_t count)` requires count 12. On success status 0, proof 0 and proof 1..10 are 1, proof 11(dynamic code) is 0. It exercises fresh owned scalar state only and neither initializes the production shortcut state nor touches the game. Core/native table sizes stay unchanged.
