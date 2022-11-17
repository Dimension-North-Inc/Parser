//
//  Parser.swift
//  Parser
//
//  Created by Mark Onyschuk on 2017-03-10.
//  Copyright © 2017 Mark Onyschuk. All rights reserved.
//

import Foundation

/// A parser which consumes `Input` and produces `Output`

public struct Parser<Input, Output> where Input: Parsable {
    /// `Element`s of `Input`
    
    public typealias Element = Input.Element
    
    let body: (ParserInput<Input>)throws -> ParserOutput<Output, ParserInput<Input>>
    
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
    
    
    /// Applies the parser to `input`, producing parsed output, or throwing if the parser fails to match
    /// - Parameter input: input to be parsed
    
    public func parse(_ input: Input) throws -> Output {
        return try body(ParserInput(input: input)).value
    }
}

public struct ParserError<Input, Underlying>: Error where Input: Parsable, Underlying: Error {
    public let error: Underlying
    public let input: ParserInput<Input>
}

public enum ParseError: Error {
    case overflow
    case unmatched
}

extension ParserError: Equatable where Input: Equatable, Underlying: Equatable {
}



extension Parser {

    /// Returns a new parser which throws the custom error `error` on failure
    /// - Parameter error: an `Error` to throw
    /// - Returns: a new parser
    
    public func throwing<E>(error err: E) -> Parser<Input, Output> where E: Error {
        return Parser<Input, Output> {
            do {
                return try body($0)
            }
            catch let error as ParserError<Input, E> {
                throw error
            }
            catch {
                throw ParserError<Input, E>(error: err, input: $0)
            }
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
        return input[position] == value
            ? ParserOutput(value: input[position], remainder: self.advanced(by: 1))
            : nil
    }
    
    public func first(_ matching: (Input.Element) -> Bool) -> ParserOutput<Input.Element, Self>? {
        return matching(input[position])
            ? ParserOutput(value: input[position], remainder: self.advanced(by: 1))
            : nil
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
