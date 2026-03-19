import CoreMediaIO
import Foundation

@main
struct CameraHook {
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
            if running {
                print("camera on")
            } else {
                print("camera off")
            }
        }

        guard status == noErr else {
            print("Failed to add listener: \(status)")
            exit(1)
        }

        print("Listening for camera events... (Ctrl+C to quit)")
        fflush(stdout)
        dispatchMain()
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
