# Ethos Gemkit

Shared development defaults for Ethos Link gems: Ruby 4, Standard, optional Rails
8 linting, hooks, package checks and one shared release workflow. The toolkit
belongs in the development/test Gemfile, never a consumer's runtime gemspec.

## Documentation

This README and the linked repository guides describe the checked-out code.
The [Ethos Link project page](https://www.ethos-link.com/opensource/ethos-gemkit)
provides the canonical public project guide, overview and resources.

- [Release preparation, registries and recovery](docs/releasing.md)

## Requirements

Ruby 4.0 or newer, Bundler, Git and mise. Install the pinned native tools with
`bundle exec rake tools:install` after installing the bundle. Rails is optional;
Rails-specific linting activates when Rails 8 components are in the bundle.

## Setup

Install the published gem in the development/test Gemfile:

```ruby
gem "ethos-gemkit", "0.3.1", group: [:development, :test], require: false
```

Pin workflow callers to the full commit behind the installed Gemkit release tag.
Resolve that commit with:

```sh
git ls-remote https://github.com/ethos-link/ethos-gemkit.git 'refs/tags/v0.3.1^{}'
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

The gem ships `mise.toml` and `mise.lock` to pin development tools for local use
and CI. No Node.js or npm installation is needed for Gemkit.

| Tools | Installation and version ownership |
| --- | --- |
| git-cliff 2.12.0, GitHub CLI 2.103.2 | Native binaries installed by mise from the shipped lockfile |
| Ruby 4.0.9 | Local mise pin; matching `ruby/setup-ruby` pin in CI |
| Bundler 4.0.11 | Explicit CI pin; install the same version locally |
| Standard, Standard Rails, Rake, Lefthook | Bundler and the consumer's `Gemfile.lock` |
| Git, SSH, sha256sum, shell utilities | System prerequisites; hosted CI uses the Ubuntu runner image |
| Consumer-specific binaries | Consumer local setup |

Install mise (CI uses 2026.10.19), Ruby and Bundler, then run:

```sh
bundle install
bundle exec rake tools:install
bundle exec rake verify
```

The install task trusts the gem's mise configuration and installs its pinned
native git-cliff and GitHub CLI binaries. Verification and release preparation
resolve those binaries through mise using the installed gem's configuration,
even when called from a consumer directory. They do not fall back to global
installations or download tools on demand. Re-run installation after upgrading
Gemkit. Consumer repositories need no npm manifest or copied tool pins.

For work on Gemkit itself, install the Ruby and CLI pins with
`mise install --locked ruby git-cliff gh`; activate mise in your shell or run
`mise exec ruby git-cliff gh -- bundle exec rake verify`. The lockfile covers
Linux and macOS on x64 and arm64. Ruby version parity with CI is checked by
the tests.
Git and OS utilities still come from the host; identical tool versions do not
provide an identical operating system.

The release build workflow loads the installed gem's configuration through a
SHA-pinned mise action. The isolated release-notes job has its own
exact GitHub CLI pin, checked against `mise.toml` by the tests, so it can publish
notes without loading consumer code.

Run verification locally before pushing and when preparing a release. GitHub
Actions checks commit messages on ordinary PRs and main pushes; it does not run
tests, lint, browser checks or integration suites. Release workflows validate
release source and package integrity, then tag and publish without repeating
the locally completed checks. Commitlint checks out Gemkit at the caller's
`toolkit-ref` and runs its Ruby CLI without installing the consumer bundle. Set
that input to the same immutable commit as the workflow pin.

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

Run `bundle exec rake release:prepare` only from clean, current `main` when
preparing an actual release. It updates the version, changelog and lockfile,
runs verification, pushes a release branch and opens a PR. Merging that release
PR starts publication; `rake verify` alone does not publish.

See the [release guide](docs/releasing.md) for registry permissions, trusted
publishers, version selection, merge behaviour and recovery. The guide is
versioned with the release tooling it describes.

GitLab is a separate optional [workflow](.github/workflows/sync-gitlab.yml).
Only add its caller when a target exists, passing an SSH `url`, a project write
deploy key and independently verified known hosts. Without a URL the job skips;
Cloudflare Tunnel has no caller. It copies current main using a fast-forward
push, without tags, force or deletions. Provision target visibility no broader
than the source. Local bare-repository fixtures cover repeat/stale events and
divergence; live SSH credentials and host keys still require target validation.

## Development and releases

Develop with `bundle install` and `bundle exec rake verify`. Release and registry
fixtures live in tests, using real Git and native gem builds with fake network
publishers. No production rehearsal command or registry client is required.

## License

MIT. See [LICENSE.txt](LICENSE.txt).

## About Ethos Link

[Ethos Link](https://www.ethos-link.com) is a software company founded by
[Paulo Fidalgo](https://www.fidalgo.pt). This gem is part of the open-source
tooling we publish alongside our business products:

- [Reviato](https://www.reviato.com): collect private customer feedback and analyse public reviews.
- [Nuntio](https://www.nuntiohq.com): prepare, review and schedule social posts.
- [EthosPlaces](https://www.ethos.place): find places, opening hours and contact details.

Explore our [open-source projects](https://www.ethos-link.com/opensource).
