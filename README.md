# XTop

**XTop** is a powerful and lightweight macOS menu bar application designed for developers and power users who need instant access to system telemetry and context-aware developer information.

It lives in your menu bar, providing real-time insights into your system's performance and, for developers, information about your current Xcode environment.

## Features

- **Real-time System Monitoring:** Keep an eye on key system metrics directly from your menu bar.
- **Developer-Focused Telemetry:** Integrates with your development environment to show relevant project information (e.g., current Git context, focused Xcode project).
- **Elegant Menu Bar Interface:** A clean, unobtrusive panel that gives you data when you need it without getting in your way.
- **Customizable:** Configure what you want to see through the app's settings.

## Screenshots

| Menu Bar Panel | Settings — Sensors |
|---|---|
| ![Menu Bar Panel](.github/images/menu-bar-panel.png) | ![Settings Sensors Tab](.github/images/settings-sensors-tab.png) |

## Getting Started

### Prerequisites

- macOS
- Xcode

### Building and Running

1.  Clone the repository:
    ```sh
    git clone https://github.com/your-username/XTop.git
    cd XTop
    ```
2.  Open the project in Xcode:
    ```sh
    open XTop.xcodeproj
    ```
3.  Select the `XTop` scheme and your Mac as the run destination.
4.  Press **Cmd+R** to build and run the application.

## Download & Install

If you do not want to build from source, download the latest binary from Releases:

- https://github.com/your-username/XTop/releases/latest

Install steps:

1. Download `XTop-<version>.dmg` (or `XTop-<version>.zip`).
2. If using the DMG, drag `XTop.app` into `Applications`.
3. On first launch, right-click `XTop.app` and choose **Open**.

If macOS still blocks launch, clear quarantine metadata:

```sh
xattr -dr com.apple.quarantine /Applications/XTop.app
```

Note: release builds are ad-hoc signed and not notarized, so Gatekeeper warnings are expected on first launch.

## Releasing

Tag-based releases are automated by GitHub Actions.

```sh
git tag vX.Y.Z
git push origin vX.Y.Z
```

Pushing a `v*` tag triggers a build, creates `.dmg` and `.zip` artifacts, generates SHA-256 checksums, and publishes a GitHub Release.

## How to Use

Once running, the XTop icon will appear in your macOS menu bar. Click it to open the main panel and view your system and developer telemetry. You can access preferences from the panel to customize the display.
