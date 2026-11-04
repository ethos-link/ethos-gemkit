# Upgrading Gemkit

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
