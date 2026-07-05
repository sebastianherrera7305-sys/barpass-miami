import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    // Placeholder data
    private let points  = 1240
    private let level   = "Insider"
    private let checkins = 8
    private let nextLevel = "VIP"
    private let nextPoints = 2000

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // Header
                    VStack(spacing: 14) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [amber.opacity(0.3), amber.opacity(0.1)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 80, height: 80)
                                .overlay(Circle().strokeBorder(amber.opacity(0.3), lineWidth: 1.5))
                            Text("🎉")
                                .font(.system(size: 34))
                        }

                        VStack(spacing: 4) {
                            Text("Miami Nightlifer")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                            HStack(spacing: 6) {
                                Text(level)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(amber)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(amber.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().strokeBorder(amber.opacity(0.25)))
                            }
                        }
                    }
                    .padding(.top, 60)

                    // Points card
                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("BarPass Points")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white.opacity(0.4))
                                Text("\(points) BPX")
                                    .font(.system(size: 28, weight: .black, design: .rounded))
                                    .foregroundStyle(amber)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Próximo nivel")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white.opacity(0.4))
                                Text(nextLevel)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [amber, amberB], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * CGFloat(points) / CGFloat(nextPoints), height: 6)
                            }
                        }
                        .frame(height: 6)

                        Text("\(nextPoints - points) BPX para llegar a \(nextLevel)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(18)
                    .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(amber.opacity(0.15)))
                    .padding(.horizontal, 20)

                    // Stats
                    HStack(spacing: 12) {
                        statCard(value: "\(checkins)", label: "Check-ins", icon: "mappin.circle.fill")
                        statCard(value: "3",           label: "Reviews",   icon: "star.fill")
                        statCard(value: "2",           label: "Invitados", icon: "person.2.fill")
                    }
                    .padding(.horizontal, 20)

                    // How to earn
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Cómo ganar puntos")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        VStack(spacing: 10) {
                            earnRow(icon: "mappin.circle.fill", action: "Check-in en venue",    points: "+50 BPX")
                            earnRow(icon: "camera.fill",        action: "Review con foto",       points: "+75 BPX")
                            earnRow(icon: "person.fill.badge.plus", action: "Invitar un amigo", points: "+200 BPX")
                            earnRow(icon: "square.and.arrow.up", action: "Compartir venue",     points: "+25 BPX")
                        }
                    }
                    .padding(18)
                    .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.07)))
                    .padding(.horizontal, 20)

                    Spacer(minLength: 120)
                }
            }
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(amber)
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.07)))
    }

    private func earnRow(icon: String, action: String, points: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(amber)
                .frame(width: 24)
            Text(action)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.7))
            Spacer()
            Text(points)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(amber)
        }
    }
}
