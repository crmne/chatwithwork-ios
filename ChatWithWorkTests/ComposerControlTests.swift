import Testing
import UIKit
@testable import ChatWithWork

/// The composer's buttons are the web's touch buttons: 44-point targets
/// painting 34-point squares with 9-point corners (the globe's 5), never
/// circles.
@MainActor
@Suite("Composer controls")
struct ComposerControlTests {
    private func laidOut(_ style: ComposerControl.Style) -> (ComposerControl, UIView) {
        let control = ComposerControl(style: style)
        control.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        control.layoutIfNeeded()
        let plate = control.subviews.first!
        return (control, plate)
    }

    @Test("every style paints a 34-point square inside a 44-point target, with 9-point corners and the globe's 5")
    func geometry() {
        for style in [ComposerControl.Style.ghost, .toggle, .primary, .subtle] {
            let (control, plate) = laidOut(style)
            #expect(control.bounds.size == CGSize(width: 44, height: 44))
            #expect(plate.frame == CGRect(x: 5, y: 5, width: 34, height: 34))
            #expect(plate.layer.cornerRadius == (style == .toggle ? 5 : 9))
        }
    }

    @Test("a ghost button is ink on nothing, with no outline")
    func ghost() {
        let (control, plate) = laidOut(.ghost)
        #expect(control.colors.plate == .clear)
        #expect(control.colors.icon == Palette.ink)
        #expect(plate.layer.borderWidth == 0)
        control.isEnabled = false
        #expect(control.colors.icon == Palette.ink.withAlphaComponent(0.2))
    }

    @Test("send is an ink square, faint when it can't send")
    func primary() {
        let (control, _) = laidOut(.primary)
        #expect(control.colors.plate == Palette.ink)
        #expect(control.colors.icon == Palette.inkInverted)
        control.isEnabled = false
        #expect(control.colors.plate == Palette.ink.withAlphaComponent(0.05))
        #expect(control.colors.icon == Palette.ink.withAlphaComponent(0.1))
    }

    @Test("the globe is muted off, ink on a pressed square on, and faint where it can't search")
    func toggle() {
        let (control, _) = laidOut(.toggle)
        #expect(control.colors.icon == Palette.inkMuted)
        control.isOn = true
        #expect(control.colors.plate == Palette.ink.withAlphaComponent(0.1))
        #expect(control.colors.icon == Palette.ink)
        #expect(control.layer.sublayers?.contains { $0 is CAShapeLayer && !$0.isHidden } == true, "On, the inset shadow shows")
        control.isInert = true
        #expect(control.colors.icon == Palette.inkFaint)
        #expect(control.layer.sublayers?.contains { $0 is CAShapeLayer && !$0.isHidden } == false, "Faint, it doesn't")
    }

    @Test("stop beside send is the subtle button: surface with a strong hairline")
    func subtle() {
        let (control, plate) = laidOut(.subtle)
        #expect(control.colors.plate == Palette.surface)
        #expect(control.colors.edge == Palette.lineStrong)
        #expect(plate.layer.borderWidth == 1)
    }
}
