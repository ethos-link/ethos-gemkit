# frozen_string_literal: true

require_relative "test_helper"
require "ethos/gemkit/setup"

class SetupTest < GemkitTest
  def test_setup_previews_preserves_local_configuration_and_is_idempotent
    in_fixture do |directory|
      FileUtils.mkdir_p(File.join(directory, "lib/fixture"))
      File.write(File.join(directory, "lib/fixture/version.rb"), 'VERSION = "1.0.0"')
      File.write(File.join(directory, "fixture.gemspec"), <<~SPEC)
        Gem::Specification.new do |s|
          s.name = "fixture"
          s.version = "1.0.0"
          s.metadata["allowed_push_host"] = "https://rubygems.org"
        end
      SPEC
      standard = "# Preserve exclusions\nplugins:\n  - standard-rails\nignore:\n  - generated.rb\n"
      rakefile = "require \"standard/rake\"\ntask :test do\n  puts \"local check\"\nend\n"
      File.write(File.join(directory, ".standard.yml"), standard)
      File.write(File.join(directory, "Rakefile"), rakefile)
      setup = Ethos::Gemkit::Setup.new(directory)
      assert_equal 3, setup.changes.size
      assert_equal standard, File.read(File.join(directory, ".standard.yml"))
      Dir.mktmpdir do |external|
        target = File.join(external, "Rakefile")
        File.write(target, "External file")
        File.delete(File.join(directory, "Rakefile"))
        File.symlink(target, File.join(directory, "Rakefile"))
        assert_raises(Ethos::Gemkit::Error) { setup.apply }
        assert_equal "External file", File.read(target)
        File.unlink(File.join(directory, "Rakefile"))
        missing = File.join(external, "new-file")
        File.symlink(missing, File.join(directory, "Rakefile"))
        assert_raises(Ethos::Gemkit::Error) { setup.apply }
        refute File.exist?(missing)
        File.unlink(File.join(directory, "Rakefile"))
        File.write(File.join(directory, "Rakefile"), rakefile)
      end
      setup.apply
      assert_empty setup.changes
      assert_includes File.read(File.join(directory, "Rakefile")), 'puts "local check"'
      assert_includes File.read(File.join(directory, ".standard.yml")), "# Preserve exclusions"
      assert_includes File.read(File.join(directory, ".standard.yml")), "- generated.rb"
      assert_equal ["test"], Ethos::Gemkit::Configuration.load(directory).checks
    end
  end
end
