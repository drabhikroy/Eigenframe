import SwiftUI
import AppKit

/// A plain-language, visual walkthrough for granting Input Monitoring permission.
///
/// This replaces a text-only alert. The alert assumed the reader already knew
/// what System Settings looks like and could find a permission list inside it.
/// Many people do not, so each step here is paired with a picture of what the
/// screen will actually look like when they get there.
struct PermissionGuideView: View {

    /// Called when the user asks to open System Settings.
    var onOpenSettings: () -> Void

    /// Called when the user asks to open the full help page.
    var onOpenHelp: () -> Void

    /// Called when the user dismisses the window.
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(red: 0.06, green: 0.06, blue: 0.16),
                    Color(red: 0.03, green: 0.03, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Divider().background(Color.white.opacity(0.08)).padding(.vertical, 20)
                    steps
                    troubleshooting
                    Divider().background(Color.white.opacity(0.08)).padding(.vertical, 20)
                    buttons
                }
                .padding(28)
            }
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 520, idealHeight: 640)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One permission is needed")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.white)

            Text("You turned on Pause while typing. For that to work, macOS needs your permission to notice when you are typing.")
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            Text("Eigenframe only checks whether a key was pressed. It cannot see which key, and it never records or stores anything you type.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    // MARK: - Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: 22) {
            step(
                number: 1,
                title: "Open the permission list",
                body: "Click the blue button at the bottom of this window. It takes you straight to the right page in System Settings, so you do not have to go looking for it."
            ) {
                settingsPathIllustration
            }

            step(
                number: 2,
                title: "Find Eigenframe in the list",
                body: "You will see a list of apps. Look for Eigenframe. There is a switch to the right of its name."
            ) {
                toggleRowIllustration(isOn: false)
            }

            step(
                number: 3,
                title: "Turn the switch on",
                body: "Click the switch so it turns blue. If your Mac asks for your password or fingerprint, that is normal. Enter it to confirm."
            ) {
                toggleRowIllustration(isOn: true)
            }

            step(
                number: 4,
                title: "Quit Eigenframe and open it again",
                body: "This last step matters. macOS only applies the new permission when the app starts fresh."
            ) {
                quitIllustration
            }
        }
    }

    private func step<Illustration: View>(
        number: Int,
        title: String,
        body: String,
        @ViewBuilder illustration: () -> Illustration
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.45, green: 0.78, blue: 0.95))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color(red: 0.45, green: 0.78, blue: 0.95).opacity(0.14)))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)

                Text(body)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                illustration()
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Illustrations

    /// Shows the path through System Settings, so the words in the button match
    /// what the person will see on screen.
    private var settingsPathIllustration: some View {
        HStack(spacing: 6) {
            pathChip("System Settings")
            pathArrow
            pathChip("Privacy & Security")
            pathArrow
            pathChip("Input Monitoring")
        }
    }

    private func pathChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(Color.white.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var pathArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.3))
    }

    /// A small mock of the row the person is looking for, drawn twice: once
    /// switched off (what they will find) and once on (what they should end up
    /// with). Seeing the before and after removes the guesswork.
    private func toggleRowIllustration(isOn: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.1))
                .frame(width: 20, height: 20)
                .overlay(
                    Text("λ")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.45, green: 0.78, blue: 0.95))
                )

            Text("Eigenframe")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.85))

            Spacer()

            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color(red: 0.20, green: 0.52, blue: 0.94) : Color.white.opacity(0.16))
                    .frame(width: 34, height: 20)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 2)
            }
            .frame(width: 34, height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isOn ? Color(red: 0.20, green: 0.52, blue: 0.94).opacity(0.4) : Color.white.opacity(0.07),
                        lineWidth: 1)
        )
    }

    /// Eigenframe has no Dock icon, so people reasonably assume closing the
    /// window quits it. It does not. This shows where Quit actually lives.
    private var quitIllustration: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("λ")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.45, green: 0.78, blue: 0.95))
                Text("Click the Eigenframe icon in the menu bar at the top of your screen, then choose Quit.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.07), lineWidth: 1))

            Text("Closing the Eigenframe window is not the same as quitting. Eigenframe keeps running in the menu bar.")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Troubleshooting

    private var troubleshooting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("If Eigenframe is already switched on")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)

            Text("Switch it off, then on again. When an app is replaced with a newer version, macOS sometimes keeps showing the old setting as on while no longer honoring it. Turning it off and on again clears that up. Then quit Eigenframe and open it once more.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.top, 24)
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: onOpenSettings) {
                Text("Open System Settings for me")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.20, green: 0.52, blue: 0.94))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button("Read the full guide", action: onOpenHelp)
                    .buttonStyle(GhostButtonStyle())

                Spacer()

                Button("Not now", action: onDismiss)
                    .buttonStyle(GhostButtonStyle())
            }

            Text("Pause while typing is optional. Everything else in Eigenframe works without this permission.")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }
}

// MARK: - Window Controller

/// Hosts PermissionGuideView in its own window.
@MainActor
final class PermissionGuideWindowController {

    static let shared = PermissionGuideWindowController()

    private var window: NSWindow?

    private init() {}

    func show(onOpenSettings: @escaping () -> Void, onOpenHelp: @escaping () -> Void) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                styleMask:   [.titled, .closable, .resizable, .fullSizeContentView],
                backing:     .buffered,
                defer:       false
            )
            w.titlebarAppearsTransparent  = true
            w.titleVisibility             = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed        = false
            w.minSize                     = NSSize(width: 460, height: 480)
            w.title                       = "Eigenframe"
            w.collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.center()
            window = w
        }

        window?.contentView = NSHostingView(
            rootView: PermissionGuideView(
                onOpenSettings: onOpenSettings,
                onOpenHelp:     onOpenHelp,
                onDismiss:      { [weak self] in self?.close() }
            )
        )

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }
}
