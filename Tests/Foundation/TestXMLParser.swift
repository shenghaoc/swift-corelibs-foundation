// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//

enum XMLParserDelegateEvent {
    case startDocument
    case endDocument
    case didStartElement(String, String?, String?, [String: String])
    case didEndElement(String, String?, String?)
    case foundCharacters(String)
}

extension XMLParserDelegateEvent: Equatable {

    public static func ==(lhs: XMLParserDelegateEvent, rhs: XMLParserDelegateEvent) -> Bool {
        switch (lhs, rhs) {
        case (.startDocument, startDocument):
            return true
        case (.endDocument, endDocument):
            return true
        case let (.didStartElement(lhsElement, lhsNamespace, lhsQname, lhsAttr),
                  didStartElement(rhsElement, rhsNamespace, rhsQname, rhsAttr)):
            return lhsElement == rhsElement && lhsNamespace == rhsNamespace && lhsQname == rhsQname && lhsAttr == rhsAttr
        case let (.didEndElement(lhsElement, lhsNamespace, lhsQname),
                  .didEndElement(rhsElement, rhsNamespace, rhsQname)):
            return lhsElement == rhsElement && lhsNamespace == rhsNamespace && lhsQname == rhsQname
        case let (.foundCharacters(lhsChar), .foundCharacters(rhsChar)):
            return lhsChar == rhsChar
        default:
            return false
        }
    }

}

class XMLParserDelegateEventStream: NSObject, XMLParserDelegate {
    var events: [XMLParserDelegateEvent] = []

    func parserDidStartDocument(_ parser: XMLParser) {
        events.append(.startDocument)
    }
    func parserDidEndDocument(_ parser: XMLParser) {
        events.append(.endDocument)
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        events.append(.didStartElement(elementName, namespaceURI, qName, attributeDict))
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        events.append(.didEndElement(elementName, namespaceURI, qName))
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        events.append(.foundCharacters(string))
    }
}

class TestXMLParser : XCTestCase {

    // Helper method to embed the correct encoding in the XML header
    static func xmlUnderTest(encoding: String.Encoding? = nil) -> String {
        let xmlUnderTest = "<test attribute='value'><foo>bar</foo></test>"
        guard var encoding = encoding?.description else {
            return xmlUnderTest
        }
        if let open = encoding.range(of: "(") {
            let range: Range<String.Index> = open.upperBound..<encoding.endIndex
            encoding = String(encoding[range])
        }
        if let close = encoding.range(of: ")") {
            encoding = String(encoding[..<close.lowerBound])
        }
        return "<?xml version='1.0' encoding='\(encoding.uppercased())' standalone='no'?>\n\(xmlUnderTest)\n"
    }

    static func xmlUnderTestExpectedEvents(namespaces: Bool = false) -> [XMLParserDelegateEvent] {
        let uri: String? = namespaces ? "" : nil
        return [
            .startDocument,
            .didStartElement("test", uri, namespaces ? "test" : nil, ["attribute": "value"]),
            .didStartElement("foo", uri, namespaces ? "foo" : nil, [:]),
            .foundCharacters("bar"),
            .didEndElement("foo", uri, namespaces ? "foo" : nil),
            .didEndElement("test", uri, namespaces ? "test" : nil),
            .endDocument,
        ]
    }


    func test_withData() {
        let xml = Array(TestXMLParser.xmlUnderTest().utf8CString)
        let data = xml.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<CChar>) -> Data in
            return buffer.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: buffer.count * MemoryLayout<CChar>.stride) {
                return Data(bytes: $0, count: buffer.count)
            }
        }
        let parser = XMLParser(data: data)
        let stream = XMLParserDelegateEventStream()
        parser.delegate = stream
        let res = parser.parse()
        XCTAssertEqual(stream.events, TestXMLParser.xmlUnderTestExpectedEvents())
        XCTAssertTrue(res)
    }

    func test_withDataEncodings() {
        // If th <?xml header isn't present, any non-UTF8 encodings fail. This appears to be libxml2 behavior.
        // These don't work, it may just be an issue with the `encoding=xxx`.
        //   - .nextstep, .utf32LittleEndian
        var encodings: [String.Encoding] = [.utf16LittleEndian, .utf16BigEndian,  .utf8]
#if !os(Windows)
        // libxml requires iconv support for UTF32
        encodings.append(.utf32BigEndian)
#endif
        for encoding in encodings {
            let xml = TestXMLParser.xmlUnderTest(encoding: encoding)
            let parser = XMLParser(data: xml.data(using: encoding)!)
            let stream = XMLParserDelegateEventStream()
            parser.delegate = stream
            let res = parser.parse()
            XCTAssertEqual(stream.events, TestXMLParser.xmlUnderTestExpectedEvents())
            XCTAssertTrue(res)
        }
    }

    func test_withDataOptions() {
        let xml = TestXMLParser.xmlUnderTest()
        let parser = XMLParser(data: xml.data(using: .utf8)!)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = true
        let stream = XMLParserDelegateEventStream()
        parser.delegate = stream
        let res = parser.parse()
        XCTAssertEqual(stream.events, TestXMLParser.xmlUnderTestExpectedEvents(namespaces: true)  )
        XCTAssertTrue(res)
    }

    func test_startElementNamespaceAndAttributeArrays() {
        class Delegate: NSObject, XMLParserDelegate {
            var starts: [String] = []
            var mappings: [String] = []
            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
                starts.append("\(elementName) \(namespaceURI ?? "nil") \(qName ?? "nil") \(attributeDict.sorted { $0.key < $1.key })")
            }
            func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
                mappings.append("\(prefix) \(namespaceURI)")
            }
        }
        let xml = "<r xmlns='urn:d' xmlns:p='urn:p'><a/><b x='1'/><c p:y='2'/></r>"
        let expected = [
            (starts: [
                "r nil nil [(key: \"xmlns\", value: \"urn:d\"), (key: \"xmlns:p\", value: \"urn:p\")]",
                "a nil nil []",
                "b nil nil [(key: \"x\", value: \"1\")]",
                "c nil nil [(key: \"p:y\", value: \"2\")]",
            ], mappings: [String]()),
            (starts: [
                "r urn:d r []",
                "a urn:d a []",
                "b urn:d b [(key: \"x\", value: \"1\")]",
                "c urn:d c [(key: \"p:y\", value: \"2\")]",
            ], mappings: [" urn:d", "p urn:p"]),
        ]
        for (namespaces, expected) in zip([false, true], expected) {
            let parser = XMLParser(data: xml.data(using: .utf8)!)
            parser.shouldProcessNamespaces = namespaces
            parser.shouldReportNamespacePrefixes = namespaces
            let delegate = Delegate()
            parser.delegate = delegate
            XCTAssertTrue(parser.parse())
            XCTAssertEqual(delegate.starts, expected.starts)
            XCTAssertEqual(delegate.mappings.sorted(), expected.mappings)
        }
    }

    func test_sr9758_abortParsing() {
        class Delegate: NSObject, XMLParserDelegate {
            func parserDidStartDocument(_ parser: XMLParser) { parser.abortParsing() }
        }
        let xml = TestXMLParser.xmlUnderTest(encoding: .utf8)
        let parser = XMLParser(data: xml.data(using: .utf8)!)
        let delegate = Delegate()
        defer {
            // XMLParser holds a weak reference to delegate. Keep it alive.
            _fixLifetime(delegate)
        }
        parser.delegate = delegate
        XCTAssertFalse(parser.parse())
        XCTAssertNotNil(parser.parserError)
    }

    func test_sr10157_swappedElementNames() {
        class ElementNameChecker: NSObject, XMLParserDelegate {
            let name: String
            init(_ name: String) { self.name = name }
            func parser(_ parser: XMLParser,
                        didStartElement elementName: String,
                        namespaceURI: String?,
                        qualifiedName qName: String?,
                        attributes attributeDict: [String: String] = [:])
            {
                if parser.shouldProcessNamespaces {
                    XCTAssertEqual(self.name, qName)
                } else {
                    XCTAssertEqual(self.name, elementName)
                }
            }
            func parser(_ parser: XMLParser,
                        didEndElement elementName: String,
                        namespaceURI: String?,
                        qualifiedName qName: String?)
            {
                if parser.shouldProcessNamespaces {
                    XCTAssertEqual(self.name, qName)
                } else {
                    XCTAssertEqual(self.name, elementName)
                }
            }
            func check() {
                let elementString = "<\(self.name) />"
                var parser = XMLParser(data: elementString.data(using: .utf8)!)
                parser.delegate = self
                XCTAssertTrue(parser.parse())
                
                // Confirm that the parts of QName is also not swapped.
                parser = XMLParser(data: elementString.data(using: .utf8)!)
                parser.delegate = self
                parser.shouldProcessNamespaces = true
                XCTAssertTrue(parser.parse())
            }
        }
        
        ElementNameChecker("noPrefix").check()
        ElementNameChecker("myPrefix:myLocalName").check()
    }

    func testExternalEntity() throws {
        class Delegate: XMLParserDelegateEventStream {
            override func parserDidStartDocument(_ parser: XMLParser) {
                // Start a child parser, updating `currentParser` to the child parser
                // to ensure that `currentParser` won't be reset to `nil`, which would
                // ignore any external entity related configuration.
                let childParser = XMLParser(data: "<child />".data(using: .utf8)!)
                XCTAssertTrue(childParser.parse())
                super.parserDidStartDocument(parser)
            }
        }
        try withTemporaryDirectory { dir, _ in
            let greetingPath = dir.appendingPathComponent("greeting.xml")
            try Data("<hello />".utf8).write(to: greetingPath)
            let xml = """
            <?xml version="1.0" standalone="no"?>
            <!DOCTYPE doc [
              <!ENTITY greeting SYSTEM "\(greetingPath.absoluteString)">
            ]>
            <doc>&greeting;</doc>
            """

            let parser = XMLParser(data: xml.data(using: .utf8)!)
            // Explicitly disable external entity resolving
            parser.externalEntityResolvingPolicy = .never
            let delegate = Delegate()
            parser.delegate = delegate
            // The parse result changes depending on the libxml2 version
            // because of the following libxml2 commit (shipped in libxml2 2.9.10):
            // https://gitlab.gnome.org/GNOME/libxml2/-/commit/eddfbc38fa7e84ccd480eab3738e40d1b2c83979
            // So we don't check the parse result here.
            _ = parser.parse()
            XCTAssertEqual(delegate.events, [
                .startDocument,
                .didStartElement("doc", nil, nil, [:]),
                // Should not have parsed the external entity
                .didEndElement("doc", nil, nil),
                .endDocument,
            ])
        }
    }

    // MARK: - DTD and processing instruction callback values

    private final class DTDDelegate: NSObject, XMLParserDelegate {
        struct AttributeDeclaration: Equatable {
            let name: String
            let element: String
            let defaultValue: String?
        }

        struct NotationDeclaration: Equatable {
            let name: String
            let publicID: String?
            let systemID: String?
        }

        struct UnparsedEntityDeclaration: Equatable {
            let name: String
            let publicID: String?
            let systemID: String?
            let notationName: String?
        }

        struct ProcessingInstruction: Equatable {
            let target: String
            let data: String?
        }

        private(set) var attributeDeclarations: [AttributeDeclaration] = []
        private(set) var notationDeclarations: [NotationDeclaration] = []
        private(set) var unparsedEntityDeclarations: [UnparsedEntityDeclaration] = []
        private(set) var processingInstructions: [ProcessingInstruction] = []
        private(set) var startedElements: [String] = []

        func parser(_ parser: XMLParser, foundAttributeDeclarationWithName attributeName: String, forElement elementName: String, type: String?, defaultValue: String?) {
            attributeDeclarations.append(AttributeDeclaration(name: attributeName, element: elementName, defaultValue: defaultValue))
        }

        func parser(_ parser: XMLParser, foundNotationDeclarationWithName name: String, publicID: String?, systemID: String?) {
            notationDeclarations.append(NotationDeclaration(name: name, publicID: publicID, systemID: systemID))
        }

        func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String, publicID: String?, systemID: String?, notationName: String?) {
            unparsedEntityDeclarations.append(UnparsedEntityDeclaration(name: name, publicID: publicID, systemID: systemID, notationName: notationName))
        }

        func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
            processingInstructions.append(ProcessingInstruction(target: target, data: data))
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
            startedElements.append(elementName)
        }
    }

    private func parse(_ xml: String, with delegate: XMLParserDelegate) -> Bool {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        return withExtendedLifetime(delegate) { parser.parse() }
    }

    func test_attributeDeclarationEnumeratedDefaults() {
        let delegate = DTDDelegate()
        let xml = #"<!DOCTYPE Rec [<!ELEMENT Rec EMPTY><!ATTLIST Rec a (x|y) #IMPLIED b (x|y) "x">]><Rec/>"#
        XCTAssertTrue(parse(xml, with: delegate))
        XCTAssertEqual(delegate.attributeDeclarations, [
            .init(name: "a", element: "Rec", defaultValue: nil),
            .init(name: "b", element: "Rec", defaultValue: "x"),
        ])
    }

    func test_notationDeclarationWithoutPublicOrSystemID() {
        let delegate = DTDDelegate()
        let xml = #"<!DOCTYPE Rec [<!NOTATION s SYSTEM "x"><!NOTATION p PUBLIC "y">]><Rec/>"#
        XCTAssertTrue(parse(xml, with: delegate))
        XCTAssertEqual(delegate.notationDeclarations, [
            .init(name: "s", publicID: nil, systemID: "x"),
            .init(name: "p", publicID: "y", systemID: nil),
        ])
    }

    func test_processingInstructionWithoutData() {
        let delegate = DTDDelegate()
        let xml = "<root><?foo?></root>"
        XCTAssertTrue(parse(xml, with: delegate))
        XCTAssertEqual(delegate.processingInstructions, [
            .init(target: "foo", data: nil),
        ])
    }

    func test_unparsedEntityDeclarationNullableValues() {
        let delegate = DTDDelegate()
        let xml = #"<!DOCTYPE Rec [<!ENTITY a SYSTEM "x" NDATA n><!ENTITY b PUBLIC "p" NDATA n><!ENTITY c SYSTEM "y" NDATA >]><Rec/>"#
        _ = parse(xml, with: delegate)
        XCTAssertEqual(delegate.unparsedEntityDeclarations, [
            .init(name: "a", publicID: nil, systemID: "x", notationName: "n"),
            .init(name: "b", publicID: "p", systemID: nil, notationName: "n"),
            .init(name: "c", publicID: nil, systemID: "y", notationName: nil),
        ])
    }

    func test_dtdCallbacksWithNullArgumentsDoNotCrash() {
        for xml in ["<!DOCTYPE Rec [<!ELEMENT Rec EMPTY>]><Rec/>", "<!DOCTYPE [<!ELEMENT Rec EMPTY>]><Rec/>"] {
            let delegate = DTDDelegate()
            _ = parse(xml, with: delegate)
            XCTAssertEqual(delegate.startedElements, ["Rec"])
        }
    }

    func test_dataWithRequiredAndImpliedAttributeDeclarations() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE HealthData [
        <!ELEMENT HealthData (Rec*)>
        <!ELEMENT Rec EMPTY>
        <!ATTLIST Rec
          type CDATA #REQUIRED
          value CDATA #IMPLIED
        >
        ]>
        <HealthData>
        <Rec type="HKQuantityTypeIdentifierHeartRate" value="150"/>
        <Rec type="HKQuantityTypeIdentifierHeartRate" value="151"/>
        </HealthData>

        """
        XCTAssertEqual(xml.utf8.count, 324)

        let delegate = DTDDelegate()
        XCTAssertTrue(parse(xml, with: delegate))
        XCTAssertEqual(delegate.startedElements, ["HealthData", "Rec", "Rec"])
        XCTAssertEqual(delegate.attributeDeclarations, [
            .init(name: "type", element: "Rec", defaultValue: nil),
            .init(name: "value", element: "Rec", defaultValue: nil),
        ])
    }
}
