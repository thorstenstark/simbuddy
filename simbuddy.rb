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

def build_runtime_lookup(platform)
	# Query actual runtime identifiers from simctl for the given platform.
	# Keyed by the full runtime version (e.g. "26.4.1"), not major.minor.
	data = JSON.parse(`xcrun simctl list -j runtimes`)
	lookup = {}
	data['runtimes'].each do |r|
		next unless r['isAvailable'] && r['platform'] == platform
		lookup[r['version']] = r['identifier']
	end
	lookup
end

def resolve_version(lookup, requested)
	# Resolve a requested version against the available runtimes, ignoring the
	# patch component: an exact match wins, otherwise pick the newest runtime
	# whose version starts with "requested." (e.g. "26.4" → "26.4.1").
	# Returns the actual available version string, or nil if nothing matches.
	return requested if lookup.key?(requested)
	candidates = lookup.keys.select { |v| v.start_with?("#{requested}.") }
	candidates.max_by { |v| Gem::Version.new(v) }
end

def prompt(default, *args)
	print(*args)
	result = gets.strip
	result.empty? ? default : result
end

def newest_version_from(lookup)
	lookup.keys.max_by { |v| Gem::Version.new(v) }
end

def print_available_runtimes
	# Show all installed simulator runtimes up front, grouped by platform,
	# so the user sees which OS SDKs are available before any sync happens.
	data = JSON.parse(`xcrun simctl list -j runtimes`)
	available = data['runtimes'].select { |r| r['isAvailable'] }

	puts "=== Available OS Runtimes ==="
	if available.empty?
		puts "  (none installed)"
		puts ""
		return
	end

	available.group_by { |r| r['platform'] }.sort.each do |platform, runtimes|
		versions = runtimes.sort_by { |r| Gem::Version.new(r['version']) }.map { |r| r['version'] }
		puts "  #{platform}: #{versions.join(', ')}"
	end
	puts ""
end

# Show all available OS SDKs/runtimes before doing anything else
print_available_runtimes

# Load config and split iOS vs watch
config = YAML.load_file('SIM.yml')
watch_config = config.delete('watch') || {}

# Build lookup tables from simctl (actual identifiers, not guessed)
device_types = build_device_type_lookup
ios_runtime_lookup = build_runtime_lookup('iOS')
existing_devices = JSON.parse(`xcrun simctl list -j devices`)

if ios_runtime_lookup.empty?
	puts "Error: No available iOS runtimes found."
	exit 1
end

# Resolve 'newest' keyword to actual iOS version
newest_ios = newest_version_from(ios_runtime_lookup)
puts "Newest available iOS runtime: #{newest_ios}"

config.each do |device, versions|
	versions.map! { |v| v == 'newest' ? newest_ios : v }
	versions.uniq!
end

# Resolve watchOS if watch config is present
watch_runtime_lookup = {}
newest_watch = nil
if !watch_config.empty?
	watch_runtime_lookup = build_runtime_lookup('watchOS')
	if watch_runtime_lookup.empty?
		puts "Warning: No available watchOS runtimes found — skipping all watch entries"
		watch_config = {}
	else
		newest_watch = newest_version_from(watch_runtime_lookup)
		puts "Newest available watchOS runtime: #{newest_watch}"

		watch_config.each do |_device, entry|
			entry['os'].map! { |v| v == 'newest' ? newest_watch : v }
			entry['os'].uniq!
		end
	end
end

puts ""

# --- Build desired iOS set ---
desired = {}
config.each do |device, versions|
	type_id = device_types[device]
	unless type_id
		puts "Warning: Unknown device '#{device}' — skipping (use `xcrun simctl list devicetypes` to see valid names)"
		next
	end
	versions.each do |version|
		resolved = resolve_version(ios_runtime_lookup, version)
		rt_id = resolved && ios_runtime_lookup[resolved]
		unless rt_id
			puts "Warning: iOS #{version} runtime not installed — skipping '#{device} (#{version})'"
			next
		end
		key = [type_id, rt_id]
		desired[key] = { device: device, version: resolved }
	end
end

# --- Build desired watch set ---
desired_watches = {}
desired_pairings = {} # { watch_key => phone_device_name }
watch_config.each do |device, entry|
	type_id = device_types[device]
	unless type_id
		puts "Warning: Unknown watch device '#{device}' — skipping (use `xcrun simctl list devicetypes` to see valid names)"
		next
	end

	pair_with = entry['pair_with']
	if pair_with && !config.key?(pair_with)
		puts "Warning: pair_with '#{pair_with}' not found in iOS config — skipping '#{device}'"
		next
	end

	entry['os'].each do |version|
		resolved = resolve_version(watch_runtime_lookup, version)
		rt_id = resolved && watch_runtime_lookup[resolved]
		unless rt_id
			puts "Warning: watchOS #{version} runtime not installed — skipping '#{device} (#{version})'"
			next
		end
		key = [type_id, rt_id]
		desired_watches[key] = { device: device, version: resolved }
		desired_pairings[key] = pair_with if pair_with
	end
end

# --- Build existing sets (split iOS vs watchOS) ---
existing_ios = {}
existing_watches = {}
existing_devices['devices'].each do |runtime_key, devices|
	target = runtime_key.include?('watchOS') ? existing_watches : existing_ios
	devices.each do |dev|
		key = [dev['deviceTypeIdentifier'], runtime_key]
		target[key] ||= []
		target[key] << { udid: dev['udid'], name: dev['name'] }
	end
end

# Build existing pairs lookup
existing_pairs_data = JSON.parse(`xcrun simctl list -j pairs`)
existing_pairs = {} # { [watch_udid, phone_udid] => pair_id }
(existing_pairs_data['pairs'] || {}).each do |pair_id, pair|
	watch_udid = pair['watch']['udid']
	phone_udid = pair['phone']['udid']
	existing_pairs[[watch_udid, phone_udid]] = pair_id
end

# --- Compute iOS sync plan ---
ios_to_create = desired.keys - existing_ios.keys
ios_to_remove_keys = existing_ios.keys - desired.keys
ios_to_keep = desired.keys & existing_ios.keys

# --- Compute watch sync plan ---
watch_to_create = desired_watches.keys - existing_watches.keys
watch_to_remove_keys = existing_watches.keys - desired_watches.keys
watch_to_keep = desired_watches.keys & existing_watches.keys

# --- Display sync plan ---
puts "=== iOS Sync Plan ==="
puts "  Keep:   #{ios_to_keep.size} simulator(s)"
puts "  Create: #{ios_to_create.size} simulator(s)"
puts "  Remove: #{ios_to_remove_keys.size} unwanted simulator(s)"
puts ""

unless ios_to_keep.empty?
	puts "Keeping:"
	ios_to_keep.each { |key| info = desired[key]; puts "  #{info[:device]} (#{info[:version]})" }
	puts ""
end

unless ios_to_create.empty?
	puts "Will create:"
	ios_to_create.each { |key| info = desired[key]; puts "  #{info[:device]} (#{info[:version]})" }
	puts ""
end

unless ios_to_remove_keys.empty?
	puts "Will remove:"
	ios_to_remove_keys.each do |key|
		existing_ios[key].each { |dev| puts "  #{dev[:name]} (#{dev[:udid][0..7]}...)" }
	end
	puts ""
end

unless desired_watches.empty?
	puts "=== watchOS Sync Plan ==="
	puts "  Keep:   #{watch_to_keep.size} watch simulator(s)"
	puts "  Create: #{watch_to_create.size} watch simulator(s)"
	puts "  Remove: #{watch_to_remove_keys.size} unwanted watch simulator(s)"
	puts "  Pair:   #{desired_pairings.size} watch-phone pair(s)"
	puts ""

	unless watch_to_keep.empty?
		puts "Keeping:"
		watch_to_keep.each { |key| info = desired_watches[key]; puts "  #{info[:device]} (#{info[:version]})" }
		puts ""
	end

	unless watch_to_create.empty?
		puts "Will create:"
		watch_to_create.each { |key| info = desired_watches[key]; puts "  #{info[:device]} (#{info[:version]})" }
		puts ""
	end

	unless watch_to_remove_keys.empty?
		puts "Will remove:"
		watch_to_remove_keys.each do |key|
			existing_watches[key].each { |dev| puts "  #{dev[:name]} (#{dev[:udid][0..7]}...)" }
		end
		puts ""
	end
end

all_nothing_to_do = ios_to_remove_keys.empty? && ios_to_create.empty? &&
	watch_to_remove_keys.empty? && watch_to_create.empty? && desired_pairings.empty?

if all_nothing_to_do
	puts "Everything is up to date. Nothing to do."
	exit 0
end

answer = prompt "s", "(S)ync / (E)rase all & recreate / (C)ancel? [S]: "

# --- Execute ---
phone_udids = {} # { "iPhone 17 Pro Max" => udid } for pairing

case answer.downcase
when 'c'
	puts "Cancelled."
	exit 0
when 'e'
	puts ""
	# Unpair all existing pairs
	unless existing_pairs.empty?
		puts "Unpairing all watch-phone pairs..."
		existing_pairs.each { |_key, pair_id| `xcrun simctl unpair #{pair_id}` }
	end
	# Delete all simulators
	puts "Erasing all simulators..."
	existing_devices['devices'].each do |_runtime, devices|
		devices.each do |dev|
			puts "  Removing #{dev['name']} (#{dev['udid']})"
			`xcrun simctl delete #{dev['udid']}`
		end
	end
	ios_to_create = desired.keys
	watch_to_create = desired_watches.keys
when 's'
	# 1. Unpair watches that are being removed
	unless watch_to_remove_keys.empty?
		watch_to_remove_keys.each do |key|
			(existing_watches[key] || []).each do |dev|
				existing_pairs.each do |pair_key, pair_id|
					if pair_key[0] == dev[:udid]
						puts "  Unpairing #{dev[:name]}"
						`xcrun simctl unpair #{pair_id}`
					end
				end
			end
		end
	end

	# 2. Delete unwanted watch sims
	unless watch_to_remove_keys.empty?
		puts ""
		puts "Removing unwanted watch simulators..."
		watch_to_remove_keys.each do |key|
			existing_watches[key].each do |dev|
				puts "  Removing #{dev[:name]} (#{dev[:udid]})"
				`xcrun simctl delete #{dev[:udid]}`
			end
		end
	end

	# 3. Delete unwanted iOS sims
	unless ios_to_remove_keys.empty?
		puts ""
		puts "Removing unwanted iOS simulators..."
		ios_to_remove_keys.each do |key|
			existing_ios[key].each do |dev|
				puts "  Removing #{dev[:name]} (#{dev[:udid]})"
				`xcrun simctl delete #{dev[:udid]}`
			end
		end
	end

	# Collect UDIDs of kept phones for pairing
	ios_to_keep.each do |key|
		info = desired[key]
		udid = existing_ios[key]&.first&.dig(:udid)
		phone_udids[info[:device]] = udid if udid
	end
end

# 4. Create missing iOS sims
unless ios_to_create.empty?
	puts ""
	puts "Creating iOS simulators..."
	ios_to_create.each do |key|
		info = desired[key]
		name = "#{info[:device]} (#{info[:version]})"

		result = `xcrun simctl create "#{name}" #{key[0]} #{key[1]} 2>&1`
		if $?.success?
			puts "  Created '#{name}'"
			phone_udids[info[:device]] = result.strip
		else
			puts "  Failed to create '#{name}': #{result.strip}"
		end
	end
end

# 5. Create missing watch sims
watch_udids = {} # { watch_key => udid }
unless watch_to_create.empty?
	puts ""
	puts "Creating watch simulators..."
	watch_to_create.each do |key|
		info = desired_watches[key]
		name = "#{info[:device]} (#{info[:version]})"

		result = `xcrun simctl create "#{name}" #{key[0]} #{key[1]} 2>&1`
		if $?.success?
			puts "  Created '#{name}'"
			watch_udids[key] = result.strip
		else
			puts "  Failed to create '#{name}': #{result.strip}"
		end
	end
end

# Collect UDIDs of kept watches
watch_to_keep.each do |key|
	udid = existing_watches[key]&.first&.dig(:udid)
	watch_udids[key] = udid if udid
end

# 6. Create desired pairings
unless desired_pairings.empty?
	puts ""
	puts "Pairing watches with phones..."
	desired_pairings.each do |watch_key, phone_name|
		watch_udid = watch_udids[watch_key]
		phone_udid = phone_udids[phone_name]
		watch_info = desired_watches[watch_key]

		unless watch_udid
			puts "  Skipping pair for '#{watch_info[:device]}' — watch simulator not available"
			next
		end
		unless phone_udid
			puts "  Skipping pair for '#{watch_info[:device]}' — phone '#{phone_name}' not available"
			next
		end

		# Check if already paired correctly
		if existing_pairs[[watch_udid, phone_udid]]
			puts "  Already paired: #{watch_info[:device]} <-> #{phone_name}"
			next
		end

		# Unpair watch if paired to something else
		existing_pairs.each do |pair_key, pair_id|
			if pair_key[0] == watch_udid
				`xcrun simctl unpair #{pair_id}`
			end
		end

		result = `xcrun simctl pair #{watch_udid} #{phone_udid} 2>&1`
		if $?.success?
			puts "  Paired: #{watch_info[:device]} <-> #{phone_name}"
		else
			puts "  Failed to pair #{watch_info[:device]} with #{phone_name}: #{result.strip}"
		end
	end
end

puts ""
puts "Done."
