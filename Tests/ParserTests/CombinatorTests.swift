//
//  CombinatorTests.swift
//  Parser
//
//  Created by Mark Onyschuk on 2017-03-12.
//  Copyright © 2017 Mark Onyschuk. All rights reserved.
//

import Expect
import XCTest
import Foundation
@testable import Parser

class CombinatorTests: XCTestCase {
    func testItCanParseTheEndOfInput() {
        expect { try Parse.eof().parse("") } .notTo(throwAny())
        expect { try Parse.eof().parse("ABC") } .to(throwAny())
    }
    
    func testItCanPurposefullyParseRegardlessOfInput() {
        expect { try Parse.nothing().parse("ABC") } .notTo(throwAny())
    }
    
    func testItCanPurposefullyThrowRegardlessOfInput() {
        enum Err: Error {
            case example
        }
        
        let parseErr: Parser<String, String> = Parse.error(Err.example)
        expect { try parseErr.parse("ABC") } .to(throwError(Err.example))
    }

    func testItCanParseSimplePrefixes() {
        expect { try Parse.first("C").parse("Cat") } == Character("C")
        expect { try Parse.first("C").parse("Dog") } .to(throwAny())
        
        expect { try Parse.first({ $0 == "C" }).parse("Cat") } == Character("C")
        expect { try Parse.first({ $0 == "C" }).parse("Dog") } .to(throwAny())

        expect { try Parse.first(1).parse([1, 2, 3]) } == 1
        expect { try Parse.first(2).parse([1, 2, 3]) } .to(throwAny())
    }
    
    func testItCanParseComplexPrefixes() {
        expect { try Parse.prefix("AB").parse("ABC") } == "AB"
        expect { try Parse.prefix(while: { $0.isLetter }).parse("ABC123") } == "ABC"
        expect { try Parse.prefix(until: { $0.isWholeNumber }).parse("ABC123") } == "ABC"

        expect { try Parse.characters(in: "0"..."9").parse("ABC123") } .to(throwAny())
        expect { try Parse.characters(in: "A"..."Z").parse("ABC123") } == "ABC"
        expect { try Parse.characters(in: "A"..."Z", "0"..."9").parse("ABC123") } == "ABC123"
    }
    
    func testItCanParseWhitespaceLettersAndNumbers() {
        expect { try Parse.letters().parse("ABC123") } == "ABC"
        expect { try Parse.numbers().parse("123ABC") } == "123"
        expect { try Parse.whitespace().parse(" ABC") } == " "
    }

    func testItCanParseIntegersFromStrings() {
        expect { try Parse.int().parse("123") } == 123
        expect { try Parse.int64().parse("-123") } == -123
    }

    func testItCanParseNonBase10IntegersFromString() {
        expect { try Parse.int(radix: 16).parse("ff") } == 255
        expect { try Parse.int(radix: 16).parse("FF") } == 255
        
        expect { try Parse.int(radix: 2).parse("11") } == 3
        
        expect { try Parse.int(radix: 16, length: 2).parse("FF00") } == 255
        
        expect { try Parse.int(radix: 16, length: 4).parse("FFF") } .to(throwAny())
    }

    func testItCanOptionallyIgnoreSignsWhenParsingIntegers() {
        expect { try Parse.int(signed: false).parse("-123") } .to(throwAny())
        expect { try Parse.int64(signed: false).parse("+123") } .to(throwAny())
    }
    
    func testItCanParseFloatingPointNumbersFromStrings() {
        expect { try Parse.float().parse("0") } == 0
        expect { try Parse.decimal().parse("6.027346e23") } == Decimal(string:"6.027346e23")
    }

    func testItCanParseLiteralsWithoutWhitespacePrefixOrSuffix() {
        expect { try Parse.literal("A").parse("AB") } .notTo(throwAny())
        expect { try Parse.literal("A").parse(" A B ") } .to(throwAny())
        
        expect { try Parse.literal("a", caseInsensitive: true).parse("AB") } .notTo(throwAny())
        expect { try Parse.literal("A", caseInsensitive: true).parse(" A B ") } .to(throwAny())
    }
    
    func testItCanParseTokensWithWhitespacePrefixOrSuffix() {
        expect { try Parse.token("A").parse("AB") } .notTo(throwAny())
        expect { try Parse.token("A").parse(" A B ") } .notTo(throwAny())
        expect { try Parse.token("A").parse("BB") } .to(throwAny())
        expect { try Parse.token("A").parse(" B B ") } .to(throwAny())
        
        expect { try Parse.token("a", caseInsensitive: true).parse("AB") } .notTo(throwAny())
        expect { try Parse.token("a", caseInsensitive: true).parse(" A B ") } .notTo(throwAny())
        expect { try Parse.token("a", caseInsensitive: true).parse("BB") } .to(throwAny())
        expect { try Parse.token("a", caseInsensitive: true).parse(" B B ") } .to(throwAny())
    }


    func testItCanParseQuotedStringsWithArbitraryQuoteAndEscapeCharacters() {
        let squote    = Parse.literal("\'")
        let dquote    = Parse.literal("\"")
        let backslash = Parse.literal("\\")

        // simple
        expect { try Parse.quoted(quote: squote, escape: backslash).parse("'Hi there Gerry,' I said.") } == "'Hi there Gerry,'"
        expect { try Parse.quoted(quote: dquote, escape: backslash).parse("\"Hi there Gerry,\" I said.") } == "\"Hi there Gerry,\""
        
        // with escapes
        expect { try Parse.quoted(quote: squote, escape: squote).parse("'Hi, I''m Gerry''s friend,' I said.") } == "'Hi, I''m Gerry''s friend,'"
        expect { try Parse.quoted(quote: squote, escape: backslash).parse("'Hi, I\\'m Gerry\\'s friend,' I said.") } == "'Hi, I\\'m Gerry\\'s friend,'"

        // unmatched terminal
        expect { try Parse.quoted(quote: squote, escape: squote).parse("'Hi, I''m Gerry''s friend, I said.") } .to(throwAny())
    }

    func testItCanStripOuterQuotesAndEscapesForArbitraryQuoteAndEscapeCharacters() {
        let squote    = Parse.literal("\'")
        let backslash = Parse.literal("\\")

        expect { try Parse.unquoted(quote: squote, escape: backslash).parse("'Hi, I\\'m Gerry\\'s friend,' I said.") } == "Hi, I'm Gerry's friend,"
    }

    func testItCanParseTheResultOfEitherOfTwoParsers() {
        let a = Parse.literal("A")
        let b = Parse.literal("B")

        let aOrB = Parse.either(a, or: b)
        let altAOrB = a <|> b
        
        expect { try aOrB.parse("ABABC") } .notTo(throwAny())
        expect { try altAOrB.parse("ABABC") } .notTo(throwAny())

        expect { try aOrB.parse("CABABC") } .to(throwAny())
        expect { try altAOrB.parse("CABABC") } .to(throwAny())
    }
    
    func testItCanParseTheResultOfBothOfTwoParsers() {
        let a = Parse.literal("A")
        let b = Parse.literal("B")

        let aAndB = Parse.both(a, and: b)
        let altAAndB = a <*> b
        
        expect { try aAndB.parse("ABABC") } .notTo(throwAny())
        expect { try altAAndB.parse("ABABC") } .notTo(throwAny())

        expect { try aAndB.parse("ACBABC") } .to(throwAny())
        expect { try altAAndB.parse("ACBABC") } .to(throwAny())
    }

    func testItCanParseTheFirstOrSecondResultOfTwoParsers() {
        let a = Parse.literal("A")
        let b = Parse.literal("B")

        expect { try (a <* b).parse("ABC") } == "A"
        expect { try (a *> b).parse("ABC") } == "B"

        expect { try (a <* b).parse("ACB") } .to(throwAny())
        expect { try (a *> b).parse("ACB") } .to(throwAny())
    }

    func testItCanParseUpToThePointASecondParserSucceeds() {
        let a = Parse.literal("A")
        let b = Parse.literal("B")

        expect { try Parse.prefix(until: a <|> b).parse("123ABC") } == "123"
        expect { try Parse.prefix(until: a <|> b).parse("123XYZ") } .to(throwAny())
    }

    func testItCanParseZeroOrOneInstanceOfAnotherParser() {
        let a = Parse.literal("A")

        expect { try Parse.zeroOrOne(a).parse("AB") } == "A"
        expect { try Parse.zeroOrOne(a).parse("BB") } == nil
    }

    func testItCanParseMultipleInstancesOfAnotherParser() {
        let a = Parse.literal("A")

        expect { try Parse.zeroOrMore(a).parse("AABB") } == ["A", "A"]
        expect { try Parse.zeroOrMore(a).parse("BBAA") } == []

        expect { try Parse.oneOrMore(a).parse("AABB") } == ["A", "A"]
        expect { try Parse.oneOrMore(a).parse("BBAA") } .to(throwAny())
    }
    
    func testItCanParseMultipleInstancesOfAnotherParserWithSeparators() {
        let a = Parse.literal("A")

        let sep = Parse.token(",")
        let oneOrMoreA = Parse.oneOrMore(a, separatedBy: sep)
        let zeroOrMoreA = Parse.zeroOrMore(a, separatedBy: sep)

        expect { try oneOrMoreA.parse("A, A, B, B") } == ["A", "A"]
        expect { try zeroOrMoreA.parse("A, A, B, B") } == ["A", "A"]
        expect { try oneOrMoreA.parse("B, A, A, B, B") } .to(throwAny())
        expect { try zeroOrMoreA.parse("B, A, A, B, B") } == []
    }

    func testItCanReduceTheResultsOfParsedValuesFromEitherTheRightOrTheLeft() {
        let num = Parse.int() |> { $0.description }
        let sep = Parse.token(",")
        
        let parenthesizedL = Parse.reduce(left: num, operators: sep) {
            lhs, _, rhs in "(\(lhs), \(rhs))"
        }
        let parenthesizedR = Parse.reduce(right: num, operators: sep) {
            rhs, _, lhs in "(\(lhs), \(rhs))"
        }
        
        expect(try parenthesizedL.parse("1, 2, 3")) == "((1, 2), 3)"
        expect { try parenthesizedR.parse("1, 2, 3") } == "(1, (2, 3))"
    }
    
    func testItCanReduceTheResultOfParsedValuesFromLeftToRightWithPrecedence() {
        let num = Parse.int()
        let add = Parse.token("+") |> { (a: Int, b: Int) -> Int in a + b }
        let sub = Parse.token("-") |> { (a: Int, b: Int) -> Int in a - b }
        let mul = Parse.token("*") |> { (a: Int, b: Int) -> Int in a * b }
        let div = Parse.token("/") |> { (a: Int, b: Int) -> Int in a / b }
        
        let factor = Parse.reduce(left: num, operators: mul <|> div)
        let term   = Parse.reduce(left: factor, operators: add <|> sub)
        
        let expr = term <|> num
        
        expect { try expr.parse("2 + 5 * 4") } == 22
        expect { try expr.parse("10 / 2 + 5 * 4") } == 25
        
        expect { try expr.parse("ABAB") } .to(throwAny())
    }
}
