# Release Versioning

This bootstrap standardizes on Semantic Versioning with immutable exact tags and automatically promoted compatibility aliases.

## Tag Rules

- Exact release tags are immutable: `v1.2.3`
- Minor compatibility tags move forward automatically: `v1.2`
- Major compatibility tags move forward automatically: `v1`

Consumers should prefer `v1` for the default compatibility channel, `v1.2` when they need to stay on one minor line, and an exact tag or SHA when they need full reproducibility.

## Branch Rules

- `main` is the next minor or major release train.
- `release/X.Y` branches are maintenance lines for patch releases on older minors.
- Promote fixes forward: oldest supported `release/X.Y` first, then newer maintenance branches, then `main`.

## Automation

- `.github/workflows/release-tag.yml` runs when an exact SemVer tag matching `v*.*.*` is pushed.
- `scripts/ci/run-release-verification.sh` runs the repo release gate before publication.
- `scripts/ci/run-release-version.sh` validates that the repo version surfaces match the pushed tag before build and publish.
- `scripts/ci/run-release-build.sh` populates the release artifact directory and writes SHA256 checksums when enabled.
- `scripts/ci/run-release-publish.sh` is the repo hook for artifact publication; the generated default is a no-op until the repo needs more than GitHub releases.
- The shared reusable release workflow creates or updates the GitHub release and then advances the floating compatibility tags when enabled in `project.bootstrap.yaml`.

## Version Validation

- Version bumps land in a normal pull request before the release tag is pushed; the workflow never creates post-tag commits.
- Configure version surfaces under `release.versions` in `project.bootstrap.yaml` with a `type` of `npm`, `python`, or `container` and the file `path`.
- `scripts/ci/run-release-version.sh` fails the release when a configured `package.json` or `pyproject.toml` version does not equal the tag (with the `v` prefix stripped). Container surfaces are derived from the tag at publish time.
- With no configured surfaces the hook prints an explicit no-op rather than silently passing.

## Release Artifacts

- The default release artifact directory is `dist/release/`.
- `scripts/ci/run-release-build.sh` is where repo-specific build steps populate that directory; with no artifacts it prints an explicit no-op message instead of failing silently.
- Checksum generation is `sha256`; when set to `sha256` a `SHA256SUMS` file is written alongside the artifacts.
- The reusable workflow uploads every file in the artifact directory to the GitHub Release.
- SBOM/provenance is `optional` and is designed into the manifest for repos that opt in.

## Release Notes

- Release notes are generated automatically for every exact tag from changes since the previous exact SemVer tag.
- The default implementation uses GitHub generated notes; `.github/release.yml` maps bootstrap labels to categories.
- Override categories under `release.changelog.categories` in `project.bootstrap.yaml`. The default categories are Features, Fixes, Operations, and Documentation, with everything else under Other Changes.
- The reusable workflow writes the notes to `dist/release/RELEASE_NOTES.md` before creating the GitHub Release.
