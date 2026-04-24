# discar - iOS Companion App

iOS + watchOS sensor recording app for synchronized multi-camera vehicle data collection.

## Architecture: Pragmatic MVVM

```
┌─────────────────────────────────────────────────────────────┐
│                      Views (SwiftUI)                         │
│   StatusView (+ Record)  │  SessionsView  │  SettingsView   │
└───────────────────────┬─────────────────────────────────────┘
                        │ @StateObject
┌───────────────────────▼─────────────────────────────────────┐
│                      ViewModels                              │
│   StatusVM  │  RecordVM  │  SessionsVM  │  SettingsVM       │
│   - UI state (@Published)                                    │
│   - Orchestrates services                                    │
│   - No business logic duplication                            │
└───────────────────────┬─────────────────────────────────────┘
                        │ Direct calls
┌───────────────────────▼─────────────────────────────────────┐
│                      Services                                │
│   SensorManager    │  StorageService  │  APIClient          │
│   WebSocketService │  WatchCoordinator │  Logger            │
│   - Singletons (.shared)                                     │
│   - Thread-safe (actor/@MainActor)                           │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────┐
│                   Data + Config                              │
│   Session (SwiftData)  │  SensorData (CSV)  │  AppConfig    │
└─────────────────────────────────────────────────────────────┘
```

### Design Principles

- **Simple over clever** - Direct service calls, no unnecessary abstractions
- **Singletons are fine** - For this app scale (~9k lines)
- **No protocol ceremony** - Add protocols only when testing requires mocking
- **Feature-based folders** - Each feature is self-contained

## Project Structure

```
discar/
├── App/
│   └── discarApp.swift           # Entry point
│
├── Config/
│   └── AppConfig.swift           # All settings in one place
│
├── Core/
│   ├── Theme/
│   │   └── AppTheme.swift        # Design system
│   ├── Components/               # Reusable UI
│   │   ├── MetricCard.swift      # Bold stat display (Fitness-style)
│   │   ├── ProgressRing.swift    # Circular progress
│   │   ├── StatusBadge.swift     # Connection indicators
│   │   ├── ActionButton.swift    # Styled buttons
│   │   ├── SensorHealthBar.swift # Sensor status
│   │   └── StatCard.swift        # Simple stat card
│   ├── State/
│   │   ├── LoadState.swift       # Async loading state
│   │   └── SensorHealth.swift    # Sensor health tracking
│   └── Utilities/
│       ├── Validators.swift      # IP, UUID validation
│       └── Formatters.swift      # Duration, bytes, etc.
│
├── Models/
│   ├── Session.swift             # SwiftData model
│   ├── SensorData.swift          # CSV data types
│   └── SensorType.swift          # Sensor enumeration
│
├── Services/
│   ├── SensorManager.swift       # iPhone sensor recording
│   ├── StorageService.swift      # CSV I/O + sync uploads
│   ├── ExportService.swift       # ZIP export
│   ├── Logger.swift              # Remote logging
│   ├── Network/
│   │   ├── APIClient.swift       # HTTP requests
│   │   └── WebSocketService.swift # Real-time status
│   └── Watch/
│       └── WatchCoordinator.swift # Watch communication
│
└── Features/
    ├── Status/                   # System monitoring
    ├── Record/                   # Recording control
    ├── Sessions/                 # Session browser
    └── Settings/                 # Configuration
```

## Key Services

| Service | Purpose |
|---------|---------|
| `SensorManager` | Records 10 sensors simultaneously at 1Hz |
| `StorageService` | CSV file I/O, session sync to controller |
| `APIClient` | All HTTP requests to controller |
| `WebSocketService` | Real-time status updates |
| `WatchCoordinator` | Apple Watch communication |
| `RemoteLogger` | Fire-and-forget logging to controller |

## Sensors Recorded

| Sensor | Data |
|--------|------|
| Accelerometer | x, y, z (g) |
| Gyroscope | x, y, z (rad/s) |
| Magnetometer | x, y, z (μT) |
| Barometer | pressure, altitude |
| GPS | lat, lon, speed, course |
| Device Motion | attitude, quaternion, user accel |
| Heading | magnetic, true, accuracy |
| Gravity | x, y, z |
| Orientation | roll, pitch, yaw |
| Headphone Motion | AirPods motion |

## Data Format

CSV with Melbourne timezone timestamps:
```csv
time,datetime,x,y,z
0.0,2025-04-24 14:30:00.123,0.123,-0.456,9.81
```

Session folder:
```
Documents/Sessions/{UUID}/
├── accelerometer.csv
├── gyroscope.csv
├── ...
├── metadata.json
└── watch/              # Watch data
    └── accelerometer.csv
```

## Controller API

### WebSocket (Real-time)
`ws://{ip}:8000/ws/status`

| Message | Data |
|---------|------|
| `initial` | Full state snapshot |
| `controller` | ready, recording, uuid, duration |
| `camera` | name, state, cpu, temp |
| `system` | cpu%, mem%, temp |
| `can` | connected, frame_count |
| `storage` | mount status, free space |

### REST
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/status` | GET | Full status |
| `/api/record/start?uuid={uuid}` | POST | Start recording |
| `/api/record/stop` | POST | Stop recording |
| `/api/sync/phone` | POST | Upload session |

## Configuration

All settings centralized in `AppConfig.swift`:
- Controller IP (default: `192.168.8.145`)
- Sensor frequency (1 Hz)
- Buffer flush interval (10s)
- API timeouts

## UI Design

Inspired by Apple Fitness:
- Bold metrics with `MetricCard`
- Circular progress with `ProgressRing`
- Clean status indicators with `StatusBadge`
- System colors for light/dark mode

## Development

### Mock Server
```bash
cd ~/syncdrivenet/mock_ctlr
source venv/bin/activate
python server.py
```

### Build
- Xcode 15+
- iOS 17+ / watchOS 10+
- Pure Swift, no external dependencies

## Watch App

### Sensors Recorded
- Heart Rate (via HealthKit workout)
- Device Motion (accelerometer, gyroscope, magnetometer fused)
- Barometer (pressure, relative altitude)
- Compass (heading)

### Communication Flow (Decoupled)

The watch uses a **decoupled flow** via `applicationContext` instead of direct messages. This provides:
- Reliability: State persists even if watch app restarts
- Independence: User controls watch recording manually
- Simplicity: No complex handshakes or confirmations

**Phone State Publishing:**
- Phone publishes state via `updateApplicationContext`:
  - `phoneRecording`: Whether phone is recording
  - `sessionID`: Current session UUID
  - `timestamp`: State update time
- Watch reads this state and displays it in a status panel

**Watch Status Panel:**
- Shows phone connection status (green/orange dot)
- Shows phone recording state (Recording/Idle)
- Shows session UUID (first 8 characters) when phone is recording

**Manual Watch Control:**
- Start button: Always enabled (green when phone recording, orange when not)
- Uses phone's full sessionID if available, otherwise generates own UUID
- Stop button: Shown during watch recording
- User has full control over watch recording lifecycle
- No strict restrictions - just visual guidance

**Recommended Flow:**
1. User taps Record on iPhone
2. Phone publishes state: `{phoneRecording: true, sessionID: "full-uuid"}`
3. Phone shows prompt: "Open Watch app and tap Start"
4. User opens Watch app, sees phone status panel with UUID
5. User taps Start on Watch → uses same UUID as phone
6. User taps Stop on iPhone when done
7. Phone publishes state: `{phoneRecording: false}`
8. Phone shows prompt: "Open Watch app and tap Stop"
9. User taps Stop on Watch to end watch recording
10. Watch auto-syncs files to `Sessions/{uuid}/watch/` on phone

**File Sync (Watch → Phone):**
- Triggered automatically after watch recording stops
- Uses `WCSession.transferFile()` (background transfer)
- Files saved to `Sessions/{uuid}/watch/` on phone

**Manual Sync (Phone → Watch):**
- Phone sends `{command: sendSession, sessionID: ...}`
- Watch transfers all CSV files for that session

## Documentation

- `ARCHITECTURE.md` - Detailed architecture decisions
- `REFACTORING.md` - Refactoring plan and rationale
- `mock_ctlr/CTLR_MIGRATION.md` - WebSocket migration guide

---

## Changelog (April 2026)

### UI Changes

**Merged Record into Status Tab**
- Record button now at top of Status tab
- Removed separate Record tab (now 3 tabs: Status, Sessions, Settings)
- Phone sensors displayed below record button in compact format

**Settings Cleanup**
- Removed Diagnostics section (sensor status + recheck button)

**Sessions Tab**
- Removed SyncStatusCard (Sync All button at top)

**Status Tab Improvements**
- CAN and System cards now uniform height (minHeight: 70)
- Eject button disabled during recording with "Can't eject during recording" message
- Compact phone sensors card showing active/inactive sensors

**Record Button**
- Updated to match AppTheme styling
- Uses AppTheme.Colors, Typography, Spacing, Radius

### Swift 6 Concurrency Fixes

**APIClient.swift**
- Moved response models to separate file (`Models/APIResponses.swift`)
- Fixes "Main actor-isolated conformance of Decodable" errors
- Response models are plain `Codable, Sendable` structs

**AppConfig.swift**
- All nested enums marked `Sendable`
- All static properties marked `nonisolated`
- Validation functions marked `nonisolated`

**WatchCoordinator.swift**
- Fixed `didReceive file` delegate to copy file synchronously before async Task
- Prevents temp file deletion before copy completes

### Code Cleanup

**Deleted Files**
- `HTTPServerService.swift` (unused)
- `ConnectivityManager.swift` (duplicate of WatchCoordinator)
- `WatchDataTransferManager.swift` (merged into WatchCoordinator)
- `WatchTransferCard.swift` (unused)
- `CANStatusCard.swift` (unused)
- `LoadState.swift` (unused)
- `Status/Components/` folder
- `Sessions/Components/` folder

**New Files**
- `Models/APIResponses.swift` - API response models (separate from actor)
- `Core/Components/ShareSheet.swift` - UIActivityViewController wrapper
- `Core/Components/DocumentExporter.swift` - UIDocumentPickerViewController wrapper

**RecordViewModel**
- Made `modelContext` optional with `updateModelContext()` method
- Supports lazy initialization for StatusView integration

### Architecture

```
Status Tab (merged)
├── RecordSection
│   ├── Recording card (button, health bar, connections)
│   └── SensorStatusCardCompact (below button)
├── ConnectionCard
├── ControllerCard
├── CamerasCard
├── CAN & System cards (HStack, uniform height)
├── StorageCard (eject disabled during recording)
└── SessionsCard
```

### Files Modified

- `Features/Status/StatusView.swift` - Added RecordSection, compact sensors
- `Features/Record/RecordView.swift` - Updated RecordButton styling
- `Features/Record/RecordViewModel.swift` - Optional modelContext
- `Features/Settings/SettingsView.swift` - Removed diagnostics
- `Features/Sessions/SessionsView.swift` - Removed SyncStatusCard
- `Core/MainTabView.swift` - Removed Record tab
- `Core/Components/SensorStatusCard.swift` - Card-based design
- `Services/Network/APIClient.swift` - Simplified, models moved out
- `Services/Watch/WatchCoordinator.swift` - Fixed file receive
- `Config/AppConfig.swift` - Swift 6 nonisolated fixes
- `Services/Logger.swift` - nonisolated shared instance

### Decoupled Watch Flow

**Unified Watch Managers:**
- iPhone: `WatchCoordinator` (single manager for all watch communication)
- Watch: `WatchConnectionManager` (handles WCSession) + `WatchSensorManager` (records sensors)
- Old duplicates deleted: `ConnectivityManager`, `WatchDataTransferManager`

**WatchCoordinator.swift (iPhone)**
- Removed `startRecording(sessionID:timeout:)` - no longer waits for watch
- Removed `sendStatus()`, `WatchCommand` enum, `receivedCommand` - all legacy coupled flow
- Added `publishRecordingState(isRecording:sessionID:)` using `updateApplicationContext`
- All iPhone watch status UI uses `WatchCoordinator.shared.$isReachable`

**WatchConnectionManager.swift (Watch)**
- Added `phoneIsRecording`, `phoneSessionID`, `phoneStateTimestamp` published properties
- Added `session(_:didReceiveApplicationContext:)` delegate
- Added `processPhoneState()` to handle applicationContext updates
- Added `startWatchRecording()` and `stopWatchRecording()` for manual control
- Reads existing applicationContext on activation
- Removed legacy message handlers (old coupled flow)
- Removed dead `getStatus` command

**Watch ContentView.swift**
- Added phone status panel showing connection and recording state
- Added manual Start/Stop buttons for watch recording
- Start button always enabled (green/orange color indicates phone state)
- Displays phone's full session UUID (truncated for display)

**RecordViewModel.swift**
- Replaced watch synchronous start with `publishRecordingState()`
- Replaced watch stop message with `publishRecordingState(isRecording: false)`
- Added `showWatchStartPrompt` and `showWatchStopPrompt` alerts
- Removed Combine subscription to watch commands (no longer needed)

**StatusView.swift**
- Added alerts for watch start/stop prompts

---

## Changelog (April 24, 2026)

### Sync Status Improvements

**SessionDetailView - SyncCard Overhaul**
- UUID-based sync status: Now queries `/api/sync/status?uuid=X` for session-specific data
- Real-time segment counts: Shows "X/Y" format per camera (e.g., "2/5 segments")
- Auto-polling: Polls every 3 seconds while syncing, stops when complete
- Better status handling:
  - `syncing` → spinner + X/Y (orange)
  - `waiting` → spinner + 0/Y (orange) - waiting for first segment
  - `partial` → X/Y (yellow) - some synced
  - `complete` → X/Y + checkmark (green)
  - Connected but no data yet → spinner + "Waiting..."
  - Not connected → "No data"

**Watch Status Simplified**
- Removed request-based watch data fetch (auto-sync handles it)
- Shows "Data Ready" if local watch CSV files exist
- Shows "No data" if watch wasn't recording for this session
- Shows transfer progress when watch is actively syncing

**Controller API Changes**
- `/api/sync/status?uuid=X` now counts actual segment files on disk per camera
- Returns: `segments_on_ctlr`, `segments_expected`, `segments_pending`, `total_segments`
- Added `/api/can/status` endpoint (was missing, caused 404s)

### Files Modified

- `Features/Sessions/SessionDetailView.swift` - SyncCard overhaul with polling
- `Core/Components/SensorStatusCard.swift` - Minor fixes
- `Core/State/SensorHealth.swift` - Minor fixes
- `Features/Status/StatusView.swift` - Minor fixes
- `Models/SensorType.swift` - Added sensor type definitions
