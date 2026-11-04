# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"
require "ethos/gemkit/registry"

class RegistryTest < GemkitTest
  def test_only_a_confirmed_404_means_absent
    registry = Ethos::Gemkit::Registry.new(kind: "rubygems", host: "https://rubygems.org", name: "fixture")
    %w[200 404 401 403 429 500].each do |code|
      response = Struct.new(:code, :body).new(code, '{"sha":"verified"}')
      http = Object.new
      http.define_singleton_method(:get) { |_path| response }
      Net::HTTP.stub(:start, ->(*_args, **_opts, &block) { block.call(http) }) do
        case code
        when "404" then assert_nil registry.version_info("0.1.1")
        when "200" then assert_equal "verified", registry.version_info("0.1.1").fetch("sha")
        else assert_raises(Ethos::Gemkit::Error) { registry.unused("0.1.1") }
        end
      end
    end
  end

  def test_upload_passes_an_exact_file_and_explicit_host_to_native_rubygems
    registry = Ethos::Gemkit::Registry.new(kind: "rubygems", host: "https://rubygems.org", name: "fixture")
    arguments = nil
    status = Struct.new(:success?).new(true)
    Open3.stub(:capture3, ->(*args) {
      arguments = args
      ["", "", status]
    }) do
      assert registry.push("/tmp/verified/fixture-0.1.1.gem")
    end
    assert_equal ["gem", "push", "/tmp/verified/fixture-0.1.1.gem", "--host", "https://rubygems.org"], arguments
  end
end
