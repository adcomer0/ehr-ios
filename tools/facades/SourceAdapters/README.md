These three source adaptations remove the IL2CPP pointer/expression-compiled
constructor path, check gateway roots for passive-button guards, and route the
source exception catch to the actual owning native exception class. They retain
the pinned upstream callback signatures and any audited static-dispatch wrapper
overlay. They do not modify upstream source or implement the production host.

Run the generator with `--project`, `--upstream-root`, `--input-pins`, and
`--output`. The input pin JSON maps the three original upstream relative source
paths to the SHA256 of each selected Compile source, including static-dispatch
overlays when present. Review overlays before recording their hashes. Changed
commits, pins, missing source items, or passive-button patterns fail closed.
Run AttributeNames after these adapters so Harmony nameof strings remain pinned.

`python3 -m unittest test_source_adapters.py` validates input preservation,
adapters, changed input/commit rejection and changed pointer-pattern rejection.
