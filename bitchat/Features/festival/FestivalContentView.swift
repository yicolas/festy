import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Stores the user's own selfie locally so it can render on the map pin and
/// later be propagated to peers. Persists to Application Support so it survives
/// app updates but is wiped by the standard "Erase all content".
@MainActor
final class UserSelfieStore: ObservableObject {
    static let shared = UserSelfieStore()
    private let promptedKey = "ge136c.hasPromptedSelfie"
    private let filename = "ge136c-selfie.jpg"

    @Published var image: UIImage?
    @Published var hasPrompted: Bool {
        didSet { UserDefaults.standard.set(hasPrompted, forKey: promptedKey) }
    }

    private var fileURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true)) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(filename)
    }

    private init() {
        hasPrompted = UserDefaults.standard.bool(forKey: promptedKey)
        if let data = try? Data(contentsOf: fileURL),
           let img = UIImage(data: data) {
            image = img
        }
    }

    func save(_ image: UIImage) {
        let resized = Self.resize(image, maxDimension: 256)
        self.image = resized
        if let data = resized.jpegData(compressionQuality: 0.65) {
            try? data.write(to: fileURL, options: .atomic)
        }
        hasPrompted = true
        // Push the new selfie out to peers over Nostr + BLE.
        SelfieSyncService.shared.publishOwnSelfie()
    }

    func delete() {
        image = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    func markPrompted() {
        hasPrompted = true
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1)
        if scale >= 1 { return image }
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

/// Per-user customization for the color the user's own messages render in.
/// Persists a hex string in UserDefaults; defaults to GE136C orange.
@MainActor
final class UserChatColorStore: ObservableObject {
    static let shared = UserChatColorStore()
    private let key = "ge136c.userTextColor"
    static let defaultHex = "#FF7E15"

    @Published var hex: String {
        didSet { UserDefaults.standard.set(hex, forKey: key) }
    }

    private init() {
        hex = UserDefaults.standard.string(forKey: key) ?? Self.defaultHex
    }

    var color: Color { Color(hex: hex) ?? .orange }

    func reset() { hex = Self.defaultHex }
}

#if canImport(UIKit)
extension Color {
    /// Resolves the SwiftUI Color to a 6-digit hex string (no alpha).
    var hexString: String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp: (CGFloat) -> Int = { Int(round(max(0, min(1, $0)) * 255)) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}
#endif

#if os(iOS)
struct TextColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = UserChatColorStore.shared
    @State private var color: Color

    init() {
        _color = State(initialValue: UserChatColorStore.shared.color)
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pick the color your own messages appear in. Other people see this color on your sender name + body text in chat.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)

                ColorPicker("Message color", selection: $color, supportsOpacity: false)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(TripTheme.primaryText)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("you · just now")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(color.opacity(0.7))
                        Text("This is how your messages will look.")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(color)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TripTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(TripTheme.stroke, lineWidth: 1)
                    )
                    .cornerRadius(10)
                }

                HStack {
                    Text("Hex")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                    Text(color.hexString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.primaryText)
                    Spacer()
                    Button(action: { color = Color(hex: UserChatColorStore.defaultHex) ?? .orange }) {
                        Text("Reset")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(TripTheme.accent)
                    }
                }

                Spacer()
            }
            .padding()
            .background(TripTheme.background)
            .navigationTitle("Text Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.hex = color.hexString
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
#endif

enum InviteLink {
    /// Landing page served via GitHub Pages from the `docs/` folder of the repo.
    /// Recipients without the app installed see install instructions; recipients
    /// with the app get a button that triggers the `ge136c://join` deep link.
    static let url = URL(string: "https://yicolas.github.io/festy/")!

    static var shareText: String {
        "join me on GE136C — offline trip chat for the Sierras. install instructions: \(url.absoluteString)"
    }
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

/// Main content wrapper that shows either normal chat or trip mode.
struct TripContentView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var selfieStore = UserSelfieStore.shared
    @AppStorage("ge136c.colorScheme") private var colorSchemePreference: String = "system"

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some View {
        TripMainView()
            .environmentObject(viewModel)
            .preferredColorScheme(preferredColorScheme)
        .fullScreenCover(isPresented: Binding(
            get: { !viewModel.hasChosenNickname },
            set: { _ in }
        )) {
            NicknamePromptView()
                .environmentObject(viewModel)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.hasChosenNickname && !selfieStore.hasPrompted },
            set: { _ in }
        )) {
            SelfiePromptView()
        }
        #endif
    }
}

struct GlobalMeshBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Global mesh chat — anyone in Bluetooth range can read these messages.")
                .lineLimit(2)
            Spacer()
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange)
    }
}

#if os(iOS)
/// Camera picker wrapper for the selfie capture.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraDevice = .front
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct SelfiePromptView: View {
    @ObservedObject private var store = UserSelfieStore.shared
    @State private var showingCamera = false
    @State private var pickedImage: UIImage?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            VStack(spacing: 12) {
                if let img = pickedImage ?? store.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(TripTheme.accent, lineWidth: 3))
                } else {
                    Image(systemName: "person.crop.circle.fill.badge.plus")
                        .font(.system(size: 80))
                        .foregroundColor(TripTheme.accent)
                }

                Text("Add your face")
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(TripTheme.primaryText)

                Text("So your dot on the trip map is recognizable. You can change or delete this any time.")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 10) {
                Button(action: { showingCamera = true }) {
                    Label(pickedImage != nil || store.image != nil ? "Retake selfie" : "Take selfie", systemImage: "camera")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(TripTheme.accent)
                        .cornerRadius(10)
                }
                if pickedImage != nil {
                    Button(action: {
                        if let img = pickedImage { store.save(img) }
                    }) {
                        Text("Use this photo")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(TripTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(TripTheme.accentSoft)
                            .cornerRadius(10)
                    }
                }
                Button(action: { store.markPrompted() }) {
                    Text("Skip for now")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .background(TripTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showingCamera) {
            CameraPicker(image: $pickedImage)
                .ignoresSafeArea()
        }
    }
}
#endif

struct NicknamePromptView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @State private var draftName: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 56))
                    .foregroundColor(TripTheme.accent)

                Text("Pick your name")
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(TripTheme.primaryText)

                Text("This is how your trip group will see you in chat.")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            TextField("Your name", text: $draftName)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                #endif
                .focused($fieldFocused)
                .onSubmit(confirm)
                .padding(.horizontal, 40)

            Button(action: confirm) {
                Text("Continue")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSubmit ? TripTheme.accent : TripTheme.accent.opacity(0.4))
                    .cornerRadius(10)
            }
            .disabled(!canSubmit)
            .padding(.horizontal, 40)

            Spacer()
        }
        .background(TripTheme.background.ignoresSafeArea())
        .onAppear {
            if draftName.isEmpty, !viewModel.nickname.hasPrefix("anon") {
                draftName = viewModel.nickname
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                fieldFocused = true
            }
        }
    }

    private var canSubmit: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func confirm() {
        guard canSubmit else { return }
        viewModel.confirmNickname(draftName)
    }
}

struct TripMainView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject var scheduleManager = TripScheduleManager.shared
    @ObservedObject private var selfieStore = UserSelfieStore.shared
    @State private var selectedTabId: String = "schedule"
    @State private var isShowingShareSheet = false
    @State private var isShowingColorPicker = false
    @State private var isShowingSelfieMenu = false
    @State private var isShowingSettings = false
    #if os(iOS)
    @State private var isShowingSelfieCamera = false
    @State private var pickedSelfieImage: UIImage?
    #endif
    @AppStorage("ge136c.colorScheme") private var colorSchemePreference: String = "system"

    private var tabs: [TripTab] {
        scheduleManager.tabs
    }

    private var selectedTab: TripTab? {
        tabs.first { $0.id == selectedTabId }
    }

    var body: some View {
        VStack(spacing: 0) {
            tripBanner

            Group {
                if let tab = selectedTab {
                    tabContent(for: tab)
                } else {
                    Text("Loading...")
                        .foregroundColor(TripTheme.secondaryText)
                        .onAppear {
                            if let first = tabs.first {
                                selectedTabId = first.id
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            tabBar
        }
        .background(TripTheme.background)
        .onAppear {
            if !tabs.contains(where: { $0.id == selectedTabId }), let first = tabs.first {
                selectedTabId = first.id
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: TripTab) -> some View {
        switch tab.type {
        case .schedule:
            TripScheduleView()
        case .channels:
            TripChannelsView(
                onSelect: { channel in
                    viewModel.hashtagFilter = channel.name
                    selectedTabId = "chat"
                },
                onSelectCarTag: { tag in
                    viewModel.hashtagFilter = tag
                    selectedTabId = "chat"
                }
            )
        case .map:
            TripMapTab()
        case .chat:
            TripChatHost()
        case .info:
            TripInfoView()
        case .friends:
            FriendMapView()
        case .groups:
            NavigationStack {
                TripGroupsView()
            }
        case .custom:
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundColor(TripTheme.accent)
                Text(tab.name)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(TripTheme.primaryText)
            }
        }
    }

    private var tripBanner: some View {
        HStack {
            selfieThumb

            Text("@\(viewModel.nickname)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(TripTheme.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: 80, alignment: .leading)

            Image(systemName: "car.fill")
                .foregroundColor(TripTheme.accent)

            Text(scheduleManager.tripData?.trip.name ?? "Trip Mode")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(TripTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Menu {
                ForEach(tabs) { tab in
                    Button {
                        selectedTabId = tab.id
                    } label: {
                        Label(tab.name, systemImage: tab.icon)
                    }
                }
                Divider()
                Button {
                    isShowingShareSheet = true
                } label: {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                }
                Button {
                    isShowingSettings = true
                } label: {
                    Label("How to use & Settings", systemImage: "gear")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TripTheme.accent)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Open navigation menu")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(TripTheme.accentSoft)
        .sheet(isPresented: $isShowingSettings) {
            AppInfoView()
                .environmentObject(viewModel)
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingShareSheet) {
            ShareSheet(activityItems: [InviteLink.shareText])
        }
        .sheet(isPresented: $isShowingColorPicker) {
            TextColorPickerSheet()
        }
        .sheet(isPresented: $isShowingSelfieCamera, onDismiss: {
            if let img = pickedSelfieImage {
                selfieStore.save(img)
                pickedSelfieImage = nil
            }
        }) {
            CameraPicker(image: $pickedSelfieImage)
                .ignoresSafeArea()
        }
        .confirmationDialog("Your selfie",
                            isPresented: $isShowingSelfieMenu,
                            titleVisibility: .visible) {
            Button("Retake") { isShowingSelfieCamera = true }
            if selfieStore.image != nil {
                Button("Delete", role: .destructive) { selfieStore.delete() }
            }
            Button("Cancel", role: .cancel) {}
        }
        #endif
    }

    @ViewBuilder
    private var selfieThumb: some View {
        #if os(iOS)
        Button {
            if selfieStore.image == nil {
                isShowingSelfieCamera = true
            } else {
                isShowingSelfieMenu = true
            }
        } label: {
            Group {
                if let img = selfieStore.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill.badge.plus")
                        .font(.system(size: 18))
                        .foregroundColor(TripTheme.accent)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
            .overlay(Circle().stroke(TripTheme.accent, lineWidth: 1.5))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selfieStore.image == nil ? "Add selfie" : "Change or delete selfie")
        #else
        EmptyView()
        #endif
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button(action: {
                    selectedTabId = tab.id
                    // Opening the chat tab with no filter set lands the user in #main.
                    if tab.type == .chat,
                       viewModel.hashtagFilter == nil || viewModel.hashtagFilter?.isEmpty == true {
                        viewModel.hashtagFilter = "#main"
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19))
                        Text(tab.name)
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .foregroundColor(selectedTabId == tab.id ? TripTheme.accent : TripTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedTabId == tab.id ? TripTheme.accentSoft : .clear)
                }
            }
        }
        .background(TripTheme.background)
    }
}

/// Hosts the chat tab inside trip mode. Used to gate the chat behind an
/// encryption passcode; that gate was removed to make group messaging
/// frictionless. Now just renders the channel subheader + chat content.
struct TripChatHost: View {
    @EnvironmentObject private var viewModel: ChatViewModel
    @ObservedObject private var locationManager = LocationChannelManager.shared
    @State private var showChannelPicker = false
    @State private var showClearConfirm = false

    private var peerCount: Int {
        viewModel.allPeers.reduce(0) { count, peer in
            guard peer.peerID != viewModel.meshService.myPeerID else { return count }
            return (peer.isConnected || peer.isReachable) ? count + 1 : count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            chatMetaBar
            channelSubheader
            if viewModel.hashtagFilter == "#cars" {
                CarGroupsOverview()
                    .environmentObject(viewModel)
            } else {
                ContentView()
                    .environment(\.hidesChatHeader, true)
            }
        }
        .sheet(isPresented: $showChannelPicker) {
            LocationChannelsSheet(isPresented: $showChannelPicker)
                .environmentObject(viewModel)
                .onAppear { viewModel.isLocationChannelsSheetPresented = true }
                .onDisappear { viewModel.isLocationChannelsSheetPresented = false }
        }
        .confirmationDialog("Clear this chat log?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear chat log", role: .destructive) {
                viewModel.clearCurrentPublicTimeline()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes messages from your device only. Other phones keep their copies.")
        }
    }

    private var chatMetaBar: some View {
        HStack(spacing: 10) {
            Button(action: { showChannelPicker = true }) {
                Text("#channels")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(TripTheme.uiTint)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "person.2")
                    .font(.system(size: 12))
                Text("\(peerCount)")
                    .font(.system(.caption, design: .monospaced))
            }
            .foregroundColor(peerCount > 0 ? TripTheme.uiTint : .secondary)

            Button(action: { showClearConfirm = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
    }

    private var channelSubheader: some View {
        let activeTag: String = {
            if let tag = viewModel.hashtagFilter, !tag.isEmpty {
                return tag.hasPrefix("#") ? tag : "#\(tag)"
            }
            return "#main"
        }()
        return ZStack {
            Text(activeTag)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(TripTheme.primaryText)
                .frame(maxWidth: .infinity)

            if viewModel.hashtagFilter != nil && viewModel.hashtagFilter != "#main" {
                HStack {
                    Spacer()
                    Button(action: { viewModel.hashtagFilter = "#main" }) {
                        Text("back to #main")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(TripTheme.accent)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(TripTheme.subheaderBackground)
    }
}

/// Multi-pane overview of every discovered car group. Drivers are derived from
/// `#car-{name}` tags in the mesh timeline. Each pane is collapsible; the list
/// re-sorts so the most recently active car is on top.
struct CarGroupsOverview: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var carStore = CarAssignmentStore.shared
    @State private var expanded: Set<String> = []

    fileprivate struct CarGroup: Identifiable {
        let driver: String
        let messages: [BitchatMessage]
        let lastActivity: Date
        var id: String { driver }
    }

    private static let carTagRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "#car-([a-zA-Z0-9-]+)", options: .caseInsensitive)
    }()

    private var groups: [CarGroup] {
        guard let regex = Self.carTagRegex else { return [] }
        var byDriver: [String: [BitchatMessage]] = [:]
        for message in viewModel.messages {
            let content = message.content
            let nsRange = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, options: [], range: nsRange)
            guard !matches.isEmpty else { continue }
            // Use the first car tag in the message — a message belongs to one car.
            if let driverRange = Range(matches.first!.range(at: 1), in: content) {
                let driver = String(content[driverRange]).lowercased()
                byDriver[driver, default: []].append(message)
            }
        }
        return byDriver.map { (driver, msgs) in
            CarGroup(
                driver: driver,
                messages: msgs.sorted { $0.timestamp < $1.timestamp },
                lastActivity: msgs.map(\.timestamp).max() ?? .distantPast
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if groups.isEmpty {
                    emptyState
                } else {
                    ForEach(groups) { group in
                        CarGroupPane(
                            group: group,
                            isExpanded: expanded.contains(group.driver),
                            isMine: carStore.driver?.lowercased() == group.driver,
                            onToggle: {
                                if expanded.contains(group.driver) {
                                    expanded.remove(group.driver)
                                } else {
                                    expanded.insert(group.driver)
                                }
                            },
                            onEnter: {
                                viewModel.hashtagFilter = "#car-\(group.driver)"
                            }
                        )
                    }
                }
            }
            .padding(12)
        }
        .background(TripTheme.background)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "car.2.fill")
                .font(.largeTitle)
                .foregroundColor(TripTheme.secondaryText)
            Text("No car chats yet")
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(TripTheme.primaryText)
            Text("Cars appear here as people post #car-{driver} messages. Pick your driver from the Channels tab to start one.")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(TripTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 60)
    }

    fileprivate struct CarGroupPane: View {
        let group: CarGroup
        let isExpanded: Bool
        let isMine: Bool
        let onToggle: () -> Void
        let onEnter: () -> Void

        private var headerTitle: String {
            "\(group.driver.prefix(1).uppercased())\(group.driver.dropFirst())'s car"
        }

        private var visibleMessages: [BitchatMessage] {
            isExpanded ? Array(group.messages.suffix(15)) : Array(group.messages.suffix(2))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: onToggle) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(TripTheme.secondaryText)
                        Image(systemName: "car.fill")
                            .foregroundColor(TripTheme.accent)
                        Text(headerTitle)
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(TripTheme.primaryText)
                        if isMine {
                            Text("you")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(TripTheme.accent)
                                .cornerRadius(4)
                        }
                        Spacer()
                        Text(timeAgo(group.lastActivity))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(TripTheme.secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleMessages, id: \.id) { msg in
                        HStack(alignment: .top, spacing: 6) {
                            Text(msg.sender)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(TripTheme.accent)
                            Text(stripTags(msg.content))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(TripTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if group.messages.count > visibleMessages.count {
                        Text("… \(group.messages.count - visibleMessages.count) older")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(TripTheme.secondaryText)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 2)

                if isExpanded {
                    Button(action: onEnter) {
                        Text("Open this chat → ")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(TripTheme.accent)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(10)
            .background(TripTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(TripTheme.stroke, lineWidth: 1)
            )
            .cornerRadius(10)
        }

        private func stripTags(_ s: String) -> String {
            s.replacingOccurrences(of: "#car-[a-zA-Z0-9-]+", with: "", options: .regularExpression)
             .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func timeAgo(_ date: Date) -> String {
            let seconds = Int(-date.timeIntervalSinceNow)
            if seconds < 60 { return "now" }
            if seconds < 3600 { return "\(seconds / 60)m" }
            if seconds < 86400 { return "\(seconds / 3600)h" }
            return "\(seconds / 86400)d"
        }
    }
}

struct TripInfoView: View {
    @ObservedObject var scheduleManager = TripScheduleManager.shared
    @EnvironmentObject var viewModel: ChatViewModel
    @State private var showAppInfo: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                raftingWaiverCard
                campgroundWaiverCard
                gpsContactFormCard
                safetyCard
                kernRiverCard
                redCrossCard
                howToCard
                photoUploadCard
                feedbackCard
            }
            .padding()
        }
        .background(TripTheme.background)
        .sheet(isPresented: $showAppInfo) {
            AppInfoView()
                .environmentObject(viewModel)
        }
    }

    private var raftingWaiverCard: some View {
        mandatoryFormCard(
            title: "Rafting Waiver",
            subtitle: "Sign before the trip — tap to open form",
            icon: "pencil.and.list.clipboard",
            url: URL(string: "https://waiver.smartwaiver.com/w/5a5fdb9184660/web/?auto_tag=fh_id_345932112")!
        )
    }

    private func mandatoryFormCard(title: String, subtitle: String, icon: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.red)
                    .cornerRadius(12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚠︎ MANDATORY")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(4)
                    Text(title)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(TripTheme.onSurfaceText)
                    Text(subtitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.red)
            }
            .padding(14)
            .background(TripTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.5), lineWidth: 1.5))
            .cornerRadius(12)
        }
    }

    private var campgroundWaiverCard: some View {
        mandatoryFormCard(
            title: "Campground Liability Form",
            subtitle: "Sign before the trip — tap to open form",
            icon: "tent.fill",
            url: URL(string: "https://www.adventurecentral.com/user/web/m/wfTravelerRequest.aspx?rt=99mx9L&CLUID=fbd80c4d-b022-437f-a10b-61377bde28f4")!
        )
    }

    private var gpsContactFormCard: some View {
        mandatoryFormCard(
            title: "GPS Dept. Contact Info Form",
            subtitle: "Required for all participants — tap to open form",
            icon: "person.text.rectangle.fill",
            url: URL(string: "https://docs.google.com/forms/d/195DZvXvDZN874nnwOBHJsKCCms7bPevjT0Tj4XImj0o/viewform?edit_requested=true")!
        )
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.orange)
                    .cornerRadius(10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safety & Logistics")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(TripTheme.onSurfaceText)
                    Text("GE136C Spring 2026 · May 29 – Jun 1")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                }
            }

            Divider().background(TripTheme.stroke)

            safetyRow(icon: "person.3.fill",                 label: "Leaders",    value: "Nick Anderson · Joe Kirschvink · Sophia Westercamp")
            safetyRow(icon: "phone.fill",                    label: "Nick",        value: "(415) 500-5307  T-Mobile")
            safetyRow(icon: "phone.fill",                    label: "Joe",         value: "(213) 248-3422  Verizon")
            safetyRow(icon: "phone.fill",                    label: "Sophia",      value: "(719) 648-5461  Verizon")
            safetyRow(icon: "antenna.radiowaves.left.and.right", label: "Sat phone", value: "881651455634")

            Divider().background(TripTheme.stroke)

            safetyRow(icon: "cross.fill", label: "Hospital (Sierra)",   value: "Clovis Community MC · (559) 324-4000")
            safetyRow(icon: "cross.fill", label: "Hospital (Kernville)", value: "Kern Valley HCD · (760) 379-2681")

            Divider().background(TripTheme.stroke)

            Text("KEY HAZARDS")
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(TripTheme.accent)
            safetyBullet("Rattlesnakes — watch footing, closed-toe shoes required")
            safetyBullet("Sun / heat — SPF 30+, hat, hydrate at every stop")
            safetyBullet("River float — PFD + helmet + oar mandatory, optional activity, class 2 max")
            safetyBullet("Cold nights — Mono Creek ~7,400 ft, 35 °F possible, pack layers")
            safetyBullet("Valley Fever risk in Carrizo Plain — N95s available on request")
            safetyBullet("First aid kits — one per vehicle, group kit with Nick")

            Divider().background(TripTheme.stroke)

            Text("VEHICLES")
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(TripTheme.accent)
            Text("GPS F350 + 5 Enterprise rentals. All drivers must have defensive driving certification. Seatbelts required at all times.")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(TripTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(TripTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.4), lineWidth: 1.5))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func safetyRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(TripTheme.accent)
                .frame(width: 16)
            Text(label + ":")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(TripTheme.onSurfaceText)
                .frame(width: 95, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(TripTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func safetyBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("⚠")
                .font(.system(.caption2))
                .foregroundColor(.orange)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(TripTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var kernRiverCard: some View {
        Link(destination: URL(string: "https://waterdata.usgs.gov/monitoring-location/11186000/")!) {
            HStack(spacing: 12) {
                Image(systemName: "water.waves")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.blue)
                    .cornerRadius(12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kern River Flow Conditions")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(TripTheme.onSurfaceText)
                    Text("Live USGS gauge at Kernville — check before rafting")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(14)
            .background(TripTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.4), lineWidth: 1.5))
            .cornerRadius(12)
        }
    }

    private var redCrossCard: some View {
        Link(destination: URL(string: "https://apps.apple.com/us/app/first-aid-american-red-cross/id529379987")!) {
            HStack(spacing: 12) {
                Image(systemName: "cross.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.red)
                    .cornerRadius(12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Red Cross First Aid App")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(TripTheme.onSurfaceText)
                    Text("Step-by-step emergency guides — download before the trip")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.red)
            }
            .padding(14)
            .background(TripTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.4), lineWidth: 1.5))
            .cornerRadius(12)
        }
    }

    private var howToCard: some View {
        Button(action: { showAppInfo = true }) {
            HStack(spacing: 10) {
                Image(systemName: "book.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(TripTheme.accent)
                    .cornerRadius(10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How to use & Settings")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(TripTheme.onSurfaceText)
                    Text("Guide + every user setting")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TripTheme.secondaryText)
            }
            .contentShape(Rectangle())
            .padding(14)
            .background(TripTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(TripTheme.stroke, lineWidth: 1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var feedbackCard: some View {
        let subject = "GE136C App Feedback"
        let body = "What worked, what didn't, what would you change?\n\n— Sent from GE136C on iOS"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        let mailto = URL(string: "mailto:yick@duck.com?subject=\(encodedSubject)&body=\(encodedBody)")!
        return Link(destination: mailto) {
            HStack(spacing: 12) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(TripTheme.accent)
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Send feedback or suggestions")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(TripTheme.onSurfaceText)
                    Text("Bugs, ideas, requests → yick@duck.com")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TripTheme.accent)
            }
            .padding(14)
            .background(TripTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(TripTheme.accent.opacity(0.4), lineWidth: 1.5)
            )
            .cornerRadius(12)
        }
    }

    private var photoUploadCard: some View {
        let url = URL(string: "https://caltech.box.com/s/zxnmiov9e71oer4znp3k0f912hq7qfdi")!
        return Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(TripTheme.accent)
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Upload trip photos")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(TripTheme.onSurfaceText)
                    Text("Drop your shots into the shared Caltech Box folder.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TripTheme.accent)
            }
            .padding(14)
            .background(TripTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(TripTheme.accent.opacity(0.4), lineWidth: 1.5)
            )
            .cornerRadius(12)
        }
    }
}

#if os(iOS)
struct OfflineMapsCard: View {
    @ObservedObject private var cache = TileCacheManager.shared
    @ObservedObject private var routes = RouteCache.shared
    @State private var showingMap = false

    private var estimate: (tileCount: Int, bytes: Int) { cache.estimate(zooms: cache.preferredDetail.zooms) }

    private func formatMB(_ bytes: Int) -> String {
        String(format: "%.0f MB", Double(bytes) / 1_000_000.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Offline Trip Map")
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(TripTheme.primaryText)

            Text("Cell service drops in the Sierras. Download map tiles for the trip area now so the in-app map keeps working off-grid. Tiles are stored on this device and used the next time you open the trip map.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(TripTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Source picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Map source")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(TripTheme.primaryText)
                HStack(spacing: 8) {
                    ForEach(TileCacheManager.Source.allCases) { src in
                        let selected = cache.preferredSource == src
                        Button(action: { cache.preferredSource = src }) {
                            Text(src.displayName)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(selected ? .white : TripTheme.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity)
                                .background(selected ? Color.green : TripTheme.surface)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selected ? Color.green : Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
            }

            // Detail level picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Detail level")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(TripTheme.primaryText)
                HStack(spacing: 8) {
                    ForEach(TileCacheManager.DetailLevel.allCases) { lvl in
                        let selected = cache.preferredDetail == lvl
                        Button(action: { cache.preferredDetail = lvl }) {
                            Text(lvl.label)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(selected ? .white : TripTheme.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity)
                                .background(selected ? Color.green : TripTheme.surface)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selected ? Color.green : Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
                Text("\(cache.preferredDetail.blurb.capitalized). Zooms z\(cache.preferredDetail.zooms.lowerBound)–z\(cache.preferredDetail.zooms.upperBound) · estimated ~\(formatMB(estimate.bytes))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Status / action
            statusSection

            Divider().padding(.vertical, 4)

            // Driving routes (OSRM / OSM)
            Text("Driving routes")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(TripTheme.primaryText)
            Text("Pre-compute the day-to-day driving routes using OpenStreetMap data so they render directly on the offline map. No external app needed.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(TripTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            routesSection

            // Cache + sources
            VStack(alignment: .leading, spacing: 4) {
                Text("Currently cached: \(cache.cachedTileCount) tiles (\(formatMB(cache.cachedBytes)))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)

                Text(cache.preferredSource.attribution)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Data: OpenStreetMap contributors. Style: OpenTopoMap or OSM standard. Tiles are fetched once over your internet connection and cached for offline use; we never share your location with the tile servers beyond the standard map request.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(10)
        .sheet(isPresented: $showingMap) {
            OfflineTripMapSheet()
        }
    }

    @ViewBuilder
    private var routesSection: some View {
        switch routes.status {
        case .idle, .cancelled, .failed:
            HStack(spacing: 8) {
                Button(action: { routes.fetchAll() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up.fill")
                        Text(routes.cached.isEmpty ? "Pre-cache driving routes" : "Refresh driving routes")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(TripTheme.accent)
                    .cornerRadius(8)
                }
                if !routes.cached.isEmpty {
                    Text("\(routes.cached.count) day(s)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                    Button(action: { routes.clear() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .padding(6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }
        case .downloading(let done, let total):
            HStack {
                ProgressView(value: total == 0 ? 0 : Double(done) / Double(total))
                    .tint(TripTheme.accent)
                Text("\(done)/\(total)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
            }
        case .complete:
            Label("Routes cached (\(routes.cached.count) day(s))", systemImage: "checkmark.seal.fill")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.green)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch cache.status {
        case .idle, .cancelled, .failed:
            HStack(spacing: 8) {
                Button(action: { cache.startDownload() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download trip tiles (~\(formatMB(estimate.bytes)))")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(TripTheme.accent)
                    .cornerRadius(8)
                }
                if cache.cachedTileCount > 0 {
                    Button(action: { showingMap = true }) {
                        Text("View map")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(TripTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(TripTheme.accentSoft)
                            .cornerRadius(8)
                    }
                    Button(action: { cache.clearCache() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
        case .downloading(let done, let total):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ProgressView(value: total == 0 ? 0 : Double(done) / Double(total))
                        .tint(TripTheme.accent)
                    Text("\(done)/\(total)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                        .frame(minWidth: 70, alignment: .trailing)
                }
                Button(action: { cache.cancelDownload() }) {
                    Text("Cancel")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.red)
                }
            }
        case .complete:
            HStack(spacing: 8) {
                Label("Downloaded", systemImage: "checkmark.seal.fill")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.green)
                Spacer()
                Button(action: { showingMap = true }) {
                    Text("View offline map")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(TripTheme.accent)
                        .cornerRadius(8)
                }
                Button(action: { cache.clearCache() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
    }
}
#else
struct OfflineMapsCard: View { var body: some View { EmptyView() } }
#endif

typealias FestivalContentView = TripContentView
typealias FestivalMainView = TripMainView
typealias FestivalInfoView = TripInfoView

#if DEBUG
struct FestivalContentView_Previews: PreviewProvider {
    static var previews: some View {
        TripMainView()
    }
}
#endif
