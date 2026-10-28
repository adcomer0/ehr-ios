> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Zero-argument UnityAction family

This extension constructs real `UnityEngine.Events.UnityAction` objects and
routes them through the existing bounded native/NativeAOT Action registry.
The original 48-byte Action host and 24-byte source callback tables remain
unchanged. A separate optional 16-byte family table supplies the UnityAction
factory. The same process-lived zero-argument callback metadata record serves
both families; each delegate uses the real reflection Invoke MethodInfo for
its own native class.

Read-only metadata and disassembly verified the exact actual UnityAction
Object/IntPtr constructor and Invoke signatures and the native self/hidden
metadata call protocol. Before allowing this family, the adapter validates
both native method associations against the existing full framework hash/UUID
gate and the independently classified candidate entries. No instruction bytes
or game implementation are copied into these sources.

The existing generated UnityAction/UnityEvent partial wrappers are extended
with source callback construction, explicit Close, real Invoke and real
RemoveListener. Proxy disposal remains inherited and releases only that
proxy's native root. A native event retaining the delegate keeps invoking its
source until explicit Close or native weak-target collection.

The runtime proof separately constructs an actual ButtonClickedEvent and two
actual UnityActions, adds both listeners, and invokes the event. It then
disposes the first proxy while retained native references still invoke both
callbacks. Removing that exact native delegate through a different owning
facade must remove only the first listener. Explicit Close must make the
remaining retained listener no-op. The proof clears listeners, releases every
owned root, and requires an empty managed source dictionary. It mutates no
scene button or GameObject.

All modified native files compile for iOS ARM64 with warnings treated as errors.
The full current SourceReuse managed project, including both staged family
files and generated facades, builds with zero warnings/errors. The real family
construction/event invocation remains gated on the next signed candidate's
actual XCTest. Compile checks do not prove AddListener/RemoveListener behavior.

Private read-only evidence:

```text
/path/to/local-reports/unityaction-metadata.local.json
/path/to/local-reports/unityaction-disassembly.local.txt
```

Apply the family patch only after the corrected core Action bridge. Rebuild
the NativeAOT library. Add `EHRManagedUnityActionProbe.mm` to the native builder,
call `EHRManagedUnityActionSelfTest` after the core Action self-test, and require
its success in the managed proof. The separate asynchronous weak-collection
overlay also covers the family registrations after these constructing frames
return. Typed Action/Func/UnityAction families and automatic source lambda
conversion/event identity caching are separate work.
