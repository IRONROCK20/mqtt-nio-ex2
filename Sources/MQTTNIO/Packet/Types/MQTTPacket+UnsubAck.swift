import NIO

extension MQTTPacket {
    struct UnsubAck: MQTTPacketInboundType {
        
        // MARK: - Properties
        
        var packetId: UInt16
        
        // MARK: - MQTTPacketOutboundType
        
        static func parse(
            from packet: inout MQTTPacket,
            version: MQTTProtocolVersion
        ) throws -> Self {
            guard let packetId = packet.data.readInteger(as: UInt16.self) else {
                throw MQTTProtocolError.parsingError("Missing packet identifier")
            }
            return UnsubAck(packetId: packetId)
        }
    }
}
