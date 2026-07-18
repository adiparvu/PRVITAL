import Foundation
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

/// Connects to standards-compliant Bluetooth blood-glucose meters — **Contour**
/// (Next One / Plus), **Accu-Chek** (Guide / Instant / Aviva Connect) and any
/// other meter implementing the Bluetooth SIG **Glucose Profile** — and downloads
/// their stored readings.
///
/// The flow is the standard Glucose Service (0x1808) procedure: scan → connect →
/// discover the Glucose Measurement (0x2A18) + Record Access Control Point
/// (0x2A52) characteristics → enable notifications → write "Report Stored Records
/// (All)" on the RACP → collect each measurement until the RACP indicates
/// completion. iOS performs BLE pairing automatically on first secure access.
///
/// One implementation therefore covers many brands, with no vendor SDK. The
/// meter's advertised name is kept as the record's `deviceID` for provenance.
@MainActor
final class BluetoothGlucoseMeterSource: NSObject, GlucoseSource {
    let source: DataSource = .bloodGlucoseMeter

    #if canImport(CoreBluetooth)
    private static let glucoseService = CBUUID(string: "1808")
    private static let measurementCharacteristic = CBUUID(string: "2A18")
    private static let racpCharacteristic = CBUUID(string: "2A52")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var measurementChar: CBCharacteristic?
    private var racpChar: CBCharacteristic?
    private var notifyReady = Set<CBUUID>()

    private var collected: [GlucoseMeasurementRecord] = []
    private var sinceDate: Date = .distantPast
    private var meterName = "Glucose meter"

    private var powerContinuation: CheckedContinuation<Void, Error>?
    private var fetchContinuation: CheckedContinuation<[NormalizedGlucoseSample], Error>?
    private var scanTimeout: Task<Void, Never>?

    private(set) var connectionState: SourceConnectionState = .notConnected

    var isAvailable: Bool { true }

    // MARK: GlucoseSource

    func requestAccess() async throws {
        connectionState = .connecting
        ensureCentral()
        do {
            try await waitForPoweredOn()
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
        ensureCentral()
        try await waitForPoweredOn()
        // Only one download at a time; a concurrent call yields nothing.
        guard fetchContinuation == nil else { return [] }

        sinceDate = date
        collected = []
        notifyReady.removeAll()

        return try await withCheckedThrowingContinuation { continuation in
            fetchContinuation = continuation
            central?.scanForPeripherals(withServices: [Self.glucoseService], options: nil)
            scanTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.finish(with: nil) // no meter in range → graceful empty result
            }
        }
    }

    // MARK: Lifecycle

    private func ensureCentral() {
        if central == nil {
            // queue nil → callbacks arrive on the main queue (== MainActor).
            central = CBCentralManager(delegate: self, queue: nil)
        }
    }

    private func waitForPoweredOn() async throws {
        guard let central else { throw SourceError.unavailable }
        switch central.state {
        case .poweredOn: return
        case .unauthorized: throw SourceError.notAuthorized
        case .unsupported: throw SourceError.unavailable
        default: break
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            powerContinuation = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                self?.resumePower(throwing: SourceError.underlying("Bluetooth didn't power on in time"))
            }
        }
    }

    private func resumePower(throwing error: Error? = nil) {
        guard let continuation = powerContinuation else { return }
        powerContinuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    /// Ends the current download, resolving the fetch with the collected records
    /// (or an error). Cleans up the connection.
    private func finish(with error: Error?) {
        scanTimeout?.cancel(); scanTimeout = nil
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

        guard let continuation = fetchContinuation else { return }
        fetchContinuation = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: samples) }
    }
    #else
    private(set) var connectionState: SourceConnectionState = .unavailable
    var isAvailable: Bool { false }
    func requestAccess() async throws { throw SourceError.unavailable }
    func fetchLatest() async throws -> NormalizedGlucoseSample? { nil }
    func fetchSamples(since date: Date) async throws -> [NormalizedGlucoseSample] { [] }
    #endif
}

#if canImport(CoreBluetooth)
extension BluetoothGlucoseMeterSource: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn: resumePower()
            case .unauthorized: resumePower(throwing: SourceError.notAuthorized)
            case .unsupported: resumePower(throwing: SourceError.unavailable)
            case .poweredOff: resumePower(throwing: SourceError.underlying("Bluetooth is off"))
            default: break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard self.peripheral == nil else { return }
            central.stopScan()
            self.peripheral = peripheral
            self.meterName = peripheral.name ?? "Glucose meter"
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.discoverServices([Self.glucoseService])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            finish(with: SourceError.underlying(error?.localizedDescription ?? "Connection failed"))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            // Resolve with whatever was collected before the disconnect.
            if fetchContinuation != nil { finish(with: nil) }
        }
    }
}

extension BluetoothGlucoseMeterSource: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.glucoseService }) else {
                finish(with: SourceError.underlying("Glucose service not found")); return
            }
            peripheral.discoverCharacteristics([Self.measurementCharacteristic, Self.racpCharacteristic], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
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
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            notifyReady.insert(characteristic.uuid)
            guard notifyReady.contains(Self.measurementCharacteristic),
                  notifyReady.contains(Self.racpCharacteristic),
                  let racp = racpChar else { return }
            // Both channels ready → ask the meter to report all stored records.
            peripheral.writeValue(Data(GlucoseProfileParser.reportAllRecords), for: racp, type: .withResponse)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let data = characteristic.value else { return }
            switch characteristic.uuid {
            case Self.measurementCharacteristic:
                if let record = GlucoseProfileParser.parseMeasurement(data) {
                    collected.append(record)
                }
            case Self.racpCharacteristic:
                if GlucoseProfileParser.racpIndicatesCompletion(data) { finish(with: nil) }
            default: break
            }
        }
    }
}
#endif
