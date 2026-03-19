import CoreMediaIO
import Foundation

@main
struct CameraHook {
    static let label = "me.schembri.apps.camerahook"

    static let scriptsBaseURL: URL = {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CameraHook")
        return appSupport
    }()

    static let logPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CameraHook.log").path
    }()

    static let domain = "gui/\(getuid())"

    static let launchAgentURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }()

    static func main() {
        let args = CommandLine.arguments.dropFirst()
        let command = args.first

        switch command {
        case "watch":
            watch()
        case "status":
            status()
        case "install":
            install()
        case "uninstall":
            uninstall()
        case "restart":
            restart()
        case "logs":
            let follow = args.dropFirst().contains("-f")
            logs(follow: follow)
        case "help", "--help", "-h":
            printUsage()
        default:
            printUsage()
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        CameraHook - Run scripts when your camera turns on or off

        Usage: CameraHook <command>

        Commands:
          watch       Start listening for camera events and run scripts
          status      Show whether the launchd agent is installed and running
          install     Install the launchd agent for background operation
          uninstall   Uninstall the launchd agent
          restart     Restart the launchd agent
          logs [-f]   Show logs (use -f to follow)

        Scripts directory:
          \(scriptsBaseURL.path)/on/    Scripts to run when camera turns on
          \(scriptsBaseURL.path)/off/   Scripts to run when camera turns off

        Scripts are executed in lexical order with CAMERA_HOOK_STATE=on|off set.
        """)
    }

    // MARK: - Launch Agent

    static func status() {
        let installed = FileManager.default.fileExists(atPath: launchAgentURL.path)
        print("Installed: \(installed ? "yes" : "no")")

        if installed {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["print", "\(domain)/\(label)"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try? process.run()
            process.waitUntilExit()
            let running = process.terminationStatus == 0
            print("Running:   \(running ? "yes" : "no")")
        }

        let fm = FileManager.default
        for state in ["on", "off"] {
            let dir = scriptsBaseURL.appendingPathComponent(state)
            let entries = (try? fm.contentsOfDirectory(atPath: dir.path))?.sorted() ?? []
            let scripts = entries.filter { fm.isExecutableFile(atPath: dir.appendingPathComponent($0).path) }
            print("")
            print("Scripts (\(state)): \(scripts.isEmpty ? "none" : "")")
            for script in scripts {
                print("  \(state)/\(script)")
            }
        }
    }

    static func install() {
        let binaryPath = ProcessInfo.processInfo.arguments[0]
        let resolvedPath = URL(fileURLWithPath: binaryPath).standardized.path

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [resolvedPath, "watch"],
            "KeepAlive": true,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]

        let data = try! PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )

        let dir = launchAgentURL.deletingLastPathComponent()
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! data.write(to: launchAgentURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootstrap", domain, launchAgentURL.path]
        try? process.run()
        process.waitUntilExit()

        print("Installed and loaded launch agent.")
        print("Binary: \(resolvedPath)")
    }

    static func uninstall() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: launchAgentURL.path) else {
            print("Launch agent not installed.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "\(domain)/\(label)"]
        try? process.run()
        process.waitUntilExit()

        try! fm.removeItem(at: launchAgentURL)
        print("Unloaded and uninstalled launch agent.")
    }

    static func restart() {
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "\(domain)/\(label)"]
        try? bootout.run()
        bootout.waitUntilExit()

        let bootstrap = Process()
        bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrap.arguments = ["bootstrap", domain, launchAgentURL.path]
        try? bootstrap.run()
        bootstrap.waitUntilExit()

        print("Restarted launch agent.")
    }

    static func logs(follow: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        process.arguments = follow ? ["-f", logPath] : ["-n", "50", logPath]

        signal(SIGINT, SIG_DFL)
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Camera Watcher

    static func watch() {
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

    // MARK: - Scripts

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

    // MARK: - Camera

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
