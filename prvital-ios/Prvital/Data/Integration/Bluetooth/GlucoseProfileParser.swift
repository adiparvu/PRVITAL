import Foundation

/// A single record decoded from a Bluetooth **Glucose Measurement** (0x2A18)
/// characteristic, normalised to mg/dL.
struct GlucoseMeasurementRecord: Equatable, Sendable {
    var sequenceNumber: Int
    var timestamp: Date
    var valueMgdL: Double
    var sampleType: Int?
    var sampleLocation: Int?
}

/// Pure decoder for the Bluetooth SIG **Glucose Profile** (used by Contour,
/// Accu-Chek and other standards-compliant meters). Handles the IEEE-11073
/// 16-bit SFLOAT, the Glucose Measurement characteristic, and the Record Access
/// Control Point (RACP) commands/responses. No CoreBluetooth dependency, so it
/// is fully unit-testable.
enum GlucoseProfileParser {

    // MARK: RACP (0x2A52)

    /// "Report stored records" for the **All records** operator — downloads the
    /// meter's full memory. Op Code 0x01 (Report Stored Records), Operator 0x01.
    static let reportAllRecords: [UInt8] = [0x01, 0x01]

    /// "Report stored records" for records with sequence number **≥ value**
    /// (Operator 0x03 "greater than or equal to", filter type 0x01 = seq number).
    static func reportRecords(fromSequenceNumber seq: UInt16) -> [UInt8] {
        [0x01, 0x03, 0x01, UInt8(seq & 0xFF), UInt8(seq >> 8)]
    }

    /// True once the RACP indicates the report procedure finished. A completion
    /// carries Op Code 0x06 (Response Code); "no records found" (Op Code 0x06 with
    /// response 0x06) also ends the procedure.
    static func racpIndicatesCompletion(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard let opCode = bytes.first else { return false }
        return opCode == 0x06 // Response Code Op Code
    }

    // MARK: Glucose Measurement (0x2A18)

    /// Decodes one Glucose Measurement notification. Returns nil if the value is
    /// a special/reserved SFLOAT or the payload is malformed.
    static func parseMeasurement(_ data: Data, timeZone: TimeZone = .current) -> GlucoseMeasurementRecord? {
        let b = [UInt8](data)
        guard b.count >= 10 else { return nil }

        let flags = b[0]
        let timeOffsetPresent = flags & 0x01 != 0
        let concentrationPresent = flags & 0x02 != 0
        let unitIsMolL = flags & 0x04 != 0

        let sequenceNumber = Int(u16(b, 1))

        // Base Time — org.bluetooth date_time (year u16, month, day, h, m, s).
        var components = DateComponents()
        components.year = Int(u16(b, 3))
        components.month = Int(b[5])
        components.day = Int(b[6])
        components.hour = Int(b[7])
        components.minute = Int(b[8])
        components.second = Int(b[9])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard var timestamp = calendar.date(from: components) else { return nil }

        var index = 10
        if timeOffsetPresent {
            guard b.count >= index + 2 else { return nil }
            let offsetMinutes = Int(s16(b, index))
            timestamp = timestamp.addingTimeInterval(TimeInterval(offsetMinutes * 60))
            index += 2
        }

        var valueMgdL = 0.0
        var sampleType: Int?
        var sampleLocation: Int?
        if concentrationPresent {
            guard b.count >= index + 3 else { return nil }
            guard let concentration = parseSFloat(u16(b, index)) else { return nil }
            index += 2
            let typeLocation = b[index]
            index += 1
            sampleType = Int(typeLocation & 0x0F)
            sampleLocation = Int(typeLocation >> 4)
            // kg/L → mg/dL (×100000); mol/L → mmol/L (×1000) → mg/dL.
            if unitIsMolL {
                let mmolL = concentration * 1000
                valueMgdL = mmolL * GlucoseUnit.conversionFactor
            } else {
                valueMgdL = concentration * 100_000
            }
        } else {
            return nil // a measurement with no concentration isn't useful
        }

        return GlucoseMeasurementRecord(
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            valueMgdL: valueMgdL.rounded(),
            sampleType: sampleType,
            sampleLocation: sampleLocation
        )
    }

    // MARK: IEEE-11073 16-bit SFLOAT

    /// Decodes a 16-bit SFLOAT (4-bit signed exponent, 12-bit signed mantissa).
    /// Returns nil for the reserved special values (NaN, NRes, ±INF).
    static func parseSFloat(_ raw: UInt16) -> Double? {
        let mantissaRaw = raw & 0x0FFF
        switch mantissaRaw {
        case 0x07FF, 0x0800, 0x07FE, 0x0802: return nil // NaN / NRes / ±INF
        default: break
        }
        var mantissa = Int(mantissaRaw)
        if mantissa >= 0x0800 { mantissa -= 0x1000 }      // sign-extend 12-bit
        var exponent = Int(raw >> 12)
        if exponent >= 0x08 { exponent -= 0x10 }          // sign-extend 4-bit
        return Double(mantissa) * pow(10.0, Double(exponent))
    }

    // MARK: Little-endian helpers

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }
    private static func s16(_ b: [UInt8], _ i: Int) -> Int16 {
        Int16(bitPattern: u16(b, i))
    }
}
