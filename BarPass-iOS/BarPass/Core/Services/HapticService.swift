import UIKit

@MainActor
final class HapticService {
    private let impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [
        .light:  UIImpactFeedbackGenerator(style: .light),
        .medium: UIImpactFeedbackGenerator(style: .medium),
        .heavy:  UIImpactFeedbackGenerator(style: .heavy),
        .soft:   UIImpactFeedbackGenerator(style: .soft),
        .rigid:  UIImpactFeedbackGenerator(style: .rigid)
    ]
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator    = UISelectionFeedbackGenerator()

    init() {
        impactGenerators.values.forEach { $0.prepare() }
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        impactGenerators[style]?.impactOccurred()
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
    }

    func selection() {
        selectionGenerator.selectionChanged()
    }
}
