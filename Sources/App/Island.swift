import AppKit
import SwiftUI

/// A Dynamic Island at the top centre of the screen the pointer is on. It stays hidden until the pointer rests there;
/// then an icon and today's steps appear around the notch (or as a black pill of the same shape where there is no
/// notch). A click opens it into the card with its checklist and the question box, whose answers can carry charts; a
/// click outside, or Esc, closes it.
@MainActor
final class Island: ObservableObject {
    static let shared = Island()
    @Published var expanded = false
    @Published var shown = false  // the small icon + number view, while the pointer is at the top centre
    @Published var notch = CGSize(width: 0, height: 32)  // of the screen it is on
    private var screen: NSScreen?
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
                Task { @MainActor in Island.shared.move(to: Island.pointerScreen, force: true) }
            }
            panel = p
        }
        panel?.orderFrontRegardless()
        move(to: Self.pointerScreen, force: true)
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
        guard let s = screen else { return .zero }
        let w = notch.width + 2 * IslandView.wing + 24, h = notch.height + 8
        return NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - h, width: w, height: h)
    }

    func track() {
        guard !expanded else { return }
        move(to: Self.pointerScreen)
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

    private var closing = false

    /// The island's content changed size (an answer arrived or was cleared, a tip faded out): fit the window to it.
    func contentChanged() {
        guard !closing else { return }
        DispatchQueue.main.async { self.place() }
    }

    func close() {
        guard expanded else { return }
        closing = true  // keep the window until the card has animated back into the island
        expanded = false
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        // shrink the window once the card has animated back into the island
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.closing = false
            if !self.expanded { self.place(); self.track() }
        }
    }

    /// The screen under the pointer (each screen has its own menu bar, so the island goes where you are looking).
    static var pointerScreen: NSScreen? {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Follow the pointer to another screen while closed.
    func move(to s: NSScreen?, force: Bool = false) {
        guard let s, force || s != screen else { return }
        screen = s
        notch = Self.notch(of: s)
        DispatchQueue.main.async { self.place() }
    }

    /// Width and height of the notch, or of a notch-like pill on a screen without one.
    static func notch(of s: NSScreen) -> CGSize {
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        }
        return CGSize(width: 0, height: max(24, s.frame.maxY - s.visibleFrame.maxY))
    }

    /// Size the window to the island, centred under the notch at the top of the screen. The window changes size at
    /// once; SwiftUI animates the island inside it, pinned to the top centre, so the card always opens out of the island.
    func place() {
        guard let p = panel, let s = screen, let v = p.contentView else { return }
        let size = v.fittingSize
        let x = (s.frame.midX - size.width / 2).rounded()
        p.setFrame(NSRect(x: x, y: s.frame.maxY - size.height, width: size.width, height: size.height), display: true)
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
        let notch = island.notch
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
        .fixedSize(horizontal: false, vertical: true)  // as tall as its content, so it shrinks when an answer is cleared
        .background(GeometryReader { g in Color.clear.onChange(of: g.size) { _, _ in island.contentChanged() } })
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: island.expanded ? 30 : notch.height / 2,
                                                        bottomTrailingRadius: island.expanded ? 30 : notch.height / 2, style: .continuous))
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)  // centred and at the top whatever the window size
        // hidden: shrunk into the notch (or the top edge) and transparent
        .scaleEffect(visible ? 1 : 0.6, anchor: .top)
        .opacity(visible ? 1 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: island.expanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: island.shown)
    }
}
