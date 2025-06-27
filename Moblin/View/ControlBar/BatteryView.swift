import SwiftUI

struct BatteryView: View {
    var model: Model
    @ObservedObject var battery: Battery

    private func color(level: Double) -> Color {
        if level < 0.2 {
            return .red
        } else if level < 0.4 {
            return .yellow
        } else {
            return .white
        }
    }

    private func width(level: Double) -> Double {
        if level >= 0.0 && level <= 1.0 {
            return 23 * level
        } else {
            return 0
        }
    }

    private func percentage(level: Double) -> String {
        return String(Int(level * 100))
    }

    private func boltColor() -> Color {
        if model.isBatteryCharging() {
            return .white
        } else {
            return .black
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "bolt.fill")
                .foregroundColor(boltColor())
                .font(.system(size: 10))
            HStack(spacing: 0) {
                if model.database.batteryPercentage {
                    ZStack(alignment: .center) {
                        RoundedRectangle(cornerRadius: 2)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 12)
                        Text(percentage(level: battery.level))
                            .foregroundColor(.black)
                            .font(.system(size: 12))
                            .fixedSize()
                            .bold()
                    }
                } else {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(.gray)
                            .frame(width: 24, height: 12)
                        RoundedRectangle(cornerRadius: 1)
                            .foregroundColor(color(level: battery.level))
                            .padding([.leading], 1)
                            .frame(width: width(level: battery.level), height: 10)
                    }
                }
                Circle()
                    .trim(from: 0.0, to: 0.5)
                    .rotationEffect(.degrees(-90))
                    .foregroundColor(.gray)
                    .frame(width: 4)
            }
            .frame(width: 28, height: 13)
        }
        .padding([.top], 1)
    }
}
