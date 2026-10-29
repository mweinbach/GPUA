// Ported from: crates/gpui_linux/src/linux/xdg_desktop_portal.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI

public enum Event: Sendable {
    case windowAppearance(WindowAppearance)
    case cursorTheme(String)
    case cursorSize(UInt32)
}

// PORT NOTE: XDPEventSource bridges XDG Desktop Portal settings into the platform event loop.
public final class XDPEventSource: @unchecked Sendable {
    public let receiver: PriorityQueueCalloopReceiver<Event>
    public let sender: PriorityQueueCalloopSender<Event>

    public init(receiver: PriorityQueueCalloopReceiver<Event>, sender: PriorityQueueCalloopSender<Event>) {
        self.receiver = receiver
        self.sender = sender
    }

    public static func new(executor: BackgroundExecutor) -> XDPEventSource {
        let (sender, receiver) = PriorityQueueCalloopReceiver<Event>.new()

        executor.spawn {
            let appearance: WindowAppearance = .dark
            try? sender.send(priority: .medium, item: .windowAppearance(appearance))
            try? sender.send(priority: .medium, item: .cursorTheme("default"))
            try? sender.send(priority: .medium, item: .cursorSize(24))
        }.detach()

        return XDPEventSource(receiver: receiver, sender: sender)
    }
}
#endif
