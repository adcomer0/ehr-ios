This is a source generator and live API facade experiment for pinned EHR v8.0.3
(commit `ce23f0d050f617a59507e5bb0fbfff751d4b5134`). Generated API references,
successful compilation and metadata lookup do not establish feature parity.
No game DLL, iOS image, original IL2CPP code, metadata dump or credentials belongs
in this tools directory. Keep those read-only inputs and generated diagnostics
outside the source checkout. All paths below are explicit arguments.

The generator requires Python 3.9+ without dependencies. Its synthetic regression
fixtures are in `test_generate_facades.py`. Run `python3 -m unittest -v
test_generate_facades.py` from this directory. `MetadataAudit` is a .NET10
metadata-only reader using PEReader; it never loads the inspected assembly.
`AttributeNames` uses the .NET SDK's own Roslyn libraries and rewrites `nameof`
only within HarmonyPatch attributes to the compiler-equivalent string. Keep the
original-reference 298-selector inventory authoritative for native targets.

The generator consumes reports, not binaries:

- `references`: MetadataAudit output for the exact original IL2CPP-profile EHR
  compilation. Fields used: members (assembly, declaringType, metadataToken,
  kind, name, returnOrFieldType, parameterTypes, static/generic/byref/pointer
  flags), typeReferences, inputSha256.
- `nativeDefinitions`: merged MetadataAudit `--definitions` reports for native
  dummy modules. Every definition retains its actual image, base type, fields
  (name/type/static/readonly/constants) and exact methods/parameter modes.
- `sourceProfile`: merged `--definitions` reports of the exact source reference
  proxy modules. This distinguishes genuine C# value structs from reference
  proxies of native structs, and records source parameter names/defaults. Emission
  preserves matching source parameter names and optional defaults. Constructor
  facades resolve and validate exact public ConstructorInfo signatures in the
  actual runtime; absent/nonpublic constructors remain explicit failures.
- `selectors`: the semantically validated Harmony selector report with exact
  image/declaringType/name/parameterTypes/returnType/staticness and explicit
  resolutionStatus. Unresolved coroutine factories stay unresolved.

Verify upstream/module provenance before writing pins. `write_input_pins.py`
records hashes; it is not an authenticity checker. Do not regenerate pins merely
because existing pins fail. `generate_facades.py --pins` checks every supplied
report's file digest before producing output. The schema is
`generator-inputs.schema.json`.

```sh
python3 write_input_pins.py --references "$reference_report" \
  --native-definitions "$native_report" --source-profile "$proxy_report" \
  --selectors "$selector_report" --output "$artifact_dir/pins.json"
python3 generate_facades.py --pins "$artifact_dir/pins.json" \
  --references "$reference_report" --native-definitions "$native_report" \
  --source-profile "$proxy_report" --selectors "$selector_report" \
  --output "$artifact_dir/live"
```

Use `--source-surface` for the original namespace/inheritance compile surface.
This output still has explicit unsupported shapes; it is not a complete game
assembly replacement. Production does not include compiler-only host scaffolds
such as UnsupportedCompileHost. Generated source has no field offsets or method
addresses. Runtime matching uses exact class tokens and runtime-reported type
names, checked iOS API bindings and caught invocation; method hooks require the
separate version-pinned native adapter.

The supported single-type-argument Unity component and Instantiate methods use
real public MethodInfo discovery, exact declared owner/static/arity and type
pattern checks, MakeGenericMethod, then closed parameter/return metadata checks
before invocation. They never emit a replacement generic implementation. Missing
native AOT bodies and unsupported custom component types remain runtime errors.
Their closed signatures are validated separately from the static binding audit.

Source-proxy ExtensionAttribute and ParamArrayAttribute metadata is preserved.
Extension forwarders call the same real native methods; variadic object values
are boxed into a real rooted System.Object[] through compiled codecs. Unsupported
host object types throw instead of being stored as fabricated native objects.

ColorUtility.TryParseHtmlString is an explicit source helper adaptation because
the pinned game metadata omits that managed helper. The separate 16-byte engine
table calls the exact Unity2022.3 DoTryParseHtmlColor icall after image/layout
validation; the generated helper normalizes bytes through the actual Color
four-Single constructor. It is excluded from the MethodInfo binding audit.
