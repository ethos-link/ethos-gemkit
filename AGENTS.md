# Repository instructions

Use Ruby 4.0+ and the git-standards skill. Work on feature branches and preserve
Conventional Commit context. Run `bundle exec rake verify` before handing off.

This is development tooling. Do not add Rails as a runtime dependency, load
consumer applications to inspect their bundles, or move this toolkit into a
consumer's runtime dependency graph. Use lint_roller's public plugin interface
and the upstream Standard Rails implementation.

Release changes require disposable Git objects and registry fixtures. Do not
prepare real consumer releases, create consumer tags or publish packages unless
explicitly instructed. Do not replace existing release safeguards before their
shared implementation and hosted-workflow behavior have been verified.
