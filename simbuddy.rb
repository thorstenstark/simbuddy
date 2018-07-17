#!/usr/bin/env ruby

require 'yaml' 
require 'json'

def simulator_name_for_device(device)
	adjusted_name = device
	case device 
	when "iPad Pro (12.9-inch)"
		adjusted_name = "iPad Pro"
	else 
		adjusted_name = device
	end
	device_name = adjusted_name.gsub(/[ _.()]/, "-")	
	return device_name
end

# xcrun simctl erase all
config = YAML.load_file('SIM.yml')

def prompt(default, *args)
  print(*args)
  result = gets.strip
  return result.empty? ? default : result
end

answer = prompt "n", "Erase all Simulators? (Y/n): "
puts "#{answer}"
if answer == "Y"
	puts "deleting all simulators..."
	device_types = JSON.parse `xcrun simctl list -j devicetypes`
	runtimes = JSON.parse `xcrun simctl list -j runtimes`
	devices = JSON.parse `xcrun simctl list -j devices`

	devices['devices'].each do |runtime, runtime_devices|
	  runtime_devices.each do |device|
	    puts "Removing device #{device['name']} (#{device['udid']})"
	    `xcrun simctl delete #{device['udid']}`
	  end
	end
end

puts "create new simulators..."

config.each do |device, versions|
	device_name = simulator_name_for_device(device)
	versions.each do |os|
		os_2 = os.gsub(/[ _.,\.]/, "-")
		success = `xcrun simctl create "#{device} (#{os})" com.apple.CoreSimulator.SimDeviceType.#{device_name} com.apple.CoreSimulator.SimRuntime.iOS-#{os_2}`
		if success.length > 0
			puts "Successfully created '#{device} (#{os})'"
		 end
	end
end
