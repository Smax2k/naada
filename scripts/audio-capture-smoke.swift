import AudioToolbox
import CoreAudio
import Darwin
import Foundation

// Harnais de preuve pour Naada : produit un sinus 440 Hz, 48 kHz, stéréo,
// amplitude 0,5 dans BlackHole 2ch uniquement. Aucun haut-parleur, aucune
// sortie par défaut, aucun réglage système. Le mode --readback relit le puits
// virtuel pour prouver que la source y produit réellement de l'audio ; il ne
// prouve pas que le tap de processus de Naada reçoit ce signal.
//
// Ce fichier est un outil de vérification, pas du code de l'application.

let blackHoleUID = "BlackHole2ch_UID"
let sampleRate = 48_000.0
let frequency = 440.0
let amplitude = 0.5
let channels: UInt32 = 2
let bytesPerFrame = UInt32(MemoryLayout<Float>.size) * channels

func fail(_ message: String, code: Int32 = 64) -> Never {
    fputs("audio-capture-smoke: \(message)\n", stderr)
    exit(code)
}

func deviceID(forUID uid: String) -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var cfUID = uid as CFString
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafeMutablePointer(to: &cfUID) { pointer in
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<CFString?>.size),
            pointer,
            &size,
            &deviceID
        )
    }
    guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
        return nil
    }
    return deviceID
}

func defaultOutputDevice() -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &deviceID
    )
    guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
        return nil
    }
    return deviceID
}

func stringProperty(
    _ objectID: AudioObjectID,
    _ selector: AudioObjectPropertySelector
) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
    }
    guard status == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
}

func uint32Property(
    _ objectID: AudioObjectID,
    _ selector: AudioObjectPropertySelector
) -> UInt32? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
    guard status == noErr, size == UInt32(MemoryLayout<UInt32>.size) else { return nil }
    return value
}

func halOutputUnit() -> AudioUnit {
    var description = AudioComponentDescription(
        componentType: kAudioUnitType_Output,
        componentSubType: kAudioUnitSubType_HALOutput,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    )
    guard let component = AudioComponentFindNext(nil, &description) else {
        fail("HAL output unit unavailable")
    }
    var unit: AudioUnit?
    let status = AudioComponentInstanceNew(component, &unit)
    guard status == noErr, let unit else {
        fail("AudioComponentInstanceNew failed (\(status))")
    }
    return unit
}

func setUInt32(
    _ unit: AudioUnit,
    _ property: AudioUnitPropertyID,
    _ scope: AudioUnitScope,
    _ element: AudioUnitElement,
    _ value: UInt32
) {
    var value = value
    let status = AudioUnitSetProperty(
        unit,
        property,
        scope,
        element,
        &value,
        UInt32(MemoryLayout<UInt32>.size)
    )
    guard status == noErr else {
        fail("AudioUnitSetProperty \(property) failed (\(status))")
    }
}

func setDevice(_ unit: AudioUnit, _ deviceID: AudioObjectID) {
    var deviceID = deviceID
    let status = AudioUnitSetProperty(
        unit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &deviceID,
        UInt32(MemoryLayout<AudioObjectID>.size)
    )
    guard status == noErr else {
        fail("cannot select BlackHole output device (\(status))")
    }
}

func setFloatFormat(
    _ unit: AudioUnit,
    _ scope: AudioUnitScope,
    _ element: AudioUnitElement
) {
    var format = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: bytesPerFrame,
        mFramesPerPacket: 1,
        mBytesPerFrame: bytesPerFrame,
        mChannelsPerFrame: channels,
        mBitsPerChannel: 32,
        mReserved: 0
    )
    let status = AudioUnitSetProperty(
        unit,
        kAudioUnitProperty_StreamFormat,
        scope,
        element,
        &format,
        UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    )
    guard status == noErr else {
        fail("AudioUnitSetProperty StreamFormat failed (\(status))")
    }
}

func resolveBlackHole() -> AudioObjectID {
    guard let blackHole = deviceID(forUID: blackHoleUID) else {
        fail("BlackHole 2ch (\(blackHoleUID)) not found")
    }
    if let output = defaultOutputDevice(), output == blackHole {
        fail("refusing to use BlackHole while it is the default output device")
    }
    return blackHole
}

// MARK: - Source

final class SourceState: @unchecked Sendable {
    private let lock = NSLock()
    private var phase = 0.0
    private var renderedFrames: UInt64 = 0
    private var callbacks: UInt64 = 0

    let increment = 2.0 * Double.pi * frequency / sampleRate

    func render(
        _ ioData: UnsafeMutablePointer<AudioBufferList>?,
        frames: UInt32
    ) {
        guard let ioData else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        guard let buffer = buffers.first, let data = buffer.mData else { return }

        let frameCount = Int(frames)
        let samples = data.bindMemory(
            to: Float.self,
            capacity: frameCount * Int(channels)
        )
        lock.lock()
        var current = phase
        for frame in 0..<frameCount {
            let value = Float(sin(current) * amplitude)
            samples[frame * 2] = value
            samples[frame * 2 + 1] = value
            current += increment
            if current >= 2.0 * Double.pi {
                current -= 2.0 * Double.pi
            }
        }
        phase = current
        renderedFrames += UInt64(frameCount)
        callbacks += 1
        lock.unlock()
    }

    var snapshot: (frames: UInt64, callbacks: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (renderedFrames, callbacks)
    }
}

func runSource(seconds: Double) -> Never {
    let blackHole = resolveBlackHole()
    let name = stringProperty(blackHole, kAudioObjectPropertyName) ?? "?"
    let uid = stringProperty(blackHole, kAudioDevicePropertyDeviceUID) ?? "?"

    let unit = halOutputUnit()
    setUInt32(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, 0)
    setUInt32(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, 1)
    setDevice(unit, blackHole)
    setFloatFormat(unit, kAudioUnitScope_Input, 0)

    let state = SourceState()
    var callback = AURenderCallbackStruct(
        inputProc: { reference, _, _, _, frames, ioData in
            let state = Unmanaged<SourceState>
                .fromOpaque(reference)
                .takeUnretainedValue()
            state.render(ioData, frames: frames)
            return noErr
        },
        inputProcRefCon: Unmanaged.passUnretained(state).toOpaque()
    )
    let callbackStatus = AudioUnitSetProperty(
        unit,
        kAudioUnitProperty_SetRenderCallback,
        kAudioUnitScope_Input,
        0,
        &callback,
        UInt32(MemoryLayout<AURenderCallbackStruct>.size)
    )
    guard callbackStatus == noErr else {
        fail("cannot install render callback (\(callbackStatus))")
    }

    let initStatus = AudioUnitInitialize(unit)
    guard initStatus == noErr else {
        fail("AudioUnitInitialize failed (\(initStatus))")
    }
    let startStatus = AudioOutputUnitStart(unit)
    guard startStatus == noErr else {
        fail("AudioOutputUnitStart failed (\(startStatus))")
    }

    let ready: [String: Any] = [
        "pid": Int(getpid()),
        "device": name,
        "uid": uid,
        "frequency": frequency,
        "amplitude": amplitude,
        "sampleRate": sampleRate,
        "channels": channels,
        "seconds": seconds,
        "generatedRMS": amplitude / 2.0.squareRoot(),
        "defaultOutputUntouched": true,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: ready, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print("NAADA_SOURCE_READY \(text)")
        fflush(stdout)
    }

    Thread.sleep(forTimeInterval: max(1, seconds))

    let snapshot = state.snapshot
    let done: [String: Any] = [
        "pid": Int(getpid()),
        "renderedFrames": snapshot.frames,
        "callbacks": snapshot.callbacks,
        "seconds": seconds,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: done, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print("NAADA_SOURCE_DONE \(text)")
        fflush(stdout)
    }
    _ = AudioOutputUnitStop(unit)
    _ = AudioUnitUninitialize(unit)
    _ = AudioComponentInstanceDispose(unit)
    exit(snapshot.frames > 0 ? 0 : 3)
}

// MARK: - Readback (prouve le signal dans BlackHole, pas le tap)

final class ReadbackState: @unchecked Sendable {
    private let lock = NSLock()
    private var maximumRMS: Float = 0
    private var callbacks: UInt64 = 0
    private var frames: UInt64 = 0
    private var failures: UInt64 = 0

    func record(rms: Float, frameCount: Int) {
        lock.lock()
        maximumRMS = max(maximumRMS, rms)
        callbacks += 1
        frames += UInt64(frameCount)
        lock.unlock()
    }

    func recordFailure() {
        lock.lock()
        failures += 1
        lock.unlock()
    }

    var snapshot: (rms: Float, callbacks: UInt64, frames: UInt64, failures: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (maximumRMS, callbacks, frames, failures)
    }
}

func runReadback(seconds: Double) -> Never {
    let blackHole = resolveBlackHole()
    let name = stringProperty(blackHole, kAudioObjectPropertyName) ?? "?"
    let uid = stringProperty(blackHole, kAudioDevicePropertyDeviceUID) ?? "?"

    let unit = halOutputUnit()
    setUInt32(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, 1)
    setUInt32(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, 0)
    setDevice(unit, blackHole)
    // Format des données remises au callback d'entrée (sortie de l'élément 1).
    setFloatFormat(unit, kAudioUnitScope_Output, 1)

    let state = ReadbackState()
    let context = ReadbackContext(unit: unit, state: state)
    var inputCallback = AURenderCallbackStruct(
        inputProc: { reference, actionFlags, timeStamp, _, frames, _ in
            let context = Unmanaged<ReadbackContext>
                .fromOpaque(reference)
                .takeUnretainedValue()
            context.pull(actionFlags, timeStamp, frames: frames)
            return noErr
        },
        inputProcRefCon: Unmanaged.passUnretained(context).toOpaque()
    )
    let callbackStatus = AudioUnitSetProperty(
        unit,
        kAudioOutputUnitProperty_SetInputCallback,
        kAudioUnitScope_Global,
        0,
        &inputCallback,
        UInt32(MemoryLayout<AURenderCallbackStruct>.size)
    )
    guard callbackStatus == noErr else {
        fail("cannot install input callback (\(callbackStatus))")
    }

    let initStatus = AudioUnitInitialize(unit)
    guard initStatus == noErr else {
        fail("AudioUnitInitialize failed (\(initStatus))")
    }
    let startStatus = AudioOutputUnitStart(unit)
    guard startStatus == noErr else {
        fail("AudioOutputUnitStart failed (\(startStatus))")
    }

    Thread.sleep(forTimeInterval: max(1, seconds))

    let snapshot = state.snapshot
    let result: [String: Any] = [
        "pid": Int(getpid()),
        "device": name,
        "uid": uid,
        "maxRMS": Double(snapshot.rms),
        "callbacks": snapshot.callbacks,
        "frames": snapshot.frames,
        "failures": snapshot.failures,
        "sampleRate": sampleRate,
        "channels": channels,
        "seconds": seconds,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print("NAADA_READBACK \(text)")
        fflush(stdout)
    }
    _ = AudioOutputUnitStop(unit)
    _ = AudioUnitUninitialize(unit)
    _ = AudioComponentInstanceDispose(unit)
    context.deallocate()
    exit(snapshot.rms > 0.02 && snapshot.callbacks > 0 ? 0 : 3)
}

/// Contexte du callback d'entrée : aucune capture de closure, tout est
/// accessible depuis `inputProcRefCon`.
final class ReadbackContext: @unchecked Sendable {
    private let unit: AudioUnit
    private let state: ReadbackState
    private let maximumFrames: UInt32 = 4096
    private let raw: UnsafeMutableRawPointer
    private let bufferList: UnsafeMutableAudioBufferListPointer

    init(unit: AudioUnit, state: ReadbackState) {
        self.unit = unit
        self.state = state
        let bytes = Int(maximumFrames) * Int(bytesPerFrame)
        raw = UnsafeMutableRawPointer.allocate(
            byteCount: bytes,
            alignment: MemoryLayout<Float>.alignment
        )
        bufferList = AudioBufferList.allocate(maximumBuffers: 1)
        bufferList[0] = AudioBuffer(
            mNumberChannels: channels,
            mDataByteSize: UInt32(bytes),
            mData: raw
        )
    }

    func pull(
        _ actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>?,
        _ timeStamp: UnsafePointer<AudioTimeStamp>,
        frames: UInt32
    ) {
        bufferList[0].mDataByteSize = maximumFrames * bytesPerFrame
        let status = AudioUnitRender(
            unit,
            actionFlags,
            timeStamp,
            1,
            frames,
            bufferList.unsafeMutablePointer
        )
        guard status == noErr, let data = bufferList[0].mData else {
            state.recordFailure()
            return
        }
        let samples = data.bindMemory(
            to: Float.self,
            capacity: Int(frames) * Int(channels)
        )
        var sum = 0.0
        for index in 0..<(Int(frames) * Int(channels)) {
            let value = Double(samples[index])
            sum += value * value
        }
        let rms = Float((sum / Double(Int(frames) * Int(channels))).squareRoot())
        state.record(rms: rms, frameCount: Int(frames))
    }

    func deallocate() {
        free(bufferList.unsafeMutablePointer)
        raw.deallocate()
    }
}

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
var readback = false
var seconds = 20.0

while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "--readback":
        readback = true
    case "--seconds":
        guard let value = arguments.first, let parsed = Double(value), parsed > 0 else {
            fail("--seconds expects a positive number")
        }
        arguments.removeFirst()
        seconds = min(120, parsed)
    case "--help", "-h":
        print("usage: audio-capture-smoke [--readback] [--seconds N]")
        exit(0)
    default:
        fail("unknown argument: \(argument)")
    }
}

if readback {
    runReadback(seconds: seconds)
} else {
    runSource(seconds: seconds)
}
