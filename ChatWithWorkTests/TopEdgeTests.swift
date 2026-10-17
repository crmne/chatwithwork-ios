import Testing
import UIKit
@testable import ChatWithWork

/// A large title collapsed by WebKit's zoom reset as a page first lays out
/// opens again; a page someone scrolled or pinched is left where it is.
@MainActor
@Suite("Top edge")
struct TopEdgeTests {
    /// Stands in for a web view's scroll view: WebKit sets the zoom scale
    /// itself, which a plain scroll view without a zooming view ignores.
    final class PageScrollView: UIScrollView {
        var fakeZoomScale: CGFloat = 1
        var pinching = false
        override var zoomScale: CGFloat {
            get { fakeZoomScale }
            set { fakeZoomScale = newValue }
        }
        override var isZooming: Bool { pinching }
    }

    /// Under a navigation bar showing its large title: 168 points of bars
    /// above the page, as on an iPhone 16 Pro.
    private func page(at offset: CGFloat) -> PageScrollView {
        let scrollView = PageScrollView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset.top = 168
        scrollView.contentSize = CGSize(width: 402, height: 2000)
        scrollView.fakeZoomScale = 0.41
        scrollView.contentOffset.y = offset
        return scrollView
    }

    /// WebKit zooming to 1: the scroll view keeps its centre, the bar
    /// collapses (52 points less inset), and the offset lands down the page.
    private func zoomReset(_ scrollView: PageScrollView) {
        scrollView.fakeZoomScale = 1
        scrollView.contentInset.top = 116
        scrollView.contentOffset.y = 203.7
    }

    @Test("puts a page that sat at its top back there, under the large title")
    func restoresTheTop() {
        let scrollView = page(at: -168)
        let state = TopEdge.ZoomState(scrollView)

        zoomReset(scrollView)
        #expect(state.offsetToRestore(after: scrollView) == -168)
    }

    @Test("leaves a page someone had scrolled where the zoom puts it")
    func leavesAScrolledPage() {
        let scrollView = page(at: 300)
        let state = TopEdge.ZoomState(scrollView)

        zoomReset(scrollView)
        #expect(state.offsetToRestore(after: scrollView) == nil)
    }

    @Test("leaves a pinch alone")
    func leavesAPinch() {
        let scrollView = page(at: -168)
        let state = TopEdge.ZoomState(scrollView)

        scrollView.pinching = true
        zoomReset(scrollView)
        #expect(state.offsetToRestore(after: scrollView) == nil)
    }

    @Test("follows scrolling between zooms")
    func followsScrolling() {
        let scrollView = page(at: -168)
        let state = TopEdge.ZoomState(scrollView)

        scrollView.contentOffset.y = 400
        #expect(state.offsetToRestore(after: scrollView) == nil)
        zoomReset(scrollView)
        #expect(state.offsetToRestore(after: scrollView) == nil)

        scrollView.contentOffset.y = -116
        #expect(state.offsetToRestore(after: scrollView) == nil)
        scrollView.fakeZoomScale = 0.5
        scrollView.contentOffset.y = 50
        #expect(state.offsetToRestore(after: scrollView) == -116)
    }

    @Test("restores the top once WebKit has finished zooming")
    func followsAWebView() async {
        let scrollView = page(at: -168)
        TopEdge.follow(scrollView)

        zoomReset(scrollView)
        #expect(scrollView.contentOffset.y > 0)

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(scrollView.contentOffset.y == -168)
    }
}
