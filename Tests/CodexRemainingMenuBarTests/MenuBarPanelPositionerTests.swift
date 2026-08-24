import CoreGraphics
import Testing
@testable import CodexRemainingMenuBar

struct MenuBarPanelPositionerTests {
    private let panelSize = CGSize(width: 312, height: 438)
    private let visibleFrame = CGRect(x: 0, y: 25, width: 1_440, height: 850)
    private let panelSpacing: CGFloat = 6

    @Test
    func positionsPanelBelowMenuBarAndItsShadowSpacing() {
        let anchor = CGRect(x: 900, y: 878, width: 60, height: 19)

        let origin = MenuBarPanelPositioner.origin(
            anchorRect: anchor,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            verticalSpacing: panelSpacing
        )

        #expect(origin.y + panelSize.height == visibleFrame.maxY - panelSpacing)
        #expect(origin.x + panelSize.width / 2 == anchor.midX)
    }

    @Test
    func neverUsesInsetStatusButtonAsMenuBarBottom() {
        let anchor = CGRect(x: 900, y: 880, width: 60, height: 16)

        let origin = MenuBarPanelPositioner.origin(
            anchorRect: anchor,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            verticalSpacing: panelSpacing
        )

        #expect(origin.y + panelSize.height < visibleFrame.maxY)
        #expect(origin.y + panelSize.height < anchor.minY)
    }

    @Test
    func keepsPanelInsideRightScreenEdge() {
        let anchor = CGRect(x: 1_400, y: 875, width: 30, height: 25)

        let origin = MenuBarPanelPositioner.origin(
            anchorRect: anchor,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            verticalSpacing: panelSpacing
        )

        #expect(origin.x + panelSize.width == visibleFrame.maxX)
        #expect(origin.y + panelSize.height == visibleFrame.maxY - panelSpacing)
    }

    @Test
    func keepsPanelInsideLeftAndBottomScreenEdges() {
        let anchor = CGRect(x: -1_430, y: 20, width: 30, height: 25)
        let secondaryScreen = CGRect(x: -1_440, y: 0, width: 1_440, height: 900)

        let origin = MenuBarPanelPositioner.origin(
            anchorRect: anchor,
            panelSize: panelSize,
            visibleFrame: secondaryScreen
        )

        #expect(origin.x == secondaryScreen.minX)
        #expect(origin.y == secondaryScreen.minY)
    }
}
