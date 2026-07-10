import Foundation
import SwiftUI

// MARK: - Model

enum MissionType: String, Codable {
    case checkIn, shareVenue, reviewVenue, createTrip, completeTrip, triviaWin
}

struct Mission: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let icon: String            // SF Symbol
    let type: MissionType
    let requirement: Int
    var progress: Int = 0
    let xpReward: Int
    let expiresAt: Date
    var isCompleted: Bool = false
}

// MARK: - Engine

/// Daily missions that reward existing real actions with bonus XP.
/// PointsEngine reports every award here; when a mission completes, the
/// bonus is granted once through PointsEngine (as a non-action bonus so it
/// can't recursively re-trigger missions).
@MainActor
final class MissionEngine: ObservableObject {
    static let shared = MissionEngine()
    private static let key = "bp_missions_state"

    @Published var missions: [Mission] = []

    private struct State: Codable {
        var day: String
        var missions: [Mission]
    }

    private init() { loadMissions() }

    func loadMissions() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(State.self, from: data),
           s.day == Self.dayStamp() {
            missions = s.missions
            return
        }
        missions = Self.generateDaily()
        persist()
    }

    /// Called by PointsEngine after every action award.
    func registerAction(_ type: MissionType) {
        var completedNow: [Mission] = []
        for i in missions.indices where missions[i].type == type && !missions[i].isCompleted {
            missions[i].progress += 1
            if missions[i].progress >= missions[i].requirement {
                missions[i].isCompleted = true
                completedNow.append(missions[i])
            }
        }
        persist()
        // Grant bonuses AFTER mutating state (bonus path never re-enters here).
        for mission in completedNow {
            PointsEngine.shared.awardMissionBonus(mission.xpReward)
        }
    }

    private func persist() {
        let s = State(day: Self.dayStamp(), missions: missions)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static func generateDaily() -> [Mission] {
        let endOfDay = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        // Rotate one slot by weekday so days don't feel identical.
        let weekday = Calendar.current.component(.weekday, from: Date())
        let rotating: Mission = weekday % 2 == 0
            ? Mission(id: "m-trip", title: "Armá una noche", description: "Creá 1 trip con Prompt Your Night",
                      icon: "sparkles", type: .createTrip, requirement: 1, xpReward: 100, expiresAt: endOfDay)
            : Mission(id: "m-trivia", title: "Trivia master", description: "Acertá la trivia de hoy",
                      icon: "brain.head.profile", type: .triviaWin, requirement: 1, xpReward: 50, expiresAt: endOfDay)

        return [
            Mission(id: "m-checkin", title: "Salí esta noche", description: "Check-in en 2 venues hoy",
                    icon: "mappin.and.ellipse", type: .checkIn, requirement: 2, xpReward: 150, expiresAt: endOfDay),
            Mission(id: "m-share", title: "Corré la voz", description: "Compartí 1 venue con tu gente",
                    icon: "square.and.arrow.up", type: .shareVenue, requirement: 1, xpReward: 50, expiresAt: endOfDay),
            rotating,
        ]
    }

    private static func dayStamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
