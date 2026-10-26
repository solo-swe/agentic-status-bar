#if os(macOS)
import Darwin
import Foundation

/// The process table through libproc and sysctl: no `ps` processes.
public struct DarwinProcessInspector: ProcessInspector {
    public init() {}

    public func processes() -> [ProcessRecord] {
        // Ask for the count, then leave room for processes started in between.
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard filled > 0 else { return [] }
        return pids.prefix(Int(filled)).compactMap { $0 > 0 ? process($0) : nil }
    }

    public func process(_ pid: Int32) -> ProcessRecord? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        // pbi_name holds up to 32 characters; pbi_comm is cut at 16.
        let name = withUnsafeBytes(of: info.pbi_name) { cString($0) }
        let comm = name.isEmpty ? withUnsafeBytes(of: info.pbi_comm) { cString($0) } : name
        return ProcessRecord(
            pid: pid, ppid: Int32(info.pbi_ppid), start: Int64(info.pbi_start_tvsec), comm: comm)
    }

    public func arguments(_ pid: Int32) -> String? {
        // KERN_PROCARGS2: argc (Int32), the executable path, padding NULs, then argv[0..argc-1].
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }  // executable path
        while index < size, buffer[index] == 0 { index += 1 }  // padding
        var args: [String] = []
        while args.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args.isEmpty ? nil : args.joined(separator: " ")
    }

    private func cString(_ bytes: UnsafeRawBufferPointer) -> String {
        let end = bytes.firstIndex(of: 0) ?? bytes.count
        return String(decoding: bytes[..<end], as: UTF8.self)
    }
}
#endif
