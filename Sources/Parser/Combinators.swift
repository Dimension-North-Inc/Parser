//
//  Parse.swift
//  Parser
//
//  Created by Mark Onyschuk on 2017-03-10.
//  Copyright © 2017 Mark Onyschuk. All rights reserved.
//

import Foundation

/// An enumeration of parser combinators

public enum Parse {
    
    /// Returns a parser which  matches the end of  input, given an input type.

    public static func eof<I>() -> Parser<I, Void> {
        return Parser {
            if $0.isAtEnd() {
                return ParserOutput(value: (), remainder: $0)
            } else {
                throw ParseError.unmatched
            }
        }
    }
    
    /// Returns a parser which never matches and always throws `throwing`
    /// - Parameter throwing: an error to throw
    
    public static func error<I, O, E>(_ throwing: E) -> Parser<I, O> where E: Error {
        return Parser {
            _ in
            throw throwing
        }
    }
    
    /// Returns a parser which always matches but does not consume input.

    public static func nothing<I>() -> Parser<I, Void> {
        return Parser {
            return ParserOutput(value: (), remainder: $0)
        }
    }
    
    /// Returns a parser which always matches and returns the  parsed value `value`
    
    public static func just<I, O>(_ value: O) -> Parser<I, O> {
        return Parser {
            return ParserOutput(value: value, remainder: $0)
        }
    }
    
    public static func first<I>(_ matching: I.Element) -> Parser<I, I.Element> {
        return Parser {
            if let output = $0.first(matching) {
                return output
            } else {
                throw ParseError.unmatched
            }
        }
    }
    
    public static func first<I>(_ matching: @escaping (I.Element) -> Bool) -> Parser<I, I.Element> {
        return Parser {
            if let output = $0.first(matching) {
                return output
            } else {
                throw ParseError.unmatched
            }
        }
    }
    
    /// Returns a parser which produces a `matching` prefix on match
    /// - Parameter matching: a prefix to match
    
    public static func prefix<I>(_ matching: I) -> Parser<I, I> {
        return Parser {
            if let output = $0.take(matching) {
                return output
            } else {
                throw ParseError.unmatched
            }
        }
    }
        
    /// Returns a parser which produces the prefix of input while `condition` is met.
    /// - Parameter condition: a condition used to continue consuming prefix input

    public static func prefix<I>(while condition: @escaping (I.Element)->Bool) -> Parser<I, I> {
        return Parser {
            if let output = $0.take(while: condition) {
                return output
            } else {
                throw ParseError.unmatched
            }
        }
    }
    
    /// Returns a parser which produces the prefix of input until `condition` is met.
    /// - Parameter condition: a condition used to stop consuming prefix input

    public static func prefix<I>(until condition: @escaping (I.Element)->Bool) -> Parser<I, I> {
        return Parser {
            if let output = $0.take(until: condition) {
                return output
            } else {
                throw ParseError.unmatched
            }
        }
    }

    
    /// Returns a parser which produces the prefix of input up to `matching`, or the balance of input if `matching` is not found.
    /// - Parameter matching: an input to match
    public static func prefix<I>(until matching: Parser<I, I>) -> Parser<I, I> {
        return Parser {
            input in
            var start = input
            
            while !start.isAtEnd() {
                if let _ = try? matching.body(start) {
                    return input.take(upto: start.position)
                } else {
                    start = start.advanced(by: 1)
                }
            }
            
            throw ParseError.unmatched
        }
    }
    
    /// Returns a parser which produces string containing whitespace including spaces, tabs, and newlines on match
    
    public static func whitespace() -> Parser<String, String> {
        return prefix(while: { $0.isWhitespace })
    }

    /// Returns a parser which produces string containing letters, excluding digits, whitespace, or punctuation  on match

    public static func letters() -> Parser<String, String> {
        return prefix(while: { $0.isLetter })
    }
    
    /// Returns a parser which produces string containing whole numbers on match

    public static func numbers() -> Parser<String, String> {
        return prefix(while: { $0.isWholeNumber })
    }
    
    /// Returns  a parser which produces a prefix containing only characters in`matching`
    /// - Parameter matching: ranges of characters to match
    public static func characters(in matching: ClosedRange<Character>...) -> Parser<String, String> {
        return Parser {
            func anyMatch(_ character: Character) -> Bool {
                return matching.contains(where: { $0.contains(character) })
            }
            
            if let output = $0.take(while: anyMatch), output.value.count > 0 {
                return output
            } else {
                throw ParseError.unmatched
            }
        }
    }
    
    /// Returns a parser which produces an `Int64` on match.
    /// - Parameter signed: `true` if an associated sign should be matched

    public static func int64(signed: Bool = true) -> Parser<String, Int64> {
        func sign() -> Parser<String, Int64> {
            let pos = literal("+") |>  Int64(1)
            let neg = literal("-") |> Int64(-1)
            
            return pos <|> neg
        }
        func natural() -> Parser<String, Int64> {
            return numbers() |> {
                if let value = Int64($0) {
                    return value
                } else {
                    throw ParseError.overflow
                }
            }
        }

        return signed
            ? sign().orElse(1) <*> natural() |> { $0 * $1 }
            : natural()
    }

    /// Returns a parser which produces an `Int` on match.
    /// - Parameter signed: `true` if an associated sign should be matched

    public static func int(signed: Bool = true) -> Parser<String, Int> {
        return int64(signed: signed) |> { Int($0) }
    }

    
    /// Returns a parser which produces a positive `Int` on match.
    /// - Parameter radix: radix eg. base 2, 8, 10, 16
    /// - Parameter length: number of digits required to match
    /// - Returns: an integer
    public static func int(radix: Int, length: Int? = nil) -> Parser<String, Int> {
        var remainingCharacters = length ?? Int.max
        
        return prefix(while: { defer { remainingCharacters -= 1 }; return Int(String($0), radix: radix) != nil && remainingCharacters > 0 }) |> {
            guard let value = Int($0, radix: radix) else {
                throw ParseError.overflow
            }
            if let length = length, $0.count != length {
                throw ParseError.unmatched
            }
            return value
        }
    }
    
    
    /// Returns a parser which produces a positive `Int` on matching hex characters.
    /// - Returns: an integer
    public static func hex() -> Parser<String, Int> {
        return int(radix: 16)
    }
    
    /// Returns a parser which produces a floating point number string  on match.
    /// - Parameter decimalSeparator: the desired decimal separator

    public static func floating(decimalSeparator: String = ".") -> Parser<String, String> {
        let sign     = (literal("+") <|> literal("-")).orElse("")

        // required
        let whole    = sign <*> numbers() |> { $0 + $1 }

        let partial  = (literal(decimalSeparator) <*> numbers() |> { $0 + $1 }).orElse("")
        let exponent = (literal("e", caseInsensitive: true) <*> whole |> { $0 + $1 }).orElse("")
        
        return each(sign, whole, partial, exponent).map { $0.joined() }
    }
    
    /// Returns a parser which produces a `Decimal` on match.
    /// - Parameter decimalSeparator: the desired decimal separator

    public static func decimal(decimalSeparator: String = ".") -> Parser<String, Decimal> {
        return floating(decimalSeparator: decimalSeparator) |> {
            if let value = Decimal(string: $0) {
                return value
            } else {
                throw ParseError.unmatched
            }
        }
    }

    /// Returns a parser which produces a `Double` on match.
    /// - Parameter decimalSeparator: the desired decimal separator

     public static func double(decimalSeparator: String = ".") -> Parser<String, Double> {
        let exp: Parser<String, Double> = literal("e", caseInsensitive: true) *> int() |> {
            return pow(10, Double($0))
        }

        let frac: Parser<String, Double> = literal(decimalSeparator) *> numbers() |> {
            if let value = Double(decimalSeparator + $0) {
                return value
            } else {
                throw ParseError.overflow
            }
        }

        return (int64() <*> frac.orElse(0.0)) <*> exp.orElse(1.0) |> {
            ((Double($0.0.signum()) * Double($0.0.magnitude)) + $0.1) * $1
        }
    }
    
    /// Returns a parser which produces a `Float` on match.
    /// - Parameter decimalSeparator: the desired decimal separator

    public static func float(decimalSeparator: String = ".") -> Parser<String, Float> {
        return double(decimalSeparator: decimalSeparator) |> { Float($0) }
    }

#if (arch(x86_64) || arch(i386))
    /// Returns a parser which produces a `Float80` on match.
    /// - Parameter decimalSeparator: the desired decimal separator

    public static func float80(decimalSeparator: String = ".") -> Parser<String, Float80> {
        return double(decimalSeparator: decimalSeparator) |> { Float80($0) }
    }
#endif
    
    /// Returns a parser which produces the token`name`, including optional whitespace prefix and suffix, on match.
    /// - Parameters:
    ///   - name: a literal string to match
    ///   - caseInsensitive: `true` if the match should be case insensitive

    public static func token(_ name: String, caseInsensitive: Bool = false) -> Parser<String, String> {
        return Parser {
            if let output = $0.take(name, caseInsensitive: caseInsensitive) {
                return output
            } else {
                throw ParseError.unmatched
            }
        }.between(whitespace().optional())
    }
        
    /// Returns a parser which produces the literal string`name`, without optional whitespace prefix and suffix, on match.
    /// - Parameters:
    ///   - name: a literal string to match
    ///   - caseInsensitive: `true` if the match should be case insensitive
    
    public static func literal(_ name: String, caseInsensitive: Bool = false) -> Parser<String, String> {
        return Parser {
            if let output = $0.take(name, caseInsensitive: caseInsensitive) {
                return output
            } else {
                throw ParseError.unmatched
            }
        }
    }

    /// Returns a parser matching a quoted string whose quotes are parsed using `quote` and whose quote escape is parsed using `escape`.
    ///
    /// This parser  matches and **includes** both exterior quotes and interior escapes in its output.
    /// - Parameters:
    ///   - quote: a quote mark parser
    ///   - escape: an escape mark parser

    public static func quoted(quote: Parser<String, String>, escape: Parser<String, String>) -> Parser<String, String> {
        let qq = quote
        let eq = escape <*> quote |> { $0.0 + $0.1 }
        let ee = escape <*> escape |> { $0.0 + $0.1 }
        
        let escapedQuote  = prefix(until: eq) <*> eq |> { $0.0 + $0.1 }
        let escapedEscape = prefix(until: ee) <*> ee |> { $0.0 + $0.1 }
        let endQuote      = prefix(until: qq) <*> qq |> { $0.0 + $0.1 }
 
        return each(quote, zeroOrMore(escapedQuote <|> escapedEscape) |> { $0.joined() }, endQuote) |> { $0.joined() }
    }
    
    /// Returns a parser matching a quoted string whose quotes are parsed using `quote` and whose quote escape is parsed using `escape`.
    ///
    /// This parser matches, but **excludes** both exterior quotes and interior escapes in its output.
    ///
    /// - Note:
    /// This function can be used to strip exterior quote marks and interior escape marks from values previously parsed via `Parse.quoted(quote:escape:)`
    ///
    /// - Parameters:
    ///   - quote: a quote mark parser
    ///   - escape: an escape mark parser

    public static func unquoted(quote: Parser<String, String>, escape: Parser<String, String>) -> Parser<String, String> {
        let qq = quote |> ""
        let eq = escape *> quote
        let ee = escape *> escape
        
        let escapedQuote  = prefix(until: eq) <*> eq |> { $0.0 + $0.1 }
        let escapedEscape = prefix(until: ee) <*> ee |> { $0.0 + $0.1 }
        let endQuote      = prefix(until: qq) <*> qq |> { $0.0 + $0.1 }
        
        return each(quote |> "", zeroOrMore(escapedQuote <|> escapedEscape) |> { $0.joined() }, endQuote) |> { $0.joined() }
    }

    /// Returns a parser matching either `first` or `second`, producing the output of either
    /// - parameter first: a parser producing `O`
    /// - parameter second: a parser producing `O`
    
    public static func either<I, O>(_ first: Parser<I, O>, or second: Parser<I, O>) -> Parser<I, O> {
        return Parser {
            do    { return try first.body($0)  }
            catch { return try second.body($0) }
        }
    }

    /// Returns a parser matching both `first` and `second`, producing the output of both
    /// - parameter first: a parser producing `O`
    /// - parameter second: a parser producing `P`
    
    public static func both<I, O, P>(_ first: Parser<I, O>, and second: Parser<I, P>) -> Parser<I, (O, P)> {
        return Parser {
            let firstOutput = try first.body($0)
            let secondOutput = try second.body(firstOutput.remainder)

            return secondOutput.map { (firstOutput.value, $0) }
        }
    }
    
    /// Returns a parser matching both `first` and `second`, producing the output of the first
    /// - parameter first: a parser producing `O`
    /// - parameter second: a parser producing `P`
    
    public static func first<I, O, P>(of first: Parser<I, P>, and second: Parser<I, O>) -> Parser<I, P> {
        return Parser {
            let firstOutput = try first.body($0)
            let secondOutput = try second.body(firstOutput.remainder)

            return secondOutput.map { _ in firstOutput.value }
        }
    }

    /// Returns a parser matching both `first` and `second`, producing the output of the second
    /// - parameter first: a parser producing `O`
    /// - parameter second: a parser producing `P`
    
    public static func second<I, O, P>(of first: Parser<I, O>, and second: Parser<I, P>) -> Parser<I, P> {
        return Parser {
            let firstOutput = try first.body($0)
            let secondOutput = try second.body(firstOutput.remainder)

            return secondOutput
        }
    }
    
    /// Returns a parser which parses zero or one `parser`
    /// - Parameters:
    ///   - parser: an item parser

    public static func zeroOrOne<I, O>(_ parser: Parser<I, O>) -> Parser<I, O?> {
        return Parser {
            do {
                let output = try parser.body($0)
                return ParserOutput(value: output.value, remainder: output.remainder)
            }
            catch {
                return ParserOutput(value: nil, remainder: $0)
            }
        }
    }

    /// Returns a parser which parses one or more `parser`
    /// - Parameters:
    ///   - parser: an item parser

    public static func oneOrMore<I, O>(_ parser: Parser<I, O>) -> Parser<I, [O]> {
        return list(of: parser, separatedBy: nothing(), count: 1...Int.max)
    }

    /// Returns a parser which parses zero or more `parser`
    /// - Parameters:
    ///   - parser: an item parser

    public static func zeroOrMore<I, O>(_ parser: Parser<I, O>) -> Parser<I, [O]> {
        return list(of: parser, separatedBy: nothing(), count: 0...Int.max)
    }
    
    /// Returns a parser which parses one or more `parser`, separated by `separator`
    /// - Parameters:
    ///   - parser: an item parser
    ///   - separator: a separator parser

    public static func oneOrMore<I, O, P>(_ parser: Parser<I, O>, separatedBy separator: Parser<I, P>) -> Parser<I, [O]> {
        return list(of: parser, separatedBy: separator, count: 1...Int.max)
    }
    
    /// Returns a parser which parses zero or more `parser`, separated by `separator`
    /// - Parameters:
    ///   - parser: an item parser
    ///   - separator: a separator parser
    
    public static func zeroOrMore<I, O, P>(_ parser: Parser<I, O>, separatedBy separator: Parser<I, P>) -> Parser<I, [O]> {
        return list(of: parser, separatedBy: separator, count: 0...Int.max)
    }

    /// Returns a parser which reduces a list of `elements`, separated by `operators`, using the functions associated each operator.
    /// This function is used to declare production rules like addition, subtraction, multiplication or division, which is evaluated from left to right
    /// - parameter elements: a parser producing elements
    /// - parameter operators: a parser producing operators

    public static func reduce<I, O>(left elements: Parser<I, O>, operators: Parser<I, (O, O) -> O>) -> Parser<I, O> {
        return lists(of: elements, separatedBy: operators, count: 1...Int.max) |> {
            (values, ops) in
            
            var value = values[0]
            for (next, op) in zip(values.dropFirst(), ops) {
                value = op(value, next)
            }
            
            return value
        }
    }

    /// Returns a parser which reduces a list of `elements`, separated by `operators`, using the functions associated each operator.
    /// This function is used to declare production rules like raising values to some power, which is evaluated from right to left.
    /// - parameter elements: a parser producing elements
    /// - parameter operators: a parser producing operators

    public static func reduce<I, O>(right elements: Parser<I, O>, operators: Parser<I, (O, O) -> O>) -> Parser<I, O> {
        return lists(of: elements, separatedBy: operators, count: 1...Int.max) |> {
            (values, ops) in
            var value = values.last!
            for (next, op) in zip(values.reversed().dropFirst(), ops.reversed()) {
                value = op(value, next)
            }
            
            return value
        }
    }

    /// Returns a parser which reduces a list of `elements`, separated by `operators`, using the function `combine`.
    /// This function is used to declare production rules like raising values to some power, which is evaluated from left to right
    /// - parameter elements: a parser producing elements
    /// - parameter operators: a parser producing operators
    /// - parameter combine: a function of  element output producing a new  element output value

    public static func reduce<I, O, P>(left elements: Parser<I, O>, operators: Parser<I, P>, combine: @escaping (O, P, O) -> O) -> Parser<I, O> {
        return lists(of: elements, separatedBy: operators, count: 1...Int.max) |> {
            (values, ops) in

            var value = values[0]
            for (next, op) in zip(values.dropFirst(), ops) {
                value = combine(value, op, next)
            }
            
            return value
        }
    }
    
    /// Returns a parser which reduces a list of `elements`, separated by `operators`, using the function `combine`.
    /// This function is used to declare production rules like raising values to some power, which is evaluated from right to left.
    /// - parameter elements: a parser producing elements
    /// - parameter operators: a parser producing operators
    /// - parameter combine: a function of  element output producing a new  element output value
    
    public static func reduce<I, O, P>(right elements: Parser<I, O>, operators: Parser<I, P>, combine: @escaping (O, P, O) -> O) -> Parser<I, O> {
        return lists(of: elements, separatedBy: operators, count: 1...Int.max) |> {
            (values, ops) in

            var value = values.last!
            for (next, op) in zip(values.reversed().dropFirst(), ops.reversed()) {
                value = combine(value, op, next)
            }
            
            return value
        }
    }
    
    /// Returns a parser which applies all `parsers` and returns an array of results
    /// - Parameter parsers: a list of parsers

    public static func each<I, O>(_ parsers: Parser<I, O>...) -> Parser<I, [O]> {
        return Parser {
            var elements  = [O]()
            var remainder = $0
            
            for parser in parsers {
                let output = try parser.body(remainder)
                elements.append(output.value)
                remainder = output.remainder
            }
            
            return ParserOutput(value: elements, remainder: remainder)
        }
    }
    
    /// Returns a parser which matches the first of any of the passed parsers
    /// - Parameter parsers: a list of parsers

    public static func any<I, O>(_ parsers: Parser<I, O>...) -> Parser<I, O> {
        return Parser {
            for parser in parsers {
                if let output = try? parser.body($0) {
                    return ParserOutput(value: output.value, remainder: output.remainder)
                }
            }
            
            throw ParseError.unmatched
        }
    }

    public static func list<I, O, P>(of parser: Parser<I, O>, separatedBy separator: Parser<I, P>, count: ClosedRange<Int> = 1...Int.max) -> Parser<I, [O]> {
        return lists(of: parser, separatedBy: separator, count: count) |> { $0.0 }
    }
    
    public static func lists<I, O, P>(of parser: Parser<I, O>, separatedBy separator: Parser<I, P>, count: ClosedRange<Int>) -> Parser<I, ([O], [P])> {
        return Parser {
            var elements   = [O]()
            var separators = [P]()
            var remainder  = $0

            var err: Error?

            if !remainder.isAtEnd() {
                if let first = trying({ try parser.body(remainder) }, err: &err) {
                    elements.append(first.value)
                    remainder = first.remainder

                    while elements.count < count.upperBound {
                        guard let alt = trying({ try separator.body(remainder) }, err: &err) else { break }
                        guard let next = trying({ try parser.body(alt.remainder) }, err: &err) else { break }
                        
                        elements.append(next.value)
                        separators.append(alt.value)
                        
                        remainder = next.remainder
                    }
                }
            }

            if count.contains(elements.count) {
                return ParserOutput(value: (elements, separators), remainder: remainder)
            } else {
                throw err ?? ParseError.unmatched
            }
        }
    }

    private static func trying<T>(_ fn: @escaping () throws -> T, err: inout Error?) -> T? {
        do {
            return try fn()
        }
        catch {
            err = error
            return nil
        }
    }

    public static func lists<I, O, P>(of parser: Parser<I, O>, separatedBy separator: Parser<I, P>, prefix: Parser<I,Void> = Parse.nothing(), suffix: Parser<I,Void> = Parse.nothing(), count: ClosedRange<Int>) -> Parser<I, ([O], [P])> {
        return Parser {
            var elements   = [O]()
            var separators = [P]()
            var remainder  = $0

 
            var err: Error?

            var matchedSuffix = false
            
            if let match = trying({ try prefix.body(remainder) }, err: &err) {
                remainder = match.remainder
            } else {
                throw err ?? ParseError.unmatched
            }

            let valueWithSuffix = parser <* suffix
            let valueWithSeparator = parser <*> separator

            while !remainder.isAtEnd() && !matchedSuffix && elements.count < count.upperBound {
                if let match = trying({ try valueWithSeparator.body(remainder) }, err: &err) {
                    remainder = match.remainder
                    
                    elements.append(match.value.0)
                    separators.append(match.value.1)
                    
                } else if let match = trying({ try valueWithSuffix.body(remainder) }, err: &err) {
                    remainder = match.remainder
                    
                    elements.append(match.value)
                    
                    matchedSuffix = true
                    
                } else {
                    break
                }
            }
            
            if !matchedSuffix {
                if let match = trying({ try suffix.body(remainder) }, err: &err) {
                    remainder = match.remainder
                } else {
                    throw err ?? ParseError.unmatched
                }
            }
            
            if count.contains(elements.count) {
                return ParserOutput(value: (elements, separators), remainder: remainder)
            } else {
                throw err ?? ParseError.unmatched
            }
        }
    }
}

extension Parser {
    
    /// Shorthand for `Parse.zeroOrOne(self)`
    
    public func optional() -> Parser<Input, Output?> {
        return Parse.zeroOrOne(self)
    }
    
    
    /// Returns a parser which produces the receiver's match on success, or `value` on failure.
    /// - Parameter value: a value to produce if the receiver fails to match
    
    public func orElse(_ value: Output) -> Parser<Input, Output> {
        return Parse.zeroOrOne(self) |> { $0 ?? value }
    }

    /// Returns a parser that produces the receiver's match when surrounded by `trim`
    ///
    /// ````
    /// let ws = Parse.whitespace().optional()
    /// let plus = Parse.string("+").between(ws)
    /// ````
    public func between<P>(_ trim: Parser<Input, P>) -> Parser<Input, Output> {
        return Parse.first(of: Parse.second(of: trim, and: self), and: trim)
    }
    
    /// Returns a parser that produces the receiver's match when surrounded by `prefix` and `suffix`
    ///
    /// ````
    /// let obrack = Parse.literal("[")
    /// let cbrack = Parse.literal("]")
    /// let num    = Parse.int()
    /// let comma  = Parse.literal(",")
    /// let numList = Parse.list(of: num, separator: comma).between(obrack, cbrack)
    /// ````
    
    public func between<P, Q>(_ prefix: Parser<Input, P>, _ suffix: Parser<Input, Q>) -> Parser<Input, Output> {
        return Parse.first(of: Parse.second(of: prefix, and: self), and: suffix)
    }
}
