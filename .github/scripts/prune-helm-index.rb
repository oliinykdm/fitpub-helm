#!/usr/bin/env ruby

require "net/http"
require "uri"
require "yaml"

index_path = ARGV.fetch(0, "index.yaml")
index = YAML.load_file(index_path)
entries = index.fetch("entries", {})

def reachable?(url, limit = 5)
  raise "Too many redirects while checking #{url}" if limit.zero?

  uri = URI(url)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request_head(uri.request_uri)
  end

  case response
  when Net::HTTPSuccess
    true
  when Net::HTTPRedirection
    reachable?(response.fetch("location"), limit - 1)
  else
    false
  end
rescue StandardError => error
  warn "Pruning chart URL #{url}: #{error.message}"
  false
end

entries.each do |name, versions|
  before = versions.size

  versions.select! do |version|
    urls = Array(version["urls"])
    keep = urls.any? && urls.all? { |url| reachable?(url) }
    warn "Pruned #{name} #{version["version"]}: missing chart package" unless keep
    keep
  end

  warn "Pruned #{before - versions.size} stale #{name} version(s)" if before != versions.size
end

entries.delete_if { |_name, versions| versions.empty? }

File.write(index_path, YAML.dump(index))
