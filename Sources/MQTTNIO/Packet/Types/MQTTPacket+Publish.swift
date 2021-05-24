import NIO

extension MQTTPacket {
    struct Publish: MQTTPacketDuplexType {
        
        // MARK: - Properties
        
        var message: MQTTMessage {
            return messageWrapper.message
        }
        var packetId: UInt16?
        var isDuplicate: Bool = false
        
        private let messageWrapper: MessageWrapper
        
        init(message: MQTTMessage, packetId: UInt16?, isDuplicate: Bool = false) {
            messageWrapper = MessageWrapper(message: message)
            self.packetId = packetId
            self.isDuplicate = isDuplicate
        }
        
        // MARK: - MQTTPacketDuplexType
        
        static func parse(
            from packet: inout MQTTPacket,
            version: MQTTProtocolVersion
        ) throws -> Self {
            let flags = Flags(rawValue: packet.fixedHeaderData)
            
            let topic = try packet.data.readMQTTString("Topic")
            
            let packetId: UInt16?
            if flags.qos != .atMostOnce {
                packetId = packet.data.readInteger(as: UInt16.self)
                guard packetId != nil else {
                    throw MQTTProtocolError.parsingError("Missing packet identifier")
                }
            } else {
                packetId = nil
            }
            
            let payload: MQTTPayload
            if packet.data.readableBytes > 0 {
                payload = .bytes(packet.data)
            } else {
                payload = .empty
            }
            
            return Publish(
                message: MQTTMessage(
                    topic: topic,
                    payload: payload,
                    qos: flags.qos,
                    retain: flags.contains(.retain)
                ),
                packetId: packetId,
                isDuplicate: flags.contains(.dup)
            )
        }
        
        func serialize(version: MQTTProtocolVersion) throws -> MQTTPacket {
            let flags = generateFlags()
            
            var buffer = Allocator.shared.buffer(capacity: 0)
            
            try buffer.writeMQTTString(message.topic, "Topic")
            
            if flags.qos != .atMostOnce {
                guard let packetId = packetId else {
                    throw MQTTProtocolError.parsingError("Missing packet identifier")
                }
                buffer.writeInteger(packetId)
            }
            
            switch message.payload {
            case .empty:
                break
            
            case .bytes(var bytes):
                buffer.writeBuffer(&bytes)
                
            case .string(let string, _):
                buffer.writeString(string)
            }
            
            return MQTTPacket(kind: .publish, fixedHeaderData: flags.rawValue, data: buffer)
        }
        
        // MARK: - Utils
        
        private func generateFlags() -> Flags {
            var flags: Flags = []
            
            if message.retain {
                flags.insert(.retain)
            }
            
            switch message.qos {
            case .atMostOnce:
                break
            case .atLeastOnce:
                flags.insert(.qos1)
            case .exactlyOnce:
                flags.insert(.qos2)
            }
            
            if isDuplicate {
                flags.insert(.dup)
            }
            
            return flags
        }
    }
}

extension MQTTPacket.Publish {
    // Wrapper to avoid heap allocations when added to NIOAny
    fileprivate class MessageWrapper {
        let message: MQTTMessage
        
        init(message: MQTTMessage) {
            self.message = message
        }
    }
    
    struct Flags: OptionSet {
        let rawValue: UInt8

        static let retain   = Flags(rawValue: 1 << 0)
        static let qos1     = Flags(rawValue: 1 << 1)
        static let qos2     = Flags(rawValue: 1 << 2)
        static let dup      = Flags(rawValue: 1 << 3)

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
        var qos: MQTTQoS {
            if contains(.qos2) {
                return .exactlyOnce
            }
            if contains(.qos1) {
                return .atLeastOnce
            }
            return .atMostOnce
        }

        var description: String {
            return [
                "retain": contains(.retain),
                "qos1": contains(.qos1),
                "qos2": contains(.qos2),
                "dup": contains(.dup),
            ].description
        }
    }
}
