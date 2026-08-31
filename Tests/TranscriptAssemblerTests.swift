import XCTest
@testable import MacTyper

final class TranscriptAssemblerTests: XCTestCase {
    func testNormWords() {
        XCTAssertEqual(TranscriptAssembler.normWords("Hello, World!  foo"), ["hello", "world", "foo"])
        XCTAssertEqual(TranscriptAssembler.normWords("...  ,"), [])
        XCTAssertEqual(TranscriptAssembler.normWords("Привет, мир."), ["привет", "мир"])
    }

    func testSimpleFinal() {
        var a = TranscriptAssembler()
        a.addInterim("hello")
        a.addFinal("Hello world.")
        XCTAssertEqual(a.mergedText(), "Hello world.")
    }

    func testPerFinalTailRecovery() {
        // The server's final drops trailing words its own interim heard.
        var a = TranscriptAssembler()
        a.addInterim("the second phrase after a long pause")
        a.addFinal("The second phrase.")
        XCTAssertEqual(a.mergedText(), "the second phrase after a long pause")
    }

    func testMergeTimeTailRecovery() {
        // Interim extends the last final at merge time (interim arrived,
        // then the session ended before a better final).
        var a = TranscriptAssembler()
        a.addFinal("First sentence.")
        a.addInterim("First sentence. And then more")
        // Wait — interims reset per utterance; simulate an utterance-2
        // interim that extends final-2.
        var b = TranscriptAssembler()
        b.addFinal("Hello there.")
        b.addInterim("hello there my friend")
        XCTAssertEqual(b.mergedText(), "hello there my friend")
        _ = a
    }

    func testInterimOnlyNoFinals() {
        var a = TranscriptAssembler()
        a.addInterim("only interim text")
        XCTAssertEqual(a.mergedText(), "only interim text")
    }

    func testNonExtendingInterimIgnored() {
        var a = TranscriptAssembler()
        a.addFinal("The complete sentence here.")
        a.addInterim("something entirely different")
        XCTAssertEqual(a.mergedText(), "The complete sentence here.")
    }

    func testMultipleTurnsJoined() {
        var a = TranscriptAssembler()
        a.addInterim("first part")
        a.addFinal("First part.")
        a.addInterim("second part")
        a.addFinal("Second part.")
        XCTAssertEqual(a.mergedText(), "First part. Second part.")
    }

    func testPreview() {
        var a = TranscriptAssembler()
        a.addFinal("Done bit.")
        a.addInterim("in flight")
        XCTAssertEqual(a.preview, "Done bit. in flight")
    }

    func testEmpty() {
        let a = TranscriptAssembler()
        XCTAssertNil(a.mergedText())
    }
}
