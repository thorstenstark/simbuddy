#!/usr/bin/env ruby

require 'yaml'
require 'json'

def build_device_type_lookup
	# Query actual device type identifiers from simctl instead of guessing them
	types = JSON.parse(`xcrun simctl list -j devicetypes`)
	lookup = {}
	types['devicetypes'].each { |t| lookup[t['name']] = t['identifier'] }
	lookup
end

def build_runtime_lookup
	# Query actual runtime identifiers from simctl instead of constructing them
	data = JSON.parse(`xcrun simctl list -j runtimes`)
	lookup = {}
	data['runtimes'].each do |r|
		next unless r['isAvailable'] && r['platform'] == 'iOS'
		# Map "18.5" → identifier, using major.minor extracted from identifier
		if r['identifier'] =~ /iOS-(\d+)-(\d+)/
			lookup["#{$1}.#{$2}"] = r['identifier']
		end
	end
	lookup
end

def prompt(default, *args)
	print(*args)
	result = gets.strip
	result.empty? ? default : result
end

# Load config
config = YAML.load_file('SIM.yml')

# Build lookup tables from simctl (actual identifiers, not guessed)
device_types = build_device_type_lookup
runtime_lookup = build_runtime_lookup
existing_devices = JSON.parse(`xcrun simctl list -j devices`)

if runtime_lookup.empty?
	puts "Error: No available iOS runtimes found."
	exit 1
end

# Resolve 'newest' keyword to actual iOS version
newest_version = runtime_lookup.keys.max_by { |v| Gem::Version.new(v) }
puts "Newest available iOS runtime: #{newest_version}"
puts ""

config.each do |device, versions|
	versions.map! { |v| v == 'newest' ? newest_version : v }
	versions.uniq!
end

# Build desired set: { [device_type_id, runtime_id] => { device:, version: } }
desired = {}
config.each do |device, versions|
	type_id = device_types[device]
	unless type_id
		puts "Warning: Unknown device '#{device}' — skipping (use `xcrun simctl list devicetypes` to see valid names)"
		next
	end
	versions.each do |version|
		rt_id = runtime_lookup[version]
		unless rt_id
			puts "Warning: iOS #{version} runtime not installed — skipping '#{device} (#{version})'"
			next
		end
		key = [type_id, rt_id]
		desired[key] = { device: device, version: version }
	end
end

# Build existing set: { [device_type_id, runtime_id] => [{ udid:, name: }, ...] }
existing = {}
existing_devices['devices'].each do |runtime_key, devices|
	devices.each do |dev|
		key = [dev['deviceTypeIdentifier'], runtime_key]
		existing[key] ||= []
		existing[key] << { udid: dev['udid'], name: dev['name'] }
	end
end

# Determine what to create, remove, and keep
to_create = desired.keys - existing.keys
to_remove_keys = existing.keys - desired.keys
to_keep = desired.keys & existing.keys

puts "=== Sync Plan ==="
puts "  Keep:   #{to_keep.size} simulator(s)"
puts "  Create: #{to_create.size} simulator(s)"
puts "  Remove: #{to_remove_keys.size} unwanted simulator(s)"
puts ""

unless to_keep.empty?
	puts "Keeping:"
	to_keep.each do |key|
		info = desired[key]
		puts "  #{info[:device]} (#{info[:version]})"
	end
	puts ""
end

unless to_create.empty?
	puts "Will create:"
	to_create.each do |key|
		info = desired[key]
		puts "  #{info[:device]} (#{info[:version]})"
	end
	puts ""
end

unless to_remove_keys.empty?
	puts "Will remove:"
	to_remove_keys.each do |key|
		existing[key].each do |dev|
			puts "  #{dev[:name]} (#{dev[:udid][0..7]}...)"
		end
	end
	puts ""
end

if to_remove_keys.empty? && to_create.empty?
	puts "Everything is up to date. Nothing to do."
	exit 0
end

answer = prompt "s", "(S)ync / (E)rase all & recreate / (C)ancel? [S]: "

case answer.downcase
when 'c'
	puts "Cancelled."
	exit 0
when 'e'
	puts ""
	puts "Erasing all simulators..."
	existing_devices['devices'].each do |_runtime, devices|
		devices.each do |dev|
			puts "  Removing #{dev['name']} (#{dev['udid']})"
			`xcrun simctl delete #{dev['udid']}`
		end
	end
	to_create = desired.keys
when 's'
	unless to_remove_keys.empty?
		puts ""
		puts "Removing unwanted simulators..."
		to_remove_keys.each do |key|
			existing[key].each do |dev|
				puts "  Removing #{dev[:name]} (#{dev[:udid]})"
				`xcrun simctl delete #{dev[:udid]}`
			end
		end
	end
end

# Create missing simulators
unless to_create.empty?
	puts ""
	puts "Creating simulators..."
	to_create.each do |key|
		info = desired[key]
		device_type = key[0]
		runtime = key[1]
		name = "#{info[:device]} (#{info[:version]})"

		result = `xcrun simctl create "#{name}" #{device_type} #{runtime} 2>&1`
		if $?.success?
			puts "  Created '#{name}'"
		else
			puts "  Failed to create '#{name}': #{result.strip}"
		end
	end
end

puts ""
puts "Done."
