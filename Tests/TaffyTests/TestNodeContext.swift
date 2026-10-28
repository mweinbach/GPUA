// Swift-only: Test harness context and measure function matching upstream tests/common/src/lib.rs
import Taffy

public func newTestTree() -> TaffyTree<TestNodeContext> {
    TaffyTree<TestNodeContext>()
}

public struct TestNodeContext: Sendable {
    public var count: Int
    public var measureData: TestMeasureData

    public init(measureData: TestMeasureData) {
        self.count = 0
        self.measureData = measureData
    }

    public static func zero() -> TestNodeContext {
        TestNodeContext(measureData: .zero)
    }

    public static func fixed(_ width: Float, _ height: Float) -> TestNodeContext {
        TestNodeContext(measureData: .fixed(Size(width: width, height: height)))
    }

    public static func fixed(width: Float, height: Float) -> TestNodeContext {
        TestNodeContext(measureData: .fixed(Size(width: width, height: height)))
    }

    public static func aspectRatio(_ width: Float, _ heightRatio: Float) -> TestNodeContext {
        TestNodeContext(measureData: .aspectRatio(AspectRatioMeasureData(width: width, heightRatio: heightRatio)))
    }

    public static func aspectRatio(width: Float, heightRatio: Float) -> TestNodeContext {
        TestNodeContext(measureData: .aspectRatio(AspectRatioMeasureData(width: width, heightRatio: heightRatio)))
    }

    public static func ahemText(_ textContent: String, _ writingMode: WritingMode) -> TestNodeContext {
        TestNodeContext(measureData: .ahemText(AhemTextMeasureData(textContent: textContent, writingMode: writingMode)))
    }

    public static func ahemText(_ textContent: String, writingMode: WritingMode) -> TestNodeContext {
        TestNodeContext(measureData: .ahemText(AhemTextMeasureData(textContent: textContent, writingMode: writingMode)))
    }
}

public enum TestMeasureData: Sendable {
    case zero
    case fixed(Size<Float>)
    case aspectRatio(AspectRatioMeasureData)
    case ahemText(AhemTextMeasureData)
}

public struct AspectRatioMeasureData: Sendable {
    public var width: Float
    public var heightRatio: Float

    public init(width: Float, heightRatio: Float) {
        self.width = width
        self.heightRatio = heightRatio
    }

    public func measure(knownDimensions: Size<Float?>) -> Size<Float> {
        let width = knownDimensions.width ?? self.width
        let height = knownDimensions.height ?? (width * self.heightRatio)
        return Size(width: width, height: height)
    }
}

public enum WritingMode: Sendable {
    case horizontal
    case vertical
}

public struct AhemTextMeasureData: Sendable {
    public var textContent: String
    public var writingMode: WritingMode

    public init(textContent: String, writingMode: WritingMode) {
        self.textContent = textContent
        self.writingMode = writingMode
    }

    public func measure(
        knownDimensions: Size<Float?>,
        availableSpace: Size<AvailableSpace>
    ) -> Size<Float> {
        let zws: Character = "\u{200B}"
        let hWidth: Float = 10.0
        let hHeight: Float = 10.0

        let inlineAxis: AbsoluteAxis = writingMode == .horizontal ? .horizontal : .vertical
        let blockAxis: AbsoluteAxis = inlineAxis.otherAxis()
        let lines: [String] = textContent.split(separator: zws, omittingEmptySubsequences: false).map(String.init)

        if lines.isEmpty {
            return Size.ZERO
        }

        let minLineLength = lines.map(\.count).max() ?? 0
        let maxLineLength = lines.map(\.count).reduce(0, +)

        let inlineSize: Float
        if let kd = knownDimensions.getAbs(axis: inlineAxis) {
            inlineSize = kd
        } else {
            let avail = availableSpace.getAbs(axis: inlineAxis)
            let baseSize: Float
            switch avail {
            case .minContent:
                baseSize = Float(minLineLength) * hWidth
            case .maxContent:
                baseSize = Float(maxLineLength) * hWidth
            case .definite(let size):
                baseSize = min(size, Float(maxLineLength) * hWidth)
            }
            inlineSize = max(baseSize, Float(minLineLength) * hWidth)
        }

        let blockSize: Float
        if let kd = knownDimensions.getAbs(axis: blockAxis) {
            blockSize = kd
        } else {
            let inlineLineLength = Int(floor(inlineSize / hWidth))
            var lineCount = 1
            var currentLineLength = 0
            for line in lines {
                if currentLineLength + line.count > inlineLineLength {
                    if currentLineLength > 0 {
                        lineCount += 1
                    }
                    currentLineLength = line.count
                } else {
                    currentLineLength += line.count
                }
            }
            blockSize = Float(lineCount) * hHeight
        }

        switch writingMode {
        case .horizontal:
            return Size(width: inlineSize, height: blockSize)
        case .vertical:
            return Size(width: blockSize, height: inlineSize)
        }
    }
}

public func testMeasureFunction(
    _ knownDimensions: Size<Float?>,
    _ availableSpace: Size<AvailableSpace>,
    _ nodeId: NodeId,
    _ context: inout TestNodeContext?,
    _ style: Style<String>
) -> Size<Float> {
    if let width = knownDimensions.width, let height = knownDimensions.height {
        return Size(width: width, height: height)
    }

    guard var ctx = context else {
        return Size(width: knownDimensions.width ?? 0.0, height: knownDimensions.height ?? 0.0)
    }

    ctx.count += 1
    context = ctx

    let computeSize: Size<Float>
    switch ctx.measureData {
    case .zero:
        computeSize = Size.ZERO
    case .fixed(let size):
        computeSize = size
    case .aspectRatio(let data):
        computeSize = data.measure(knownDimensions: knownDimensions)
    case .ahemText(let data):
        computeSize = data.measure(knownDimensions: knownDimensions, availableSpace: availableSpace)
    }

    return Size(
        width: knownDimensions.width ?? computeSize.width,
        height: knownDimensions.height ?? computeSize.height
    )
}
