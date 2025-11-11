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
        let body: (ParserInput<String>) throws -> ParserOutput<String, ParserInput<String>> = {
             if let output = $0.take(while: { $0.isWhitespace }) {
                 return output
             } else {
                 throw ParseError(position: $0)
             }
         }
         let _ = Parser(body: body)
    }

    let whitespaceParser = Parser<String, String> {
        if let output = $0.take(while: { $0.isWhitespace }) {
            return output
        } else {
            throw ParseError(position: $0)
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
    
    func testItProducesHierarchicalErrorsOnFailure() {
        // A number is a sequence of digits.
        let number = Parse.numbers().label("number")

        // An argument list is a list of numbers separated by commas.
        let argList = Parse.list(of: number, separatedBy: Parse.literal(","))
            .label("argument list")

        // The full expression is an argument list between parentheses.
        let expression = argList
            .between(Parse.literal("("), Parse.literal(")"))
            .label("parenthesized expression")
        
        // Test a failure deep inside the parser structure
        let input = "(1,2,foo,4)"
        do {
            _ = try expression.parse(input)
            XCTFail("Parser should have thrown an error but did not.")
        } catch let error as ParseError<String> {
            // The top-level error should be our highest label
            expect { error.contextStack.first } == "parenthesized expression"
            
            // Traverse the cause chain to find the specific failure
            let cause1 = error.cause?.value
            expect { cause1?.contextStack.first } == "argument list"
            
            let cause2 = cause1?.cause?.value
            expect { cause2?.contextStack.first } == "number"

            // The position should be at the deepest point of failure
            expect { error.position.description } == "(1,2,^foo,4)"

        } catch {
            XCTFail("Caught an unexpected error type: \(error)")
        }
        
        // Test a failure at a higher level (e.g., missing closing parenthesis)
        let input2 = "(1,2,3"
        do {
            _ = try expression.parse(input2)
            XCTFail("Parser should have thrown an error but did not.")
        } catch let error as ParseError<String> {
            // The top-level error is from our highest label
            expect { error.contextStack.first } == "parenthesized expression"
            
            // The cause is the specific failure from the literal parser
            let cause = error.cause?.value
            expect { cause?.contextStack.first } == "')'"
            
            // The position of the error is at the end of the input
            expect { error.position.description } == "(1,2,3^"
            
        } catch {
            XCTFail("Caught an unexpected error type: \(error)")
        }
    }
    
    func testItCanTurnASuccessIntoAStaticFailure() {
        // Define a parser that matches a forbidden pattern.
        let forbiddenParser: Parser<String, String> = Parse.literal("forbidden")
            .fail("'forbidden' is a reserved keyword")
        
        do {
            _ = try forbiddenParser.parse("forbidden")
            XCTFail("Parser should have failed but did not.")
        } catch let error as ParseError<String> {
            expect { error.contextStack.first } == "'forbidden' is a reserved keyword"
            expect { error.position.description } == "^forbidden"
        } catch {
            XCTFail("Caught an unexpected error type: \(error)")
        }
        
        // The parser should still fail normally on non-matching input
        expect { try forbiddenParser.parse("allowed") }.to(throwAny())
    }
    
    func testItCanTurnASuccessIntoADynamicFailure() {
        // Define a parser that captures a word.
        let wordParser: Parser<String, String> = Parse.letters()
            .fail { word in "'\(word)' is not a valid command" }
        
        do {
            _ = try wordParser.parse("invalid")
            XCTFail("Parser should have failed but did not.")
        } catch let error as ParseError<String> {
            // Check that the parsed value was used in the error.
            expect { error.contextStack.first } == "'invalid' is not a valid command"
            expect { error.position.description } == "^invalid"
        } catch {
            XCTFail("Caught an unexpected error type: \(error)")
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
