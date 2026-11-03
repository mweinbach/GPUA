// Ported from: crates/rune/src/clipboard/web.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(WASI)
import CWebSys

extension ClipboardClient {
    func readFor(_ purpose: ClipboardPurpose) {
        var buf = [UInt8](repeating: 0, count: 65536)
        let len = buf.withUnsafeMutableBufferPointer { ptr in
            cwebsys_clipboard_read(ptr.baseAddress, ptr.count)
        }
        let content: ClipboardContent?
        if len > 0 {
            let slice = buf.prefix(min(len, buf.count))
            content = ClipboardContent.new(String(decoding: slice, as: UTF8.self))
        } else {
            content = nil
        }
        if let reply = purpose.reply(content), sendReply(reply) {
            wake()
        }
    }

    func pasteEvent<S>(_ rt: Runtime<S>, _ content: ClipboardContent) {
        let purpose = ClipboardPurpose.pasteForRuntime(rt, nil)
        let filtered = (purpose.forms() == .text) ? ClipboardContent.new(content.text()) : content
        if let reply = purpose.reply(filtered), sendReply(reply) {
            wake()
        }
    }

    func flush<S>(_ rt: Runtime<S>) {
        let att = hostAttachment(for: rt)
        if att.clipboard != nil {
            flushMemoryClipboard(rt)
            return
        }
        att.clearSecretRequest = false
        if let copy = att.copyRequest {
            att.copyRequest = nil
            if copy.isSecret() {
                if let slot = copy.slot() {
                    slot.setState(.failed("secret clipboard writes are unsupported on web"))
                    changed.store(true)
                    wake()
                }
            } else {
                let utf8 = Array(copy.content().text().utf8)
                utf8.withUnsafeBufferPointer { buf in
                    cwebsys_clipboard_write(buf.baseAddress, buf.count)
                }
            }
        }
        if let target = att.pasteRequest {
            att.pasteRequest = nil
            readFor(.pasteForRuntime(rt, target))
        }
        let readIds = att.readRequests
        att.readRequests.removeAll()
        for id in readIds {
            readFor(.read(id))
        }
    }
}
#endif
