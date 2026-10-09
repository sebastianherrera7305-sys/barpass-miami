import SwiftUI

/// The user's illustrated avatar, stored as `profiles.avatar_config`
/// (jsonb). Every field is a closed enum, never free text — the same
/// discipline `search_profiles()` already applies to display names, just
/// extended to the one other identity field a user controls directly.
///
/// `avatarUrl` (an uploaded photo) still wins over this when both are
/// set — see `AvatarView.swift` for the one place that precedence is
/// decided. This type only describes the drawn fallback/alternative.
struct AvatarConfig: Codable, Equatable, Hashable, Sendable {
    var skinTone: SkinTone
    var hairStyle: HairStyle
    var hairColor: HairColor
    var accessory: Accessory
    var outfitColor: OutfitColor
    var expression: Expression

    enum CodingKeys: String, CodingKey {
        case skinTone = "skin_tone"
        case hairStyle = "hair_style"
        case hairColor = "hair_color"
        case accessory
        case outfitColor = "outfit_color"
        case expression
    }

    static let `default` = AvatarConfig(
        skinTone: .tan, hairStyle: .short, hairColor: .black,
        accessory: .none, outfitColor: .amber, expression: .smile
    )

    static func random() -> AvatarConfig {
        AvatarConfig(
            skinTone: SkinTone.allCases.randomElement()!,
            hairStyle: HairStyle.allCases.randomElement()!,
            hairColor: HairColor.allCases.randomElement()!,
            accessory: Accessory.allCases.randomElement()!,
            outfitColor: OutfitColor.allCases.randomElement()!,
            expression: Expression.allCases.randomElement()!
        )
    }

    enum SkinTone: String, Codable, CaseIterable, Sendable {
        case porcelain, fair, tan, brown, deep

        var color: Color {
            switch self {
            case .porcelain: return Color(red: 0.96, green: 0.84, blue: 0.75)
            case .fair: return Color(red: 0.92, green: 0.74, blue: 0.60)
            case .tan: return Color(red: 0.80, green: 0.58, blue: 0.42)
            case .brown: return Color(red: 0.58, green: 0.38, blue: 0.26)
            case .deep: return Color(red: 0.36, green: 0.23, blue: 0.16)
            }
        }
    }

    enum HairStyle: String, Codable, CaseIterable, Sendable {
        case bald, buzz, short, curly, long, mohawk

        /// How tall above the head the hair silhouette reaches, as a
        /// fraction of head radius — used by `AvatarHeadView` to size the
        /// shape without any external art.
        var heightFraction: CGFloat {
            switch self {
            case .bald: return 0
            case .buzz: return 0.08
            case .short: return 0.18
            case .curly: return 0.30
            case .long: return 0.22
            case .mohawk: return 0.45
            }
        }
    }

    enum HairColor: String, Codable, CaseIterable, Sendable {
        case black, brown, blonde, red, silver, amber

        var color: Color {
            switch self {
            case .black: return Color(white: 0.08)
            case .brown: return Color(red: 0.32, green: 0.20, blue: 0.12)
            case .blonde: return Color(red: 0.85, green: 0.70, blue: 0.40)
            case .red: return Color(red: 0.60, green: 0.20, blue: 0.12)
            case .silver: return Color(white: 0.75)
            case .amber: return Color.bpAmber
            }
        }
    }

    enum Accessory: String, Codable, CaseIterable, Sendable {
        case none, sunglasses, cap, bucketHat, chain, earring

        var systemImage: String? {
            switch self {
            case .none: return nil
            case .sunglasses: return "sunglasses.fill"
            case .cap: return "cricket.ball.fill" // placeholder silhouette, see AvatarHeadView
            case .bucketHat: return "mountain.2.fill"
            case .chain: return "link"
            case .earring: return "circle.fill"
            }
        }
    }

    enum OutfitColor: String, Codable, CaseIterable, Sendable {
        case amber, ink, green, danger, purple, white

        var color: Color {
            switch self {
            case .amber: return Color.bpAmber
            case .ink: return Color.bpInk
            case .green: return Color.bpGreen
            case .danger: return Color.bpDanger
            case .purple: return Color(red: 0.55, green: 0.40, blue: 0.95)
            case .white: return Color.white.opacity(0.85)
            }
        }
    }

    enum Expression: String, Codable, CaseIterable, Sendable {
        case smile, neutral, cool, hype

        /// Mouth curve as a simple bezier control offset — positive
        /// curves up (smile), 0 is flat, negative would curve down (kept
        /// out of the enum on purpose: a sad face at a nightlife app has
        /// no use).
        var mouthCurve: CGFloat {
            switch self {
            case .smile: return 6
            case .neutral: return 0
            case .cool: return 2
            case .hype: return 9
            }
        }
    }
}
