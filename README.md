# Lockin

Lockin is a Flutter version of the AppBlocker Android project. The shared UI is built in Flutter, while Android-specific blocking remains native through a platform channel.

## Features

- Select installed Android apps to monitor.
- Track foreground usage in a 4-hour sliding window.
- Allow 40 minutes of use before blocking selected apps.
- Start a foreground service for persistent monitoring.
- Use Accessibility Service and Usage Access to detect and block selected apps.
- Use Device Admin as an optional protection layer against easy removal.

## Android permissions

Lockin needs these Android settings enabled manually:

- Device Admin
- Usage Access
- Accessibility Service
- Notifications on Android 13+

The app opens the relevant settings screen when activation needs a missing permission.

## Build

```sh
flutter pub get
flutter build apk --debug
```
