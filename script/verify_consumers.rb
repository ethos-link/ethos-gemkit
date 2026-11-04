#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler"
require "rubygems/package"
require "tmpdir"
require "fileutils"
require "open3"

# Run against built gems, outside both the source checkout and development bundle.
SMOKES = {
  "indexmap" => ["indexmap", 'Indexmap::Entry.new(loc: "https://example.test/")'],
  "crawlscope" => ["crawlscope", "Crawlscope.configuration"],
  "cloudflare-tunnel" => ["cloudflare-tunnel", "Cloudflare::Tunnel.configuration"],
  "ethosmark" => ["ethosmark", 'abort "rendering failed" unless Ethosmark::Renderer.new("## Hello").render.include?("Hello")'],
  "git-markdown" => ["git_markdown", "GitMarkdown::VERSION"],
  "ruby_llm-codex" => ["ruby_llm-codex", "RubyLLM::Codex::VERSION"],
  "destiller" => ["destiller", "Destiller::VERSION"],
  "ethos-gemkit" => ["ethos-gemkit", "Ethos::Gemkit::VERSION"]
}.freeze

abort "Usage: ruby script/verify_consumers.rb REPOSITORY..." if ARGV.empty?
ARGV.each do |argument|
  root = File.realpath(argument)
  name = File.basename(root)
  entry, operation = SMOKES.fetch(name)
  Dir.mktmpdir("gemkit-installed-") do |directory|
    artifact = File.join(directory, "package.gem")
    Dir.chdir(root) do
      specification = Gem::Specification.load("#{name}.gemspec")
      Gem::Package.build(specification, false, false, artifact)
    end
    package = Gem::Package.new(artifact)
    unpacked = File.join(directory, "unpacked")
    package.extract_files(unpacked)
    File.write(File.join(unpacked, "#{name}.gemspec"), package.spec.to_ruby)
    File.write(File.join(directory, "Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem #{name.inspect}, path: #{unpacked.inspect}, require: false
    GEMFILE
    code = <<~CODE
      require #{entry.inspect}
      #{operation}
      abort "Runtime installed Railties" if Gem.loaded_specs.key?("railties")
      abort "Runtime loaded Rails" if defined?(Rails::Railtie)
      abort "Toolkit leaked into runtime" if #{name != "ethos-gemkit"} && Gem.loaded_specs.key?("ethos-gemkit")
    CODE
    Bundler.with_unbundled_env do
      environment = {"BUNDLE_GEMFILE" => File.join(directory, "Gemfile")}
      [["bundle", "lock", "--local"], ["bundle", "exec", "ruby", "-e", code]].each do |command|
        output, error, status = Open3.capture3(environment, *command, chdir: directory)
        abort "#{name}: #{output}\n#{error}" unless status.success?
      end
    end
    puts "PASS #{name}: built package operates without Rails/Railties or development dependencies"
    integrations = {"indexmap" => ["indexmap", "Indexmap::Railtie"],
                    "crawlscope" => ["crawlscope", "Crawlscope::Railtie"],
                    "ethosmark" => ["ethosmark", "Ethosmark::Railtie"],
                    "cloudflare-tunnel" => ["cloudflare/tunnel", "Cloudflare::Tunnel::Railtie"]}
    if integrations.key?(name)
      prefix, constant = integrations.fetch(name)
      File.open(File.join(directory, "Gemfile"), "a") { |file| file.puts 'gem "rails", "~> 8.1.0", require: false' }
      host_code = <<~CODE
        require #{entry.inspect}
        require "#{prefix}/rails"
        abort "Railtie not registered" unless #{constant} < Rails::Railtie
        abort "Integration booted a host" if Rails.application
      CODE
      Bundler.with_unbundled_env do
        environment = {"BUNDLE_GEMFILE" => File.join(directory, "Gemfile")}
        [["bundle", "lock", "--local"], ["bundle", "exec", "ruby", "-e", host_code]].each do |command|
          output, error, status = Open3.capture3(environment, *command, chdir: directory)
          abort "#{name} Rails integration: #{output}\n#{error}" unless status.success?
        end
      end
      puts "PASS #{name}: core-first load explicitly registers its Rails 8 integration without booting a host"
    end
  end
end
