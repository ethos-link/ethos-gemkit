# Ethos Gemkit

Shared development defaults for Ethos Link gems: Ruby 4, Standard, optional Rails
8 linting, hooks, package checks and one tag-driven release workflow. The toolkit
belongs in the development/test Gemfile, never a consumer's runtime gemspec.

During bootstrap, pin the Git dependency and workflow callers to the same reviewed
commit; the toolkit has not been published. See the working
[Cloudflare Tunnel Gemfile](https://github.com/ethos-link/cloudflare-tunnel/blob/feat/ethos-gemkit/Gemfile).

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
build, and git-cliff validation. `release:prepare[patch]` (also minor, major or a
newer X.Y.Z) changes the version and changelog on a clean feature branch. Run
`bundle lock --local`, review the diff, verify and commit normally. It never
commits, pushes, tags, disables hooks or maintains a journal. Failures leave an
ordinary working diff for inspection and restoration.

After merging the release PR, create an annotated `vVERSION` tag on the reviewed
main commit and push that tag explicitly with `--no-follow-tags`. The shared
[release workflow](.github/workflows/release.yml) verifies canonical tag identity,
main ancestry, version, notes and package bytes, then builds through Bundler.
GitHub transfers the gem, notes and native SHA-256 checksums to separate publish
and notes jobs. Neither credentialed job checks out or evaluates consumer code.
Both registry profiles use the same native `gem push`; RubyGems uses OIDC and
GitHub Packages uses a scoped `PACKAGES_TOKEN` secret. No public-host fallback
exists. Live private publication remains unverified until a private pilot runs.

Retry **failed jobs** in the original workflow run (within GitHub's 30-day retry
window). A failed notes job reuses the
same artifact without publishing again. Artifacts are retained for 90 days.
An ambiguous upload, existing registry version, existing GitHub release or expired
artifact or a run older than the retry window requires normal registry/release
reconciliation. Do not rebuild an
already published version, replace tags or rerun every job to recover notes.

Before enabling the shared RubyGems publisher, configure its trusted publisher:
consumer owner/repository, workflow filename `release.yml`, workflow repository
owner `ethos-link`, workflow repository `ethos-gemkit`, environment `rubygems`.
This updates the consumer-local publisher registration used previously. See the
[official reusable publisher instructions](https://guides.rubygems.org/trusted-publishing/#using-reusable-workflows).

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
