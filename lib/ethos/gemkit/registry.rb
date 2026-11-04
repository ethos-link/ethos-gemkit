# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "open3"
require_relative "configuration"

module Ethos
  module Gemkit
    class Registry
      def initialize(kind:, host:, name:)
        unless Configuration::REGISTRIES[kind] == host
          raise Error, "Unsupported registry/host pair"
        end
        raise Error, "Invalid package name" unless name.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
        @kind, @host, @name = kind, host, name
      end

      def self.for(config)
        new(**config.data.fetch("registry").transform_keys(&:to_sym), name: config.name)
      end

      def version_info(version)
        if @kind == "rubygems"
          uri = URI("#{@host}/api/v2/rubygems/#{@name}/versions/#{version}.json")
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |http| http.get(uri.request_uri) }
          case response.code
          when "200" then JSON.parse(response.body)
          when "404" then nil
          else raise Error, "RubyGems version lookup failed (HTTP #{response.code}); absence/access is not established"
          end
        else
          endpoint = "/orgs/ethos-link/packages/rubygems/#{@name}/versions?per_page=100"
          output, _, status = Open3.capture3("gh", "api", "--paginate", "--slurp", endpoint)
          raise Error, "Authenticated GitHub Packages lookup failed; verify package access" unless status.success?
          JSON.parse(output).flatten.find { |entry| entry.fetch("name") == version }
        end
      rescue JSON::ParserError
        raise Error, "Registry returned an invalid response"
      end

      def unused(version)
        raise Error, "Registry already contains #{@name} #{version}" if version_info(version)
      end

      def push(file)
        raise Error, "GitHub Packages publication awaits its registry rehearsal" unless @kind == "rubygems"
        # Native RubyGems handles short-lived OIDC credentials and MFA behavior.
        _, _, status = Open3.capture3("gem", "push", file, "--host", @host)
        raise Error, "Package upload failed; reconcile registry state before retrying" unless status.success?
        true
      end
    end
  end
end
