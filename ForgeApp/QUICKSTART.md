# Forge macOS App - Quick Start Guide

## Installation

### Prerequisites
1. macOS 14.0 or later
2. Xcode 15.0 or later
3. XcodeGen installed via Homebrew
4. Forge CLI installed and in PATH

### Install XcodeGen
```bash
brew install xcodegen
```

### Install Forge CLI
```bash
cd ~/Projects/Active/Forge
pip install -e .
```

Verify installation:
```bash
forge --help
```

## Building the App

1. Navigate to the app directory:
   ```bash
   cd ~/Projects/Active/Forge/ForgeApp
   ```

2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

3. Open in Xcode:
   ```bash
   open ForgeApp.xcodeproj
   ```

4. Build and run (Cmd+R)

## Using the App

### First Launch

On first launch, the app will automatically scan these directories for Forge projects:
- `~/Projects/Active`
- `~/Projects`
- `~/Developer`

Any directory containing a `.forge/` folder will be detected.

### Main Interface

The app has two main sections:

**Sidebar (Left)**:
- Lists all discovered Forge projects
- Click a project to view its features
- Refresh button to re-scan for projects

**Main Area (Right)**:
- Kanban board with 4 columns: Planned, In Progress, Review, Completed
- Each feature appears as a card in its current status column
- Feature count badge on each column

### Working with Features

#### View Features
- Features are displayed as cards on the Kanban board
- Each card shows:
  - Title
  - Description (if available)
  - Complexity badge (Small, Medium, Large, Epic)
  - Status indicator (colored dot)
  - Tags
  - Branch name (if started)

#### Move Features
**Drag and Drop**:
- Click and drag a feature card to a different status column
- Release to update the status
- Changes are saved immediately to `registry.json`
- FileWatcher detects changes and updates the UI automatically

#### Context Menu (Right-Click)
- **View Details**: Opens detailed feature information
- **Start Feature**: Creates worktree and sets status to In Progress
- **Move to**: Quick menu to move feature to specific status

#### Add New Feature
1. Click "Add Feature" button in toolbar
2. Enter feature title
3. Press Enter or click "Add"
4. Feature appears in Planned column

#### Feature Details
Right-click a feature and select "View Details" to see:
- Full ID
- Title and description
- Current status
- Complexity level
- Associated branch
- Worktree path
- Created, started, and completed timestamps
- All tags

### Live Updates

The app uses FileWatcher to monitor `registry.json` for changes:
- Changes made via CLI are instantly reflected in the UI
- Multiple users/sessions can work simultaneously
- No manual refresh needed

### CLI Integration

The app integrates with the `forge` CLI:

**Add Feature**: Calls `forge add <title>`
**Start Feature**: Calls `forge start <id>`
**Status Updates**: Direct registry.json manipulation for performance

You can use both the GUI and CLI simultaneously. Changes sync automatically.

## Keyboard Shortcuts

- **Cmd+R**: Refresh projects list
- **Escape**: Close dialogs
- **Enter**: Confirm in dialogs
- **Right-click**: Context menu on features

## Troubleshooting

### "No Project Selected" Message
- Make sure you have initialized Forge in at least one project
- Run `forge init` in a project directory
- Click refresh button in sidebar

### Features Not Appearing
- Check that the project has features in `.forge/registry.json`
- Try adding a feature via CLI: `forge add "Test Feature"`
- Verify the project is selected in the sidebar

### Drag and Drop Not Working
- Make sure you're dragging to a different status column
- Try right-click → Move to instead
- Check console output for errors

### "forge command not found"
- The CLI must be in your PATH
- Add to your shell profile:
  ```bash
  export PATH="/usr/local/bin:$PATH"
  ```
- Or specify full path in `CLIBridge.swift`:
  ```swift
  init(commandPath: String = "/full/path/to/forge")
  ```

### Project Auto-Discovery Issues
The app searches:
- `~/Projects/Active`
- `~/Projects`
- `~/Developer`

If your projects are elsewhere, they won't appear automatically. You can:
1. Move/symlink projects to these locations
2. Modify `AppState.discoverProjects()` to include your directories

## Development Tips

### Regenerating Project
If you modify `project.yml`:
```bash
cd ForgeApp
xcodegen generate
```

### Debugging CLI Calls
Set breakpoints in `Services/CLIBridge.swift` to debug CLI integration.

### Viewing Registry Changes
Watch the registry file:
```bash
watch -n 1 cat .forge/registry.json
```

### Console Logs
View app console output in Xcode's debug area (Cmd+Shift+Y)

## Next Steps

- Try creating a feature in the app
- Drag it through the workflow stages
- Use `forge status` in terminal to see CLI view
- Right-click features to explore context menu options

## Known Limitations

- No persistent project favorites yet
- Project discovery is filesystem-based
- Drag and drop bypasses CLI (direct registry update)
- No feature dependency visualization yet
- No merge conflict visualization

## Getting Help

- Check the main README.md for architecture details
- Review CLAUDE.md for development guidance
- File issues on GitHub
