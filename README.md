# Ethos Gemkit

Shared development tooling for Ethos Link Ruby gems. Requires Ruby 4.0+.
The toolkit does not require Rails and belongs in a gem's development/test
Gemfile, never its runtime gemspec.

```ruby
group :development, :test do
  gem "ethos-gemkit", "~> 0.1", require: false
end
```

The first full consumer is `cloudflare-tunnel`. During bootstrap, consumers
pin this public repository to an immutable Git commit; the gem is not yet
published. Keep the Gemfile revision and workflow/action references together.
`ETHOS_GEMKIT_PATH` is an explicit local development override. The other eight
consumer branches still use adjacent checkouts and are not ready to merge.

Run `bundle install`, then `bundle exec ethos-gemkit setup` to preview the thin
Rake/configuration changes. Use `setup --write` to apply them. Existing Rake
tasks, Standard exclusions and comments are preserved. `--checks test,herb:parse`
selects the existing local checks; engines can register a task that runs their
complete `bin/ci`. A repeated setup makes no changes. Gemfile dependency edits
and repository hook commands remain explicit. Use `bundle exec ethos-gemkit guard`
in pre-commit hooks to enforce feature branches. Consumers with existing narrow
release metadata guards retain those guards until release extraction.

Available commands:

```sh
bundle exec rake lint
bundle exec rake lint:fix
bundle exec rake package:verify
bundle exec rake verify
bundle exec lefthook install
bundle exec ethos-gemkit doctor
```

`standard`, `standard:fix` and editor integrations use the same `.standard.yml`
plugin. Plain Ruby and Active Support-only bundles use Standard's Ruby rules.
Bundles containing Rails 8 framework components also receive upstream
Standard Rails rules. Rails is detected from Bundler's specifications without
booting an application. Incompatible framework minor versions fail clearly.
Optional Rails libraries may document narrow exclusions for rules that assume
application APIs, such as inheriting a host ApplicationController.

`verify` runs lint, the repository's configured Rake checks, then a disposable
package build. Configuration is loaded from `.ethos-gemkit.yml`, rejects unknown
keys and unsafe YAML, and constrains metadata paths to the repository. Package
validation checks the Ruby minimum, runtime toolkit leakage, unsafe paths and
agreement between the registry host and gemspec `allowed_push_host`.

Commit hooks and commit-message CI use `ethos-gemkit commitlint --message FILE`.
The shared types are `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `perf`,
`ci` and `build`, with a 72-character header limit. The adapter uses upstream
commitlint's validator without modifying its fixed type constants or rewriting
commit text. Engineering context in the body still requires human review.

Both public and private gems use these same tasks. The supported registry
profiles are RubyGems and `https://rubygems.pkg.github.com/ethos-link`.
Credentials never belong in configuration. The public release pilot uses native
RubyGems trusted publishing. GitHub Packages development configuration is
supported; its publication adapter remains gated pending a private registry
rehearsal.

Consumers opt into shared release tasks with:

```ruby
require "ethos/gemkit/tasks"
require "ethos/gemkit/release_tasks"
```

Install hooks before preparing a release. From clean, current `main`, run
`bundle exec rake 'release:prepare[patch]'` (also minor, major or a newer X.Y.Z).
Preparation verifies, changes only configured metadata, preserves dependency
sources/pins and changelog history, then commits with hooks enabled. Staged mode
pushes the metadata commit; review it and run `bundle exec rake release:tag`.
Atomic mode pushes metadata and its annotated tag together. Local `rake release`
and native publication tasks are blocked. These tasks create real remote changes;
use `bundle exec rake release:rehearse` for a disposable trial first.

An interrupted operation retains a journal under `.git`. Use `release:resume`
for an interrupted metadata commit/push and `release:tag` for a failed tag push.
Metadata tampering or a partial metadata write requires manual inspection and
restoration; the toolkit never overwrites a tag. Direct metadata pushes are the
current pilot policy. A protected-main rejection retains the journal and requires
owner reconciliation; automated metadata PR delivery is not implemented yet.
Initial-version bootstrap and migrating old release tags are also outside this
pilot. `cloudflare-tunnel` already has a published `v0.1.0`.

The tag workflow checks out the exact commit with full history, verifies the
canonical annotated tag, ancestry, metadata and all configured checks, and builds
one gem with `release.json`, SHA-256 and release notes. Publication runs in a
separate job without evaluating the consumer Gemfile or hooks. The composite
publisher preserves the consumer workflow's RubyGems OIDC identity. It validates
the source run and exact artifact before obtaining credentials. An existing
registry version is accepted only when its digest matches; otherwise recovery
stops. GitHub notes run separately without publishing credentials.

Recovery downloads the original run's artifact, never a replacement build. Run
recovery from `main`, select the original tag/run and choose notes-only if the
package is published. Expired artifacts require manual reconciliation. Older
consumer tags without this verified build record cannot use this recovery path.
A publication followed by failed notes does not require another upload.

GitLab sync activates solely through a nonblank `gitlab_url` in consumer YAML,
for example `git@gitlab.com:group/project.git`. Missing, null or blank means
**disabled**, with no sync credential access or GitLab Git operations. There is no
separate enable flag. Provision the target with visibility no broader than the
source, a dedicated write deploy key and independently verified host keys. Pass
`GITLAB_DEPLOY_KEY` and `GITLAB_KNOWN_HOSTS` explicitly to `sync-gitlab.yml`.
The secretless configuration job gates the credentialed job. Only current
canonical main is pushed, with no force, tags, pruning or deletions. Divergence
fails for reconciliation. GitLab CI and package publishing are outside scope.
Local bare-repository tests prove first sync, repeat/stale events and divergence;
real GitLab SSH credentials/host-key failures need provisioned-target validation.

To develop the toolkit:

```sh
bundle install
bundle exec rake verify
bundle exec rake build
ruby script/verify_consumers.rb ../indexmap ../crawlscope ../ethosmark
```

The consumer smoke script builds and unpacks each artifact outside its source
checkout, resolves only runtime dependencies, and exercises a core operation
without Rails/Railties or consumer development dependencies. It intentionally
excludes engines, whose own packaged-host checks remain required.
