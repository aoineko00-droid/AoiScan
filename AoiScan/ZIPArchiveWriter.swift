//
//  ZIPArchiveWriter.swift
//  AoiScan
//

import Foundation


enum ZIPArchiveWriterError:LocalizedError {
    case archiveTooLarge
    case invalidEntryName

    var errorDescription:String? {
        switch self {
        case .archiveTooLarge:
            return "The Word package is too large."
        case .invalidEntryName:
            return "The Word package contains an invalid file name."
        }
    }
}


/// A small standards-compliant ZIP writer using the uncompressed method.
/// DOCX readers support stored entries, so no third-party dependency is
/// needed and the entire Word export remains offline.
enum ZIPArchiveWriter {
    struct Entry {
        let path:String
        let data:Data
    }

    private struct CentralRecord {
        let nameData:Data
        let crc32:UInt32
        let size:UInt32
        let offset:UInt32
        let dosTime:UInt16
        let dosDate:UInt16
    }

    static func write(
        entries:[Entry],
        to url:URL
    ) throws {
        guard entries.count <= Int(UInt16.max) else {
            throw ZIPArchiveWriterError.archiveTooLarge
        }

        var archive = Data()
        var centralRecords:[CentralRecord] = []
        let stamp = dosTimestamp(for:Date())

        for entry in entries {
            guard !entry.path.isEmpty,
                  !entry.path.hasPrefix("/"),
                  !entry.path.contains(".."),
                  let nameData = entry.path.data(using:.utf8),
                  nameData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  archive.count <= Int(UInt32.max) else {
                throw ZIPArchiveWriterError.invalidEntryName
            }

            let size = UInt32(entry.data.count)
            let crc = CRC32.checksum(entry.data)
            let offset = UInt32(archive.count)

            archive.appendLittleEndian(UInt32(0x04034b50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(stamp.time)
            archive.appendLittleEndian(stamp.date)
            archive.appendLittleEndian(crc)
            archive.appendLittleEndian(size)
            archive.appendLittleEndian(size)
            archive.appendLittleEndian(UInt16(nameData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(nameData)
            archive.append(entry.data)

            centralRecords.append(
                CentralRecord(
                    nameData:nameData,
                    crc32:crc,
                    size:size,
                    offset:offset,
                    dosTime:stamp.time,
                    dosDate:stamp.date
                )
            )
        }

        guard archive.count <= Int(UInt32.max) else {
            throw ZIPArchiveWriterError.archiveTooLarge
        }
        let centralOffset = UInt32(archive.count)

        for record in centralRecords {
            archive.appendLittleEndian(UInt32(0x02014b50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(record.dosTime)
            archive.appendLittleEndian(record.dosDate)
            archive.appendLittleEndian(record.crc32)
            archive.appendLittleEndian(record.size)
            archive.appendLittleEndian(record.size)
            archive.appendLittleEndian(UInt16(record.nameData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt32(0))
            archive.appendLittleEndian(record.offset)
            archive.append(record.nameData)
        }

        guard archive.count <= Int(UInt32.max) else {
            throw ZIPArchiveWriterError.archiveTooLarge
        }
        let centralSize = UInt32(archive.count) - centralOffset
        let entryCount = UInt16(centralRecords.count)

        archive.appendLittleEndian(UInt32(0x06054b50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(entryCount)
        archive.appendLittleEndian(entryCount)
        archive.appendLittleEndian(centralSize)
        archive.appendLittleEndian(centralOffset)
        archive.appendLittleEndian(UInt16(0))

        try archive.write(to:url, options:.atomic)
    }

    private static func dosTimestamp(
        for date:Date
    )->(time:UInt16,date:UInt16) {
        let calendar = Calendar(identifier:.gregorian)
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from:date
        )
        let year = min(max(parts.year ?? 1980, 1980), 2107)
        let month = min(max(parts.month ?? 1, 1), 12)
        let day = min(max(parts.day ?? 1, 1), 31)
        let hour = min(max(parts.hour ?? 0, 0), 23)
        let minute = min(max(parts.minute ?? 0, 0), 59)
        let second = min(max(parts.second ?? 0, 0), 59)

        return (
            UInt16((hour << 11) | (minute << 5) | (second / 2)),
            UInt16(((year - 1980) << 9) | (month << 5) | day)
        )
    }
}


private enum CRC32 {
    static let table:[UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1
                ? 0xedb88320 ^ (crc >> 1)
                : crc >> 1
        }
        return crc
    }

    static func checksum(_ data:Data)->UInt32 {
        var crc = UInt32.max
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ UInt32.max
    }
}


private extension Data {
    mutating func appendLittleEndian<T:FixedWidthInteger>(
        _ value:T
    ) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of:&littleEndian) {
            append(contentsOf:$0)
        }
    }
}
