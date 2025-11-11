//
//  Parser.swift
//  Parser
//
//  Created by Mark Onyschuk on 2017-03-10.
//  Copyright © 2017 Mark Onyschuk. All rights reserved.
//

import Foundation

/// A simple box type to allow for recursive value types like ParseError.
public final class Box<T> {
    public let value: T
    public init(_ value: T) {
        self.value = value
    }
}

/// A rich, structured error type that provides detailed information about a parsing failure.
public struct ParseError<Input: Parsable>: Error {
    /// The exact position in the input stream where the error occurred.
    public let position: ParserInput<Input>
    
    /// A stack of context labels, showing the chain of parsers that were active when the failure occurred.
    public let contextStack: [String]
    
    /// The underlying, more specific cause of this error, if any.
    public let cause: Box<ParseError<Input>>?

    public init(position: ParserInput<Input>, contextStack: [String] = [], cause: ParseError<Input>? = nil) {
        self.position = position
        self.contextStack = contextStack
        self.cause = cause.map { Box($0) }
    }
}

extension ParseError: CustomStringConvertible where Input.SubSequence: CustomStringConvertible {
    public var description: String {
        var lines: [String] = []
        var currentError: ParseError<Input>? = self
        var indentation = ""

        while let error = currentError {
            if !error.contextStack.isEmpty {
                lines.append("\(indentation)- Expected: \(error.contextStack.joined(separator: " -> "))")
            }
            
            // Only show position for the deepest, most specific error.
            if error.cause == nil {
                lines.append("\(indentation)  at position:")
                lines.append("\(indentation)  > \(error.position.description)")
            }
            
            indentation += "  "
            currentError = error.cause?.value
        }
        
        return "Parse failed:\n" + lines.joined(separator: "\n")
    }
}


/// A parser which consumes `Input` and produces `Output`
public struct Parser<Input, Output> where Input: Parsable {
    /// `Element`s of `Input`
    
    public typealias Element = Input.Element
    
    public let body: (ParserInput<Input>)throws -> ParserOutput<Output, ParserInput<Input>>
    
    /// Initializes a new parser with a `body` that takes `ParserInput` and produces `ParserOutput`, or throws.
    /// - Parameter body: a function that consumes a `ParserInput` and produces a `ParserOutput` or throws
    
    public init(body: @escaping (ParserInput<Input>)throws -> ParserOutput<Output, ParserInput<Input>>) {
        self.body = body
    }
    
    
    /// Returns a new parser which maps the receiver's output using the function `transform`
    /// - Parameter transform: an `Output` transformation function
    
    public func map<U>(_ transform: @escaping(Output)throws -> U) -> Parser<Input, U> {
        return Parser<Input, U> {
            return try self.body($0).map(transform)
        }
    }

    /// Returns a new parser which produces `value` in place of the receiver's output
    /// - Parameter value: a value to produce in place of the receiver's output
    
    public func producing<U>(_ value: U) -> Parser<Input, U> {
        return map { _ in value }
    }
    
    /// Returns a new parser that chains the receiver's output into a new parser.
    /// This is the fundamental combinator for creating context-sensitive parsers,
    /// where the result of one parse determines the next parse to be run.
    ///
    /// - Parameter transform: A function that takes the output of the receiver
    ///   and returns a new parser to be run on the remaining input.
    public func flatMap<U>(_ transform: @escaping (Output) -> Parser<Input, U>) -> Parser<Input, U> {
        return Parser<Input, U> { input in
            // 1. Run the original parser (self).
            let originalOutput = try self.body(input)
            
            // 2. If it succeeds, take its value...
            let value = originalOutput.value
            
            // 3. ...and pass it to the transform function to get the *next* parser.
            let nextParser = transform(value)
            
            // 4. Run the next parser on the remaining input.
            return try nextParser.body(originalOutput.remainder)
        }
    }
    
    /// Applies the parser to `input`, producing parsed output, or throwing if the parser fails to match
    /// - Parameter input: input to be parsed
    
    public func parse(_ input: Input) throws -> Output {
        return try body(ParserInput(input: input)).value
    }
}

extension Parser {
    /// Returns a new parser that attaches a context label to any errors thrown by the receiver.
    /// When an error is thrown, it is wrapped in a new `ParseError` that includes the given label.
    /// This is the primary mechanism for building a descriptive, hierarchical error report.
    ///
    // - Parameter name: The context label to attach to this parser.
    /// - Returns: A new parser with labeling behavior.
    public func label(_ name: String) -> Parser<Input, Output> {
        return Parser { input in
            do {
                return try self.body(input)
            } catch let error as ParseError<Input> {
                // This is an error we already know how to handle. Wrap it.
                throw ParseError(
                    position: error.position,
                    contextStack: [name],
                    cause: error
                )
            } catch {
                // This is a generic, non-parse error. Create a new root ParseError.
                throw ParseError(
                    position: input,
                    contextStack: [name]
                )
            }
        }
    }

    /// Returns a new parser that behaves like the receiver, but any error it throws
    /// is converted into a simple, non-hierarchical error at the starting position.
    /// This is crucial for controlling backtracking in `either` or list combinators,
    /// preventing a partial match from generating a deep error that kills the entire parse.
    public func atomic() -> Parser<Input, Output> {
        return Parser { input in
            do {
                return try self.body(input)
            } catch {
                // Discard the detailed error and throw a simple one at the start.
                throw ParseError(position: input)
            }
        }
    }
    
    /// Returns a new parser that first runs the receiver, and if successful,
    /// applies a semantic validation check to its output.
    ///
    /// The `check` closure is given the parsed output and should return `nil`
    /// on success, or a `String` containing a custom error message on failure.
    /// This allows for creating rich, context-aware error messages for
    /// structurally valid but semantically invalid input.
    ///
    /// - Parameter check: A closure that takes the parser's output and returns
    ///   an optional error message.
    /// - Returns: A new parser that incorporates the validation logic.
    public func validate(_ check: @escaping (Output) -> String?) -> Parser<Input, Output> {
        Parser { input in
            // First, run the original parser. If this throws, it propagates naturally.
            let originalOutput = try self.body(input)

            // If the original parser succeeded, apply the validation check to its value.
            if let errorMessage = check(originalOutput.value) {
                // The value is invalid. Throw a new ParseError at the start
                // of the consumed token, using the custom error message.
                throw ParseError(position: input, contextStack: [errorMessage])
            }
            
            // The value is valid, so return the original success output.
            return originalOutput
        }
    }
    
    /// Returns a new parser that, upon a successful parse, immediately fails
    /// with the given static error message. The new parser's output type is
    /// generic and will be inferred by the compiler.
    ///
    /// This is a convenient way to forbid a specific pattern. For example:
    /// `let fullParser = validParser <|> Parse.literal("else").fail("keyword 'else' is not allowed")`
    ///
    /// - Parameter message: The static error message to use for the failure.
    /// - Returns: A new parser that turns a success into a failure of an inferred type.
    public func fail<U>(_ message: String) -> Parser<Input, U> {
        return Parser<Input, U> { input in
            _ = try self.body(input)
            // If the underlying parser succeeded, we must now fail.
            throw ParseError(position: input, contextStack: [message])
        }
    }
    
    /// Returns a new parser that, upon a successful parse, immediately fails
    /// by generating a dynamic error message from the parsed value. The new
    /// parser's output type is generic and will be inferred by the compiler.
    ///
    /// This is the ideal way to forbid a pattern while providing a rich error
    /// message that includes the invalid value.
    ///
    /// - Parameter message: A closure that takes the successful output and
    ///   returns the error message string.
    /// - Returns: A new parser that turns a success into a dynamic failure of an inferred type.
    public func fail<U>(_ message: @escaping (Output) -> String) -> Parser<Input, U> {
        return Parser<Input, U> { input in
            let originalOutput = try self.body(input)
            // If the underlying parser succeeded, we must now fail.
            throw ParseError(position: input, contextStack: [message(originalOutput.value)])
        }
    }
}

public struct ParserInput<Input> where Input: Parsable {
    public typealias Element = Input.Element
    
    public let input: Input
    public let position: Input.Index
    
    public init(input: Input) {
        self.input = input
        self.position = input.startIndex
    }

    private init(input: Input, position: Input.Index) {
        self.input = input
        self.position = position
    }
    
    public func advanced(by count: Int) -> Self {
        return ParserInput(input: input, position: input.index(position, offsetBy: count))
    }
    
    private func advanced(to position: Input.Index) -> Self {
        return ParserInput(input: input, position: position)
    }

    public func first(_ value: Input.Element) -> ParserOutput<Input.Element, Self>? {
        guard position < input.endIndex, input[position] == value else { return nil }
        return ParserOutput(value: input[position], remainder: self.advanced(by: 1))
    }
    
    public func first(_ matching: (Input.Element) -> Bool) -> ParserOutput<Input.Element, Self>? {
        guard position < input.endIndex, matching(input[position]) else { return nil }
        return ParserOutput(value: input[position], remainder: self.advanced(by: 1))
    }
    
    public func take(_ prefix: Input) -> ParserOutput<Input, Self>? {
        return input[position...].starts(with: prefix)
            ? ParserOutput(value: prefix, remainder: self.advanced(by: prefix.count))
            : nil
    }
    
    public func take(while condition: (Input.Element) -> Bool) -> ParserOutput<Input, Self>? {
        let prefix = input[position...].prefix(while: condition)
        
        return prefix.count > 0
            ? ParserOutput(value: Input(parsed: prefix), remainder: self.advanced(by: prefix.count))
            : nil
    }

    public func take(until condition: (Input.Element) -> Bool) -> ParserOutput<Input, Self>? {
        let prefix = input[position...].prefix(while: { !condition($0) })
        
        return prefix.count > 0
            ? ParserOutput(value: Input(parsed: prefix), remainder: self.advanced(by: prefix.count))
            : nil
    }

    public func take(upto index: Input.Index) -> ParserOutput<Input, Self> {
        return ParserOutput(value: Input(parsed: input[position..<index]), remainder: self.advanced(to: index))
    }
    
    public func isAtEnd() -> Bool {
        return position == input.endIndex
    }
}

extension ParserInput where Input.Element == Character {
    public func take(_ prefix: Input, caseInsensitive: Bool) -> ParserOutput<Input, Self>? {
        let compare: (Character, Character) -> Bool = caseInsensitive
            ? { c1, c2 in c1.uppercased() == c2.uppercased() }
            : { c1, c2 in c1 == c2 }
        
        return input[position...].starts(with: prefix, by: compare)
            ? ParserOutput(value: Input(parsed: input[position...].prefix(prefix.count)), remainder: self.advanced(by: prefix.count))
            : nil
    }
}

extension ParserInput: CustomStringConvertible where Input.SubSequence: CustomStringConvertible {
    public var description: String {
        return input[..<position].description + "^" + input[position...].description
    }
}

extension ParserInput: Equatable where Input: Equatable {}

public struct ParserOutput<Output, Remainder> {
    public let value: Output
    public let remainder: Remainder
    
    public init(value: Output, remainder: Remainder) {
        self.value = value
        self.remainder = remainder
    }
    
    public func map<U>(_ transform: (Output) throws ->U) rethrows -> ParserOutput<U, Remainder> {
        return ParserOutput<U, Remainder>(value: try transform(value), remainder: remainder)
    }
}

extension ParserOutput: CustomStringConvertible where Output: CustomStringConvertible {
    public var description: String {
        return "(value: \(value), remainder: \(remainder))"
    }
}

extension ParserOutput: Equatable where Output: Equatable, Remainder: Equatable {}

/// A deferred parser declaration. Use this to break cycles when defining production rules
/// for recursive grammars. Set `DeferredParser`'s `implementation` property prior to parsing with the grammar.

public final class DeferredParser<Input, Output> where Input: Parsable {
    
    /// the deferred parser's implementation, assign before use
    
    public var implementation: Parser<Input, Output>? = nil
    
    /// when referring to a deferred parser in production rules, use this property

    public lazy var parser: Parser<Input, Output> = {
        return Parser {
            [unowned self] input in
            if let parser = self.implementation {
                return try parser.body(input)
            } else {
                fatalError("DeferredParser implementation must be set before use")
            }
        }
    }()

    public init() {}
}
