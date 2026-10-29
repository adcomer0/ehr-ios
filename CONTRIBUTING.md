# Contributing

This is an experimental compatibility port. Start with docs/ARCHITECTURE.md, docs/KNOWN_ISSUES.md and docs/BUILDING.md. Open an issue or a small pull request describing the exact game/framework version, behavior before/after and relevant validation. Separate synthetic fixture results from actual game and phone observations.

For the frozen managed build, source-app/manifest.json is the selection authority. Its indexed compiled/ files are the selected build-52 inputs; managed/ and tools/ contain reusable support and generators. If you modify a selected source, update its hash deliberately and explain the change. Generated absolute-path manifests and compiler outputs belong outside Git.

Preserve exact native ABI/image/UUID checks, original-once dispatch, ref/out atomic copyback, rooted ownership, game permissions and consent. Do not force online eligibility, spoof authentication success, replace identity-provider tokens or remove progression/account checks. Account linking, merging, unlinking, deletion and progress changes are outside automated tests. Do not use valuable accounts for experiments.

Never commit game binaries/assets, raw metadata dumps, private device/account logs, room/player/account identifiers, profiles, certificates, keys or credentials. Keep EHR resource assets in your own pinned upstream checkout. Supply small synthetic fixtures or carefully minimized numeric evidence when reporting a failure.

No installable release or stability promise is implied by a merged contribution. Run checks relevant to the change, document any local fixture requirements, and retain upstream GPL headers and notices. Collaborators can be added by the repository owner using their exact GitHub usernames.
