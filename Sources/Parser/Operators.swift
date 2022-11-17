//
//  Operators.swift
//  Parser
//
//  Created by Mark Onyschuk on 2017-03-12.
//  Copyright © 2017 Mark Onyschuk. All rights reserved.
//

import Foundation

precedencegroup ParserLowPrecedence {
    associativity: left
}

precedencegroup ParserMidPrecedence {
    associativity: left
    higherThan: ParserLowPrecedence
}

precedencegroup ParserHighPrecedence {
    associativity: left
    higherThan: ParserMidPrecedence
}

infix operator  |> : ParserLowPrecedence    // Parser.map

infix operator  ?> : ParserLowPrecedence    // Parse.failure

infix operator <*  : ParserHighPrecedence    // Parse.first
infix operator  *> : ParserHighPrecedence    // Parse.second
infix operator <*> : ParserHighPrecedence    // Parse.both

infix operator <|> : ParserMidPrecedence    // Parser.either


/// Returns a new parser which maps the product of `lhs` through `rhs`.
///
/// Equivalent to `lhs.map(rhs)`

public func |><I, O, P>(lhs: Parser<I, O>, rhs: @escaping (O) throws -> P) -> Parser<I, P> {
    return lhs.map(rhs)
}

/// Returns a new parser which maps the product of `lhs` to the value produced by `rhs`.
///
/// Equivalent to `lhs.producing(rhs)`

public func |><I, O, P>(lhs: Parser<I, O>, rhs: P) -> Parser<I, P> {
    return lhs.producing(rhs)
}

/// Returns a new parser which produces the product of `lhs`, or throws.
///
/// - parameter rhs: a function returning an error to be thrown

public func ?><I, O>(lhs: Parser<I, O>, rhs: @escaping (ParserInput<I>) -> Error) -> Parser<I, O> {
    return Parser { input in
        do    { return try lhs.body(input) }
        catch { throw rhs(input) }
    }
}

/// Returns a new parser which produces the product of `lhs` if
/// `rhs` produces.
///
/// Equivalent to `Parse.first(of: lhs, and: rhs)`

public func <*<I, O, P>(lhs: Parser<I, P>, rhs: Parser<I, O>) -> Parser<I, P> {
    return Parse.first(of: lhs, and: rhs)
}

/// Returns a new parser which produces the product of `rhs` if
/// `lhs` produces.
///
/// Equivalent to `Parse.second(of: lhs, and: rhs)`

public func *><I, O, P>(lhs: Parser<I, O>, rhs: Parser<I, P>) -> Parser<I, P> {
    return Parse.second(of: lhs, and: rhs)
}

/// Returhs a new parser which produces the product of both `lhs'
/// and `rhs` as a tuple
///
/// Equivalent to `Parse.both(lhs, and: rhs)`

public func<*><I, O, P>(lhs: Parser<I, O>, rhs: Parser<I, P>) -> Parser<I, (O, P)> {
    return Parse.both(lhs, and: rhs)
}

/// Returns a new parser which produces the product of either `lhs`
/// or `rhs`
///
/// Equivalent to `Parse.either(lhs, or: rhs)`

public func <|><I, O>(lhs: Parser<I, O>, rhs: Parser<I, O>) -> Parser<I, O> {
    return Parse.either(lhs, or: rhs)
}

/// Returns a parser which either parses `lhs` or throws `rhs`
///
/// Equivalent to `Parser.either(lhs, or: Parse.error(rhs))`

public func ?><I, O, E>(lhs: Parser<I, O>, rhs: E) -> Parser<I, O> where E: Error {
    return lhs <|> Parse.error(rhs)
}
