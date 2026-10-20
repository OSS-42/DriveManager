import Darwin

/// One item read from a folder by `DirectoryReader`.
struct DirectoryEntry {
    enum Kind {
        case file, directory, symlink, other
    }

    let name: String
    let kind: Kind
    /// Bytes allocated on disk, all forks included. Zero for folders.
    let allocatedSize: Int64
    let linkCount: UInt32
    let device: Int32
    let fileID: UInt64
    /// Identifies the data of a file that is a pure APFS clone of others:
    /// clones that still share all their data have the same ID. Nil when the
    /// file shares no data or the disk does not report it.
    let cloneID: UInt64?
}

/// A folder's items and the device (volume) the folder is on.
struct DirectoryListing {
    let device: Int32
    let entries: [DirectoryEntry]
}

/// Reads a folder's items and their sizes with `getattrlistbulk`, which
/// returns many items per system call instead of one `stat` per item.
enum DirectoryReader {
    // Values from <sys/attr.h>. Spelled out because the headers import some of
    // them as signed integers and some as unsigned.
    private static let commonName: UInt32 = 0x0000_0001
    private static let commonDevID: UInt32 = 0x0000_0002
    private static let commonObjType: UInt32 = 0x0000_0008
    private static let commonFileID: UInt32 = 0x0200_0000
    private static let commonError: UInt32 = 0x2000_0000
    private static let commonReturnedAttrs: UInt32 = 0x8000_0000
    private static let fileLinkCount: UInt32 = 0x0000_0001
    private static let fileAllocSize: UInt32 = 0x0000_0004
    // Extended common attributes, requested in the fork attribute field.
    private static let extCloneID: UInt32 = 0x0000_0100
    private static let extFlags: UInt32 = 0x0000_0200
    private static let optionExtended: UInt64 = 0x0000_0020 // FSOPT_ATTR_CMN_EXTENDED
    private static let mayShareBlocks: UInt64 = 0x0000_0001 // EF_MAY_SHARE_BLOCKS

    // Values of fsobj_type_t (enum vtype in <sys/vnode.h>).
    private static let typeRegular: UInt32 = 1
    private static let typeDirectory: UInt32 = 2
    private static let typeSymlink: UInt32 = 5

    private static let bufferSize = 256 * 1024

    /// The folder's items, or nil when it cannot be opened.
    static func read(_ path: String) -> DirectoryListing? {
        let folder = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard folder >= 0 else { return nil }
        defer { close(folder) }

        // The device of the opened folder itself. For a mount point this is
        // the mounted disk, while its entry in the parent listing still
        // reports the parent's disk.
        var info = stat()
        guard fstat(folder, &info) == 0 else { return nil }

        var request = attrlist()
        request.bitmapcount = 5 // ATTR_BIT_MAP_COUNT
        request.commonattr = commonReturnedAttrs | commonName | commonError | commonDevID | commonObjType | commonFileID
        request.fileattr = fileLinkCount | fileAllocSize
        request.forkattr = extCloneID | extFlags
        var options = optionExtended

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        var entries: [DirectoryEntry] = []
        while true {
            var count = getattrlistbulk(folder, &request, buffer, bufferSize, options)
            if count < 0 && errno == EINVAL && options != 0 && entries.isEmpty {
                // A disk that does not support extended attributes: read
                // without clone information.
                request.forkattr = 0
                options = 0
                count = getattrlistbulk(folder, &request, buffer, bufferSize, options)
            }
            if count < 0 { return entries.isEmpty ? nil : DirectoryListing(device: info.st_dev, entries: entries) }
            if count == 0 { break }

            var record = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(record.loadUnaligned(as: UInt32.self))
                if let entry = parse(record) {
                    entries.append(entry)
                }
                record += length
            }
        }
        return DirectoryListing(device: info.st_dev, entries: entries)
    }

    /// Reads one record. Its layout: a UInt32 length, the five-word
    /// `attribute_set_t` of returned attributes, then the error code, then the
    /// requested common attributes in bit order, then the file attributes.
    private static func parse(_ record: UnsafeRawPointer) -> DirectoryEntry? {
        let returnedCommon = record.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
        let returnedFile = record.loadUnaligned(fromByteOffset: 16, as: UInt32.self)
        let returnedExtended = record.loadUnaligned(fromByteOffset: 20, as: UInt32.self)
        var offset = 4 + 20

        if returnedCommon & commonError != 0 {
            let error = record.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            offset += 4
            if error != 0 { return nil }
        }

        guard returnedCommon & commonName != 0 else { return nil }
        let nameOffset = record.loadUnaligned(fromByteOffset: offset, as: Int32.self)
        let name = String(cString: (record + offset + Int(nameOffset)).assumingMemoryBound(to: CChar.self))
        offset += 8 // attrreference_t

        var device: Int32 = 0
        if returnedCommon & commonDevID != 0 {
            device = record.loadUnaligned(fromByteOffset: offset, as: Int32.self)
            offset += 4
        }
        var type: UInt32 = 0
        if returnedCommon & commonObjType != 0 {
            type = record.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            offset += 4
        }
        var fileID: UInt64 = 0
        if returnedCommon & commonFileID != 0 {
            fileID = record.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
            offset += 8
        }
        var linkCount: UInt32 = 1
        if returnedFile & fileLinkCount != 0 {
            linkCount = record.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            offset += 4
        }
        var size: Int64 = 0
        if returnedFile & fileAllocSize != 0 {
            size = record.loadUnaligned(fromByteOffset: offset, as: Int64.self)
            offset += 8
        }
        var cloneID: UInt64 = 0
        if returnedExtended & extCloneID != 0 {
            cloneID = record.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
            offset += 8
        }
        var flags: UInt64 = 0
        if returnedExtended & extFlags != 0 {
            flags = record.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
            offset += 8
        }

        let kind: DirectoryEntry.Kind
        switch type {
        case typeRegular: kind = .file
        case typeDirectory: kind = .directory
        case typeSymlink: kind = .symlink
        default: kind = .other
        }
        return DirectoryEntry(
            name: name,
            kind: kind,
            allocatedSize: kind == .directory ? 0 : size,
            linkCount: linkCount,
            device: device,
            fileID: fileID,
            cloneID: flags & mayShareBlocks != 0 && cloneID != 0 ? cloneID : nil
        )
    }
}
