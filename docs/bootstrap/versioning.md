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
- `scripts/ci/run-release-publish.sh` is the repo hook for artifact publication; the generated default is a no-op until the repo needs more than GitHub releases.
- The shared reusable release workflow creates or updates the GitHub release and then advances the floating compatibility tags when enabled in `project.bootstrap.yaml`.
