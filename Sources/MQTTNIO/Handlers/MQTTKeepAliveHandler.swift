import NIO
import Logging

final class MQTTKeepAliveHandler: ChannelOutboundHandler {
    
    // MARK: - Types
    
    typealias OutboundIn = MQTTPacket.Outbound
    typealias OutboundOut = MQTTPacket.Outbound
    
    // MARK: - Vars
    
    let logger: Logger
    let interval: TimeAmount
    let reschedulePings: Bool
    
    private weak var channel: Channel?
    private var scheduledPing: Scheduled<Void>?
    
    // MARK: - Init
    
    init(logger: Logger, interval: TimeAmount, reschedulePings: Bool = true) {
        self.logger = logger
        self.interval = interval
        self.reschedulePings = reschedulePings
    }
    
    // MARK: - ChannelDuplexHandler
    
    func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        
        switch event {
        case MQTTConnectionEvent.didConnect:
            schedulePingRequest(in: context.eventLoop)
            
        case MQTTConnectionEvent.willDisconnect:
            unschedulePingRequest()
            
        default:
            break
        }
        
        context.triggerUserOutboundEvent(event, promise: promise)
    }
    
    func handlerAdded(context: ChannelHandlerContext) {
        channel = context.channel
    }
    
    func handlerRemoved(context: ChannelHandlerContext) {
        unschedulePingRequest()
        channel = nil
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        // Reschedule ping request as we are already sending a packet
        if reschedulePings {
            if scheduledPing != nil {
                schedulePingRequest(in: context.eventLoop)
            }
        }
        
        // Forward
        context.write(data, promise: promise)
    }
    
    // MARK: - Utils
    
    private func schedulePingRequest(in eventLoop: EventLoop) {
        unschedulePingRequest()
        
        guard interval.nanoseconds > 0 else {
            return
        }
        
        scheduledPing = eventLoop.scheduleTask(in: interval) { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.performPingRequest()
        }
    }
    
    private func unschedulePingRequest() {
        scheduledPing?.cancel()
        scheduledPing = nil
    }
    
    private func performPingRequest() {
        guard let channel = channel, scheduledPing != nil else {
            return
        }
        
        let request = MQTTPingRequest(timeoutInterval: interval)
        channel.pipeline.handler(type: MQTTRequestHandler.self).flatMap {
            $0.perform(request)
        }.whenFailure { [weak self] error in
            guard let strongSelf = self else {
                return
            }
            strongSelf.unschedulePingRequest()
            strongSelf.channel?.close(mode: .all, promise: nil)
        }
    }
}