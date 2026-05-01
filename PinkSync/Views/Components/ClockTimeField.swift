import SwiftUI

struct ClockTimeField: View {
    @Binding var time: String

    @State private var minutes = 10
    @State private var seconds = 0

    var body: some View {
        HStack(spacing: 0) {
            Picker("Minutes", selection: $minutes) {
                ForEach(0...20, id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 70)
            .clipped()

            Text(":")
                .font(.system(size: 28, weight: .bold, design: .monospaced))

            Picker("Seconds", selection: $seconds) {
                ForEach(0...59, id: \.self) { s in
                    Text(String(format: "%02d", s)).tag(s)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 70)
            .clipped()
        }
        .frame(height: 120)
        .onAppear {
            parseTime()
        }
        .onChange(of: minutes) { _, _ in syncTime() }
        .onChange(of: seconds) { _, _ in syncTime() }
    }

    private func parseTime() {
        let parts = time.split(separator: ":")
        if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) {
            minutes = m
            seconds = s
        }
    }

    private func syncTime() {
        time = String(format: "%02d:%02d", minutes, seconds)
    }
}
