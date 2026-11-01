import AppKit
import SwiftUI

/// A Dynamic Island at the top centre of the screen. It stays hidden until the pointer rests there; then an icon and
/// today's steps appear around the notch (or as a black pill of the same shape where there is no notch). A click opens
/// it into the card with its checklist and the question box; a click outside, or Esc, closes it.
@MainActor
final class Island: ObservableObject {
    static let shared = Island()
    @Published var expanded = false
    @Published var shown = false  // the small icon + number view, while the pointer is at the top centre
    private var panel: IslandPanel?
    private var monitors: [Any] = []
    private var poll: Timer?
    private var hide: DispatchWorkItem?

    func show(_ on: Bool, model: Model) {
        guard on else {
            close()
            poll?.invalidate(); poll = nil
            panel?.orderOut(nil)
            return
        }
        if panel == nil {
            let p = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 32), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)  // over the menu bar, like the notch
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true  // while hidden, clicks reach the menu bar underneath
            p.contentView = FirstClickHostingView(rootView: IslandView(model: model, island: self))
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in Island.shared.place() }
            }
            panel = p
        }
        panel?.orderFrontRegardless()
        place()
        if poll == nil {
            // the pointer's position, ten times a second: mouse-moved events do not reliably arrive over the menu bar
            let t = Timer(timeInterval: 0.1, repeats: true) { _ in Task { @MainActor in Island.shared.track() } }
            t.tolerance = 0.05
            RunLoop.main.add(t, forMode: .common)
            poll = t
            setShown(true)  // show it for a moment, so it is clear where it lives
            schedule(after: 2.5)
        }
    }

    /// Where the pointer makes the island appear: the closed island plus a little margin.
    var zone: NSRect {
        guard let s = Self.screen else { return .zero }
        let w = Self.notch.width + 2 * IslandView.wing + 24, h = Self.notch.height + 8
        return NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - h, width: w, height: h)
    }

    func track() {
        guard !expanded else { return }
        if zone.contains(NSEvent.mouseLocation) {
            hide?.cancel(); hide = nil
            setShown(true)
        } else if shown, hide == nil {
            schedule(after: 0.35)
        }
    }

    private func schedule(after delay: Double) {
        hide?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hide = nil
            if !self.expanded && !self.zone.contains(NSEvent.mouseLocation) { self.setShown(false) }
        }
        hide = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private func setShown(_ on: Bool) {
        guard shown != on else { return }
        shown = on
        panel?.ignoresMouseEvents = !on
    }

    func toggle() { expanded ? close() : open() }

    func open() {
        expanded = true
        setShown(true)
        panel?.makeKey()  // so the question box takes typing without activating the app
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in Island.shared.close() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { Task { @MainActor in Island.shared.close() }; return nil }  // Esc
            return e
        } as Any)
        DispatchQueue.main.async { self.place() }
    }

    func close() {
        guard expanded else { return }
        expanded = false
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        DispatchQueue.main.async { self.place(); self.track() }
    }

    /// The screen with a notch if there is one, else the one with the menu bar.
    static var screen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first }

    /// Width and height of the notch, or of a notch-like pill on a screen without one.
    static var notch: CGSize {
        guard let s = screen else { return CGSize(width: 0, height: 32) }
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        }
        return CGSize(width: 0, height: max(24, s.frame.maxY - s.visibleFrame.maxY))
    }

    /// Size the window to the island and keep it centred at the top of the screen.
    func place() {
        guard let p = panel, let s = Self.screen, let v = p.contentView else { return }
        let size = v.fittingSize
        let frame = NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height, width: size.width, height: size.height)
        p.setFrame(frame, display: true, animate: p.isVisible && abs(frame.height - p.frame.height) > 1)
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct IslandView: View {
    @ObservedObject var model: Model
    @ObservedObject var island: Island

    static let wing: CGFloat = 62  // the space left and right of the notch for the icon and the number

    /// Steps, or the first metric there is: the one number the closed island shows.
    var key: String? {
        guard let m = model.summary?.metrics else { return nil }
        return m["steps"] != nil ? "steps" : CardView.order.first { m[$0] != nil }
    }

    var body: some View {
        let notch = Island.notch
        let visible = island.shown || island.expanded
        VStack(spacing: 0) {
            Button { island.toggle() } label: { HStack(spacing: 0) {
                Image(systemName: key.map(MetricStyle.icon) ?? "heart.fill")
                    .foregroundStyle(key.map(MetricStyle.tint) ?? .pink)
                    .frame(width: Self.wing, alignment: .center)
                Color.clear.frame(width: max(notch.width, 8))
                Text(key.flatMap { k in model.summary?.metrics[k].map { Metrics.format(k, $0) } } ?? "–")
                    .foregroundStyle(.white).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: Self.wing, alignment: .center)
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(height: notch.height)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle()) }
            .buttonStyle(.plain)
            if island.expanded {
                VStack(alignment: .leading, spacing: 12) {
                    CardView(summary: model.summary, size: .large, lang: model.summary?.lang ?? model.lang) { model.toggleTip($0) }
                        .frame(minHeight: CardSize.large.frame.height - 2 * WidgetStyle.margin, alignment: .top)
                    AskView(model: model)
                }
                .padding(.horizontal, WidgetStyle.margin + 2)
                .padding(.top, 6)
                .padding(.bottom, WidgetStyle.margin + 2)
                .frame(width: CardSize.large.frame.width + 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: island.expanded ? CardSize.large.frame.width + 16 : notch.width + 2 * Self.wing)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: island.expanded ? 30 : notch.height / 2,
                                                        bottomTrailingRadius: island.expanded ? 30 : notch.height / 2, style: .continuous))
        .environment(\.colorScheme, .dark)
        // hidden: shrunk into the notch (or the top edge) and transparent
        .scaleEffect(visible ? 1 : 0.6, anchor: .top)
        .opacity(visible ? 1 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: island.expanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: island.shown)
    }
}
