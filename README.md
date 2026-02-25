# USCIS Case Status Tracker - iOS App

A SwiftUI iOS app to track the status of your USCIS immigration cases.

## Features

- **Track Multiple Cases** — Add and monitor multiple USCIS cases on a single page
- **Real-time Status** — Fetches the latest case status directly from the USCIS website
- **Nicknames** — Assign friendly nicknames to each case (e.g., "My H1B", "Wife's EAD")
- **Pull to Refresh** — Swipe down to refresh all cases at once, or tap the refresh button on individual cases
- **Persistent Storage** — Cases are saved locally and restored on app launch
- **Status Icons** — Visual indicators for different case statuses (approved, denied, received, mailed, etc.)
- **Expandable Cards** — Collapse/expand case details for a cleaner view

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Getting Started

1. Open `USCISCaseTracker.xcodeproj` in Xcode
2. Select your target device or simulator
3. Build and run (Cmd + R)

## Architecture

```
USCISCaseTracker/
├── USCISCaseTrackerApp.swift    # App entry point
├── Models/
│   └── CaseItem.swift           # Data models (CaseItem, CaseStatus)
├── Services/
│   ├── USCISService.swift       # Network service for fetching case status
│   └── PersistenceService.swift # Local storage via UserDefaults
├── ViewModels/
│   └── CaseTrackerViewModel.swift # Main view model (MVVM)
└── Views/
    ├── ContentView.swift        # Main screen with case list
    ├── CaseCardView.swift       # Individual case card component
    └── AddCaseSheet.swift       # Sheet for adding new cases
```

## How It Works

The app sends a POST request to the USCIS Case Status Online portal (`egov.uscis.gov/casestatus/mycasestatus.do`) with the receipt number and parses the HTML response to extract the case status title and details.

## Receipt Number Format

USCIS receipt numbers follow the format: **3 letters + 10 digits** (e.g., `EAC2190000001`, `WAC2390123456`).

## License

MIT
