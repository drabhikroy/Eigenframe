import SwiftUI
import AVKit
import UniformTypeIdentifiers
import OSLog

// MARK: - Main Control Panel

struct ControlPanelView: View {
    @ObservedObject var engine: WallpaperEngine
    @ObservedObject private var spaceManager = SpaceManager.shared
    @ObservedObject private var config       = ConfigStore.shared

    @State private var hoveredSpace: CGSSpaceID? = nil

    var body: some View {
        ZStack {
            backgroundGradient
            StarFieldView()
                .opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                    .padding(.top, 28)
                    .padding(.horizontal, 32)

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                spacesGridView
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                Spacer()

                footerView
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.04, blue: 0.10),
                Color(red: 0.06, green: 0.06, blue: 0.16),
                Color(red: 0.03, green: 0.03, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint:   .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .topLeading,
                                endPoint:   .bottomTrailing
                            )
                        )
                        .accessibilityHidden(true)

                    Text("Eigenframe")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                Text("Assign a scene to each Space, still or moving")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.4))
            }

            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        Button(action: { engine.isPaused.toggle() }) {
            HStack(spacing: 7) {
                Circle()
                    .fill(engine.isPaused ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                    .shadow(color: engine.isPaused ? Color.orange.opacity(0.6) : Color.green.opacity(0.6), radius: 3)
                Text(engine.isPaused ? "Resume" : "Pause")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(engine.isPaused ? "Resume wallpapers" : "Pause wallpapers")
    }

    // MARK: - Spaces Grid

    private var spacesGridView: some View {
        // Adaptive columns: each card is at least 180px wide, reflows on window resize
        let columns = [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 16)]

        return ScrollView {
            if spaceManager.allSpaceIDs.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(spaceManager.allSpaceIDs, id: \.self) { spaceID in
                        SpaceSlotView(
                            spaceID:    spaceID,
                            spaceIndex: spaceManager.index(of: spaceID),
                            isActive:   spaceManager.currentSpaceID == spaceID,
                            isHovered:  hoveredSpace == spaceID
                        )
                        .onHover { hoveredSpace = $0 ? spaceID : nil }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(Color.white.opacity(0.2))
                .accessibilityHidden(true)
            Text("No Spaces detected")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.3))
            Text("Open Mission Control and create some Spaces first.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.2))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.25))
                .accessibilityHidden(true)
            Text("Click + or drag to assign a scene. Assignments are saved automatically.")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.25))
                .lineLimit(1)

            Spacer()

            Toggle(isOn: Binding(
                get: { ConfigStore.shared.pauseOnTyping },
                set: { newValue in
                    ConfigStore.shared.pauseOnTyping = newValue
                    if newValue {
                        engine.requestTypingDetection()
                    }
                }
            )) {
                Text("Pause while typing")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.45))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()
            .help("Pause video wallpapers while you are typing. Requires Input Monitoring permission.")

            Toggle(isOn: Binding(
                get: { ConfigStore.shared.launchAtLogin },
                set: { ConfigStore.shared.launchAtLogin = $0 }
            )) {
                Text("Launch at login")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.45))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()
            .help("Start Eigenframe automatically when you log in")

            Button("Refresh") {
                SpaceManager.shared.refresh()
                Log.ui.info("User refreshed spaces")
            }
            .buttonStyle(GhostButtonStyle())
            .help("Reload your Space list after adding or removing Spaces in Mission Control")
        }
    }
}
