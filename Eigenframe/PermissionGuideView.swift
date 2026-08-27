import SwiftUI
import AppKit
import CoreGraphics
import OSLog

// MARK: - Palette and metrics

private enum Guide {
    static let accent   = Color(red: 0.45, green: 0.78, blue: 0.95)
    static let systemOn = Color(red: 0.20, green: 0.52, blue: 0.94)
    static let success  = Color(red: 0.35, green: 0.82, blue: 0.55)

    /// Same width as the control panel so Eigenframe's windows match. The
    /// window can be resized, and its height follows whatever the current step
    /// needs, so the background always fills it.
    static let defaultWidth: CGFloat = 720
    static let minWidth:     CGFloat = 520
}

// MARK: - Permission monitoring

/// Watches the Input Monitoring permission so the guide can move forward on its
/// own once it has been granted.
///
/// Detection is done by trying to create a listen-only event tap and throwing it
/// away again. `CGPreflightListenEventAccess` looks like the obvious choice, but
/// its answer is cached for the life of the process: once it has reported the
/// permission as absent it keeps reporting that until the app restarts, so it
/// can never notice a grant that happens while the guide is open. Creating a tap
/// reflects the real current state every time.
@MainActor
final class PermissionMonitor: ObservableObject {

    /// True once macOS lets this process create an event tap.
    @Published private(set) var isGranted = false

    /// True once System Settings has come to the front, which means the first
    /// step is done and the person is looking at the list.
    @Published private(set) var hasOpenedSettings = false

    /// Called the first time the permission is seen to work, so the engine can
    /// install its real tap and start pausing on typing straight away.
    var onGranted: (() -> Void)?

    private var timer: DispatchSourceTimer?

    init() {
        isGranted = Self.canCreateTap()
    }

    func start() {
        guard timer == nil else { return }
        if isGranted { onGranted?(); return }

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.6, repeating: 0.6, leeway: .milliseconds(150))
        t.setEventHandler { [weak self] in
            guard let self else { return }

            if !self.hasOpenedSettings, Self.isSettingsFrontmost() {
                self.hasOpenedSettings = true
                Log.engine.info("System Settings came to the front")
            }

            guard !self.isGranted else { return }
            if Self.canCreateTap() {
                self.isGranted = true
                Log.engine.info("Input Monitoring permission detected while the guide was open")
                self.onGranted?()
                self.stop()
            }
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Creates a throwaway tap purely to see whether macOS allows it. Returns
    /// false when the permission is missing. This never shows a prompt.
    private static func canCreateTap() -> Bool {
        guard let probe = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CGEvent.tapEnable(tap: probe, enable: false)
        CFMachPortInvalidate(probe)
        return true
    }

    /// Whether System Settings is the app in front. Used to tell that the
    /// first step has been carried out without asking the person to confirm it.
    private static func isSettingsFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
    }

    /// Asks macOS for the permission. This shows the system prompt and, just as
    /// usefully, registers Eigenframe in the Input Monitoring list so there is
    /// something to switch on when the person gets there.
    static func requestAccess() {
        _ = CGRequestListenEventAccess()
    }
}

// MARK: - Steps

private enum GuideStep: Int, CaseIterable {
    case openSettings
    case findEigenframe
    case turnOn
    case finish

    var number: Int { rawValue + 1 }
    static var count: Int { allCases.count }

    func title(granted: Bool) -> String {
        switch self {
        case .openSettings:   return "Open the permission list"
        case .findEigenframe: return "Find Eigenframe in the list"
        case .turnOn:         return "Turn the switch on"
        case .finish:         return granted ? "That is everything" : "One more thing"
        }
    }
}

private enum RowState { case absent, off, on }

// MARK: - Guide

struct PermissionGuideView: View {

    var onOpenSettings:      () -> Void
    var onOpenHelp:          () -> Void
    var onDismiss:           () -> Void
    var onPermissionGranted: () -> Void

    /// Told when the visible step changes, so the window can settle to the
    /// height that step needs. Deliberately not called while the person is
    /// dragging the window: measuring on every layout pass and resizing in
    /// response sets up a loop that grows the window until it runs off screen.
    var onStepChange:        () -> Void

    @StateObject private var monitor = PermissionMonitor()
    @State private var step: GuideStep = .openSettings
    @State private var hasAutoAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().overlay(Color.white.opacity(0.07))

            stepBody
                .padding(.horizontal, 34)
                .padding(.top, 26)
                .padding(.bottom, 24)

            Divider().overlay(Color.white.opacity(0.07))
            footerBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(red: 0.06, green: 0.06, blue: 0.16),
                    Color(red: 0.03, green: 0.03, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .textSelection(.enabled)
        .onAppear {
            monitor.onGranted = onPermissionGranted
            monitor.start()
        }
        .onDisappear { monitor.stop() }
        .onChange(of: step) { _ in onStepChange() }
        .onChange(of: monitor.isGranted) { granted in
            guard granted, !hasAutoAdvanced else { return }
            hasAutoAdvanced = true
            withAnimation(.easeInOut(duration: 0.3)) { step = .finish }
        }
        .onChange(of: monitor.hasOpenedSettings) { opened in
            // The list is on screen, so the first step is done.
            guard opened, step == .openSettings else { return }
            withAnimation(.easeInOut(duration: 0.3)) { step = .findEigenframe }
        }
    }

    // MARK: Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Let Eigenframe notice when you type")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                ForEach(GuideStep.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(pipColor(for: s))
                        .frame(height: 5)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: step)

            HStack(spacing: 10) {
                Text("Step \(step.number) of \(GuideStep.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.62))

                if monitor.isGranted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                        Text("Permission granted")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(Guide.success)
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 30)
        .padding(.bottom, 22)
    }

    private func pipColor(for s: GuideStep) -> Color {
        if monitor.isGranted && s != .finish { return Guide.success.opacity(0.7) }
        if s == step { return Guide.accent }
        if s.rawValue < step.rawValue { return Guide.accent.opacity(0.35) }
        return Color.white.opacity(0.12)
    }

    // MARK: Step body

    @ViewBuilder
    private var stepBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(step.title(granted: monitor.isGranted))
                .font(.system(size: 23, weight: .semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            switch step {
            case .openSettings:   openSettingsStep
            case .findEigenframe: findEigenframeStep
            case .turnOn:         turnOnStep
            case .finish:         finishStep
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var openSettingsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            bodyText("Eigenframe can pause your wallpapers while you type. macOS asks for your permission before any app is allowed to notice keystrokes.")

            infoRow(
                icon: "lock.fill",
                color: Guide.accent,
                text: "Eigenframe is told only that a key was pressed. It is never told which key, and it does not record, save, or send anything you type."
            )

            Button(action: {
                PermissionMonitor.requestAccess()
                onOpenSettings()
            }) {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Open System Settings")
                        .font(.system(size: 15.5, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Guide.systemOn)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open System Settings to the Input Monitoring page")

            HStack(spacing: 7) {
                Text("Or go there yourself:")
                    .font(.system(size: 13.5))
                    .foregroundColor(Color.white.opacity(0.6))
                pathChip("System Settings")
                chevron
                pathChip("Privacy & Security")
                chevron
                pathChip("Input Monitoring")
            }
        }
    }

    private var findEigenframeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            bodyText("A list of apps appears. Look for Eigenframe. If it is already there, continue to the next step.")

            panelMock(row: .off, highlightPlus: false)
                .accessibilityLabel("The Input Monitoring list showing an Eigenframe row with its switch off")

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Guide.accent.opacity(0.9))
                    Text("Eigenframe is not there?")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }

                bodyText("Add it yourself. Click the small plus button at the bottom left of the list, choose Eigenframe from your Applications folder, then click Open.", size: 14.5)

                panelMock(row: .absent, highlightPlus: true)
                    .accessibilityLabel("The same list with no Eigenframe row, and the plus button at the bottom left highlighted")
            }
            .padding(16)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Guide.accent.opacity(0.2), lineWidth: 1))
        }
    }

    private var turnOnStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            bodyText("Click the switch beside Eigenframe so it turns blue. This window notices as soon as you do and moves on by itself.")

            panelMock(row: .on, highlightPlus: false)
                .accessibilityLabel("The list with the Eigenframe switch turned on and blue")

            infoRow(
                icon: "touchid",
                color: Guide.accent,
                text: "If your Mac asks for your password, Touch ID, or Apple Watch, that is macOS confirming the change. It is not Eigenframe asking."
            )

            infoRow(
                icon: "arrow.triangle.2.circlepath",
                color: Color.white.opacity(0.65),
                text: "Already switched on but nothing has happened? Switch it off, wait a moment, then switch it on again. A setting left over from an earlier version can look correct while no longer working."
            )
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            if monitor.isGranted {
                HStack(spacing: 11) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Guide.success)
                    Text("Pause while typing is working now.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Guide.success.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Guide.success.opacity(0.3), lineWidth: 1))

                bodyText("Your video wallpapers will pause while you type and start again a couple of seconds after you stop. You can turn this off at any time from the switch at the bottom of the Eigenframe window.")
            } else {
                bodyText("If you have switched Eigenframe on and this window has not noticed, Eigenframe may need to start fresh before macOS applies the change. Click the Eigenframe icon in the menu bar at the top of your screen, choose Quit, then open Eigenframe again.")

                menuBarMock
                    .accessibilityLabel("The Eigenframe menu bar icon with the Quit item highlighted")

                infoRow(
                    icon: "exclamationmark.triangle.fill",
                    color: Color(red: 0.95, green: 0.75, blue: 0.35),
                    text: "Closing this window does not quit Eigenframe. It has no Dock icon because it lives in the menu bar, so it keeps running until you choose Quit."
                )
            }
        }
    }

    // MARK: Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            if step != .openSettings {
                Button(action: goBack) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Back").font(.system(size: 14, weight: .medium))
                    }
                }
                .buttonStyle(GhostButtonStyle())
            }

            Button("Help", action: onOpenHelp)
                .buttonStyle(GhostButtonStyle())

            Spacer()

            if step == .finish {
                Button(action: onDismiss) {
                    Text(monitor.isGranted ? "Done" : "Close")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(monitor.isGranted ? Guide.success.opacity(0.85) : Guide.systemOn.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            } else {
                Button("Skip for now", action: onDismiss)
                    .buttonStyle(GhostButtonStyle())

                Button(action: goNext) {
                    HStack(spacing: 6) {
                        Text("Next").font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Guide.systemOn.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
    }

    private func goNext() {
        guard let next = GuideStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }

    private func goBack() {
        guard let prev = GuideStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { step = prev }
    }

    // MARK: Small pieces

    private func bodyText(_ text: String, size: CGFloat = 15.5) -> some View {
        Text(text)
            .font(.system(size: size))
            .foregroundColor(Color.white.opacity(0.78))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color.opacity(0.95))
                .frame(width: 18)
                .padding(.top, 2)

            Text(text)
                .font(.system(size: 14.5))
                .foregroundColor(Color.white.opacity(0.72))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func pathChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(Color.white.opacity(0.72))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.35))
    }

    // MARK: Illustrations

    private func panelMock(row: RowState, highlightPlus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Allow the applications below to monitor input from your keyboard even while using other applications.")
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.top, 13)
                .padding(.bottom, 11)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            Group {
                switch row {
                case .absent:
                    HStack(spacing: 9) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 14))
                            .foregroundColor(Color.white.opacity(0.3))
                        Text("No Eigenframe here yet")
                            .font(.system(size: 14))
                            .foregroundColor(Color.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 15)

                case .off, .on:
                    HStack(spacing: 11) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text("\u{03BB}")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Guide.accent)
                            )

                        Text("Eigenframe")
                            .font(.system(size: 15))
                            .foregroundColor(Color.white.opacity(0.9))

                        Spacer(minLength: 8)

                        switchMock(isOn: row == .on)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            HStack(spacing: 0) {
                plusButtonMock(highlighted: highlightPlus)

                Text("\u{2212}")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.35))
                    .frame(width: 32, height: 26)

                if highlightPlus {
                    Text("Click here to add Eigenframe")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Guide.accent)
                        .padding(.leading, 6)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(row == .on ? Guide.systemOn.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func switchMock(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Guide.systemOn : Color.white.opacity(0.16))
                .frame(width: 40, height: 23)
            Circle()
                .fill(Color.white)
                .frame(width: 19, height: 19)
                .padding(.horizontal, 2)
        }
        .frame(width: 40, height: 23)
    }

    private func plusButtonMock(highlighted: Bool) -> some View {
        Text("+")
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(highlighted ? Guide.accent : Color.white.opacity(0.4))
            .frame(width: 32, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(highlighted ? Guide.accent.opacity(0.16) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(highlighted ? Guide.accent.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
    }

    private var menuBarMock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("\u{03BB}")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Guide.accent)
                Text("Eigenframe")
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.78))
                Spacer(minLength: 0)
                Text("menu bar, top of your screen")
                    .font(.system(size: 12.5))
                    .foregroundColor(Color.white.opacity(0.42))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            HStack(spacing: 9) {
                Image(systemName: "power")
                    .font(.system(size: 13))
                    .foregroundColor(Guide.accent)
                Text("Quit")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Guide.accent.opacity(0.1))
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Window Controller

@MainActor
final class PermissionGuideWindowController {

    static let shared = PermissionGuideWindowController()

    /// Set by AppDelegate so the guide joins the same menu bar and activation
    /// policy handling as the control panel.
    var windowDelegate: NSWindowDelegate?
    var onWillShow: (() -> Void)?

    private var window: NSWindow?

    private var openSettingsAction: (() -> Void)?
    private var openHelpAction:     (() -> Void)?
    private var grantedAction:      (() -> Void)?

    private init() {}

    func show(
        onOpenSettings: @escaping () -> Void,
        onOpenHelp: @escaping () -> Void,
        onPermissionGranted: @escaping () -> Void
    ) {
        onWillShow?()

        self.openSettingsAction = onOpenSettings
        self.openHelpAction     = onOpenHelp
        self.grantedAction      = onPermissionGranted

        let w: NSWindow
        if let existing = window {
            w = existing
        } else {
            w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: Guide.defaultWidth, height: 560),
                styleMask:   [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing:     .buffered,
                defer:       false
            )
            w.titlebarAppearsTransparent  = true
            w.titleVisibility             = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed        = false
            w.title                       = "Eigenframe"
            w.collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.delegate                    = windowDelegate
            w.minSize                     = NSSize(width: Guide.minWidth, height: 320)
            w.center()
            window = w
        }

        w.contentView = NSHostingView(rootView: makeContent())

        // Settle to the height the opening step needs. After this the person is
        // free to resize, and the window only adjusts again when the step changes.
        fitHeightToCurrentStep()

        w.alphaValue = 0
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            w.animator().alphaValue = 1
        }
    }

    private func makeContent() -> some View {
        // The scroll view is what makes shrinking the window safe: content is
        // reachable at any size rather than being cut off. At the sizes the
        // window settles to it never actually scrolls.
        ScrollView(.vertical) {
            PermissionGuideView(
                onOpenSettings:      { [weak self] in self?.openSettingsAction?() },
                onOpenHelp:          { [weak self] in self?.openHelpAction?() },
                onDismiss:           { [weak self] in self?.close() },
                onPermissionGranted: { [weak self] in self?.grantedAction?() },
                onStepChange:        { [weak self] in self?.fitHeightToCurrentStep() }
            )
        }
    }

    /// Grows or shrinks the window to fit the step now showing, keeping the top
    /// edge and the width where they are.
    ///
    /// The measurement is taken from a throwaway copy of the view rather than
    /// from the one on screen. Measuring the live view means every resize feeds
    /// back into another resize, which walks the window off the screen.
    private func fitHeightToCurrentStep() {
        // Give the layout a moment to settle after a step change before measuring.
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window, let host = w.contentView else { return }

            let width = w.contentLayoutRect.width
            guard width > 1 else { return }

            host.layoutSubtreeIfNeeded()
            let needed = host.fittingSize.height
            guard needed > 1 else { return }

            let screen  = w.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let target  = min(needed, visible.height - 40)

            let chrome  = w.frame.height - w.contentLayoutRect.height
            let newTotal = target + chrome
            guard abs(newTotal - w.frame.height) > 2 else { return }

            var frame = w.frame
            frame.origin.y   += frame.height - newTotal   // hold the top edge still
            frame.size.height = newTotal

            // Keep the whole window on screen no matter what the maths produced.
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
            if frame.minY < visible.minY { frame.origin.y = visible.minY }

            w.setFrame(frame, display: true, animate: true)
        }
    }

    func close() {
        guard let w = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            w.animator().alphaValue = 0
        }, completionHandler: {
            w.orderOut(nil)
        })
    }
}
