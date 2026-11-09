import Testing
import UIKit
@testable import ChatWithWork

/// The composer's buttons are the web's touch buttons: 44-point targets
/// painting 34-point squares with 9-point corners, never circles.
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

    @Test("every style paints a 34-point square inside a 44-point target, with 9-point corners, the globe's too")
    func geometry() {
        for style in [ComposerControl.Style.ghost, .toggle, .primary, .subtle] {
            let (control, plate) = laidOut(style)
            #expect(control.bounds.size == CGSize(width: 44, height: 44))
            #expect(plate.frame == CGRect(x: 5, y: 5, width: 34, height: 34))
            #expect(plate.layer.cornerRadius == 9)
            #expect(plate.layer.cornerCurve == .continuous)
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

    @Test("the globe is a muted outline off, filled ink on a quiet wash on, and faint where it can't search")
    func toggle() throws {
        let (control, plate) = laidOut(.toggle)
        control.setIcon("Globe", on: "GlobeFill")
        let outline = try #require(UIImage(named: "Globe"))
        let filled = try #require(UIImage(named: "GlobeFill"))
        #expect(control.colors.plate == .clear)
        #expect(control.colors.icon == Palette.inkMuted)
        #expect(control.iconImage?.size == outline.size)
        #expect(control.iconImage?.pngData() == outline.withRenderingMode(.alwaysTemplate).pngData())
        control.isHighlighted = true
        #expect(control.colors.plate == Palette.ink.withAlphaComponent(0.07))
        control.isHighlighted = false

        control.isOn = true
        #expect(control.colors.plate == Palette.ink.withAlphaComponent(0.08))
        #expect(control.colors.icon == Palette.ink)
        #expect(control.colors.edge == nil)
        #expect(control.iconImage?.pngData() == filled.withRenderingMode(.alwaysTemplate).pngData())
        #expect(control.iconImage?.size == outline.size, "The filled globe is the outline's size")
        #expect(plate.layer.borderWidth == 0 && plate.layer.shadowOpacity == 0)
        #expect(control.layer.sublayers?.contains { $0 is CAShapeLayer } == false, "No inset shadow round the target")
        control.isHighlighted = true
        #expect(control.colors.plate == Palette.ink.withAlphaComponent(0.13))
        control.isHighlighted = false

        control.isOn = false
        control.isInert = true
        #expect(control.colors.plate == .clear)
        #expect(control.colors.icon == Palette.inkFaint)
        #expect(control.iconImage?.pngData() == outline.withRenderingMode(.alwaysTemplate).pngData())
        // Locked while on, as the web's aria-pressed one: still filled, but faint on nothing.
        control.isOn = true
        #expect(control.colors.plate == .clear && control.colors.icon == Palette.inkFaint)
        #expect(control.iconImage?.pngData() == filled.withRenderingMode(.alwaysTemplate).pngData())
    }

    @Test("send beside stop is the subtle button: the surface, its hairline hidden as on the web's touch bar")
    func subtle() {
        let (control, plate) = laidOut(.subtle)
        #expect(control.colors.plate == Palette.surface)
        #expect(control.colors.icon == Palette.ink)
        #expect(control.colors.edge == nil)
        #expect(plate.layer.borderWidth == 0)
    }

    @Test("UIKit never dims the icon a second time: only colors decides its ink, pressed or disabled")
    func noDoubleDimming() {
        let (control, _) = laidOut(.primary)
        control.setSymbol("arrow.up")
        #expect(control.image(for: .normal) == nil && control.image(for: .disabled) == nil && control.image(for: .highlighted) == nil)
        #expect(control.iconImage != nil)
        control.isEnabled = false
        #expect(control.subviews.compactMap { $0 as? UIImageView }.first { $0.image == control.iconImage }?.tintColor == Palette.ink.withAlphaComponent(0.1))
        control.isEnabled = true
        control.isHighlighted = true
        #expect(control.subviews.compactMap { $0 as? UIImageView }.first { $0.image == control.iconImage }?.tintColor == Palette.inkInverted)
    }

    @Test("stop's ring is the web's: 40 points across, 2 thick, 13-point corners, grey while stopping")
    func ring() throws {
        let (control, _) = laidOut(.primary)
        control.showsRing = true
        control.layoutIfNeeded()
        let ring = try #require(control.ringView)
        #expect(ring.frame == CGRect(x: 2, y: 2, width: 40, height: 40))
        #expect(!ring.stopping && ring.alpha == 1)
        control.isEnabled = false
        #expect(ring.stopping && ring.alpha == 0.5)
        control.showsRing = false
        #expect(control.ringView == nil)
    }
}
