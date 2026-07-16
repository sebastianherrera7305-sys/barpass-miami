import SwiftUI

/// Juegos y misiones: trivia diaria + misiones que premian acciones reales.
struct GamificationView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var trivia = TriviaEngine.shared
    @ObservedObject private var missionEngine = MissionEngine.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAnswer: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        triviaCard
                        missionsSection
                        Spacer(minLength: 60)
                    }
                    .padding(BPSpacing.lg)
                }
            }
            .navigationTitle(l10n.t("games.navTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n.t("table.close")) { dismiss() }.foregroundStyle(Color.bpAmber)
                }
            }
            .onAppear {
                trivia.loadTodayQuestion()
                missionEngine.loadMissions()
            }
        }
    }

    // MARK: - Trivia

    private var triviaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("🎯")
                Text(l10n.t("games.trivia"))
                    .font(.bpHeadline()).foregroundStyle(Color.bpInk)
                Spacer()
                Text("+100 XP")
                    .font(.bpScaled(11, weight: .bold)).foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.bpAmber.opacity(0.12), in: Capsule())
            }

            if let q = trivia.todayQuestion {
                Text(l10n.t(q.question))
                    .font(.bpScaled(16, weight: .bold)).foregroundStyle(Color.bpInk)
                    .fixedSize(horizontal: false, vertical: true)

                if trivia.answeredToday {
                    answeredState(q)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                            optionButton(i, option, q)
                        }
                    }
                }
            } else {
                ShimmerSkeleton(height: 60)
            }
        }
        .padding(16)
        .background(Color.bpCardBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpAmber.opacity(0.18)))
    }

    private func optionButton(_ index: Int, _ option: String, _ q: TriviaQuestion) -> some View {
        Button {
            BPHaptics.light()
            selectedAnswer = index
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                _ = trivia.answer(index)
            }
        } label: {
            HStack {
                Text(l10n.t(option))
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpInk.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t(option), hint: l10n.t("games.trivia.hint"), isButton: true)
    }

    private func answeredState(_ q: TriviaQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Reveal each option colored by correctness.
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                let isCorrect = i == q.correctIndex
                let wasPicked = i == selectedAnswer
                HStack {
                    Text(l10n.t(option)).font(.system(size: 14, weight: isCorrect ? .bold : .regular))
                        .foregroundStyle(isCorrect ? Color.bpGreen : (wasPicked ? Color.bpDanger : Color.bpTextSecondary))
                    Spacer()
                    if isCorrect { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.bpGreen) }
                    else if wasPicked { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.bpDanger) }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    (isCorrect ? Color.bpGreen.opacity(0.08) : (wasPicked ? Color.bpDanger.opacity(0.08) : Color.bpInk.opacity(0.03))),
                    in: RoundedRectangle(cornerRadius: BPRadius.md)
                )
            }

            HStack(spacing: 6) {
                Text(trivia.lastAnswerCorrect == true ? l10n.t("games.correct") : l10n.t("games.answered"))
                    .font(.bpScaled(13, weight: .bold))
                    .foregroundStyle(trivia.lastAnswerCorrect == true ? Color.bpGreen : Color.bpTextSecondary)
            }
            Text("💡 \(l10n.t(q.funFact))")
                .font(.bpCaption())
                .foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Missions

    private var missionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("🏆")
                Text(l10n.t("games.missions")).font(.bpHeadline()).foregroundStyle(Color.bpInk)
            }

            if missionEngine.missions.isEmpty {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in ShimmerSkeleton(height: 120) }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(missionEngine.missions) { mission in
                            missionCard(mission)
                        }
                    }
                }
            }
        }
    }

    private func missionCard(_ m: Mission) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: m.isCompleted ? "checkmark.circle.fill" : m.icon)
                    .font(.bpScaled(18))
                    .foregroundStyle(m.isCompleted ? Color.bpGreen : Color.bpAmber)
                Spacer()
                Text("+\(m.xpReward) XP")
                    .font(.bpScaled(10, weight: .bold)).foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.bpAmber.opacity(0.12), in: Capsule())
            }

            Text(l10n.t(m.title)).font(.bpScaled(14, weight: .bold)).foregroundStyle(Color.bpInk)
            Text(l10n.t(m.description)).font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                .lineLimit(2)

            // Progress
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bpInk.opacity(0.08)).frame(height: 5)
                    Capsule().fill(m.isCompleted ? Color.bpGreen : Color.bpAmber)
                        .frame(width: geo.size.width * CGFloat(min(Double(m.progress) / Double(m.requirement), 1)), height: 5)
                }
            }
            .frame(height: 5)

            Text("\(min(m.progress, m.requirement))/\(m.requirement)")
                .font(.bpScaled(10, weight: .semibold))
                .foregroundStyle(m.isCompleted ? Color.bpGreen : Color.bpTextSecondary)
        }
        .padding(14)
        .frame(width: 170)
        .background(Color.bpCardBackground.opacity(m.isCompleted ? 0.5 : 0.9), in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg)
            .strokeBorder(m.isCompleted ? Color.bpGreen.opacity(0.3) : Color.bpInk.opacity(0.08)))
        .opacity(m.isCompleted ? 0.75 : 1)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: String(format: l10n.t("games.mission.a11y"), l10n.t(m.title), m.progress, m.requirement), hint: l10n.t(m.description))
    }
}
