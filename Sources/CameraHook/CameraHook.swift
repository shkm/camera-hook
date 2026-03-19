import CoreMediaIO
import Foundation

@main
struct CameraHook {
    static let scriptsBaseURL: URL = {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CameraHook")
        return appSupport
    }()

    static func main() {
        guard let deviceID = getBuiltInCameraID() else {
            print("No camera found.")
            exit(1)
        }

        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        let status = CMIOObjectAddPropertyListenerBlock(deviceID, &property, DispatchQueue.main) { _, _ in
            let running = isRunning(deviceID)
            let state = running ? "on" : "off"
            print("camera \(state)")
            fflush(stdout)
            sendNotification(state: state)
            runScripts(for: state)
        }

        guard status == noErr else {
            print("Failed to add listener: \(status)")
            exit(1)
        }

        print("Scripts directory: \(scriptsBaseURL.path)")
        print("Listening for camera events... (Ctrl+C to quit)")
        fflush(stdout)
        dispatchMain()
    }

    static func runScripts(for state: String) {
        let dir = scriptsBaseURL.appendingPathComponent(state)
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else {
            return
        }

        let scripts = entries.sorted()

        for script in scripts {
            let path = dir.appendingPathComponent(script).path
            guard fm.isExecutableFile(atPath: path) else { continue }

            print("  running \(state)/\(script)")
            fflush(stdout)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["CAMERA_HOOK_STATE": state]
            ) { _, new in new }

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("  error running \(state)/\(script): \(error.localizedDescription)")
                fflush(stdout)
            }
        }
    }

    static func sendNotification(state: String) {
        let message = state == "on" ? "Camera is now active" : "Camera is now off"
        let script = "display notification \"\(message)\" with title \"CameraHook\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    static func getBuiltInCameraID() -> CMIOObjectID? {
        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, &dataSize)

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, dataSize, &dataSize, &devices)

        return devices.first
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
}
