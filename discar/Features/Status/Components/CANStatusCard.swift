//
//  CANStatusCard.swift
//  discar
//

import SwiftUI

struct CANStatusCard: View {
    let connected: Bool
    let frameCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CAN Bus")
                    .font(.headline)
                    .foregroundStyle(.gray)

                HStack {
                    Circle()
                        .fill(connected ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                        .padding(2)
                        .background(Circle().stroke((connected ? Color.green : Color.gray).opacity(0.3), lineWidth: 2))

                    Text(connected ? "Connected" : "Disconnected")
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(1)
                }

                if connected && frameCount > 0 {
                    Text("\(frameCount.formatted()) frames")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "car.side.fill")
                .font(.largeTitle)
                .foregroundStyle(connected ? Color.green : Color.gray)
                .opacity(0.8)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

#Preview {
    VStack(spacing: 20) {
        CANStatusCard(connected: true, frameCount: 12345)
        CANStatusCard(connected: false, frameCount: 0)
    }
    .padding()
}
