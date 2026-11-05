# Upgrading Gemkit

## Next release

Install mise (CI uses 2026.10.19) and run `bundle exec rake tools:install` after
upgrading the gem and matching workflow pins. Gemkit now uses native git-cliff
and GitHub CLI binaries pinned in its shipped `mise.toml` and `mise.lock`.
Node.js/npm is not required. Existing global CLI installations are no longer
used by verification or release preparation. git-cliff stays at 2.12.0 for this
installation change; GitHub CLI is pinned to 2.103.2.

## Maintaining tool versions

Dependabot checks Ruby dependencies and GitHub Actions weekly. Review the mise
CLI, tool pins and system dependencies monthly, or sooner for security fixes;
Dependabot does not update mise tool versions. Do not auto-merge tool upgrades.

To update a tool, edit its exact version in `mise.toml`, then regenerate the
lockfile for every supported platform and install it:

```sh
mise lock --platform linux-x64,linux-arm64,macos-x64,macos-arm64
bundle exec rake tools:install
bundle exec rake verify
```

Commit `mise.toml` and `mise.lock` together. For Ruby updates, also update
`.ruby-version` and every `ruby/setup-ruby` pin; preserve native Bundler caching
in CI. For GitHub CLI updates, also update the release-notes job's isolated mise
configuration. Tests reject version drift in these duplicated pins. For mise
updates, keep the action's `version` input aligned across jobs and verify with
that version locally. Review Bundler's explicit version separately and keep
local installation aligned with the workflow pins.

Verification exercises changelog parsing, release preparation against disposable
Git repositories, and registry fixtures. Review changed changelog output before
accepting an upgrade, and wait for commitlint before merging. Tests and lint remain local. Never
use a real consumer release, tag or registry publication as a test. Update
consumer gem and workflow pins together after the toolkit release.

Git and shell utilities follow the host or CI runner image. Review image
upgrades separately; exact OS parity would require a shared container. Keep
Bundler-owned tools in Bundler rather than adding them to mise.

## 0.3.1

Run `bundle exec rake verify` locally before pushing. `release:prepare` still
runs the complete local verification gate. `release:build` validates release
source and packages it without repeating tests or lint in GitHub Actions.

Delete verification workflow callers (`ruby.yml` or `verify.yml`) and retain
commitlint and release callers. Pin the installed Gemkit and remaining callers
to the same release. Pass that immutable commit as `toolkit-ref` to the commitlint
caller; commitlint runs the pinned Ruby CLI without a bundle install. Remove the release caller's `build-setup` input; databases,
browsers and other test dependencies are now provisioned only locally.

## 0.2.1

Release preparation now fetches registry checksums with Bundler instead of
using local-only resolution. Network access to configured gem sources is
required. Existing compatible dependency versions stay locked; complete
checksums prevent frozen CI installs from rejecting local cache metadata.

## 0.2.0

Update the gem version and pin each workflow caller to the commit behind the
matching release tag. Release callers must grant `contents: write`,
`id-token: write` and `packages: write`, including public-gem callers: the shared
publisher supports both registries.

GitHub Packages publication now defaults to the workflow's `GITHUB_TOKEN`.
Grant the repository Actions access to its package. Existing `PACKAGES_TOKEN`
overrides remain supported; no new personal access token is required.

Release preparation prints each phase and streams verification, hook and push
output. Versioning, review and publication remain the same: prepare from clean,
current main, review the release PR, then merge to publish through Actions.

Projects with system-dependent checks can pass `build-setup` to the release
workflow. Keep those checks in the project's existing command; setup only
provisions dependencies before the read-only build job runs verification.
