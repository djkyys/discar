# Discar Clean Architecture

## Design Philosophy

**Inspired by**: Apple Fitness app, Tailscale iOS
**Pattern**: Clean MVVM + Services
**Principles**:
- Single Responsibility
- Dependency Injection (via singletons for services)
- Protocol-Oriented Design
- Unidirectional Data Flow

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         UI Layer                                 │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐ │
│  │  StatusView │ │ RecordView  │ │SessionsView │ │ Settings  │ │
│  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘ └─────┬─────┘ │
│         │               │               │               │       │
│         ▼               ▼               ▼               ▼       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    ViewModels                            │   │
│  │  StatusVM │ RecordVM │ SessionsVM │ SessionDetailVM │...│   │
│  └─────────────────────────┬───────────────────────────────┘   │
└────────────────────────────┼────────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────────┐
│                    Service Layer                                 │
│                            │                                     │
│  ┌─────────────────────────┼─────────────────────────────────┐  │
│  │                   Coordinators                             │  │
│  │   ┌──────────────────┐  │  ┌──────────────────┐           │  │
│  │   │ RecordingCoord.  │◄─┼─►│  WatchCoordinator │           │  │
│  │   └────────┬─────────┘     └────────┬─────────┘           │  │
│  └────────────┼────────────────────────┼─────────────────────┘  │
│               │                        │                         │
│  ┌────────────▼────────────────────────▼─────────────────────┐  │
│  │                     Services                               │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │  │
│  │  │SensorManager │ │StorageService│ │  APIClient   │       │  │
│  │  └──────────────┘ └──────────────┘ └──────────────┘       │  │
│  │  ┌──────────────┐ ┌──────────────┐                        │  │
│  │  │WebSocketSvc  │ │   Logger     │                        │  │
│  │  └──────────────┘ └──────────────┘                        │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────────┐
│                      Data Layer                                  │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │   Session    │ │  SensorData  │ │   Config     │             │
│  │  (SwiftData) │ │    (CSV)     │ │ (UserDefaults)│            │
│  └──────────────┘ └──────────────┘ └──────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

---

## New Folder Structure

```
discar/
├── App/
│   ├── discarApp.swift           # Entry point
│   └── AppDelegate.swift         # Background tasks, lifecycle
│
├── Config/
│   └── AppConfig.swift           # All configuration in one place
│
├── Core/
│   ├── Theme/
│   │   └── AppTheme.swift        # Design system
│   │
│   ├── Components/               # Reusable UI components
│   │   ├── MetricCard.swift      # Bold stat display
│   │   ├── ProgressRing.swift    # Circular progress (Fitness-style)
│   │   ├── StatusBadge.swift     # Connection/state indicators
│   │   ├── SensorHealthBar.swift # Sensor status row
│   │   └── ActionButton.swift    # Primary/secondary buttons
│   │
│   ├── Extensions/
│   │   ├── Date+Formatting.swift
│   │   ├── Double+Formatting.swift
│   │   └── Color+Theme.swift
│   │
│   └── Utilities/
│       ├── Validators.swift      # IP, UUID validation
│       └── Formatters.swift      # Duration, bytes, etc.
│
├── Models/
│   ├── Session.swift             # SwiftData model
│   ├── SensorData.swift          # All sensor reading types
│   └── SensorType.swift          # Sensor enumeration
│
├── Services/
│   ├── Sensors/
│   │   └── SensorManager.swift   # iPhone sensor recording
│   │
│   ├── Storage/
│   │   ├── StorageService.swift  # CSV I/O
│   │   └── ExportService.swift   # ZIP export
│   │
│   ├── Network/
│   │   ├── APIClient.swift       # HTTP requests (NEW)
│   │   ├── WebSocketService.swift # Real-time updates
│   │   └── Logger.swift          # Remote logging
│   │
│   └── Watch/
│       └── WatchCoordinator.swift # Merged connectivity (NEW)
│
├── Features/
│   ├── Status/
│   │   ├── StatusView.swift
│   │   ├── StatusViewModel.swift
│   │   └── Components/
│   │       ├── SystemMetricsCard.swift
│   │       ├── CameraListCard.swift
│   │       └── StorageCard.swift
│   │
│   ├── Record/
│   │   ├── RecordView.swift
│   │   ├── RecordViewModel.swift
│   │   └── Components/
│   │       ├── DurationDisplay.swift
│   │       ├── SensorGrid.swift
│   │       └── RecordButton.swift
│   │
│   ├── Sessions/
│   │   ├── SessionsView.swift
│   │   ├── SessionsViewModel.swift
│   │   ├── SessionDetailView.swift
│   │   ├── SessionDetailViewModel.swift
│   │   ├── SensorDataView.swift
│   │   ├── SensorDataViewModel.swift
│   │   └── Components/
│   │       ├── SessionRow.swift
│   │       └── SensorChart.swift
│   │
│   └── Settings/
│       ├── SettingsView.swift
│       ├── SettingsViewModel.swift
│       └── Components/
│           └── SettingsRow.swift
│
└── Resources/
    ├── Assets.xcassets
    └── Info.plist
```

---

## Key Architectural Decisions

### 1. Single Config Source

**Before**: 6 files with duplicated IP/timeout logic
**After**: One `AppConfig.swift`

```swift
// Config/AppConfig.swift
enum AppConfig {
    enum Controller {
        static var ip: String {
            UserDefaults.standard.string(forKey: Keys.controllerIP) ?? Defaults.controllerIP
        }
        static var baseURL: URL { URL(string: "http://\(ip):8000")! }
        static var wsURL: URL { URL(string: "ws://\(ip):8000/ws/status")! }
    }

    enum Recording {
        static let sensorFrequency: Double = 1.0
        static let bufferFlushInterval: TimeInterval = 10.0
        static let canPollInterval: TimeInterval = 2.0
    }

    enum Timeouts {
        static let api: TimeInterval = 10.0
        static let watchTransfer: TimeInterval = 30.0
        static let sensorHealth: TimeInterval = 5.0
    }

    private enum Keys {
        static let controllerIP = "controllerIP"
    }

    private enum Defaults {
        static let controllerIP = "192.168.8.145"
    }
}
```

### 2. Unified API Client

**Before**: HTTP requests scattered in ViewModels
**After**: Centralized `APIClient`

```swift
// Services/Network/APIClient.swift
actor APIClient {
    static let shared = APIClient()

    func startRecording(uuid: String) async throws {
        try await post("/api/record/start", query: ["uuid": uuid])
    }

    func stopRecording() async throws {
        try await post("/api/record/stop")
    }

    func getStatus() async throws -> ControllerStatus {
        try await get("/api/status")
    }

    func uploadSession(_ session: Session) async throws -> SyncResponse {
        try await upload("/api/sync/phone", session: session)
    }

    // Private helpers
    private func get<T: Decodable>(_ path: String) async throws -> T { ... }
    private func post(_ path: String, query: [String: String] = [:]) async throws { ... }
}
```

### 3. Merged Watch Coordinator

**Before**: `ConnectivityManager` + `WatchDataTransferManager` (2 delegates)
**After**: Single `WatchCoordinator`

```swift
// Services/Watch/WatchCoordinator.swift
@MainActor
class WatchCoordinator: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchCoordinator()

    // State
    @Published var isReachable = false
    @Published var watchState: WatchRecordingState = .idle
    @Published var transferProgress: Double = 0

    // Commands
    func startRecording(sessionID: String) async -> Bool { ... }
    func stopRecording() async { ... }
    func requestData(sessionID: String) async -> Bool { ... }

    // WCSessionDelegate (all in one place)
    func session(_ session: WCSession, activationDidCompleteWith state: ...) { }
    func session(_ session: WCSession, didReceiveMessage message: ...) { }
    func session(_ session: WCSession, didReceive file: ...) { }
}
```

### 4. Protocol-Based Services

```swift
// For testing/mocking
protocol SensorRecording {
    func startRecording(session: Session) async
    func stopRecording() async
    var isRecording: Bool { get }
}

protocol SessionStorage {
    func save(session: Session) async throws
    func load(id: UUID) async throws -> Session
    func delete(session: Session) async throws
}

// Real implementations
final class SensorManager: SensorRecording { ... }
actor StorageService: SessionStorage { ... }
```

### 5. Feature-Based Modules

Each feature is self-contained:
```
Features/Record/
├── RecordView.swift          # UI
├── RecordViewModel.swift     # Logic
└── Components/               # Feature-specific components
    ├── DurationDisplay.swift
    └── RecordButton.swift
```

---

## Data Flow

### Recording Flow
```
User taps Record
       │
       ▼
RecordView (Button)
       │
       ▼
RecordViewModel.startRecording()
       │
       ├──► WatchCoordinator.startRecording()
       │           │
       │           └──► Watch app starts
       │
       ├──► APIClient.startRecording(uuid)
       │           │
       │           └──► ctlr starts cameras
       │
       └──► SensorManager.startRecording(session)
                   │
                   └──► StorageService.appendCSV()
                              │
                              └──► CSV files on disk
```

### WebSocket Status Flow
```
WebSocketService connects
       │
       ▼
Receives JSON message
       │
       ▼
Parses → updates @Published properties
       │
       ▼
StatusViewModel observes via Combine
       │
       ▼
StatusView re-renders automatically
```

---

## UI Design System (Apple Fitness-Inspired)

### Color Palette
```swift
struct AppColors {
    // Backgrounds
    static let background = Color(.systemBackground)
    static let card = Color(.secondarySystemBackground)
    static let elevated = Color(.tertiarySystemBackground)

    // Semantic
    static let accent = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let recording = Color.red

    // Text
    static let primary = Color(.label)
    static let secondary = Color(.secondaryLabel)
    static let tertiary = Color(.tertiaryLabel)
}
```

### Typography
```swift
struct AppTypography {
    // Display (large numbers)
    static let display = Font.system(size: 48, weight: .bold, design: .rounded)
    static let metric = Font.system(size: 28, weight: .semibold, design: .rounded)

    // Headings
    static let title = Font.title2.weight(.semibold)
    static let headline = Font.headline

    // Body
    static let body = Font.body
    static let caption = Font.caption

    // Monospace (data)
    static let mono = Font.system(.body, design: .monospaced)
}
```

### Core Components

```swift
// Bold metric display (like Fitness workout stats)
struct MetricCard: View {
    let value: String
    let label: String
    let icon: String?
    let color: Color
}

// Circular progress (like Activity rings)
struct ProgressRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
}

// Status indicator
struct StatusBadge: View {
    let status: Status
    enum Status { case connected, disconnected, recording, idle }
}

// Sensor health row
struct SensorRow: View {
    let name: String
    let isHealthy: Bool
    let value: String?
}

// Primary action button
struct ActionButton: View {
    let title: String
    let icon: String
    let style: Style
    let action: () -> Void
    enum Style { case primary, secondary, destructive }
}
```

---

## Files to Delete

| File | Reason |
|------|--------|
| `Core/Components/StatePanel.swift` | Unused |
| `Core/Components/DocumentExporter.swift` | Duplicate of ExportService |
| `Services/ConnectivityManager.swift` | Merged into WatchCoordinator |
| `Services/WatchDataTransferManager.swift` | Merged into WatchCoordinator |
| `Services/HTTPServerService.swift` | Audit: remove if unused |
| Root `Features/` folder | Duplicates at wrong path |

## Files to Create

| File | Purpose |
|------|---------|
| `Config/AppConfig.swift` | Centralized configuration |
| `Services/Network/APIClient.swift` | HTTP request handling |
| `Services/Watch/WatchCoordinator.swift` | Merged watch communication |
| `Core/Utilities/Validators.swift` | Input validation |
| `Core/Utilities/Formatters.swift` | Display formatting |
| `Core/Components/MetricCard.swift` | Fitness-style stat card |
| `Core/Components/ProgressRing.swift` | Circular progress |
| `Core/Components/ActionButton.swift` | Styled buttons |

---

## Migration Strategy

### Phase 1: Foundation (1-2 days)
1. Create `Config/AppConfig.swift`
2. Update all files to use AppConfig
3. Delete dead code files
4. Move files to new folder structure

### Phase 2: Services (1-2 days)
1. Create `APIClient.swift`
2. Create `WatchCoordinator.swift`
3. Update ViewModels to use new services
4. Delete old files

### Phase 3: UI Refresh (2-3 days)
1. Create new core components
2. Update StatusView (Fitness-style)
3. Update RecordView (Fitness-style)
4. Update SessionsView
5. Polish Settings

### Phase 4: Polish (1 day)
1. Add validators
2. Improve error handling
3. Add haptic feedback
4. Test on device

---

## Summary

| Aspect | Current | Target |
|--------|---------|--------|
| Architecture | MVVM (scattered) | Clean MVVM + Services |
| Config locations | 6 | 1 |
| Watch delegates | 2 | 1 |
| HTTP handling | ViewModels | APIClient |
| UI style | Mixed | Apple Fitness |
| Dead code | ~300 lines | 0 |
| Folder depth | Flat | Feature-based |

**Total effort**: ~5-7 days for complete cleanup
**Risk**: Low (incremental, non-breaking changes)
**Benefit**: Maintainable, scalable, clean codebase
