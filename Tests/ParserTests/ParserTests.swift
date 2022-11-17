//
//  ParserTests.swift
//  ParserTests
//
//  Created by Mark Onyschuk on 2017-03-10.
//  Copyright © 2017 Mark Onyschuk. All rights reserved.
//

import Expect
import XCTest
@testable import Parser

class ParserTests: XCTestCase {

    func testItCanBeInitializedWithABodyFunction() {
        let body: (ParserInput<String>)throws->ParserOutput<String, ParserInput<String>> = {
             if let output = $0.take(while: { $0.isWhitespace }) {
                 return output
             } else {
                 throw ParseError.unmatched
             }
         }
         let _ = Parser(body: body)
    }

    let whitespaceParser = Parser<String, String> {
        if let output = $0.take(while: { $0.isWhitespace }) {
            return output
        } else {
            throw ParseError.unmatched
        }
    }
    
    func testItProducesOnMatch() {
        expect { try self.whitespaceParser.parse(" A") } == " "
    }
    
    func testItThrowsIfItCantMatch() {
        expect { try self.whitespaceParser.parse("A ") } .to(throwAny())
    }

    func testItCanMapItsOutput() {
        let whitespaceCounter = whitespaceParser.map{ $0.count }
        expect { try whitespaceCounter.parse("   A") } == 3
    }
    
    func testItCanThrowCustomErrors() {
        let a = Parse.token("a")
        
        let twoAs = a <*> a

        // generic errors
        expect { try twoAs.parse("aa") } .notTo(throwAny())
        expect { try twoAs.parse("ab") } .to(throwError(ParseError.unmatched))
        
        // custom error
        enum Err: Error {
            case custom
        }
        
        let customA = a.throwing(error: Err.custom)
        let customTwoAs = customA <*> customA
        
        do {
            _ = try customTwoAs.parse("ab")
        }
        catch let err as ParserError<String, Err> {
            expect { err.error } == .custom
            expect { err.input.description } == "a^b"
        }
        catch {
            XCTFail()
        }
    }
    
    func testItBubblesUpMeaningfulErrorsToTheTopLevel() {
        enum Err: Error, Equatable {
            case missingNumber
            case missingSeparator
            case unclosedParens
        }
        
        let arg  = Parse.numbers().throwing(error: Err.missingNumber)
        let sep  = Parse.token(",").throwing(error: Err.missingSeparator)
        
        let obrak = Parse.token("(")
        let cbrak = Parse.token(")").throwing(error: Err.unclosedParens)
        
        let fname = Parse.letters()
        let fargs = Parse.list(of: arg, separatedBy: sep).between(obrak, cbrak)
        
        let expr  = fname<*>fargs
        
        expect { try expr.parse("f(1, 2, 3)") } .notTo(throwAny())

        do {
            _ = try expr.parse("f(1, 2")
        }
        catch let error as ParserError<String, Err> {
            expect { error.error } == .unclosedParens
        }
        catch {
            XCTFail()
        }

        do {
            _ = try expr.parse("f(1,")
        }
        catch let error as ParserError<String, Err> {
            expect { error.error } == .unclosedParens
        }
        catch {
            XCTFail()
        }

    }
}

class ParserInputTests: XCTestCase {
    func testItCanBeInitializedWithAParsableValue() {
        let text = "ABC"
        let stringInput = ParserInput(input: text)
        expect { stringInput.input } == text
        
        let numbers = [1, 2, 3]
        let numericInput = ParserInput(input: numbers)
        expect { numericInput.input } == numbers
    }
    
    func testItInitiallyPointsToTheBeginningOfItsInput() {
        let text = "ABC"
        let input = ParserInput(input: text)
        expect { input.position } == input.input.startIndex
    }
    
    func testItReturnsNilWhenNotMatchingAPrefix() {
        let input = ParserInput(input: "ABC")
        expect { input.take("C") } .to(beNil())
    }
    
    func testItReturnsANewInputWhenMatchingAPrefix() {
        let input = ParserInput(input: "ABC")
        expect { input.take("AB") } .notTo(beNil())
    }
    
    func testItReturnsNilWhenNotMatchingAWhilePrefix() {
        let input = ParserInput(input: "ABC123")
        expect { input.take(while: { $0.isNumber }) } .to(beNil())
    }
    
    func testItReturnsANewInputWhenMatchingAWhilePrefix() {
        let input = ParserInput(input: "ABC123")
        expect { input.take(while: { $0.isLetter }) } .notTo(beNil())
    }
    
    func testItReturnsNilWhenNotMatchingAnUntilPrefix() {
        let input = ParserInput(input: "ABC123")
        expect { input.take(until: { $0.isLetter }) } .to(beNil())
    }
    
    func testItReturnsANewInputWhenMatchingAnUntilPrefix() {
        let input = ParserInput(input: "ABC123")
        expect { input.take(until: { $0.isNumber }) } .notTo(beNil())
    }
    
    func testItCanReportWhenItIsAtTheEndOfInput() {
        let input = ParserInput(input: "ABC")
        expect { input.isAtEnd() } == false
        
        let remainder = input.take("ABC")?.remainder
        expect { remainder?.isAtEnd() } == true
    }
}

class TestParserOutput: XCTestCase {
    func testItCanMapItsResultValue() {
        expect { try Parse.whitespace().map({ $0.count }).parse(" A") } == 1
    }
}
