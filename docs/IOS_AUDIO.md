> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

The iOS source profile uses a separate custom-sound backend beneath the native host's dedicated `EHRSource/resources/sounds` directory. The original SFX/configuration checks, host/recipient RPC guards, and Windows implementation remain intact. Vanilla players do not receive custom audio assets from this host-only mod.

`prepare_ios_audio_behavior.py` composes the narrow `CustomSounds.cs` overlay and own helpers. It requires the exact pinned upstream sound source. With no `--runtime-proof`, the original Windows-only guard remains. Enabling the iOS route requires the complete successful 16-word data and muted-route proof vectors from `EHRSourceAudioProof.json`. Apply it to the current protected full-source project, pass the adopted `managed/PcmWaveData.cs` through `--pcm-source`, and write a fresh external output directory.

The current tool directly selects all four adopted helpers: `PcmWaveData`, `OwnedSoundFiles`, `SourceAudioPlayback` and `SourceAudioNames`. Its report must contain `namesSelected: true`. Duplicate helper basenames and conflicting existing name adapters are rejected; reviewed helper paths are selected explicitly rather than retaining stale implementations. Do not run the legacy `prepare_audio_names.py` during current canonical regeneration: that tool upgrades only the frozen build40 helper pair.

An exact existing custom filename takes priority; an exact authored resource name follows; otherwise only a unique case-insensitive authored name is accepted. This handles the original CameraMan `teleport` call against `Teleport.wav` without editing role/RPC bodies. The bounded loader checks the canonical existing custom file before extracting a resource. No existing custom WAV is overwritten.

Apply any current control-sizing overlay after the audio project. Capture and build the final project with `build_source_application.py`; do not publish a raw inherited project. Its emitter produces exact dotted names for all 224 resources and pins GitInfo to the reviewed source repository. Run `tests/ArtifactAudit` against the emitted managed assembly and captured manifest before handing off a NativeAOT library. Base-game DLLs, generated upstream derivatives and build products stay outside source Git.

The decoder accepts bounded authored PCM16/PCM24 mono/stereo WAVs. It selects the left channel, preserving upstream PCM16 behavior. Each native array upload has at most 65,536 samples; `Boom.wav` requires two uploads and `Line.wav` uses PCM24. A clip enters the cache only after every upload succeeds. Temporary array, manager and source wrappers are disposed. Cleanup stops and destroys only this adapter's cached clips, with no global audio/listener changes.

Actual game-hosted evidence on the Mac iOS runtime:

- Build 39 passed both data and muted playback proofs after real source startup. The muted test used an existing SoundManager, its own eight zero samples and volume 0; no account actions occurred. Evidence: `RuntimeFullSourceAudio39/Attachments/EHRSourceAudioProof.json`.
- Build 40 passed the production loader's exact 16-word proof: `{1,0,6,18,19,18,1,1,18,18,1,0,0,18,0,0}`. It extracted/read 18 own resources, uploaded 19 chunks, compared every sample through actual AudioClip.GetData and retired its cache. It made no playback call. Real startup still reported 5,049 options and 292 active bindings. Evidence: `RuntimeFullSourceAudioLoader40/Attachments/EHRSourceAudioLoaderProof.json`.
- The joined44 delivery image repeats both audio probes, the complete production loader and failure cleanup successfully alongside the new touch/identity proofs. Its original candidate binaries remain unchanged. Evidence: `RuntimeFullFeatures44/Attachments` in the private build directory.

These are bounded runtime checks, not physical-iPhone playback or full gameplay verification. The optional main-thread `ehr_source_ios_audio_loader_probe_v1` refuses if the production cache is already in use. `ehr_source_audio_close_v1` retires only owned clips; native failure cleanup calls it after source dispatch has been deactivated.

Own filesystem/name fixtures use no Unity/game/account/network APIs. Generate either with:

```sh
python3 tools/prepare_audio_file_fixture.py --kind files --output <fresh-files-fixture>
python3 tools/prepare_audio_file_fixture.py --kind names --output <fresh-names-fixture>
dotnet publish <fixture>/EHRAudioOwnFixture.csproj -c Release -r osx-arm64 -o <fresh-publish>
<fresh-publish>/EHRAudioOwnFixture
python3 -m unittest discover -s tests -p 'test_*audio*.py'
```

The executed file fixture passed 22 checks; the name fixture passed 14, including real case-sensitive filename matching on the host filesystem, custom-file precedence, ambiguity rejection and symlink rejection. The original PCM decoder fixture separately passed 61 checks, including full-frame parity against the 17 original PCM16 resources, the PCM24 resource and malformed input bounds. No audible test is required by these fixtures.
