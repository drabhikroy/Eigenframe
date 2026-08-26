import SwiftUI
import AVFoundation
import OSLog

// MARK: - Space Slot Card

struct SpaceSlotView: View {
    let spaceUUID:  String
    let spaceIndex: Int      // 1-based display position only — never a storage key
    let isActive:   Bool
    let isHovered:  Bool

    // Read directly from ConfigStore so the view updates reactively
    // when assignments change — a plain `let mediaPath` prop would not
    // trigger a re-render when the store updates.
    @ObservedObject private var config = ConfigStore.shared
    private var mediaPath: String? { config.mediaPath(forSpaceUUID: spaceUUID) }

    @State private var isDroppingOver = false
    @State private var thumbnail:     NSImage?   = nil
    @State private var mediaType:     MediaType? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background card
            RoundedRectangle(cornerRadius: 14)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(borderColor, lineWidth: isActive ? 3.5 : 0.75)
                )
                .shadow(color: isActive ? Color.cyan.opacity(0.3) : .clear, radius: 16)

            // Thumbnail or drop hint
            if let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .opacity(0.6)
                    .accessibilityHidden(true)
            } else {
                dropHintView
            }

            // Drop target highlight
            if isDroppingOver {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.cyan.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.cyan.opacity(0.8), lineWidth: 2)
                    )
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.cyan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }

            // Footer label
            VStack { Spacer(); slotFooter }

            // Media type badge
            if let type = mediaType {
                mediaTypeBadge(label: type.badgeLabel)
            }


        }
        .frame(height: 120)
        .onDrop(of: [.fileURL], isTargeted: $isDroppingOver, perform: handleDrop)
        .onAppear(perform: reloadThumbnail)
        .onChange(of: mediaPath) { _ in reloadThumbnail() }
        .contextMenu { contextMenuItems }
        .animation(.easeInOut(duration: 0.15), value: isDroppingOver)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Subviews

    private var dropHintView: some View {
        Button(action: chooseFile) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(Color.white.opacity(isHovered ? 0.5 : 0.2))
                Text("Click to browse, or drag & drop")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(isHovered ? 0.4 : 0.15))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose a scene for Space \(spaceIndex)")
    }

    private var slotFooter: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Space \(spaceIndex)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                if let path = mediaPath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if mediaPath != nil {
                Image(systemName: mediaType == .image ? "photo.fill" : "play.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        )
    }

    private func mediaTypeBadge(label: String) -> some View {
        HStack {
            Spacer()
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.5))
                .clipShape(Capsule())
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if mediaPath != nil {
            Button("Choose Different Scene...") { chooseFile() }
            Divider()
            Button("Remove Scene", role: .destructive) {
                ConfigStore.shared.setMediaPath(nil, forSpaceUUID: spaceUUID)
            }
        } else {
            Button("Choose Scene...") { chooseFile() }
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts = ["Space \(spaceIndex)"]
        if isActive { parts.append("currently active") }
        if let path = mediaPath {
            let name = URL(fileURLWithPath: path).lastPathComponent
            parts.append("\(mediaType?.badgeLabel.lowercased() ?? "media"): \(name)")
        } else {
            parts.append("no scene assigned")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Computed Styles

    private var cardBackground: some ShapeStyle {
        if isDroppingOver {
            return AnyShapeStyle(Color(red: 0.05, green: 0.15, blue: 0.20))
        }
        if isActive {
            return AnyShapeStyle(Color(red: 0.07, green: 0.10, blue: 0.18))
        }
        return AnyShapeStyle(Color(red: 0.08, green: 0.08, blue: 0.13))
    }

    private var borderColor: Color {
        if isDroppingOver { return .cyan }
        if isActive       { return Color.cyan.opacity(0.4) }
        if isHovered      { return Color.white.opacity(0.15) }
        return Color.white.opacity(0.07)
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Capture the Space uuid before the async call.
        let targetUUID = spaceUUID

        // The drop message arrives on the main thread via kDragIPCDrop.
        // We must return from handleDrop immediately — any work done here
        // blocks the drag IPC message pump and causes kDragIPCDropPing
        // timeout errors that freeze drag and drop system-wide.
        //
        // Defer ALL work to a background queue, then dispatch the final
        // assignment back to the main queue asynchronously.
        DispatchQueue.global(qos: .userInitiated).async {
            let semaphore = DispatchSemaphore(value: 0)
            var resolvedPath: String? = nil

            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { semaphore.signal() }

                if let error {
                    Log.ui.error("Drop error: \(error.localizedDescription)")
                    return
                }

                guard let data = item as? Data,
                      let url  = URL(dataRepresentation: data, relativeTo: nil),
                      url.isFileURL
                else {
                    Log.ui.warning("Drop item not a file URL. Type: \(type(of: item))")
                    return
                }

                let finalURL = url.resolvingSymlinksInPath()
                Log.ui.info("Drop resolved to: \(finalURL.path)")

                guard MediaType.from(url: finalURL) != nil else {
                    Log.ui.warning("Unsupported type: \(finalURL.pathExtension)")
                    return
                }

                resolvedPath = finalURL.path
            }

            // Wait for loadItem to complete on the background queue —
            // safe here because we are NOT on the main thread.
            semaphore.wait()

            if let path = resolvedPath {
                // Dispatch the assignment back to main after the drop
                // IPC transaction has fully completed.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    ConfigStore.shared.setMediaPath(path, forSpaceUUID: targetUUID)
                    Log.ui.info("Assigned space \(targetUUID) -> \(URL(fileURLWithPath: path).lastPathComponent)")
                }
            }
        }

        return true
    }


    // MARK: - File Picker

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes     = MediaType.allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.message                 = "Choose an image or video for Space \(spaceIndex)"
        panel.prompt                  = "Assign"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        ConfigStore.shared.setMediaPath(url.path, forSpaceUUID: spaceUUID)
    }

    // MARK: - Thumbnail

    private func reloadThumbnail() {
        guard let path = mediaPath else {
            thumbnail  = nil
            mediaType  = nil
            return
        }

        // Clear immediately so stale thumbnail never shows for the new path
        thumbnail = nil
        mediaType = nil

        let url  = URL(fileURLWithPath: path)
        let type = MediaType.from(url: url)
        mediaType = type

        switch type {
        case .video:
            Task.detached(priority: .userInitiated) {
                let thumb = await generateVideoThumbnail(url: url)
                await MainActor.run { self.thumbnail = thumb }
            }
        case .image:
            Task.detached(priority: .userInitiated) {
                // Try multiple loading strategies — CGImageSource can fail
                // on paths with special characters or iCloud files.
                var image: NSImage? = nil

                // Strategy 1: CGImageSource with properly encoded URL
                let encodedURL = URL(fileURLWithPath: url.path)
                if let source = CGImageSourceCreateWithURL(encodedURL as CFURL, nil),
                   let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    image = NSImage(cgImage: cgImage, size: .zero)
                }

                // Strategy 2: NSImage direct load
                if image == nil {
                    image = NSImage(contentsOf: url)
                }

                // Strategy 3: NSImage by path
                if image == nil {
                    image = NSImage(contentsOfFile: url.path)
                }

                await MainActor.run {
                    self.thumbnail = image
                    Log.ui.info("Image thumbnail loaded: \(image != nil) for \(url.lastPathComponent)")
                }
            }
        case nil:
            thumbnail = nil
        }
    }

    private func generateVideoThumbnail(url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let gen   = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 400, height: 240)

        do {
            let (cgImage, _) = try await gen.image(at: .zero)
            return NSImage(cgImage: cgImage, size: .zero)
        } catch {
            Log.ui.warning("Thumbnail generation failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Star Field

/// Renders a static field of randomised stars. The star positions are
/// generated once at init time and never change, avoiding recalculation
/// on every SwiftUI render pass.
struct StarFieldView: View {

    private struct Star: Identifiable {
        let id:      Int
        let x:       CGFloat
        let y:       CGFloat
        let size:    CGFloat
        let opacity: CGFloat
    }

    // Generated once; `let` prevents SwiftUI from recreating them.
    private let stars: [Star] = (0..<120).map { i in
        Star(
            id:      i,
            x:       CGFloat.random(in: 0...1),
            y:       CGFloat.random(in: 0...1),
            size:    CGFloat.random(in: 0.5...2.0),
            opacity: CGFloat.random(in: 0.1...0.6)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(stars) { star in
                Circle()
                    .fill(Color.white.opacity(star.opacity))
                    .frame(width: star.size, height: star.size)
                    .position(x: star.x * geo.size.width, y: star.y * geo.size.height)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Ghost Button Style

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color.white.opacity(configuration.isPressed ? 0.9 : 0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
