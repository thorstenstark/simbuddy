#!/usr/bin/env ruby

# Lists all available iOS devices with their compatible runtimes,
# so you can pick the right names for SIM.yml.

require 'json'

runtimes = JSON.parse(`xcrun simctl list -j runtimes`)
device_types = JSON.parse(`xcrun simctl list -j devicetypes`)

# Build a quick lookup: identifier → name
type_names = {}
device_types['devicetypes'].each { |t| type_names[t['identifier']] = t['name'] }

ios_runtimes = runtimes['runtimes']
	.select { |r| r['platform'] == 'iOS' && r['isAvailable'] }
	.sort_by { |r| Gem::Version.new(r['version']) }

if ios_runtimes.empty?
	puts "No available iOS runtimes found."
	exit 1
end

# Build device → [versions] mapping
devices = {}
ios_runtimes.each do |runtime|
	version = runtime['version']
	(runtime['supportedDeviceTypes'] || []).each do |d|
		name = type_names[d['identifier']] || d['name']
		next unless name.start_with?('iPhone') || name.start_with?('iPad')
		devices[name] ||= []
		devices[name] << version
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
