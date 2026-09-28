# Nudge

A small macOS menu-bar utility that makes today's tasks hard to forget, without becoming another project manager.

- **Menu-bar icon and a floating edge tab** that show today's count and nudge you when something is due
- **Quick Add from anywhere** (⇧⌘Space) with natural language: `Call Alex tomorrow 11am`, `Review metrics every Monday 10am #work`
- **Overdue / Today / Tomorrow / Upcoming**, one-click completion with undo
- **Persistent reminders** with Complete, Remind Me Later and Don't Notify Again
- **Recurring tasks**, a **daily briefing** on startup or wake, **categories**, **history** and **⌘K search**
- Light and dark mode, launch at login, JSON export/import

Everything stays on your Mac: no account, no server, no analytics, no network access.

## Requirements

- macOS 14 or later
- Swift 6 (Xcode, or just the Command Line Tools: `xcode-select --install`)

## Build and run

```sh
make run    # build, install to /Applications/Nudge.app and launch
make test   # run the test suite
```

The app is a Swift package: `Sources/DailyCore` holds the model, storage (SQLite), date parsing and scheduling logic with tests; `Sources/Nudge` is the AppKit/SwiftUI app.

## License

MIT — see [LICENSE](LICENSE).
