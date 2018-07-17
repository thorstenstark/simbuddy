[![License](https://img.shields.io/badge/license-MIT-green.svg?style=flat)]

# SimulatorHelper
SimulatorHelper is a little tool, to help you set up only specific iOS simulators instead of all possible devices for a given iOS version.

## Prequesites
You need to have Xcode and its Command Line tools already installed.

## Usage
In the SIM.yml file you specify the devices and the iOS version they should use:
```bash
'iPad Air 2': ['9.3', '10.3']
'iPad Pro (12.9-inch)': ['11.0', '11.4']
'iPhone 4s': ['9.3']
'iPhone 6': ['10.3', '11.0', '11.4']
'iPhone 7': ['10.3', '11.4']
'iPhone 8 Plus': ['11.4']
'iPhone X': ['11.4']
```
Note: The device name must match the names used by Xcode. Use `xcrun simctl list -j devices` to see all available devices.

When you're happy with your specified simulators run:
```bash
./simbuddy.rb
```

You will be prompted whether you want to delete all currently created simulators or not.


## TODO
* Create Simulator with paired Watch Simulator
* Initialization/Onboarding for new Users