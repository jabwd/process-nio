import NIO
import Foundation

public typealias ProcessOutputHandler = (String) -> Void

public final class ProcessChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = ByteBuffer
  public var outputHandler: ProcessOutputHandler?

  init(outputHandler: ProcessOutputHandler? = nil) {
    self.outputHandler = outputHandler
  }

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let inboundData = self.unwrapInboundIn(data)

    guard let str = String(bytes: inboundData.readableBytesView, encoding: .utf8) else {
      return
    }
    outputHandler?(str)
  }

  public func channelInactive(context: ChannelHandlerContext) {
    print("Channel dieded")
  }
}
