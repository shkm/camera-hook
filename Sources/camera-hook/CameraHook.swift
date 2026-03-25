import CoreMediaIO
import Foundation

@main
struct CameraHook {
    static let scriptsBaseURL: URL = {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/camera-hook")
        return appSupport
    }()

    static func main() {
        let args = CommandLine.arguments.dropFirst()
        let command = args.first

        switch command {
        case "watch":
            watch()
        case "status":
            status()
        case "help", "--help", "-h":
            printUsage()
        case "--version":
            print(version)
        default:
            printUsage()
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        camera-hook \(version) - Run scripts when your camera turns on or off

        Usage: camera-hook <command>

        Commands:
          watch       Start listening for camera events and run scripts
          status      Show installed scripts

        Scripts directory:
          \(scriptsBaseURL.path)/on/    Scripts to run when camera turns on
          \(scriptsBaseURL.path)/off/   Scripts to run when camera turns off

        Scripts are executed in lexical order with CAMERA_HOOK_STATE=on|off set.
        """)
    }

    // MARK: - Status

    static func status() {
        let fm = FileManager.default
        for state in ["on", "off"] {
            let dir = scriptsBaseURL.appendingPathComponent(state)
            let entries = (try? fm.contentsOfDirectory(atPath: dir.path))?.sorted() ?? []
            let scripts = entries.filter { fm.isExecutableFile(atPath: dir.appendingPathComponent($0).path) }
            print("Scripts (\(state)): \(scripts.isEmpty ? "none" : "")")
            for script in scripts {
                print("  \(state)/\(script)")
            }
            if state == "on" { print("") }
        }
    }

    // MARK: - Camera Watcher

    /// Tracks which devices we're currently listening to, so we can detect additions/removals.
    /// All access happens on the main queue (via DispatchQueue.main listener blocks).
    nonisolated(unsafe) static var monitoredDevices: Set<CMIOObjectID> = []

    static func watch() {
        let devices = getAllCameraIDs()

        if devices.isEmpty {
            log("No cameras found. Waiting for a camera to be connected...")
        } else {
            log("Found \(devices.count) camera(s)")
            for device in devices {
                addCameraListener(device)
            }
        }

        addDeviceListListener()

        log("Scripts directory: \(scriptsBaseURL.path)")
        log("Listening for camera events... (Ctrl+C to quit)")
        fflush(stdout)
        dispatchMain()
    }

    /// Listens for changes to the system-wide device list (cameras plugged in or removed).
    static func addDeviceListListener() {
        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        let status = CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject), &property, DispatchQueue.main
        ) { _, _ in
            handleDeviceListChanged()
        }

        guard status == noErr else {
            log("Failed to add device list listener: \(status)")
            exit(1)
        }
    }

    /// Called when the system device list changes. Diffs against our tracked set
    /// to add listeners for new cameras and remove listeners for unplugged ones.
    static func handleDeviceListChanged() {
        let currentDevices = Set(getAllCameraIDs())
        let added = currentDevices.subtracting(monitoredDevices)
        let removed = monitoredDevices.subtracting(currentDevices)

        for device in removed {
            removeCameraListener(device)
        }

        for device in added {
            addCameraListener(device)
        }
    }

    /// Registers a listener for camera on/off events on the given device.
    static func addCameraListener(_ deviceID: CMIOObjectID) {
        let name = getDeviceName(deviceID)
        log("Watching camera: \(name) (id: \(deviceID))")

        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        let status = CMIOObjectAddPropertyListenerBlock(deviceID, &property, DispatchQueue.main) { _, _ in
            let running = isRunning(deviceID)
            let state = running ? "on" : "off"
            log("camera \(state) (\(name))")
            fflush(stdout)
            runScripts(for: state, cameraName: name)
        }

        if status == noErr {
            monitoredDevices.insert(deviceID)
        } else {
            log("Failed to add listener for \(name) (id: \(deviceID)): \(status)")
        }

        fflush(stdout)
    }

    /// Removes the listener for a camera that has been unplugged.
    static func removeCameraListener(_ deviceID: CMIOObjectID) {
        log("Camera removed (id: \(deviceID))")
        monitoredDevices.remove(deviceID)
        // Note: CMIOObjectRemovePropertyListenerBlock requires the original block reference,
        // which we don't retain. The listener is effectively dead once the device is gone,
        // so removal from our tracked set is sufficient.
        fflush(stdout)
    }

    // MARK: - Scripts

    static func runScripts(for state: String, cameraName: String) {
        let dir = scriptsBaseURL.appendingPathComponent(state)
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else {
            return
        }

        let scripts = entries.sorted()

        for script in scripts {
            let path = dir.appendingPathComponent(script).path
            guard fm.isExecutableFile(atPath: path) else { continue }

            log("  running \(state)/\(script)")
            fflush(stdout)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["CAMERA_HOOK_STATE": state, "CAMERA_HOOK_DEVICE": cameraName]
            ) { _, new in new }

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                log("  error running \(state)/\(script): \(error.localizedDescription)")
                fflush(stdout)
            }
        }
    }

    // MARK: - Camera

    /// Returns all camera device IDs currently known to the system.
    static func getAllCameraIDs() -> [CMIOObjectID] {
        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, &dataSize)

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        guard count > 0 else { return [] }

        var devices = [CMIOObjectID](repeating: 0, count: count)
        CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, dataSize, &dataSize, &devices)

        return devices
    }

    /// Returns a human-readable name for a camera device.
    static func getDeviceName(_ deviceID: CMIOObjectID) -> String {
        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        let sizeStatus = CMIOObjectGetPropertyDataSize(deviceID, &property, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return "Unknown" }

        var name = Unmanaged<CFString>.passUnretained("" as CFString)
        let status = CMIOObjectGetPropertyData(deviceID, &property, 0, nil, dataSize, &dataSize, &name)

        if status == noErr {
            return name.takeUnretainedValue() as String
        }
        return "Unknown"
    }

    static func isRunning(_ deviceID: CMIOObjectID) -> Bool {
        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var running: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        CMIOObjectGetPropertyData(deviceID, &property, 0, nil, dataSize, &dataSize, &running)
        return running != 0
    }

    // MARK: - Logging

    static func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] \(message)")
        fflush(stdout)
    }
}
