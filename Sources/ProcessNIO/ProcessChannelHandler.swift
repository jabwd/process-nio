import NIO
import Foundation

public typealias ProcessOutputHandler = ([UInt8]) -> Void

public final class ProcessChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = ByteBuffer
  public var outputHandler: ProcessOutputHandler?

  init(outputHandler: ProcessOutputHandler? = nil) {
    self.outputHandler = outputHandler
  }

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let inboundData = self.unwrapInboundIn(data)
    let bytes = Array(inboundData.readableBytesView)
    outputHandler?(bytes)
  }
}
