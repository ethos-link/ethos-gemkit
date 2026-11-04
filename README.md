# Ethos Gemkit

Shared development tooling for Ethos Link Ruby gems. Requires Ruby 4.0+.
The toolkit does not require Rails and belongs in a gem's development/test
Gemfile, never its runtime gemspec.

```ruby
group :development, :test do
  gem "ethos-gemkit", "~> 0.1", require: false
end
```

During bootstrap, use `path: "../ethos-gemkit"` or set `ETHOS_GEMKIT_PATH` in
consumer repositories. Keep the toolkit checkout adjacent to those repositories.
There is no published version or hosted reusable-workflow revision yet. Consumer
branches using the local path are for local review; installable distribution and
immutable workflow references must be established before merging them.

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

Both public and private gems use these same tasks. The supported registry
profiles are RubyGems and `https://rubygems.pkg.github.com/ethos-link`.
Credentials never belong in configuration. This initial toolkit does not
publish packages, change versions, create tags or replace consumer release
tasks. Existing release safeguards remain authoritative until the journal,
registry adapters and reusable release workflows pass their sandbox gates.

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
