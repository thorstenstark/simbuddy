![License](https://img.shields.io/badge/license-MIT-green.svg?style=flat)

# SimBuddy
SimBuddy is a little command line tool, to help you set up only specific iOS simulators instead of all possible devices for a given iOS version.

From this            |  To this
:-------------------------:|:-------------------------:
![](/images/devices_long_list.png)  |  ![](/images/devices_short_list.png)
## Prequesites
You need to have Xcode and its Command Line tools already installed.

## Usage
In the SIM.yml file you specify the devices and the iOS version they should use:
```bash
'iPad Air 2': ['12.4']
'iPad Pro (12.9-inch)': ['14.1']
'iPad Pro (11-inch) (2nd generation)': ['15.4']
'iPhone SE (2nd generation)': ['15.4']
'iPhone 12': ['14.1', '15.4']
'iPhone 13 mini': ['15.4']
'iPhone 8': ['15.4']
'iPhone 13': ['15.4']
'iPhone 13 Pro Max': ['15.4']
'iPhone 13 Pro': ['15.4']
```
Note: The device name must match the names used by Xcode. Use `xcrun simctl list` to see all available devices.
You can use `xcrun simctl list -j devices` to see your currently configured simulators

When you're happy with your specified simulators run:
```bash
./simbuddy.rb
```

You will be prompted whether you want to delete all currently created simulators or not.


## TODO
* Create Simulator with paired Watch Simulator
* Initialization/Onboarding for new Users
