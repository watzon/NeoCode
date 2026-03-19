import AppKit
import SwiftUI

struct TranscriptScrollPinning {
    static let upwardScrollTolerance: CGFloat = 8

    static func nextPinnedState(
        for metrics: TranscriptScrollMetrics,
        previousOffsetY: CGFloat?,
        isMaintainingPinnedPosition: Bool,
        autoScrollThreshold: CGFloat
    ) -> Bool {
        if isMaintainingPinnedPosition {
            return true
        }

        if let previousOffsetY,
           metrics.contentOffsetY < previousOffsetY - upwardScrollTolerance {
            return false
        }

        let distanceToBottom = max(0, metrics.contentHeight - metrics.visibleMaxY)
        return distanceToBottom <= autoScrollThreshold
    }
}

struct TranscriptScrollObserver: NSViewRepresentable {
    let onMetricsChange: (TranscriptScrollMetrics) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMetricsChange: onMetricsChange)
    }

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        context.coordinator.onMetricsChange = onMetricsChange
        nsView.attachToEnclosingScrollViewIfNeeded()
        context.coordinator.reportMetricsIfPossible()
    }

    final class Coordinator: NSObject {
        var onMetricsChange: (TranscriptScrollMetrics) -> Void
        weak var clipView: NSClipView?
        weak var documentView: NSView?

        init(onMetricsChange: @escaping (TranscriptScrollMetrics) -> Void) {
            self.onMetricsChange = onMetricsChange
        }

        func attach(to scrollView: NSScrollView) {
            guard clipView !== scrollView.contentView else { return }

            detach()

            let clipView = scrollView.contentView
            let documentView = scrollView.documentView

            self.clipView = clipView
            self.documentView = documentView

            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )

            documentView?.postsFrameChangedNotifications = true
            if let documentView {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(documentViewFrameDidChange),
                    name: NSView.frameDidChangeNotification,
                    object: documentView
                )
            }
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            clipView = nil
            documentView = nil
        }

        @objc
        func clipViewBoundsDidChange() {
            reportMetricsIfPossible()
        }

        @objc
        func documentViewFrameDidChange() {
            reportMetricsIfPossible()
        }

        func reportMetricsIfPossible() {
            guard let clipView, let documentView else { return }

            let visibleRect = clipView.documentVisibleRect
            let contentHeight = max(documentView.bounds.height, visibleRect.height)
            let contentOffsetY: CGFloat

            if documentView.isFlipped {
                contentOffsetY = max(0, visibleRect.minY)
            } else {
                contentOffsetY = max(0, contentHeight - visibleRect.maxY)
            }

            let metrics = TranscriptScrollMetrics(
                contentOffsetY: contentOffsetY,
                contentHeight: contentHeight,
                visibleMaxY: min(contentHeight, contentOffsetY + visibleRect.height)
            )

            onMetricsChange(metrics)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }

    final class ObserverView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attachToEnclosingScrollViewIfNeeded()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachToEnclosingScrollViewIfNeeded()
        }

        func attachToEnclosingScrollViewIfNeeded() {
            guard let coordinator else { return }
            guard let scrollView = locateScrollView() else { return }
            coordinator.attach(to: scrollView)
            coordinator.reportMetricsIfPossible()
        }

        private func locateScrollView() -> NSScrollView? {
            if let direct = enclosingScrollView {
                return direct
            }

            var ancestor = superview
            while let current = ancestor {
                if let discovered = findScrollView(in: current) {
                    return discovered
                }
                ancestor = current.superview
            }

            return window?.contentView.flatMap(findScrollView(in:))
        }

        private func findScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }

            for child in view.subviews {
                if let discovered = findScrollView(in: child) {
                    return discovered
                }
            }

            return nil
        }
    }
}
