# Discar Codebase Guided Tour

A complete walkthrough of the discar iOS app architecture, data flow, and key logic.

---

## Table of Contents

1. [App Overview](#1-app-overview)
2. [Architecture Layers](#2-architecture-layers)
3. [Data Flow Diagrams](#3-data-flow-diagrams)
4. [Feature Deep Dives](#4-feature-deep-dives)
5. [Service Layer](#5-service-layer)
6. [File-by-File Reference](#6-file-by-file-reference)

---

## 1. App Overview

**Discar** is a multi-sensor data collection app for synchronized vehicle recording.

### What It Does
1. Records 10 iPhone sensors simultaneously at 1Hz
2. Coordinates with Apple Watch for motion data
3. Syncs with a Raspberry Pi controller that manages cameras
4. Saves data as CSV files for later analysis

### Key Screens
```
┌─────────┬─────────┬──────────┬──────────┐
│ Status  │ Record  │ Sessions │ Settings │
│   🟢    │   ⏺️    │   📋     │   ⚙️     │
└─────────┴─────────┴──────────┴──────────┘
```

### Tech Stack
- **UI**: SwiftUI
- **Storage**: SwiftData (sessions) + CSV files (sensor data)
- **Networking**: URLSession + WebSocket
- **Watch**: WatchConnectivity framework
- **Concurrency**: Swift async/await + actors

---

## 2. Architecture Layers

### Layer Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         VIEWS                                │
│   Pure SwiftUI - no business logic                          │
│   StatusView, RecordView, SessionsView, SettingsView        │
└─────────────────────────┬───────────────────────────────────┘
                          │ @StateObject / @ObservedObject
┌─────────────────────────▼───────────────────────────────────┐
│                      VIEWMODELS                              │
│   @MainActor ObservableObject classes                       │
│   StatusVM, RecordVM, SessionsVM, SettingsVM                │
│                                                              │
│   Responsibilities:                                          │
│   • Hold UI state (@Published properties)                    │
│   • Orchestrate service calls                                │
│   • Transform data for display                               │
└─────────────────────────┬───────────────────────────────────┘
                          │ Direct calls to singletons
┌─────────────────────────▼───────────────────────────────────┐
│                       SERVICES                               │
│   Singletons with focused responsibilities                  │
│                                                              │
│   SensorManager      - iPhone sensor recording              │
│   StorageService     - CSV file I/O (actor)                 │
│   APIClient          - HTTP requests (actor)                │
│   WebSocketService   - Real-time status updates             │
│   WatchCoordinator   - Watch communication                  │
│   RemoteLogger       - Fire-and-forget logging              │
│   ExportService      - ZIP export (actor)                   │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                     DATA LAYER                               │
│   Session (SwiftData)   - Recording metadata                │
│   SensorData (CSV)      - Raw sensor readings               │
│   AppConfig (static)    - Centralized configuration         │
└─────────────────────────────────────────────────────────────┘
```

### Why This Architecture?

| Decision | Reason |
|----------|--------|
| Singletons | Simple for ~9k line app, no DI overhead |
| No protocols | Add them only when testing requires mocking |
| Direct service calls | Avoids unnecessary abstraction layers |
| Feature folders | Each feature is self-contained |
| actors for storage | Thread-safe file I/O |

---

## 3. Data Flow Diagrams

### Recording Flow

```
User taps "Start Recording"
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│                   RecordViewModel                            │
├─────────────────────────────────────────────────────────────┤
│ 1. Check controller readiness                               │
│    └─► APIClient.getStatus()                                │
│        └─► GET http://{ip}:8000/api/status                  │
│                                                              │
│ 2. Generate session UUID                                     │
│    └─► UUID().uuidString                                    │
│                                                              │
│ 3. Start Watch                                               │
│    └─► WatchCoordinator.startRecording(sessionID: uuid)     │
│        └─► WCSession.sendMessage(["command": "start", ...]) │
│        └─► Wait for reply["started"] == true                │
│                                                              │
│ 4. Start Controller                                          │
│    └─► APIClient.startRecording(uuid: uuid)                 │
│        └─► POST http://{ip}:8000/api/record/start?uuid=...  │
│                                                              │
│ 5. Start Phone sensors                                       │
│    └─► StorageService.createSessionFolder(session)          │
│    └─► SensorManager.startRecording(session)                │
│        └─► CMMotionManager.startAccelerometerUpdates()      │
│        └─► CMMotionManager.startGyroUpdates()               │
│        └─► CLLocationManager.startUpdatingLocation()        │
│        └─► ... (10 sensors total)                           │
│                                                              │
│ 6. Start CAN polling                                         │
│    └─► Timer every 2s → APIClient.getCANStatus()            │
└─────────────────────────────────────────────────────────────┘
```

### Sensor Data Pipeline

```
Hardware Sensor (CMMotionManager)
         │
         │ Callback at 1Hz
         ▼
┌─────────────────────────────────────────────────────────────┐
│                    SensorManager                             │
├─────────────────────────────────────────────────────────────┤
│ 1. Create reading struct                                     │
│    AccelerometerReading(time: elapsed, datetime: now,       │
│                         x: data.x, y: data.y, z: data.z)    │
│                                                              │
│ 2. Append to in-memory buffer                                │
│    accelerometerBuffer.append(reading)                       │
│                                                              │
│ 3. Every 10 seconds (flush timer):                           │
│    └─► StorageService.appendCSVData(session, filename, buf) │
│    └─► Clear buffer                                          │
│                                                              │
│ 4. Update sensor health                                      │
│    └─► If no data in 5s → mark sensor unhealthy             │
└─────────────────────────────────────────────────────────────┘
         │
         │ Flush every 10s
         ▼
┌─────────────────────────────────────────────────────────────┐
│                   StorageService (actor)                     │
├─────────────────────────────────────────────────────────────┤
│ appendCSVData<T: CSVConvertible>()                          │
│                                                              │
│ 1. Get file handle for CSV file                              │
│ 2. If new file, write CSV header                             │
│ 3. For each reading:                                         │
│    └─► Write reading.csvRow + newline                       │
│ 4. Close file handle                                         │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│                      File System                             │
├─────────────────────────────────────────────────────────────┤
│ Documents/Sessions/{UUID}/                                   │
│ ├── accelerometer.csv                                        │
│ ├── gyroscope.csv                                            │
│ ├── magnetometer.csv                                         │
│ ├── barometer.csv                                            │
│ ├── gps.csv                                                  │
│ ├── devicemotion.csv                                         │
│ ├── heading.csv                                              │
│ ├── gravity.csv                                              │
│ ├── orientation.csv                                          │
│ └── metadata.json                                            │
└─────────────────────────────────────────────────────────────┘
```

### WebSocket Status Flow

```
App becomes active
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│                   WebSocketService                           │
├─────────────────────────────────────────────────────────────┤
│ 1. Connect to ws://{ip}:8000/ws/status                       │
│                                                              │
│ 2. Receive initial snapshot:                                 │
│    {"type": "initial", "data": {controller, cameras, ...}}  │
│                                                              │
│ 3. Parse and update @Published properties:                   │
│    • controller: ControllerStatus?                           │
│    • cameras: [CameraStatus]                                 │
│    • system: SystemStatus?                                   │
│    • can: CANStatus?                                         │
│    • storage: StorageStatus?                                 │
│                                                              │
│ 4. Receive incremental updates:                              │
│    {"type": "camera", "data": {name, state, temp, ...}}     │
│    └─► Update specific camera in array                       │
│                                                              │
│ 5. Ping loop every 25s to keep connection alive              │
│                                                              │
│ 6. On disconnect: auto-reconnect with exponential backoff   │
└─────────────────────────────────────────────────────────────┘
         │
         │ @Published properties update
         ▼
┌─────────────────────────────────────────────────────────────┐
│                   StatusViewModel                            │
├─────────────────────────────────────────────────────────────┤
│ Binds to WebSocketService via Combine:                       │
│                                                              │
│ WebSocketService.shared.$controller                          │
│     .assign(to: &$controller)                               │
│                                                              │
│ WebSocketService.shared.$cameras                             │
│     .assign(to: &$cameras)                                  │
└─────────────────────────────────────────────────────────────┘
         │
         │ SwiftUI observes @Published
         ▼
┌─────────────────────────────────────────────────────────────┐
│                     StatusView                               │
├─────────────────────────────────────────────────────────────┤
│ UI automatically re-renders when viewModel changes          │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Feature Deep Dives

### Status Tab

**Purpose**: Real-time monitoring of the entire recording system

**Components**:
- `StatusView.swift` - Main UI
- `StatusViewModel.swift` - WebSocket bindings + session stats
- `WebSocketService.swift` - Persistent WebSocket connection

**Data Sources**:
| Data | Source | Update Frequency |
|------|--------|------------------|
| Controller state | WebSocket | On change |
| Camera status | WebSocket | On change |
| System metrics | WebSocket | Every 5s |
| CAN status | WebSocket | On change |
| Storage health | WebSocket | On change |
| Session stats | SwiftData | On appear |

**Key Logic** (`StatusViewModel`):
```swift
// Bind to WebSocket service
WebSocketService.shared.$controller
    .receive(on: DispatchQueue.main)
    .assign(to: &$controller)

// Load local session stats
func loadSessionStats() {
    let sessions = try? modelContext.fetch(FetchDescriptor<Session>())
    totalSessions = sessions?.count ?? 0
    totalTime = sessions?.reduce(0) { $0 + $1.duration } ?? 0
}
```

---

### Record Tab

**Purpose**: Start/stop synchronized recording across all devices

**Components**:
- `RecordView.swift` - Recording UI
- `RecordViewModel.swift` - Orchestration logic
- `SensorManager.swift` - Sensor recording engine

**Recording State Machine**:
```
         ┌──────────────┐
         │    IDLE      │
         └──────┬───────┘
                │ startRecording()
                ▼
         ┌──────────────┐
         │   STARTING   │◄─────────────┐
         └──────┬───────┘              │
                │ all checks pass      │ error
                ▼                      │
         ┌──────────────┐              │
         │  RECORDING   │──────────────┘
         └──────┬───────┘
                │ stopRecording()
                ▼
         ┌──────────────┐
         │   SAVING     │
         └──────┬───────┘
                │ session saved
                ▼
         ┌──────────────┐
         │    IDLE      │
         └──────────────┘
```

**Sensors Recorded**:
| Sensor | Framework | Rate | CSV Columns |
|--------|-----------|------|-------------|
| Accelerometer | CoreMotion | 1Hz | time, datetime, x, y, z |
| Gyroscope | CoreMotion | 1Hz | time, datetime, x, y, z |
| Magnetometer | CoreMotion | 1Hz | time, datetime, x, y, z |
| Barometer | CoreMotion | 1Hz | time, datetime, pressure, altitude |
| GPS | CoreLocation | 1Hz | time, datetime, lat, lon, alt, speed, ... |
| Device Motion | CoreMotion | 1Hz | time, datetime, attitude, quaternion, ... |
| Heading | CoreLocation | 1Hz | time, datetime, magnetic, true, accuracy |
| Gravity | CoreMotion | 1Hz | time, datetime, x, y, z |
| Orientation | CoreMotion | 1Hz | time, datetime, yaw, roll, pitch, q* |
| Headphone | CoreMotion | 1Hz | (same as device motion) |

---

### Sessions Tab

**Purpose**: Browse, export, sync, and delete recorded sessions

**Components**:
- `SessionsView.swift` - Session list
- `SessionsViewModel.swift` - CRUD operations
- `SessionDetailView.swift` - Single session details
- `SensorDataView.swift` - Sensor data visualization

**Operations**:
| Action | Implementation |
|--------|----------------|
| List | SwiftData query, sorted by date desc |
| Delete | SwiftData delete + FileManager remove folder |
| Export | ExportService creates ZIP of folder |
| Sync | StorageService uploads multipart to controller |

---

### Settings Tab

**Purpose**: App configuration and diagnostics

**Components**:
- `SettingsView.swift` - Settings UI
- `SettingsViewModel.swift` - Config + connection test

**Settings**:
| Setting | Storage | Default |
|---------|---------|---------|
| Dark Mode | UserDefaults | false |
| Controller IP | UserDefaults | 192.168.8.145 |
| Test Mode | UserDefaults | false |

---

## 5. Service Layer

### SensorManager

**File**: `Services/SensorManager.swift`
**Type**: `@MainActor class`
**Lines**: ~635

**Responsibilities**:
1. Start/stop 10 different sensors
2. Buffer readings in memory
3. Flush to disk every 10 seconds
4. Track sensor health (timeout detection)
5. Play silent audio to prevent background termination

**Key Methods**:
```swift
func startRecording(session: Session)
func stopRecording() async
func warmUp()  // Pre-initialize sensors for faster start
```

---

### StorageService

**File**: `Services/StorageService.swift`
**Type**: `actor` (thread-safe)
**Lines**: ~366

**Responsibilities**:
1. Create session folders
2. Append CSV data atomically
3. Load/parse sensor data (CSV, JSON, NDJSON)
4. Upload sessions to controller
5. Delete sessions

**Key Methods**:
```swift
func createSessionFolder(session: Session) throws
func appendCSVData<T: CSVConvertible>(session:, filename:, data:)
func uploadSession(session: Session) async throws -> Int
func loadSensorData<T: Codable>(session:, filename:) async -> [T]?
```

---

### APIClient

**File**: `Services/Network/APIClient.swift`
**Type**: `actor` (thread-safe)
**Lines**: ~180

**Responsibilities**:
All HTTP requests to the controller

**Endpoints**:
| Method | URL | Purpose |
|--------|-----|---------|
| GET | /api/status | Full system status |
| POST | /api/record/start | Start recording |
| POST | /api/record/stop | Stop recording |
| GET | /api/can/status | CAN bus status |
| GET | /api/storage/status | Storage mount status |
| POST | /api/storage/remount | Remount drives |
| POST | /api/storage/unmount | Eject sync drive |

---

### WebSocketService

**File**: `Services/Network/WebSocketService.swift`
**Type**: `@MainActor class ObservableObject`
**Lines**: ~444

**Responsibilities**:
1. Maintain persistent WebSocket connection
2. Parse JSON messages by type
3. Update @Published properties
4. Auto-reconnect with exponential backoff

**Message Types**:
| Type | Data |
|------|------|
| initial | Full state snapshot |
| controller | Recording state |
| camera | Single camera update |
| cameras | All cameras |
| system | CPU, memory, temp |
| can | CAN bus state |
| storage | Mount status |
| sync | Sync progress |
| ping | Keep-alive |

---

### WatchCoordinator

**File**: `Services/Watch/WatchCoordinator.swift`
**Type**: `@MainActor class ObservableObject`
**Lines**: ~250

**Responsibilities**:
1. Activate WCSession
2. Send commands to Watch
3. Receive commands from Watch
4. Handle file transfers from Watch

**Communication**:
```
iPhone                              Watch
   │                                  │
   ├── sendStatus(isRecording) ──────►│
   │                                  │
   │◄─────── command: getStatus ──────┤
   │                                  │
   ├── startRecording(sessionID) ────►│
   │◄─────── reply: {started: true} ──┤
   │                                  │
   │◄────── file: accelerometer.csv ──┤
   │◄────── file: gyroscope.csv ──────┤
```

---

### RemoteLogger

**File**: `Services/Logger.swift`
**Type**: `final class @unchecked Sendable`
**Lines**: ~70

**Responsibilities**:
Fire-and-forget logging to controller via HTTP POST

**Usage**:
```swift
RemoteLogger.shared.info("recording", "Started session")
RemoteLogger.shared.error("watch", "Connection lost")
```

---

## 6. File-by-File Reference

### App Entry
| File | Purpose |
|------|---------|
| `discarApp.swift` | Entry point, WatchCoordinator init, scene lifecycle |
| `AppState.swift` | Sensor availability checks on launch |

### Configuration
| File | Purpose |
|------|---------|
| `Config/AppConfig.swift` | All settings: IPs, timeouts, frequencies |

### Core
| File | Purpose |
|------|---------|
| `Core/Theme/AppTheme.swift` | Design system: colors, fonts, spacing |
| `Core/Components/MetricCard.swift` | Fitness-style stat display |
| `Core/Components/ProgressRing.swift` | Circular progress indicator |
| `Core/Components/StatusBadge.swift` | Connection status indicators |
| `Core/Components/ActionButton.swift` | Styled buttons |
| `Core/State/LoadState.swift` | Generic async loading state |
| `Core/State/SensorHealth.swift` | Sensor availability tracking |
| `Core/Utilities/Formatters.swift` | Duration, bytes, percentage |
| `Core/Utilities/Validators.swift` | IP, UUID validation |

### Models
| File | Purpose |
|------|---------|
| `Models/Session.swift` | SwiftData model for recordings |
| `Models/SensorData.swift` | All sensor reading structs + CSV |
| `Models/SensorType.swift` | Sensor enum + filename mapping |

### Services
| File | Purpose |
|------|---------|
| `Services/SensorManager.swift` | iPhone sensor recording |
| `Services/StorageService.swift` | CSV file I/O |
| `Services/ExportService.swift` | ZIP export |
| `Services/Logger.swift` | Remote logging |
| `Services/Network/APIClient.swift` | HTTP requests |
| `Services/Network/WebSocketService.swift` | Real-time status |
| `Services/Watch/WatchCoordinator.swift` | Watch communication |

### Features
| Feature | Files |
|---------|-------|
| Status | StatusView, StatusViewModel, CANStatusCard |
| Record | RecordView, RecordViewModel |
| Sessions | SessionsView, SessionsViewModel, SessionDetailView, SensorDataView |
| Settings | SettingsView, SettingsViewModel |

---

## Quick Reference

### Start Recording
```swift
// RecordViewModel.startRecording()
1. APIClient.shared.getStatus()           // Check ready
2. WatchCoordinator.shared.startRecording() // Start watch
3. APIClient.shared.startRecording()       // Start controller
4. SensorManager.startRecording()          // Start sensors
```

### Stop Recording
```swift
// RecordViewModel.stopRecording()
1. WatchCoordinator.shared.sendStatus(false) // Stop watch
2. SensorManager.stopRecording()              // Stop sensors
3. modelContext.save()                        // Save session
4. APIClient.shared.stopRecording()           // Stop controller
```

### Sync Session
```swift
// SessionsViewModel.syncSession()
1. WatchCoordinator.shared.requestSessionData()  // Get watch data
2. StorageService.shared.uploadSession()         // Upload all CSVs
```

---

**End of Guided Tour**
