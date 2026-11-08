# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.2] - 2026-11-08

### Changed

- pin native release tools with mise


### Documentation

- make Ethos Link the canonical documentation home
- keep audited technical guidance alongside the code

## [0.3.1] - 2026-11-05

### Changed

- remove unused package and changelog entries
- provision consumer dependencies before checks
- run checks locally to preserve Actions budget


### Fixed

- normalize generated release notes

## [0.3.0] - 2026-11-05

### Changed

- remove unused package and changelog entries
- provision consumer dependencies before checks

## [0.2.1] - 2026-11-05

### Documentation

- clarify current setup
- document checksums for frozen installs
- distinguish source fixes from workflow retries

### Fixed

- preserve checksums during preparation

## [0.2.0] - 2026-11-04

### Added

- support native private publishing and project setup

### Documentation

- document the published Gemkit release
- clarify per-gem publishers and safe retries

### Fixed

- show preparation progress and live command output

## [0.1.0] - 2026-11-04

### Added

- bootstrap shared gem development contracts
- enforce the shared commit message policy
- centralize verified gem release orchestration
- prepare release PRs and publish after merging

### Changed

- exercise standalone core operations
- expose shared commit message validation
- replace release orchestration with native workflows
- remove the redundant bootstrap fixture

### Fixed

- lock toolkit development to patched Active Support
- disable inherited publishing tasks
- complete checksums for frozen hosted installs
- declare and isolate framework fixture dependencies
- bind package files to the verified tag tree
- expose scoped bundle executables to subprocesses
- retain confirmed publication evidence for recovery
- scope source fetch authentication to GitHub
- select the current artifact run explicitly
- prevent implicit pushes of unrelated tags
- bootstrap Bundler for plain rake commands
- keep Bundler's CI cache out of release source
- recycle fully merged local release branches
