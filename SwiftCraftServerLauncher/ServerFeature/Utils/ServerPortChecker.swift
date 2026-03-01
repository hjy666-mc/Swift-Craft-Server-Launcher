import Foundation
import Darwin

enum ServerPortChecker {
    static func isPortAvailable(_ port: Int) -> Bool {
        return canBind(port: port, family: AF_INET) && canBind(port: port, family: AF_INET6)
    }

    static func findAvailablePort(startingAt port: Int, maxPort: Int = 30000) -> Int? {
        guard port > 0 else { return nil }
        var current = port
        while current <= maxPort {
            if isPortAvailable(current) { return current }
            current += 1
        }
        return nil
    }

    private static func canBind(port: Int, family: Int32) -> Bool {
        let sock = socket(family, SOCK_STREAM, 0)
        if sock < 0 { return false }
        var value: Int32 = 1
        _ = setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout.size(ofValue: value)))

        var result: Int32 = -1
        if family == AF_INET {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(UInt16(port).bigEndian)
            addr.sin_addr = in_addr(s_addr: inet_addr("0.0.0.0"))
            result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        } else if family == AF_INET6 {
            var addr = sockaddr_in6()
            addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = in_port_t(UInt16(port).bigEndian)
            addr.sin6_addr = in6addr_any
            result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }

        close(sock)
        return result == 0
    }
}
