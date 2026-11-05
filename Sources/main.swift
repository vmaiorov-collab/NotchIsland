import AppKit
import SwiftUI
import IOKit.ps
import ServiceManagement

// MARK: - SkyLight (private): a dedicated top-level space keeps the window pinned during desktop switches

@_silgen_name("SLSMainConnectionID") func SLSMainConnectionID() -> Int32
@_silgen_name("SLSSpaceCreate") func SLSSpaceCreate(_ cid: Int32, _ flag: Int32, _ options: CFDictionary?) -> Int32
@_silgen_name("SLSSpaceSetAbsoluteLevel") func SLSSpaceSetAbsoluteLevel(_ cid: Int32, _ space: Int32, _ level: Int32)
@_silgen_name("SLSShowSpaces") func SLSShowSpaces(_ cid: Int32, _ spaces: CFArray)
@_silgen_name("SLSSpaceAddWindowsAndRemoveFromSpaces") func SLSSpaceAddWindowsAndRemoveFromSpaces(_ cid: Int32, _ space: Int32, _ windows: CFArray, _ flags: Int32)

func pinToTopSpace(_ window: NSWindow) {
    let cid = SLSMainConnectionID()
    let space = SLSSpaceCreate(cid, 1, nil)
    SLSSpaceSetAbsoluteLevel(cid, space, 2147483647)
    SLSShowSpaces(cid, [space] as CFArray)
    SLSSpaceAddWindowsAndRemoveFromSpaces(cid, space, [window.windowNumber] as CFArray, 7)
}

// MARK: - Geometry

struct NotchGeometry {
    let screen: NSScreen
    var hasNotch: Bool { screen.safeAreaInsets.top > 0 }
    var notchHeight: CGFloat { hasNotch ? screen.safeAreaInsets.top : 28 }
    var notchWidth: CGFloat {
        if hasNotch, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return screen.frame.width - l.width - r.width
        }
        return 170
    }
}

func notchScreen() -> NSScreen {
    NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
}

// MARK: - Media

enum Player: String { case music = "Music", spotify = "Spotify"
    var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
}

final class Model: ObservableObject {
    @Published var expanded = false
    @Published var playing = false
    @Published var hasTrack = false
    @Published var title = ""
    @Published var artist = ""
    @Published var battery = 100
    @Published var charging = false
    var geo = NotchGeometry(screen: notchScreen())
    var activePlayer: Player?

    private let q = DispatchQueue(label: "media")

    var size: CGSize {
        if expanded {
            return CGSize(width: max(geo.notchWidth + 220, 400), height: geo.notchHeight + 96)
        }
        let wings: CGFloat = hasTrack && playing ? 90 : 0
        return CGSize(width: geo.notchWidth + wings, height: geo.notchHeight)
    }

    func refresh() {
        q.async { [weak self] in
            guard let self else { return }
            let np = Self.nowPlaying()
            let bat = Self.readBattery()
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                    self.hasTrack = np != nil
                    self.playing = np?.2 ?? false
                    self.title = np?.0 ?? ""
                    self.artist = np?.1 ?? ""
                    self.battery = bat.0
                    self.charging = bat.1
                }
            }
        }
    }

    /// Reads the system-wide Now Playing info. MediaRemote is blocked for third-party
    /// processes on recent macOS, so the helper dylib is loaded inside /usr/bin/perl (a platform binary).
    static func nowPlaying() -> (String, String, Bool)? {
        guard let lib = Bundle.main.path(forResource: "libnp", ofType: "dylib") else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", "use DynaLoader; my $l=DynaLoader::dl_load_file($ARGV[0],0) or exit 1; my $s=DynaLoader::dl_find_symbol($l,'np_get') or exit 1; DynaLoader::dl_install_xsub('main::np',$s); np();", lib]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let parts = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .newlines).components(separatedBy: "\t")
        guard parts.count >= 3, !parts[0].isEmpty else { return nil }
        return (parts[0], parts[1], parts[2] == "1")
    }

    /// Sends a media key (works with any app that owns Now Playing: Yandex Music, Spotify, Music, browsers…).
    func command(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refresh() }
    }

    static func readBattery() -> (Int, Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let d = IOPSGetPowerSourceDescription(info, first)?.takeUnretainedValue() as? [String: Any]
        else { return (100, false) }
        let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 100
        let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
        let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
        return (cur * 100 / Swift.max(max, 1), charging)
    }
}

// MARK: - UI

struct Equalizer: View {
    var active: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    let h = active ? 5 + 11 * abs(sin(t * 4 + Double(i) * 1.3)) : 4
                    Capsule().fill(Color.green).frame(width: 3, height: h)
                }
            }.frame(height: 16)
        }
    }
}

struct IslandView: View {
    @ObservedObject var m: Model

    var body: some View {
        let s = m.size
        let nh = m.geo.notchHeight
        let nw = m.geo.notchWidth
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: m.expanded ? 28 : 14,
                                   bottomTrailingRadius: m.expanded ? 28 : 14)
                .fill(Color.black)

            if m.expanded {
                VStack(spacing: 0) {
                    HStack {
                        Text(Date(), style: .time).font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: nw)
                        HStack(spacing: 4) {
                            Text("\(m.battery)%").font(.system(size: 13, weight: .semibold))
                            Image(systemName: m.charging ? "battery.100.bolt" : batteryIcon)
                                .foregroundStyle(m.charging || m.battery > 20 ? Color.green : Color.red)
                        }
                    }
                    .padding(.horizontal, 22).frame(height: nh)

                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 48, height: 48)
                            .overlay(Image(systemName: "music.note").font(.title2))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.hasTrack ? m.title : "Ничего не играет").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text(m.hasTrack ? m.artist : "Включите музыку").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if m.hasTrack {
                            HStack(spacing: 14) {
                                btn("backward.fill") { m.command(18) }
                                btn(m.playing ? "pause.fill" : "play.fill") { m.command(16) }
                                btn("forward.fill") { m.command(17) }
                            }
                        }
                    }
                    .padding(.horizontal, 22).padding(.top, 6)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .transition(.opacity.animation(.easeInOut(duration: 0.2).delay(0.1)))
            } else if m.hasTrack && m.playing {
                HStack {
                    Image(systemName: "music.note").foregroundStyle(.pink).font(.system(size: 13)).padding(.leading, 14)
                    Spacer()
                    Equalizer(active: true).padding(.trailing, 14)
                }
                .frame(height: nh)
                .transition(.opacity)
            }
        }
        .frame(width: s.width, height: s.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: m.expanded)
    }

    var batteryIcon: String {
        switch m.battery { case ..<13: "battery.0"; case ..<38: "battery.25"; case ..<63: "battery.50"; case ..<88: "battery.75"; default: "battery.100" }
    }

    func btn(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 16)) }.buttonStyle(.plain)
    }
}

// MARK: - App

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var panel: Panel!
    var statusItem: NSStatusItem!
    var collapseAt: Date?
    let canvas = CGSize(width: 520, height: 220)

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: IslandView(m: model))
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        place()
        panel.orderFrontRegardless()
        pinToTopSpace(panel)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.place() }

        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.model.refresh() }
        model.refresh()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        setupMenu()
    }

    func place() {
        let screen = notchScreen()
        model.geo = NotchGeometry(screen: screen)
        let f = screen.frame
        panel.setFrame(NSRect(x: f.midX - canvas.width / 2, y: f.maxY - canvas.height, width: canvas.width, height: canvas.height), display: true)
        model.objectWillChange.send()
    }

    func tick() {
        let mouse = NSEvent.mouseLocation
        let f = model.geo.screen.frame
        let s = model.size
        // hit area in screen coords (a few px of tolerance, and extends past the top edge)
        let padX: CGFloat = model.expanded ? 20 : 90
        let padY: CGFloat = model.expanded ? 20 : 40
        let rect = NSRect(x: f.midX - s.width / 2 - padX, y: f.maxY - s.height - padY, width: s.width + padX * 2, height: s.height + padY + 20)
        let inside = rect.contains(mouse)
        panel.ignoresMouseEvents = !inside
        if inside {
            collapseAt = nil
            if !model.expanded { model.expanded = true }
        } else if model.expanded {
            if collapseAt == nil { collapseAt = Date().addingTimeInterval(0.25) }
            if let c = collapseAt, Date() > c { model.expanded = false; collapseAt = nil }
        }
    }

    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "NotchIsland")
        let menu = NSMenu()
        let login = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func toggleLogin(_ item: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister(); item.state = .off }
            else { try SMAppService.mainApp.register(); item.state = .on }
        } catch { NSSound.beep() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
