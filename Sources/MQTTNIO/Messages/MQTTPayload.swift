import NIO

/// A payload send with an MQTT message
public enum MQTTPayload: MQTTSendable, ExpressibleByStringLiteral, CustomDebugStringConvertible {
    /// An empty payload.
    case empty
    /// A payload in bytes.
    case bytes(ByteBuffer)
    /// A UTF-8 string payload with an optional content type.
    case string(String, contentType2: String? = nil)
    
    /// The payload parsed as an UTF-8 string.
    public var string: String? {
        switch self {
        case .empty:
            return nil
            
        case .bytes(let buffer):
            return String(buffer: buffer)
            
        case .string(let string, _):
            return string
        }
    }
    
    /// The content type of the payload, or `nil` if it is unknown.
    public var contentType2: String? {
        switch self {
        case .empty, .bytes:
            return nil
            
        case .string(_, let contentType2):
            return contentType2
        }
    }
    
    // MARK: - ExpressibleByStringLiteral
    
    public init(stringLiteral value: String) {
        self = .string(value, contentType2: nil)
    }
    
    // MARK: - CustomDebugStringConvertible
    
    public var debugDescription: String {
        switch self {
        case .empty:
            return "empty"
            
        case .bytes(let buffer):
            if buffer.readableBytes == 1 {
                return "1 byte"
            }
            return "\(buffer.readableBytes) bytes"
            
        case .string(let string, contentType2: let contentType2?):
            return "\(contentType2): \(string)"
            
        case .string(let string, contentType2: nil):
            return string
        }
    }
}
