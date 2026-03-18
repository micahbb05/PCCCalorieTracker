import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: WatchCalorieStore

    var body: some View {
        summaryPage
            .background(Color.black.ignoresSafeArea())
    }

    private var summaryPage: some View {
        let remaining = max(store.dailyGoal - store.todaysCalories, 0)
        let stateColor = ringColor(
            consumed: store.todaysCalories,
            goal: store.dailyGoal,
            burned: store.activityCalories,
            goalTypeRaw: store.goalTypeRaw
        )

        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(stateColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text("\(remaining)")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .monospacedDigit()
                    Text("left")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.78, green: 0.81, blue: 0.86))
                }
            }
            .frame(width: 116, height: 116)

            Text("Goal \(store.dailyGoal) cal")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.95, green: 0.96, blue: 0.98))
        }
        .padding(10)
    }

    private var progress: Double {
        guard store.dailyGoal > 0 else { return 0 }
        return min(Double(store.todaysCalories) / Double(store.dailyGoal), 1)
    }

    private func ringColor(consumed: Int, goal: Int, burned: Int, goalTypeRaw: String) -> Color {
        let safeGoal = max(goal, 1)
        let safeBurned = max(burned, 1)
        let safeConsumed = max(consumed, 0)
        if goalTypeRaw == "fixed" {
            if safeConsumed <= safeGoal { return Color.green }
            if safeConsumed < safeBurned { return Color.yellow }
            return Color.red
        }

        let isSurplus = goalTypeRaw == "surplus" || safeGoal > safeBurned

        if isSurplus {
            if safeConsumed < safeBurned { return Color.yellow }
            if safeConsumed <= safeGoal { return Color.green }
            return Color.red
        }
        if safeConsumed > safeBurned { return Color.red }
        if safeConsumed <= safeGoal { return Color.green }
        return Color.yellow
    }
}

#Preview {
    DashboardView()
        .environmentObject(WatchCalorieStore())
}
