# Discar Refactoring Plan

Inspired by Apple Fitness app - clean, minimal, focused on key data.

## Executive Summary

**Current State**: 9,100+ lines across 36 Swift files
**Goal**: Clean, maintainable codebase with Apple Fitness-inspired UI

---

## Phase 1: Immediate Cleanup (Dead Code Removal)

### Files to Delete

| File | Reason |
|------|--------|
| `Core/Components/StatePanel.swift` | No references found, unused |
| `Core/Components/DocumentExporter.swift` | Overlaps with ExportService, unused |
| `Features/` (root level duplicates) | Old files at wrong path, use `discar/Features/` |

### Files to Audit

| File | Issue |
|------|-------|
| `Services/HTTPServerService.swift` | 520+ lines, purpose unclear - document or remove |
| `Services/OBDService.swift` | Mentioned in old README but not in codebase - already removed? |

---

## Phase 2: Configuration Centralization

### Create: `Core/Config/AppConfig.swift`

```swift
import Foundation

enum AppConfig {

    enum Controller {
        static var ip: String {
            UserDefaults.standard.string(forKey: "controllerIP") ?? "192.168.8.145"
        }
        static var baseURL: String { "http://\(ip):8000" }
        static var wsURL: String { "ws://\(ip):8000/ws/status" }

        static let apiTimeout: TimeInterval = 10.0
        static let pingInterval: TimeInterval = 25.0
        static let maxReconnectAttempts = 10
    }

    enum Recording {
        static let bufferFlushInterval: TimeInterval = 10.0
        static let sensorTimeout: TimeInterval = 5.0
        static let canPollInterval: TimeInterval = 2.0
        static let sensorFrequency: Double = 1.0  // Hz
    }

    enum UI {
        static let chartMaxPoints = 100
        static let previewRowCount = 20
    }

    enum Export {
        static let cleanupAge: TimeInterval = 3600  // 1 hour
    }
}
```

### Files to Update (remove duplicated IP logic)

- `RecordViewModel.swift` - use `AppConfig.Controller.ip`
- `StatusViewModel.swift` - use `AppConfig.Controller.baseURL`
- `SettingsViewModel.swift` - use `AppConfig.Controller.ip`
- `WebSocketService.swift` - use `AppConfig.Controller.wsURL`
- `StorageService.swift` - use `AppConfig.Controller.baseURL`
- `Logger.swift` - use `AppConfig.Controller.baseURL`

---

## Phase 3: SensorDataViewModel Refactor

### Problem
279 lines with 10 nearly-identical switch cases for data processing.

### Solution: Generic Data Processor

```swift
// New: Core/Data/SensorDataProcessor.swift

protocol SensorDataProcessing {
    associatedtype Reading: Codable
    static func chartPoint(from reading: Reading, index: Int) -> ChartDataPoint
    static func previewString(from reading: Reading) -> String
}

// New: SensorDataViewModel refactored
@MainActor
class SensorDataViewModel: ObservableObject {

    func loadData() async throws {
        let processor = SensorProcessorFactory.processor(for: sensorType)
        let data = try await processor.load(session: session)

        statistics = processor.computeStatistics(data)
        chartData = processor.generateChartData(data, maxPoints: AppConfig.UI.chartMaxPoints)
        rawDataPreview = processor.generatePreview(data, count: AppConfig.UI.previewRowCount)
    }
}
```

**Lines saved**: ~150 (from 279 to ~130)

---

## Phase 4: Apple Fitness-Inspired UI

### Design Principles (from Apple Fitness)

1. **Cards with purpose** - Each card shows one metric clearly
2. **Activity rings style** - Circular progress for completion
3. **Bold numbers** - Large, prominent statistics
4. **Subtle labels** - Small, secondary text
5. **Generous spacing** - Breathing room between elements
6. **SF Symbols** - Consistent iconography
7. **System colors** - Adapts to light/dark mode

### UI Components to Create

```swift
// Core/Components/MetricCard.swift
struct MetricCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// Core/Components/ProgressRing.swift
struct ProgressRing: View {
    let progress: Double  // 0.0 - 1.0
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
```

### Screen Redesigns

#### Status Tab (Fitness-style)
```
┌─────────────────────────────────────┐
│  Controller Status                  │
│  ┌─────────┐  ┌─────────┐          │
│  │  ◉ Ready │  │ ● Recording       │
│  └─────────┘  └─────────┘          │
├─────────────────────────────────────┤
│  System          ┌───────┐          │
│  ┌─────┬─────┐   │  52°  │          │
│  │ 45% │ 62% │   │  ───  │          │
│  │ CPU │ MEM │   │ Temp  │          │
│  └─────┴─────┘   └───────┘          │
├─────────────────────────────────────┤
│  Cameras                            │
│  ┌─────────────────────────────┐   │
│  │ cam-01    ● Recording   52° │   │
│  │ cam-02    ● Recording   58° │   │
│  │ cam-03    ○ Idle        48° │   │
│  └─────────────────────────────┘   │
├─────────────────────────────────────┤
│  Storage                            │
│  ┌────────────┐ ┌────────────┐     │
│  │ Logging    │ │ Sync       │     │
│  │ ████████░░ │ │ ██████████ │     │
│  │ 450 GB     │ │ 1.2 TB     │     │
│  └────────────┘ └────────────┘     │
└─────────────────────────────────────┘
```

#### Record Tab (Fitness-style workout)
```
┌─────────────────────────────────────┐
│           ┌─────────┐               │
│           │  12:34  │               │
│           │ Duration│               │
│           └─────────┘               │
│                                     │
│     ┌─────┐   ┌─────┐   ┌─────┐    │
│     │ GPS │   │ IMU │   │ CAN │    │
│     │  ●  │   │  ●  │   │  ●  │    │
│     └─────┘   └─────┘   └─────┘    │
│                                     │
│  ┌─────────────────────────────┐   │
│  │                             │   │
│  │       [ STOP ]              │   │
│  │                             │   │
│  └─────────────────────────────┘   │
│                                     │
│  ⌚ Watch: Connected                │
└─────────────────────────────────────┘
```

---

## Phase 5: Watch Coordinator Consolidation

### Problem
Two classes handle WCSession: `ConnectivityManager` + `WatchDataTransferManager`

### Solution: Single Coordinator

```swift
// Services/WatchCoordinator.swift (merge both files)

@MainActor
class WatchCoordinator: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchCoordinator()

    // From ConnectivityManager
    @Published var isWatchReachable = false
    @Published var watchRecordingState: WatchRecordingState = .idle

    // From WatchDataTransferManager
    @Published var transferProgress: Double = 0
    @Published var isTransferring = false

    // Unified delegate methods
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { }
    func session(_ session: WCSession, didReceive file: WCSessionFile) { }
    func session(_ session: WCSession, didFinishFileTransfer: WCSessionFileTransfer, error: Error?) { }
}
```

**Files merged**: `ConnectivityManager.swift` + `WatchDataTransferManager.swift` → `WatchCoordinator.swift`

---

## Phase 6: Remove Legacy Data Formats

### Current (3 formats)
1. CSV (modern) ✓
2. JSON Array (legacy)
3. NDJSON (legacy)

### Target (1 format)
1. CSV only

### Migration
1. Add data migration on app launch
2. Convert any JSON/NDJSON to CSV
3. Remove legacy parsing code from `StorageService.swift`

**Lines removed**: ~50

---

## Phase 7: Background Task Cleanup

### Problem
`ExportService.cleanupOldExports()` never called

### Solution
```swift
// In discarApp.swift
@main
struct discarApp: App {
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task {
                    try? await ExportService.shared.cleanupOldExports()
                }
            }
        }
    }
}
```

---

## Phase 8: Input Validation

### Add URL/IP Validation
```swift
// Core/Validation/Validators.swift

enum Validators {
    static func isValidIP(_ string: String) -> Bool {
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part) else { return false }
            return (0...255).contains(num)
        }
    }

    static func isValidUUID(_ string: String) -> Bool {
        UUID(uuidString: string) != nil
    }
}
```

---

## Summary: Files Changed

### Delete (3 files)
- `Core/Components/StatePanel.swift`
- `Core/Components/DocumentExporter.swift`
- Root level `Features/` duplicates

### Create (4 files)
- `Core/Config/AppConfig.swift`
- `Core/Components/MetricCard.swift`
- `Core/Components/ProgressRing.swift`
- `Core/Validation/Validators.swift`

### Merge (2 → 1)
- `ConnectivityManager.swift` + `WatchDataTransferManager.swift` → `WatchCoordinator.swift`

### Refactor (major changes)
- `SensorDataViewModel.swift` - Generic processor
- `StatusView.swift` - Fitness-style UI
- `RecordView.swift` - Fitness-style UI
- All ViewModels - Use AppConfig

### Cleanup (minor changes)
- `StorageService.swift` - Remove legacy formats
- `discarApp.swift` - Add cleanup task
- `SettingsViewModel.swift` - Add validation

---

## Estimated Impact

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Swift files | 36 | 34 | -2 |
| Total lines | 9,100 | ~8,200 | -900 |
| Config locations | 6 | 1 | -5 |
| Data formats | 3 | 1 | -2 |
| WCSession delegates | 2 | 1 | -1 |

---

## Priority Order

1. **Phase 1**: Delete dead code (immediate, low risk)
2. **Phase 2**: AppConfig (high impact, moderate effort)
3. **Phase 4**: UI redesign (user-facing, high effort)
4. **Phase 5**: Watch consolidation (reduces complexity)
5. **Phase 3**: ViewModel refactor (code quality)
6. **Phase 6**: Legacy removal (cleanup)
7. **Phase 7-8**: Polish (minor improvements)
