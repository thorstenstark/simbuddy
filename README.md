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
```yaml
'iPad Air 2': ['12.4']
'iPad Pro (12.9-inch)': ['15.5']
'iPhone 12': ['14.1', '17.4']
'iPhone 15': ['17.4', 'newest']
'iPhone 16 Pro': ['newest']
```

Use `newest` instead of a version number to always resolve to the latest installed runtime (iOS or watchOS respectively). This way you don't need to update your config every time a new Xcode version is installed.

### watchOS Simulators

You can also create watchOS simulators and pair them with an iPhone using the `watch` section:
```yaml
'iPhone 17 Pro Max': ['newest']

watch:
  'Apple Watch Series 11 (46mm)':
    os: ['newest']
    pair_with: 'iPhone 17 Pro Max'
```

- `os` works the same as iOS versions (array, supports `newest`)
- `pair_with` references an iPhone defined in the same config file (optional — omit to create an unpaired watch)

Note: The device name must match the names used by Xcode. To see all available devices and their compatible runtimes, run:
```bash
./simlist.rb
```
This lists every iPhone, iPad, and Apple Watch with the runtimes it supports, making it easy to pick the right names for your config:
```
━━━ iPhones ━━━
  iPhone SE (3rd generation)   15.4, 16.4, 18.4, 18.5, 26.2, 26.4
  iPhone 16 Pro                18.4, 18.5, 26.2, 26.4
  ...

━━━ iPads ━━━
  iPad mini (A17 Pro)          18.4, 18.5, 26.2, 26.4
  ...

━━━ Apple Watches ━━━
  Apple Watch Series 11 (46mm)  11.4, 11.5, 26.2, 26.4
  Apple Watch Ultra 3 (49mm)    11.4, 11.5, 26.2, 26.4
  ...
```

When you're happy with your specified simulators run:
```bash
./simbuddy.rb
```

SimBuddy will show a sync plan and let you choose between:
- **Sync** (default) -- only removes simulators not in your config and creates missing ones, keeping existing matches untouched
- **Erase all** -- deletes all simulators and recreates from config (old behavior)
- **Cancel** -- abort without changes


## TODO
* Initialization/Onboarding for new Users
