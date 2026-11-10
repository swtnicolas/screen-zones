import AppKit
import IOKit
import PrivateAPI

enum Displays {
    static func online() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func uuid(_ id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func active() -> [CGDirectDisplayID] {
        online()
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .sorted { CGDisplayBounds($0).minX < CGDisplayBounds($1).minX }
    }

    static func display(uuid: String) -> CGDirectDisplayID? {
        active().first { Self.uuid($0) == uuid }
    }

    static func name(of id: CGDirectDisplayID) -> String? {
        NSScreen.screens.first { $0.displayID == id }?.localizedName
    }

    static func nativeSize(of id: CGDirectDisplayID) -> CGSize? {
        let modes = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] ?? []
        if let native = modes.first(where: { $0.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 }) {
            return CGSize(width: native.pixelWidth, height: native.pixelHeight)
        }
        guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        return CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
    }

    static func showingFullScreen() -> Set<String> {
        let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? []
        return displays.reduce(into: []) { covered, display in
            guard let identifier = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any], current["type"] as? Int == 4 else { return }
            if identifier == "Main" {
                covered.formUnion(NSScreen.screens.compactMap(\.uuid))
            } else {
                covered.insert(identifier)
            }
        }
    }
}
