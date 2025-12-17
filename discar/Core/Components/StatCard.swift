//
//  StatCard.swift
//  discar
//

import SwiftUI

// Simple card component for displaying statistics
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .frame(width: 60)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    StatCard(
        title: "Total Sessions",
        value: "42",
        icon: "list.bullet"
    )
    .padding()
}


