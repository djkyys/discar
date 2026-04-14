# discar - iOS Companion App

iOS app for the multi-camera recording system. Captures phone sensor data synchronized with camera recordings.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  iOS App (discar)                                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Status    │    │   Record    │    │  Sessions   │     │
│  │    View     │    │    View     │    │    View     │     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘     │
│         │                  │                  │             │
│         │           ┌──────▼──────┐           │             │
│         └──────────►│  Services   │◄──────────┘             │
│                     │             │                         │
│                     ├─────────────┤                         │
│                     │ SensorService│ ◄── CoreMotion        │
│                     │ StorageService│◄── CSV files         │
│                     │ OBDService   │ ◄── Bluetooth OBD     │
│                     └─────────────┘                         │
│                            │                                │
└────────────────────────────┼────────────────────────────────┘
                             │ HTTP
                             ▼
                      ┌─────────────┐
                      │   ctlr      │
                      │  (Pi 4)     │
                      └─────────────┘
```

## Features

### Status View
- Controller connection status
- Camera status cards (supports 2+ cameras dynamically):
  - State (idle/recording)
  - Current segment
  - System stats (CPU, temp, disk)
  - Sync status (segments synced/pending)
- Controller storage and system stats
- **Storage health card**:
  - Logging mount status + free space
  - Sync mount status + free space
  - Remount button if storage issues detected
  - Eject Sync Drive button for safe USB removal

### Record View
- Start/stop recording (test mode or via controller)
- Real-time sensor data display
- Supported sensors:
  - Accelerometer
  - Gyroscope
  - Magnetometer
  - Barometer
  - GPS
  - Device Motion (attitude, rotation)
  - AirPods Motion
  - Heading (compass)
  - Gravity (separated from Device Motion)
  - Orientation (yaw, roll, pitch, quaternion)

### Sessions View
- List of recorded sessions
- Session details:
  - Duration
  - Sensor data counts
  - Data visualization
- **Sync to Controller**:
  - Preflight checks (camera sync status)
  - Upload phone sensor CSVs
  - Triggers post-processing on ctlr

## Data Flow

### Recording
```
1. User starts recording (or ctlr triggers via UUID)
2. SensorService captures data at configured Hz
3. Data buffered in memory
4. Periodically flushed to CSV files
5. Session saved to SwiftData
```

### Sync
```
1. User opens session detail
2. App fetches /api/sync/status from ctlr
3. Shows camera sync status (per camera)
4. If all cameras synced:
   a. User taps "Upload Phone Data"
   b. App POSTs CSVs to /api/sync/phone
   c. ctlr saves to /mnt/logging/phone/{uuid}/
   d. ctlr triggers postprocess.py
5. Session marked as synced
```

### Storage Health
```
1. StatusView polls /api/storage/status
2. Shows mount status for logging + sync drives
3. If unhealthy, displays "Remount" button
4. User taps button → POST /api/storage/remount
5. ctlr unmounts and remounts drives
6. Status refreshes automatically

Safe Drive Removal:
1. User taps "Eject Sync Drive" button
2. App POSTs to /api/storage/unmount?mount=sync
3. ctlr flushes buffers and unmounts exFAT drive
4. User can safely remove USB drive
```

## File Structure

```
discar/
├── Features/
│   ├── Status/
│   │   ├── StatusView.swift        # Main status screen + StorageHealthCard
│   │   └── StatusViewModel.swift   # Polling + state + remount
│   │
│   ├── Record/
│   │   ├── RecordView.swift        # Recording UI
│   │   └── RecordViewModel.swift   # Sensor coordination
│   │
│   ├── Sessions/
│   │   ├── SessionsView.swift      # Session list
│   │   ├── SessionDetailView.swift # Detail + sync card
│   │   └── SensorDataView.swift    # Data visualization
│   │
│   └── Settings/
│       └── SettingsView.swift      # App configuration
│
├── Services/
│   ├── SensorService.swift         # CoreMotion wrapper
│   ├── StorageService.swift        # CSV + sync upload
│   ├── OBDService.swift           # Bluetooth OBD-II
│   └── ExportService.swift        # ZIP export
│
├── Models/
│   ├── Session.swift              # SwiftData model
│   └── SensorData.swift           # Sensor data types + CSV
│
└── App/
    └── discarApp.swift            # App entry point
```

## Configuration

Settings screen allows:
- **Controller IP**: Default `192.168.8.145`
- **OBD Service**: Enable/disable Bluetooth OBD
- **Test Connection**: Verify controller connectivity

## Sensor Data Format

All sensor data saved as CSV. Every file includes:
- `time`: Seconds elapsed since recording start
- `datetime`: Melbourne timezone timestamp (YYYY-MM-DD HH:mm:ss.SSS)

| Sensor | Columns |
|--------|---------|
| Accelerometer | time, datetime, x, y, z |
| Gyroscope | time, datetime, x, y, z |
| Magnetometer | time, datetime, x, y, z |
| Barometer | time, datetime, pressure, relativeAltitude |
| GPS | time, datetime, lat, lon, altitude, speed, course, horizontalAccuracy, ... |
| Device Motion | time, datetime, roll, pitch, yaw, qx, qy, qz, qw, rotMatrix, userAccel, gravity, rotRate, magField, heading |
| Headphone Motion | time, datetime, (same as Device Motion) |
| Heading | time, datetime, magneticHeading, trueHeading, accuracy, x, y, z |
| **Gravity** | time, datetime, x, y, z |
| **Orientation** | time, datetime, yaw, roll, pitch, qx, qy, qz, qw |

## Session Storage

```
Documents/Sessions/{date}_{shortid}/
├── accelerometer.csv
├── gyroscope.csv
├── magnetometer.csv
├── barometer.csv
├── gps.csv
├── devicemotion.csv
├── headphonemotion.csv
├── heading.csv
├── gravity.csv         # Separated from devicemotion
├── orientation.csv     # Separated from devicemotion
└── metadata.json
```

Note: `{shortid}` is the first 6 characters of the controller's recording UUID.

## Sync Preflight Checks

Before uploading phone data, the app verifies:
1. Recording is stopped
2. No cameras actively syncing
3. All camera segments received on ctlr
4. Storage mounts are healthy

This ensures complete data before post-processing.

## API Endpoints Used

| Endpoint | Purpose |
|----------|---------|
| `GET /api/status` | Poll camera/controller status |
| `GET /api/sync/status` | Preflight check before upload |
| `POST /api/sync/phone` | Upload phone sensor data |
| `GET /api/storage/status` | Check SSD mount health |
| `POST /api/storage/remount` | Remount stale drives |
| `POST /api/storage/unmount?mount=sync` | Safely eject sync drive |

## Dependencies

- SwiftUI
- SwiftData
- CoreMotion
- CoreLocation
- CoreBluetooth (OBD)
