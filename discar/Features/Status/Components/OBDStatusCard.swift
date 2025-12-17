//
//  OBDStatusCard.swift
//  discar
//
//  Created by Drogba on 2025/11/24.
//

import SwiftUI

struct OBDStatusCard: View {
    @ObservedObject var obdService = OBDService.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("OBD-II (Pi)")
                    .font(.headline)
                    .foregroundStyle(.gray)
                
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .padding(2)
                        .background(Circle().stroke(statusColor.opacity(0.3), lineWidth: 2))
                    
                    Text(statusMessage)
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(1)
                }
                
                if obdService.connectionState == .recording || obdService.connectionState == .connected {
                    Text("Samples: \(obdService.samplesCollected)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "car.side.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.blue)
                .opacity(0.8)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private var statusMessage: String {
        switch obdService.connectionState {
        case .disconnected: return "Disconnected"
        case .checking: return "Discovering..."
        case .connected: return "Ready"
        case .recording: return "Recording"
        case .error: return "Error"
        }
    }
    
    private var statusColor: Color {
        switch obdService.connectionState {
        case .disconnected: return .gray
        case .checking: return .orange
        case .connected: return .green
        case .recording: return .red
        case .error: return .red
        }
    }
}

#Preview {
    VStack {
        OBDStatusCard()
            .padding()
    }
}


