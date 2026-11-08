# Releasing a gem

[README](../README.md) · [Project guide](https://www.ethos-link.com/opensource/ethos-gemkit)

**Run `release:prepare` from clean, up-to-date `main`.** It creates the conventional
release branch and opens a PR. **Merging that release PR starts publication.**
This is the same process for Gemkit itself and its adopted consumer gems.
Ordinary feature/fix PRs run commitlint; only a release PR starts publication.

## One-time prerequisites

- Commit `Gemfile.lock`. Before its first commit, run
  `bundle lock --add-checksums`; frozen CI installs reject empty registry
  checksum entries, even when the gems are already installed locally.
- Ignore `/.bundle/`, `/vendor/bundle/` and `/pkg/` in `.gitignore`. The shared
  workflows use Ruby setup's native `vendor/bundle` cache; generated files must
  leave the release checkout clean.
- Install the bundle, Git and mise. Run
  `bundle exec rake tools:install`. Configure your Git identity,
  authenticate with `gh auth login`, and install hooks with
  `bundle exec lefthook install`. You need permission to push branches and open PRs.
- Public gems: configure a matching RubyGems trusted publisher for **each gem**
  before merging its first release PR. Use the exact settings below. Gemkit's
  publisher does not authorize consumer gems.
- A new gem also needs a pending trusted publisher. Supply its numeric RubyGems
  owner through the caller's `rubygems-owner` input or the repository/organization
  variable `RUBYGEMS_OWNER` (the publisher account used by Tunnel is `27209`).
- Private gems: set `registry: github_packages`. Publishing uses the workflow's
  short-lived `GITHUB_TOKEN`; the package must grant its repository Actions access.
  Pass `PACKAGES_TOKEN` only when an explicit token override is needed. Local
  installation from other private repositories still needs `read:packages` access.
- Configure the `rubygems` GitHub environment to allow `main` and `v*` tags.
  Release callers grant `contents: write`, `id-token: write` and `packages: write`.
  Repository rules must permit the workflow's annotated release tags.

The SDK release workflow listens directly for merged release PRs and version-tag
pushes. Consumer callers must listen for both `pull_request: types: [closed]`
against `main` and `push: tags: ["v*"]`, and pin the commit matching the installed
Gemkit release.
See the [Tunnel caller](https://github.com/ethos-link/cloudflare-tunnel/blob/main/.github/workflows/release.yml).

Projects keep their own local checks. Engines can register `checks: [ci:local]`
in `.ethos-gemkit.yml` and have that task run `bin/ci`. Provision PostgreSQL or
browser dependencies locally before running verification. Release callers do
not install test dependencies or accept `build-setup`.

## RubyGems trusted-publisher settings

On RubyGems, open the **consumer gem's** page, then **Trusted publishers**. For
Cloudflare Tunnel, create or update the publisher with these exact values:

| RubyGems field | Value |
|---|---|
| Repository owner | `ethos-link` |
| Repository name | `cloudflare-tunnel` |
| Workflow filename | `release.yml` |
| Environment | `rubygems` |
| Workflow Repository Owner | `ethos-link` |
| Workflow Repository Name | `ethos-gemkit` |

The repository identifies the consumer; the Workflow Repository fields identify
the repository containing the shared workflow file. Those last two fields are
required for consumers,
even though RubyGems labels them optional. For another consumer, substitute its
repository name. For Gemkit itself, use repository name `ethos-gemkit` and leave
both Workflow Repository fields blank because the workflow is in the same repo.

The numeric `rubygems-owner` input identifies the account for pending publishers;
it does not register a publisher or grant access to a consumer gem. See the
[upstream reusable-workflow instructions](https://guides.rubygems.org/trusted-publishing/#using-reusable-workflows).

## Prepare and review

For a normal patch release:

```sh
git switch main
git pull --ff-only
bundle install
bundle exec rake release:prepare
```

The default is `patch`. Select another target explicitly:

```sh
bundle exec rake 'release:prepare[minor]'
bundle exec rake 'release:prepare[major]'
bundle exec rake 'release:prepare[1.2.0]'
```

For an initial, unpublished version that is already in the gemspec and has no
tag, an explicit current version is supported. For example, a new gem starting
at 0.1.0 can use `bundle exec rake 'release:prepare[0.1.0]'` after pending-publisher
setup.

The task prints each step and streams command output as it runs. It checks the
working tree, canonical origin, current main, installed hooks and target tag.
It creates `chore/release-vX.Y.Z`, updates the version and
changelog, runs `bundle lock --add-checksums` and the full `rake verify`, then
commits the three metadata files with hooks enabled, pushes the branch, and opens a
`chore(release): prepare vX.Y.Z` PR. Main stays unchanged. You can also start on
that exact pre-created release branch if its HEAD still equals `origin/main`.
When starting from main, a leftover local release branch is recreated only if
all its commits are already in main; unmerged work is preserved and stops the task.

Review the generated notes, lockfile and version in the PR. Add or adjust upgrade
notes in a follow-up commit when needed, rerun affected checks locally, and wait
for commitlint before merging. The task
prints the PR URL and makes clear that merging it publishes the release.

## Merge and publish

Merging a same-repository `chore/release-vX.Y.Z` PR into main runs the shared
workflow against its exact merge commit, including squash and rebase merges:

1. Verify the expected version, main ancestry, notes and committed package bytes;
   build one release artifact through Bundler. Tests and lint already ran locally
   during `release:prepare` and are not repeated in Actions.
2. Create and push the annotated `vX.Y.Z` tag without overwriting existing tags
   or following unrelated local tags.
3. In an isolated job, verify the artifact's SHA-256 checksums, obtain the proper
   registry credentials, and publish that exact gem.
4. In a separate job, create the GitHub release with the same gem and notes.

There is no manual tagging step in the normal flow. Build, tag and publication
continue in the same run because a tag pushed by GitHub's `GITHUB_TOKEN` does not
start another workflow. Existing manually pushed annotated version tags remain a
supported trigger and receive full canonical-tag verification.

Publish and notes jobs never check out or evaluate consumer code. Public gems
use short-lived OIDC credentials; private gems use the workflow token or an
explicit override. Both profiles push the same verified artifact to their
configured host; no registry fallback exists.

## Failures and retries

If preparation fails, inspect `git status` and `git diff`. A failed verification
leaves changes on the local release branch without a release commit or push.
Fix and finish that ordinary branch, or restore the changes before starting over.
If the commit/push succeeded but opening the PR failed, use
`gh pr create --base main --head chore/release-vX.Y.Z --fill` after fixing access.
There is no journal or automatic reset of your working tree.

If credential setup fails with `No trusted publisher configured for this workflow`,
check the consumer's RubyGems settings against the table above. A successful
build and tag do not mean the gem was published. When `gem push` was skipped,
correct the publisher settings, then rerun **failed jobs only** in the original
workflow run. This reuses its verified artifact and existing tag; do not run
`release:prepare` again, bump the version or replace the tag for this failure.

```sh
gh run rerun RUN_ID --repo OWNER/REPOSITORY --failed
```

If a failed build needs a source fix and no tag or upload exists, keep the
prepared version and notes. Update its `chore/release-vX.Y.Z` branch from main,
commit the fix, run verification and open a replacement release PR. Merge that
PR to run the corrected source. The original run stays pinned to its original
commit; rerunning it cannot pick up a source fix. Do not replace an existing tag
or reuse a version that was already published.

For transient CI failures, retry **failed jobs in the original run** within GitHub's 30-day
retry window. Artifacts are retained for 90 days. A failed tag step can reuse an
existing annotated tag only when it points to the same verified commit. A failed
notes job reuses the original artifact without uploading again. Ambiguous uploads,
already published versions, existing GitHub releases or expired runs/artifacts
require registry/release reconciliation. Never replace a tag or rebuild a
published version to repair release notes.

Provider references: [reusable RubyGems trusted publishers](https://guides.rubygems.org/trusted-publishing/#using-reusable-workflows),
[GitHub token-trigger behavior](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow),
and [failed-job retries](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs).
