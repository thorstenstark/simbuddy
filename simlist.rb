#!/usr/bin/env ruby

# Lists all available iOS and watchOS devices with their compatible runtimes,
# so you can pick the right names for SIM.yml.

require 'json'

runtimes = JSON.parse(`xcrun simctl list -j runtimes`)
device_types = JSON.parse(`xcrun simctl list -j devicetypes`)

# Build a quick lookup: identifier → name
type_names = {}
device_types['devicetypes'].each { |t| type_names[t['identifier']] = t['name'] }

# Collect devices per platform
devices = {}
['iOS', 'watchOS'].each do |platform|
	platform_runtimes = runtimes['runtimes']
		.select { |r| r['platform'] == platform && r['isAvailable'] }
		.sort_by { |r| Gem::Version.new(r['version']) }

	platform_runtimes.each do |runtime|
		version = runtime['version']
		(runtime['supportedDeviceTypes'] || []).each do |d|
			name = type_names[d['identifier']] || d['name']
			devices[name] ||= []
			devices[name] << version
		end
	end
end

# Find longest device name for alignment
max_len = devices.keys.map(&:length).max

puts "━━━ iPhones ━━━"
devices.select { |name, _| name.start_with?('iPhone') }.each do |name, versions|
	puts "  %-#{max_len}s  %s" % [name, versions.join(', ')]
end

puts ""
puts "━━━ iPads ━━━"
devices.select { |name, _| name.start_with?('iPad') }.each do |name, versions|
	puts "  %-#{max_len}s  %s" % [name, versions.join(', ')]
end

puts ""
puts "━━━ Apple Watches ━━━"
devices.select { |name, _| name.start_with?('Apple Watch') }.each do |name, versions|
	puts "  %-#{max_len}s  %s" % [name, versions.join(', ')]
end
