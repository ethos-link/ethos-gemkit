# Ethos Gemkit

Share linting, package checks and release tooling across Ruby gems.

For Ruby gem maintainers sharing local verification and reviewed release workflows. Install Gemkit in development and test groups. It must not enter a consumer gem’s runtime dependency graph. Publishing requires separate registry and repository permissions.

[Project and full documentation](https://www.ethos-link.com/opensource/ethos-gemkit) · [RubyGems](https://rubygems.org/gems/ethos-gemkit) · [Changelog](CHANGELOG.md)

## Requirements

Ruby 4.0 or newer, Bundler, Git, mise and the pinned native tools shipped with Gemkit. Rails 8 lint rules activate when matching Rails components are present in the consumer bundle; Rails is not a runtime dependency.

## Installation

```sh
gem install ethos-gemkit
```

## Quick start

```ruby
# Gemfile
gem "ethos-gemkit", "0.3.1", group: [:development, :test], require: false
```

Add a `Rakefile`:

```ruby
require "bundler/setup"
require "ethos/gemkit/rake"
```

Add `.standard.yml`:

```yaml
ruby_version: "4.0"
plugins:
  - ethos-gemkit
```

Run `bundle install`, then run `bundle exec rake tools:install` and `bundle exec rake verify`. Verification runs lint, registered checks, a disposable gem build and git-cliff validation. It does not publish a release.

See the [full documentation](https://www.ethos-link.com/opensource/ethos-gemkit) for configuration, workflows, operational details and limitations.
For existing installations, read [UPGRADE.md](UPGRADE.md).



## About Ethos Link

[Ethos Link](https://www.ethos-link.com) is a software company founded by
[Paulo Fidalgo](https://www.fidalgo.pt). We publish these Ruby tools alongside
our business products:

- [Reviato](https://www.reviato.com): private customer feedback and public review analysis.
- [Nuntio](https://www.nuntiohq.com): prepare, review and schedule social posts.
- [EthosPlaces](https://www.ethos.place): find places, opening hours and contact details.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
