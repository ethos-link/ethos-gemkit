# Ethos Gemkit

Shared development defaults for Ethos Link gems: Ruby 4, Standard, optional Rails
8 linting, hooks, package checks and one shared release workflow. The toolkit
belongs in the development/test Gemfile, never a consumer's runtime gemspec.

Install the published gem in the development/test Gemfile:

```ruby
gem "ethos-gemkit", "0.2.0", group: [:development, :test], require: false
```

Pin workflow callers to the full commit behind the installed Gemkit release tag.
Resolve that commit with:

```sh
git ls-remote https://github.com/ethos-link/ethos-gemkit.git 'refs/tags/v0.2.0^{}'
```

Upgrade the gem version and workflow pins together. Consumer READMEs should cover
their own APIs and checks, then link here for shared setup and release details.

A standard gem needs this Rakefile:

```ruby
require "bundler/setup"
require "ethos/gemkit/rake"
```

Use the native configuration files rather than a setup generator:

```yaml
# .standard.yml
ruby_version: "4.0"
plugins:
  - ethos-gemkit
```

Keep Standard exclusions locally. The plugin detects Rails 8 components from the
bundle without booting an application; plain Ruby and Active Support-only bundles
use Ruby rules. SDK Rake tasks reject configurations that omit the shared plugin.
Existing hooks call `bundle exec ethos-gemkit guard` before commits and
`bundle exec ethos-gemkit commitlint --message {1}` for commit messages. Install
hooks with `bundle exec lefthook install`. Direct main/master commits are blocked.

No `.ethos-gemkit.yml` is needed for standard public gems. Private gems declare
`registry: github_packages`; custom checks use `checks: [ci:local]`. Optional
`gem_name`, `repository` and `version_file` override the one-gemspec, Ethos Link
repository and one-version-file conventions. Unknown keys and unsafe paths fail.
The lower-level `ethos/gemkit/tasks` entrypoint retains existing custom test and
release tasks while a repository is adopting the toolkit.

`bundle exec rake verify` runs lint, registered checks, a disposable native gem
build, and git-cliff validation.

## Private gem access

To install private gems locally, use a GitHub personal access token (classic)
with `read:packages` and access to the package. Configure Bundler once, replacing
`USERNAME` and `TOKEN` with your credentials:

```sh
bundle config set --global https://rubygems.pkg.github.com/ethos-link USERNAME:TOKEN
```

Keep credentials out of Gemfiles. Each gem documents its scoped source block.
Actions publishing uses `GITHUB_TOKEN`; installing another private repository's
package requires that repository to grant the workflow access or an explicit
token. See [GitHub's registry guide](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-rubygems-registry).

## Releasing a gem

**Run `release:prepare` from clean, up-to-date `main`.** It creates the conventional
release branch and opens a PR. **Merging that release PR starts publication.**
This is the same process for Gemkit itself and its adopted consumer gems.
Ordinary feature/fix PRs run verification; only a release PR starts publication.

### One-time prerequisites

- Commit `Gemfile.lock`. Before its first commit, run
  `bundle lock --add-checksums`; frozen CI installs reject empty registry
  checksum entries, even when the gems are already installed locally.
- Ignore `/.bundle/`, `/vendor/bundle/` and `/pkg/` in `.gitignore`. The shared
  workflows use Ruby setup's native `vendor/bundle` cache; generated files must
  leave the release checkout clean.
- Install the bundle, Git, git-cliff and GitHub CLI. Configure your Git identity,
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

Projects keep their own checks. Engines can register `checks: [ci:local]` in
`.ethos-gemkit.yml` and have that task run `bin/ci`. Set the release caller's
optional `build-setup` input to provision those checks' dependencies, such as
PostgreSQL or browser packages. Setup runs only in the read-only build job;
publishing credentials remain in the separate publish job.

### RubyGems trusted-publisher settings

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

### Prepare and review

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
changelog, runs `bundle lock --local` and the full `rake verify`, then commits the
three metadata files with hooks enabled, pushes the branch, and opens a
`chore(release): prepare vX.Y.Z` PR. Main stays unchanged. You can also start on
that exact pre-created release branch if its HEAD still equals `origin/main`.
When starting from main, a leftover local release branch is recreated only if
all its commits are already in main; unmerged work is preserved and stops the task.

Review the generated notes, lockfile and version in the PR. Add or adjust upgrade
notes in a follow-up commit when needed, and wait for CI before merging. The task
prints the PR URL and makes clear that merging it publishes the release.

### Merge and publish

Merging a same-repository `chore/release-vX.Y.Z` PR into main runs the shared
workflow against its exact merge commit, including squash and rebase merges:

1. Verify the expected version, main ancestry, notes, committed package bytes and
   all registered checks; build one release artifact through Bundler.
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

### Failures and retries

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

For CI failures, retry **failed jobs in the original run** within GitHub's 30-day
retry window. Artifacts are retained for 90 days. A failed tag step can reuse an
existing annotated tag only when it points to the same verified commit. A failed
notes job reuses the original artifact without uploading again. Ambiguous uploads,
already published versions, existing GitHub releases or expired runs/artifacts
require registry/release reconciliation. Never replace a tag or rebuild a
published version to repair release notes.

Provider references: [reusable RubyGems trusted publishers](https://guides.rubygems.org/trusted-publishing/#using-reusable-workflows),
[GitHub token-trigger behavior](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow),
and [failed-job retries](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs).

GitLab is a separate optional [workflow](.github/workflows/sync-gitlab.yml).
Only add its caller when a target exists, passing an SSH `url`, a project write
deploy key and independently verified known hosts. Without a URL the job skips;
Cloudflare Tunnel has no caller. It copies current main using a fast-forward
push, without tags, force or deletions. Provision target visibility no broader
than the source. Local bare-repository fixtures cover repeat/stale events and
divergence; live SSH credentials and host keys still require target validation.

Develop with `bundle install` and `bundle exec rake verify`. Release and registry
fixtures live in tests, using real Git and native gem builds with fake network
publishers. No production rehearsal command or registry client is required.

## Built by Ethos Link

[Ethos Link](https://www.ethos-link.com) builds business software and integrations
that replace manual handoffs with connected workflows. We help teams automate
routine work, use their data and improve the processes their business runs on.

- [Reviato](https://www.reviato.com): Read public review trends and collect
  private customer feedback, so your team can decide what to improve.
- [EthosPlaces](https://www.ethos.place): Give customers the details they need to
  choose and visit your business, from opening hours to directions.
- [Nuntio](https://www.nuntiohq.com): Draft, review and schedule social posts in
  one workspace, then track each publishing result.
