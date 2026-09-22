import XCTest
@testable import RewindButFast

final class ImageSizingTests: XCTestCase {
    func testWidthFillsViewportWithoutShrinkingTallScreens() {
        let image = CGSize(width: 1600, height: 2400)
        let viewport = CGSize(width: 1000, height: 500)
        let width = ImageSizing.width.scale(image: image, viewport: viewport)
        let fit = ImageSizing.fit.scale(image: image, viewport: viewport)
        XCTAssertEqual(image.width * width, viewport.width, accuracy: 0.01)
        XCTAssertGreaterThan(image.height * width, viewport.height)
        XCTAssertEqual(image.height * fit, viewport.height, accuracy: 0.01)
        XCTAssertGreaterThan(width, fit * 2)
    }

    func testActualSizeAndInvalidDimensions() {
        let viewport = CGSize(width: 1000, height: 500)
        XCTAssertEqual(ImageSizing.custom(1).scale(image: CGSize(width: 2560, height: 1600), viewport: viewport), 1)
        XCTAssertEqual(ImageSizing.width.scale(image: .zero, viewport: viewport), 1)
        XCTAssertEqual(ImageSizing.custom(100).scale(image: viewport, viewport: viewport), 4)
    }
}
