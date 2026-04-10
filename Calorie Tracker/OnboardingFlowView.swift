import SwiftUI

struct OnboardingFlowView: View {
    @Binding var currentPage: Int
    @Binding var deficitCalories: Int
    @Binding var goalTypeRaw: String
    @Binding var surplusCalories: Int
    @Binding var fixedGoalCalories: Int
    @Binding var manualBMRCalories: Int
    @Binding var bmrSourceRaw: String
    @Binding var trackedNutrientKeys: [String]
    @Binding var nutrientGoals: [String: Int]
    let availableNutrients: [NutrientDefinition]
    let healthAuthorizationState: HealthKitService.AuthorizationState
    let healthProfile: HealthKitService.SyncedProfile?
    let hasRequestedHealthAccess: Bool
    let backgroundTop: Color
    let backgroundBottom: Color
    let surfacePrimary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onRequestHealthAccess: () -> Void
    let onSkip: () -> Void
    let onFinish: () -> Void

    private let pageCount = 4

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [backgroundTop, backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                TabView(selection: $currentPage) {
                    onboardingCard {
                        welcomeSlide
                    }
                    .tag(0)

                    onboardingCard {
                        healthSlide
                    }
                    .tag(1)

                    onboardingCard {
                        deficitSlide
                    }
                    .tag(2)

                    onboardingCard {
                        nutrientSlide
                    }
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .onAppear(perform: ensureNutrientGoalsExist)
        .onChange(of: trackedNutrientKeys) { _, _ in
            ensureNutrientGoalsExist()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Welcome")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)

                Spacer()

                if currentPage < pageCount - 1 {
                    Button("Skip", action: onSkip)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textSecondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == currentPage ? accent : Color.white.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: 6)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
        }
        .padding(.bottom, 20)
    }

    private func onboardingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .frame(minHeight: 580, alignment: .top)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(surfacePrimary.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(textSecondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 12)
    }

    private var welcomeSlide: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Calorie Tracker")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)

                Text("Set up the app once and start logging with calorie goals, Health data, and the nutrients that matter to you.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(textSecondary)
            }

            VStack(spacing: 14) {
                welcomeFeatureCard(
                    icon: "heart.text.square.fill",
                    title: "Connect Health",
                    detail: "Optional: use Apple Health for automatic BMR and more accurate step-calorie estimates.",
                    tint: Color(red: 0.46, green: 0.90, blue: 0.60)
                )
                welcomeFeatureCard(
                    icon: "target",
                    title: "Deficit, surplus, or fixed",
                    detail: "Choose a dynamic goal from burn (deficit/surplus) or a fixed daily calorie target.",
                    tint: accent
                )
                welcomeFeatureCard(
                    icon: "list.bullet.rectangle.portrait.fill",
                    title: "Pick nutrients",
                    detail: "Control which nutrient fields and progress cards appear across the app.",
                    tint: Color(red: 0.96, green: 0.63, blue: 0.28)
                )
            }
        }
    }

    private var healthSlide: some View {
        VStack(alignment: .leading, spacing: 18) {
            slideHeading(
                eyebrow: "Slide 2 of 4",
                title: "Connect Apple Health",
                detail: "Read height, weight, sex, and age so the app can calculate BMR and personalize step-calorie estimates."
            )

            if let healthProfile, healthAuthorizationState == .connected {
                HStack {
                    statusBadge(title: healthAuthorizationState.title, isConnected: true)
                    Spacer()
                }

                HStack(spacing: 10) {
                    healthValueChip(title: "Sex", value: healthProfile.bmrProfile.sex.title)
                    healthValueChip(title: "Height", value: healthProfile.heightDisplay)
                    healthValueChip(title: "Weight", value: healthProfile.weightDisplay)
                }

                Text("Health is connected. The app will keep using the latest profile data it can read from Apple Health.")
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: onRequestHealthAccess) {
                        Text("Connect Apple Health")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    Text(healthFallbackText)
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("BMR Source")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textPrimary)

                Picker("BMR Source", selection: $bmrSourceRaw) {
                    Text("Automatic").tag(ContentView.BMRSource.automatic.rawValue)
                    Text("Manual").tag(ContentView.BMRSource.manual.rawValue)
                }
                .pickerStyle(.segmented)

                if bmrSourceRaw == ContentView.BMRSource.manual.rawValue {
                    DeficitGoalEditor(
                        deficitCalories: $manualBMRCalories,
                        title: "Manual BMR",
                        subtitle: "Calories burned at rest each day",
                        helperText: "This value will be used for calorie targets until you switch BMR Source back to Automatic.",
                        accent: accent,
                        minCalories: 800,
                        maxCalories: 4000
                    )
                }
            }
        }
    }

    private var deficitSlide: some View {
        return VStack(alignment: .leading, spacing: 18) {
            slideHeading(
                eyebrow: "Slide 3 of 4",
                title: goalTypeRaw == "fixed" ? "Set Your Fixed Goal" : (goalTypeRaw == "surplus" ? "Set Your Surplus Goal" : "Set Your Deficit Goal"),
                detail: goalTypeRaw == "fixed"
                    ? "This is your direct daily intake target, independent of calories burned."
                    : (goalTypeRaw == "surplus"
                        ? "This amount is added to calories burned to create your daily intake target."
                        : "This amount is subtracted from calories burned to create your daily intake target.")
            )

            Picker("Goal Type", selection: $goalTypeRaw) {
                Text("Deficit").tag("deficit")
                Text("Surplus").tag("surplus")
                Text("Fixed").tag("fixed")
            }
            .pickerStyle(.segmented)

            if goalTypeRaw == "deficit" {
                DeficitGoalEditor(
                    deficitCalories: $deficitCalories,
                    title: "Daily deficit",
                    subtitle: "Common moderate range: 250-500 cal",
                    helperText: "You can change this later in Profile. The app allows any value from 0 to 2500 calories.",
                    accent: accent
                )
            } else if goalTypeRaw == "surplus" {
                DeficitGoalEditor(
                    deficitCalories: $surplusCalories,
                    title: "Daily surplus",
                    subtitle: "Common moderate range: 200-500 cal",
                    helperText: "You can change this later in Profile. The app allows any value from 0 to 2500 calories.",
                    accent: accent
                )
            } else {
                DeficitGoalEditor(
                    deficitCalories: $fixedGoalCalories,
                    title: "Daily calorie goal",
                    subtitle: "Total calories to eat per day",
                    helperText: "You can change this later in Profile. The app allows any value from 1 to 6000 calories.",
                    accent: accent,
                    maxCalories: 6000
                )
            }
        }
    }

    private var nutrientSlide: some View {
        VStack(alignment: .leading, spacing: 18) {
            slideHeading(
                eyebrow: "Slide 4 of 4",
                title: "Choose Nutrients to Track",
                detail: "Your selections determine which nutrient inputs, progress cards, and goals appear throughout the app."
            )

            Text("You can change this later in Settings. Deselect all to track calories only.")
                .font(.subheadline)
                .foregroundStyle(textSecondary)

            NutrientSelectionList(
                trackedNutrientKeys: $trackedNutrientKeys,
                availableNutrients: availableNutrients
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if currentPage > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = max(currentPage - 1, 0)
                    }
                } label: {
                    Text("Back")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                if currentPage == pageCount - 1 {
                    onFinish()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = min(currentPage + 1, pageCount - 1)
                    }
                }
            } label: {
                Text(currentPage == pageCount - 1 ? "Finish" : "Continue")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accent)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 18)
    }

    private var healthFallbackText: String {
        switch healthAuthorizationState {
        case .connected:
            return "Health is connected."
        case .unavailable:
            return "Health data is not available on this device. You can continue with a manual BMR."
        case .notConnected:
            if hasRequestedHealthAccess {
                return "If you skipped or denied access, onboarding can still continue. You can keep using manual BMR or connect Health later from Profile."
            }
            return "Health is optional. If you skip it now, the app uses your manual BMR."
        }
    }

    private func welcomeFeatureCard(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func slideHeading(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(textPrimary)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(textSecondary)
        }
    }

    private func statusBadge(title: String, isConnected: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isConnected ? Color(red: 0.46, green: 0.90, blue: 0.60) : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isConnected ? Color(red: 0.13, green: 0.28, blue: 0.18) : Color.white.opacity(0.08))
            )
    }

    private func healthValueChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func ensureNutrientGoalsExist() {
        for key in trackedNutrientKeys {
            if nutrientGoals[key] == nil {
                nutrientGoals[key] = NutrientCatalog.definition(for: key).defaultGoal
            }
        }
    }
}
