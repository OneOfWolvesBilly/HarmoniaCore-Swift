//
//  SystemAudioRouteAdapter.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Implements AudioRoutePort by asking the platform which output device the
//  system currently routes sound to.
//
//  One stateless class, two platform paths: the CoreAudio HAL on macOS
//  (default output device → UID → name), AVAudioSession's current route on
//  iOS. Stateless by design — every call re-queries the platform, nothing is
//  cached, and no notification is observed; route-change observation is
//  deliberately outside this port's contract.
//
//  The returned values name real hardware, so they cannot be asserted by
//  unit tests; this adapter is verified manually against the device shown in
//  the system's sound settings.
//

import Foundation
#if os(macOS)
import CoreAudio
#else
import AVFAudio
#endif

public final class SystemAudioRouteAdapter: AudioRoutePort {

    public init() {}

    public func currentOutputDevice() -> AudioOutputDevice? {
        #if os(macOS)
        guard let deviceID = defaultOutputDeviceID(),
              let uid = stringProperty(of: deviceID, selector: kAudioDevicePropertyDeviceUID),
              let name = stringProperty(of: deviceID, selector: kAudioObjectPropertyName)
        else {
            return nil
        }
        return AudioOutputDevice(id: uid, name: name)
        #else
        guard let port = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            return nil
        }
        return AudioOutputDevice(id: port.uid, name: port.portName)
        #endif
    }

    #if os(macOS)

    // MARK: - CoreAudio HAL queries (macOS)

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    private func stringProperty(of deviceID: AudioDeviceID,
                                selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr, let cfString = value?.takeRetainedValue() else {
            return nil
        }
        return cfString as String
    }

    #endif
}
