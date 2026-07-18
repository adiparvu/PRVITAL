import Foundation
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

/// Connects to standards-compliant Bluetooth blood-glucose meters — **Contour**
/// (Next One / Plus), **Accu-Chek** (Guide / Instant / Aviva Connect) and any
/// other meter implementing the Bluetooth SIG **Glucose Profile** — and downloads
/// their stored readings.
///
/// The `GlucoseSource` façade is `@MainActor` (like every source). The actual
/// CoreBluetooth work runs in a separate `BluetoothGlucoseScanner` that confines
/// all of its non-Sendable CoreBluetooth state to a private dispatch queue and
/// hands back only the `Sendable` result, so nothing crosses an isolation
/// boundary unsafely.
@MainActor
final class BluetoothGlucoseMeterSource: GlucoseSource {
    let source: DataSource = .bloodGlucoseMeter
    private(set) var connectionState: SourceConnectionState = .notConnected

    #if canImport(CoreBluetooth)
    private let scanner = BluetoothGlucoseScanner()
    var isAvailable: Bool { true }

    func requestAccess() async throws {
        connectionState = .connecting
        do {
            try await scanner.ensureAuthorized()
            connectionState = .connected
        } catch {
            connectionState = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
            throw error
        }
    }

    func fetchLatest() async throws -> NormalizedGlucoseSample? {
        try await fetchSamples(since: .distantPast).max { $0.timestamp < $1.timestamp }
    }

    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample] {
        try await scanner.downloadRecords(since: date)
    }
    #else
    var isAvailable: Bool { false }
    func requestAccess() async throws { throw SourceError.unavailable }
    func fetchLatest() async throws -> NormalizedGlucoseSample? { nil }
    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample] { [] }
    #endif
}

#if canImport(CoreBluetooth)
/// The CoreBluetooth engine. Everything runs on `queue`: the manager delivers its
/// callbacks there, and all public entry points dispatch onto it, so the mutable
/// state and the non-Sendable CoreBluetooth objects are single-queue-confined —
/// which is what `@unchecked Sendable` asserts here.
final class BluetoothGlucoseScanner: NSObject, @unchecked Sendable {
    private static let glucoseService = CBUUID(string: "1808")
    private static let measurementCharacteristic = CBUUID(string: "2A18")
    private static let racpCharacteristic = CBUUID(string: "2A52")

    private let queue = DispatchQueue(label: "app.prvital.bluetooth.glucose")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var measurementChar: CBCharacteristic?
    private var racpChar: CBCharacteristic?
    private var notifyReady = Set<CBUUID>()

    private var collected: [GlucoseMeasurementRecord] = []
    private var sinceDate: Date = .distantPast
    private var meterName = "Glucose meter"

    private var authContinuation: CheckedContinuation<Void, Error>?
    private var downloadContinuation: CheckedContinuation<[NormalizedGlucoseSample], Error>?
    private var timeout: DispatchWorkItem?

    // MARK: Public API (dispatch onto `queue`)

    func ensureAuthorized() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.ensureCentral()
                switch self.central?.state {
                case .poweredOn: continuation.resume()
                case .unauthorized: continuation.resume(throwing: SourceError.notAuthorized)
                case .unsupported: continuation.resume(throwing: SourceError.unavailable)
                default:
                    // Waiting for the first state callback.
                    self.authContinuation = continuation
                    let work = DispatchWorkItem { [weak self] in
                        self?.resumeAuth(throwing: SourceError.underlying("Bluetooth didn't power on in time"))
                    }
                    self.queue.asyncAfter(deadline: .now() + 6, execute: work)
                }
            }
        }
    }

    func downloadRecords(since date: Date) async throws -> [NormalizedGlucoseSample] {
        try await ensureAuthorized()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[NormalizedGlucoseSample], Error>) in
            queue.async {
                guard self.downloadContinuation == nil else { continuation.resume(returning: []); return }
                self.downloadContinuation = continuation
                self.sinceDate = date
                self.collected = []
                self.notifyReady.removeAll()
                self.central?.scanForPeripherals(withServices: [Self.glucoseService], options: nil)

                let work = DispatchWorkItem { [weak self] in self?.finishDownload(error: nil) }
                self.timeout = work
                self.queue.asyncAfter(deadline: .now() + 15, execute: work) // no meter in range → empty
            }
        }
    }

    // MARK: Queue-confined helpers

    private func ensureCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: queue)
        }
    }

    private func resumeAuth(throwing error: Error? = nil) {
        guard let continuation = authContinuation else { return }
        authContinuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    private func finishDownload(error: Error?) {
        timeout?.cancel(); timeout = nil
        central?.stopScan()

        let samples = collected
            .filter { $0.timestamp >= sinceDate }
            .map { record in
                NormalizedGlucoseSample(
                    id: "bgm-\(meterName)-\(record.sequenceNumber)",
                    valueMgdL: record.valueMgdL,
                    timestamp: record.timestamp,
                    source: .bloodGlucoseMeter,
                    measurementType: .fingerstick,
                    sensorTimestamp: record.timestamp,
                    confidence: nil,
                    deviceID: meterName
                )
            }

        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        measurementChar = nil
        racpChar = nil

        guard let continuation = downloadContinuation else { return }
        downloadContinuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples) }
    }
}

extension BluetoothGlucoseScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: resumeAuth()
        case .unauthorized: resumeAuth(throwing: SourceError.notAuthorized)
        case .unsupported: resumeAuth(throwing: SourceError.unavailable)
        case .poweredOff: resumeAuth(throwing: SourceError.underlying("Bluetooth is off"))
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
        central.stopScan()
        self.peripheral = peripheral
        meterName = peripheral.name ?? "Glucose meter"
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.glucoseService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finishDownload(error: SourceError.underlying(error?.localizedDescription ?? "Connection failed"))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if downloadContinuation != nil { finishDownload(error: nil) }
    }
}

extension BluetoothGlucoseScanner: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.glucoseService }) else {
            finishDownload(error: SourceError.underlying("Glucose service not found")); return
        }
        peripheral.discoverCharacteristics([Self.measurementCharacteristic, Self.racpCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.measurementCharacteristic:
                measurementChar = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.racpCharacteristic:
                racpChar = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default: break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        notifyReady.insert(characteristic.uuid)
        guard notifyReady.contains(Self.measurementCharacteristic),
              notifyReady.contains(Self.racpCharacteristic),
              let racp = racpChar else { return }
        peripheral.writeValue(Data(GlucoseProfileParser.reportAllRecords), for: racp, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case Self.measurementCharacteristic:
            if let record = GlucoseProfileParser.parseMeasurement(data) { collected.append(record) }
        case Self.racpCharacteristic:
            if GlucoseProfileParser.racpIndicatesCompletion(data) { finishDownload(error: nil) }
        default: break
        }
    }
}
#endif
