import NIO
import Logging

final class MQTTPublishRequest: MQTTRequest {
    
    // MARK: - Types
    
    private enum Event {
        case retry
    }
    
    // MARK: - Vars
    
    let message: MQTTMessage
    let retryInterval: TimeAmount
    
    private var acknowledgedPub: Bool = false
    private var packetId: UInt16?
    
    private var scheduledRetry: Scheduled<Void>?
    
    // MARK: - Init
    
    init(message: MQTTMessage, retryInterval: TimeAmount = .seconds(5)) {
        self.message = message
        self.retryInterval = retryInterval
    }
    
    // MARK: - MQTTRequest
    
    func start(context: MQTTRequestContext) -> MQTTRequestResult<Void> {
        let result: MQTTRequestResult<Void>
        switch message.qos {
        case .atMostOnce:
            result = .success
            
        case .atLeastOnce, .exactlyOnce:
            result = .pending
            packetId = context.getNextPacketId()
            
            scheduleRetry(context: context)
        }
        
        context.logger.debug("Sending: Publish", metadata: [
            "packetId": .string(packetId.map { $0.description } ?? "none"),
            "topic": .string(message.topic),
            "payload": .string(message.payload.debugDescription),
            "qos": .stringConvertible(message.qos.rawValue),
            "retain": .stringConvertible(message.retain)
        ])
        
        context.write(MQTTPacket.Publish(message: message, packetId: packetId))
        return result
    }
    
    func process(context: MQTTRequestContext, packet: MQTTPacket.Inbound) -> MQTTRequestResult<Void> {
        guard case .acknowledgement(let acknowledgement) = packet, acknowledgement.packetId == packetId else {
            return .pending
        }
        
        let packetId = acknowledgement.packetId
        
        switch message.qos {
        case .atMostOnce:
            return .success
            
        case .atLeastOnce:
            guard acknowledgement.kind == .pubAck else {
                return .pending
            }
            
            context.logger.debug("Received: Publish Acknowledgement", metadata: [
                "packetId": .stringConvertible(acknowledgement.packetId),
            ])
            
            cancelRetry()
            return .success
            
        case .exactlyOnce:
            if acknowledgement.kind == .pubRec {
                acknowledgedPub = true
                cancelRetry()
                
                context.logger.debug("Received: Publish Received", metadata: [
                    "packetId": .stringConvertible(acknowledgement.packetId),
                ])
                context.logger.debug("Sending: Publish Release", metadata: [
                    "packetId": .stringConvertible(acknowledgement.packetId),
                ])
                
                let pubRel = MQTTPacket.Acknowledgement(kind: .pubRel, packetId: packetId)
                context.write(pubRel)
                scheduleRetry(context: context)
                
                return .pending
            }
            
            guard acknowledgedPub && acknowledgement.kind == .pubComp else {
                return .pending
            }
            
            context.logger.debug("Received: Publish Complete", metadata: [
                "packetId": .stringConvertible(acknowledgement.packetId),
            ])
            
            cancelRetry()
            return .success
        }
    }
    
    func handleEvent(context: MQTTRequestContext, event: Any) -> MQTTRequestResult<Void> {
        if scheduledRetry != nil, case Event.retry = event {
            retry(context: context)
        }
        return .pending
    }
    
    func disconnected(context: MQTTRequestContext) -> MQTTRequestResult<Void> {
        cancelRetry()
        return .pending
    }
    
    func connected(context: MQTTRequestContext, isSessionPresent: Bool) -> MQTTRequestResult<Void> {
        if !isSessionPresent && acknowledgedPub {
            return .failure(MQTTPublishError.sessionCleared)
        }
        
        retry(context: context)
        return .pending
    }
    
    // MARK: - Utils
    
    private func scheduleRetry(context: MQTTRequestContext) {
        cancelRetry()
        
        guard retryInterval.nanoseconds > 0 else {
            return
        }
        
        context.scheduleEvent(Event.retry, in: retryInterval)
    }
    
    private func cancelRetry() {
        scheduledRetry?.cancel()
        scheduledRetry = nil
    }
    
    private func retry(context: MQTTRequestContext) {
        guard let packetId = packetId else {
            return
        }
        
        switch (message.qos, acknowledgedPub) {
        case (.atLeastOnce, _), (.exactlyOnce, false):
            let publish = MQTTPacket.Publish(
                message: message,
                packetId: packetId,
                isDuplicate: true
            )
            context.write(publish)
            
        case (.exactlyOnce, true):
            let pubRel = MQTTPacket.Acknowledgement(kind: .pubRel, packetId: packetId)
            context.write(pubRel)
            
        default:
            break
        }
    }
}
