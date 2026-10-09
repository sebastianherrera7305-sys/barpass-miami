import XCTest
@testable import BarPass_app

/// Covers the one piece of the avatar system that's real logic, not just
/// SwiftUI layout: encoding/decoding `avatar_config` jsonb the same way
/// the Friends RPCs and `profiles.avatar_config` round-trip it.
final class AvatarConfigTests: XCTestCase {

    func test_roundTrip_throughSnakeCaseJSON_matchesWhatTheRPCsSend() throws {
        let config = AvatarConfig(
            skinTone: .brown, hairStyle: .curly, hairColor: .amber,
            accessory: .chain, outfitColor: .purple, expression: .hype
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])

        // These are the literal column-friendly keys avatar_system.sql
        // writes into profiles.avatar_config — a drift here would mean the
        // app and the RPCs disagree on the shape of the same jsonb blob.
        XCTAssertEqual(json["skin_tone"], "brown")
        XCTAssertEqual(json["hair_style"], "curly")
        XCTAssertEqual(json["hair_color"], "amber")
        XCTAssertEqual(json["accessory"], "chain")
        XCTAssertEqual(json["outfit_color"], "purple")
        XCTAssertEqual(json["expression"], "hype")

        let decoded = try JSONDecoder().decode(AvatarConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func test_decode_fromSupabaseStyleSnakeCaseKeys_succeeds() throws {
        // What SupabaseRESTClient.decoder (snake_case key strategy) hands
        // this type after a GET on profiles?select=avatar_config.
        let json = """
        {"skin_tone":"tan","hair_style":"mohawk","hair_color":"silver","accessory":"earring","outfit_color":"green","expression":"cool"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AvatarConfig.self, from: json)
        XCTAssertEqual(decoded.skinTone, .tan)
        XCTAssertEqual(decoded.hairStyle, .mohawk)
        XCTAssertEqual(decoded.accessory, .earring)
    }

    func test_default_isStable_forExistingUsersWithNoAvatarConfig() {
        // A profile that has never touched the editor gets this, not a
        // crash and not a forced random pick — "sensible default" from
        // the spec.
        XCTAssertEqual(AvatarConfig.default.skinTone, .tan)
        XCTAssertEqual(AvatarConfig.default.accessory, .none)
    }

    func test_random_producesAValidConfigEveryTime() {
        for _ in 0..<50 {
            let config = AvatarConfig.random()
            XCTAssertTrue(AvatarConfig.SkinTone.allCases.contains(config.skinTone))
            XCTAssertTrue(AvatarConfig.HairStyle.allCases.contains(config.hairStyle))
            XCTAssertTrue(AvatarConfig.Accessory.allCases.contains(config.accessory))
        }
    }

    func test_baldHairStyle_hasZeroHeight_soNoHairShapeIsDrawn() {
        // AvatarIllustration's `hair` view skips drawing entirely when
        // style == .bald; heightFraction == 0 is the other half of that
        // contract staying true.
        XCTAssertEqual(AvatarConfig.HairStyle.bald.heightFraction, 0)
    }

    func test_everyAccessoryExceptNone_hasASystemImage() {
        for accessory in AvatarConfig.Accessory.allCases where accessory != .none {
            XCTAssertNotNil(accessory.systemImage, "\(accessory) should resolve to a symbol")
        }
        XCTAssertNil(AvatarConfig.Accessory.none.systemImage)
    }
}
