# ForgeApp - macOS SwiftUI Application

A native macOS app for Forge that provides a visual Kanban board interface for managing features.

## Features

- Kanban board with drag-and-drop feature management
- Real-time updates via file watching
- Project discovery and switching
- Feature creation and status updates
- Integration with Forge CLI

## Requirements

- macOS 14.0+
- Xcode 15.0+
- XcodeGen
- Forge CLI (`forge` command in PATH)

## Setup

1. Install XcodeGen:
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   cd ForgeApp
   xcodegen generate
   ```

3. Open the project:
   ```bash
   open ForgeApp.xcodeproj
   ```

4. Build and run in Xcode (Cmd+R)

## Architecture

### Models
- `Feature.swift` - Feature data model matching Python backend
- `Project.swift` - Project configuration model
- `AppState.swift` - Observable app state with feature management

### Services
- `CLIBridge.swift` - Interfaces with `forge` CLI via Process
- `FileWatcher.swift` - Monitors registry.json for changes

### Views
- `ContentView.swift` - Main navigation container
- `ProjectListView.swift` - Sidebar project selector
- `KanbanView.swift` - Main board with add feature dialog
- `StatusColumn.swift` - Column per status with drag/drop
- `FeatureCard.swift` - Draggable feature card with context menu

## Usage

1. The app automatically discovers Forge projects in:
   - `~/Projects/Active`
   - `~/Projects`
   - `~/Developer`

2. Select a project from the sidebar to view its features

3. Drag features between status columns to update their status

4. Right-click features for additional actions:
   - View details
   - Start feature
   - Move to specific status

5. Click "Add Feature" to create new features

## Integration with CLI

The app shells out to the `forge` CLI for operations:
- `forge add <title>` - Add new feature
- `forge start <id>` - Start feature
- Direct registry.json manipulation for status updates

Registry changes are automatically detected via FileWatcher.

## Development

### Project Generation

The project uses XcodeGen for project file generation. Edit `project.yml` and regenerate:
```bash
xcodegen generate
```

### Adding New Views

1. Create Swift file in appropriate Views subdirectory
2. XcodeGen will automatically include it (no project.yml update needed)

### Debugging CLI Integration

Set breakpoints in `CLIBridge.swift` to debug CLI communication.
Check console output for registry loading errors.

## Known Limitations

- Requires `forge` CLI to be in PATH
- Project discovery is filesystem-based (no persistent storage yet)
- No offline mode - requires valid Forge projects
- Drag and drop updates registry directly (not via CLI)

## Future Enhancements

- Persistent project favorites
- Feature dependency visualization
- Merge conflict visualization
- In-app terminal for CLI commands
- Rich text editing for feature descriptions
