//
//  Combinators.swift
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
        Parser {
            guard $0.isAtEnd() else {
                throw ParseError(position: $0, contextStack: ["end of input"])
            }
            return ParserOutput(value: (), remainder: $0)
        }
    }

    /// Returns a parser which never matches and always throws `throwing`
    /// - Parameter throwing: an error to throw

    public static func error<I, O, E>(_ throwing: E) -> Parser<I, O> where E: Error {
        Parser {
            input in
            throw throwing
        }
    }

    /// Returns a parser which always matches but does not consume input.

    public static func nothing<I>() -> Parser<I, Void> {
        Parser {
            ParserOutput(value: (), remainder: $0)
        }
    }

    /// Returns a parser which always matches and returns the  parsed value `value`

    public static func just<I, O>(_ value: O) -> Parser<I, O> {
        Parser {
            ParserOutput(value: value, remainder: $0)
        }
    }

    public static func first<I>(_ matching: I.Element) -> Parser<I, I.Element> {
        Parser {
            guard let output = $0.first(matching) else {
                throw ParseError(position: $0)
            }
            return output
        }
    }

    public static func first<I>(_ matching: @escaping (I.Element) -> Bool) -> Parser<I, I.Element> {
        Parser {
            guard let output = $0.first(matching) else {
                throw ParseError(position: $0)
            }
            return output
        }
    }

    /// Returns a parser which produces a `matching` prefix on match
    /// - Parameter matching: a prefix to match

    public static func prefix<I>(_ matching: I) -> Parser<I, I> {
        Parser {
            guard let output = $0.take(matching) else {
                throw ParseError(position: $0)
            }
            return output
        }
    }

    /// Returns a parser which produces the prefix of input while `condition` is met.
    /// - Parameter condition: a condition used to continue consuming prefix input

    public static func prefix<I>(while condition: @escaping (I.Element) -> Bool) -> Parser<I, I> {
        Parser {
            guard let output = $0.take(while: condition) else {
                throw ParseError(position: $0)
            }
            return output
        }
    }

    /// Returns a parser which produces the prefix of input until `condition` is met.
    /// - Parameter condition: a condition used to stop consuming prefix input

    public static func prefix<I>(until condition: @escaping (I.Element) -> Bool) -> Parser<I, I> {
        Parser {
            guard let output = $0.take(until: condition) else {
                throw ParseError(position: $0)
            }
            return output
        }
    }

    /// Returns a parser which produces the prefix of input up to `matching`, or the balance of input if `matching` is not found.
    /// - Parameter matching: an input to match
    public static func prefix<I>(until matching: Parser<I, I>) -> Parser<I, I> {
        Parser {
            input in
            var start = input

            while !start.isAtEnd() {
                // Use a non-throwing body check to avoid catching our rich errors
                if (try? matching.body(start)) != nil {
                    return input.take(upto: start.position)
                } else {
                    start = start.advanced(by: 1)
                }
            }

            throw ParseError(position: input)
        }
    }

    /// Returns a parser which produces string containing whitespace including spaces, tabs, and newlines on match

    public static func whitespace() -> Parser<String, String> {
        prefix(while: { $0.isWhitespace })
    }

    /// Returns a parser which produces string containing letters, excluding digits, whitespace, or punctuation  on match

    public static func letters() -> Parser<String, String> {
        prefix(while: { $0.isLetter })
    }

    /// Returns a parser which produces string containing whole numbers on match

    public static func numbers() -> Parser<String, String> {
        prefix(while: { $0.isWholeNumber })
    }

    /// Returns a parser which produces a prefix containing any characters _not_ in `excluding`
    /// - Parameter excluding: A list of characters or character ranges to exclude.
    public static func characters(excluding: CharacterContainer...) -> Parser<String, String> {
        Parser {
            func isExcluded(_ character: Character) -> Bool {
                excluding.contains { $0.contains(character) }
            }

            guard let output = $0.take(while: { !isExcluded($0) }), output.value.count > 0 else {
                throw ParseError(position: $0)
            }
            return output
        }
    }

    /// Returns a parser which produces an `Int64` on match.
    /// - Parameter signed: `true` if an associated sign should be matched

    public static func int64(signed: Bool = true) -> Parser<String, Int64> {
        func sign() -> Parser<String, Int64> {
            let pos = literal("+") |> Int64(1)
            let neg = literal("-") |> Int64(-1)

            return pos <|> neg
        }
        func natural() -> Parser<String, Int64> {
            numbers() |> {
                if let value = Int64($0) {
                    return value
                } else {
                    fatalError("Integer overflow is not a recoverable parse error")
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
        int64(signed: signed) |> { Int($0) }
    }

    /// Returns a parser which produces a positive `Int` on match.
    /// - Parameter radix: radix eg. base 2, 8, 10, 16
    /// - Parameter length: number of digits required to match
    /// - Returns: an integer
    public static func int(radix: Int, length: Int? = nil) -> Parser<String, Int> {
        var remainingCharacters = length ?? Int.max

        return prefix(while: {
            defer { remainingCharacters -= 1 }
            return Int(String($0), radix: radix) != nil && remainingCharacters > 0
        }) |> {
            text in
            guard let value = Int(text, radix: radix) else {
                fatalError("Integer overflow is not a recoverable parse error")
            }
            if let length = length, text.count != length {
                throw ParseError(position: ParserInput(input: text))  // Not ideal, but hard to get original position
            }
            return value
        }
    }

    /// Returns a parser which produces a positive `Int` on matching hex characters.
    /// - Returns: an integer
    public static func hex() -> Parser<String, Int> {
        int(radix: 16)
    }

    /// Returns a parser which produces a floating point number string  on match.
    /// - Parameter decimalSeparator: the desired decimal separator

    public static func floating(decimalSeparator: String = ".") -> Parser<String, String> {
        let sign = (literal("+") <|> literal("-")).orElse("")

        // required
        let whole = sign <*> numbers() |> { $0 + $1 }

        let partial = (literal(decimalSeparator) <*> numbers() |> { $0 + $1 }).orElse("")
        let exponent = (literal("e", caseInsensitive: true) <*> whole |> { $0 + $1 }).orElse("")

        return each(sign, whole, partial, exponent).map { $0.joined() }
    }

    /// Returns a parser which produces a `Decimal` on match.
    /// - Parameter decimalSeparator: the desired decimal separator

    public static func decimal(decimalSeparator: String = ".") -> Parser<String, Decimal> {
        floating(decimalSeparator: decimalSeparator) |> {
            guard let value = Decimal(string: $0) else {
                throw ParseError(position: ParserInput(input: $0))
            }
            return value
        }
    }

    /// Returns a parser which produces a `Double` on match.
    /// - Parameter decimalSeparator: the desired decimal separator

    public static func double(decimalSeparator: String = ".") -> Parser<String, Double> {
        let exp: Parser<String, Double> =
            literal("e", caseInsensitive: true) *> int() |> {
                pow(10, Double($0))
            }

        let frac: Parser<String, Double> =
            literal(decimalSeparator) *> numbers() |> {
                if let value = Double(decimalSeparator + $0) {
                    return value
                } else {
                    fatalError("Double overflow is not a recoverable parse error")
                }
            }

        return (int64() <*> frac.orElse(0.0)) <*> exp.orElse(1.0) |> {
            ((Double($0.0.signum()) * Double($0.0.magnitude)) + $0.1) * $1
        }
    }

    /// Returns a parser which produces a `Float` on match.
    /// - Parameter decimalSeparator: the desired decimal separator

    public static func float(decimalSeparator: String = ".") -> Parser<String, Float> {
        double(decimalSeparator: decimalSeparator) |> { Float($0) }
    }

    #if (arch(x86_64) || arch(i386))
        /// Returns a parser which produces a `Float80` on match.
        /// - Parameter decimalSeparator: the desired decimal separator

        public static func float80(decimalSeparator: String = ".") -> Parser<String, Float80> {
            double(decimalSeparator: decimalSeparator) |> { Float80($0) }
        }
    #endif

    /// Returns a parser which produces the specific token `name`, consuming any optional surrounding whitespace.
    /// - Parameters:
    ///   - name: A literal string to match.
    ///   - caseInsensitive: `true` if the match should be case insensitive.
    public static func token(_ name: String, caseInsensitive: Bool = false) -> Parser<
        String, String
    > {
        literal(name, caseInsensitive: caseInsensitive)
            .between(whitespace().optional())
    }

    /// Returns a parser that produces a token, which is a sequence of characters terminated by a delimiter.
    /// The parser consumes optional whitespace surrounding the token content. The delimiter itself is not consumed.
    ///
    /// - By default, this is ideal for parsing whitespace-separated words or numbers.
    ///
    /// - Parameter delimiter: A `Parser` that matches the delimiter. Defaults to `Parse.whitespace()`.
    /// - Returns: A parser that produces the matched token string.
    public static func token(delimitedBy delimiter: Parser<String, String> = Parse.whitespace())
        -> Parser<String, String>
    {
        // The content is defined as everything UNTIL the delimiter parser would succeed again.
        let contentParser = Parse.prefix(until: delimiter)

        // A token is then defined as this construct, surrounded by optional whitespace.
        return contentParser.between(Parse.optional(Parse.whitespace()))
    }

    /// Returns a parser which produces the literal string`name`, without optional whitespace prefix and suffix, on match.
    /// - Parameters:
    ///   - name: a literal string to match
    ///   - caseInsensitive: `true` if the match should be case insensitive

    public static func literal(_ name: String, caseInsensitive: Bool = false) -> Parser<
        String, String
    > {
        Parser {
            guard let output = $0.take(name, caseInsensitive: caseInsensitive) else {
                throw ParseError(position: $0, contextStack: ["'\(name)'"])
            }
            return output
        }
    }

    /// Returns a parser matching a quoted string whose quotes are parsed using `quote` and whose quote escape is parsed using `escape`.
    ///
    /// This parser  matches and **includes** both exterior quotes and interior escapes in its output.
    /// - Parameters:
    ///   - quote: a quote mark parser
    ///   - escape: an escape mark parser

    public static func quoted(quote: Parser<String, String>, escape: Parser<String, String>)
        -> Parser<String, String>
    {
        let qq = quote
        let eq = escape <*> quote |> { $0.0 + $0.1 }
        let ee = escape <*> escape |> { $0.0 + $0.1 }

        let escapedQuote = prefix(until: eq) <*> eq |> { $0.0 + $0.1 }
        let escapedEscape = prefix(until: ee) <*> ee |> { $0.0 + $0.1 }
        let endQuote = prefix(until: qq) <*> qq |> { $0.0 + $0.1 }

        return each(quote, zeroOrMore(escapedQuote <|> escapedEscape) |> { $0.joined() }, endQuote)
            |> { $0.joined() }
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

    public static func unquoted(quote: Parser<String, String>, escape: Parser<String, String>)
        -> Parser<String, String>
    {
        let qq = quote |> ""
        let eq = escape *> quote
        let ee = escape *> escape

        let escapedQuote = prefix(until: eq) <*> eq |> { $0.0 + $0.1 }
        let escapedEscape = prefix(until: ee) <*> ee |> { $0.0 + $0.1 }
        let endQuote = prefix(until: qq) <*> qq |> { $0.0 + $0.1 }

        return each(
            quote |> "", zeroOrMore(escapedQuote <|> escapedEscape) |> { $0.joined() }, endQuote)
            |> { $0.joined() }
    }

    /// Returns a parser matching either `first` or `second`, producing the output of either
    /// - parameter first: a parser producing `O`
    /// - parameter second: a parser producing `O`

    public static func either<I, O>(_ first: Parser<I, O>, or second: Parser<I, O>) -> Parser<I, O>
    {
        Parser {
            input in
            do { return try first.body(input) } catch { return try second.body(input) }
        }
    }

    /// Returns a parser matching both `first` and `second`, producing the output of both
    /// - parameter first: a parser producing `O`
    /// - parameter second: a parser producing `P`

    public static func both<I, O, P>(_ first: Parser<I, O>, and second: Parser<I, P>) -> Parser<
        I, (O, P)
    > {
        Parser {
            let firstOutput = try first.body($0)
            let secondOutput = try second.body(firstOutput.remainder)

            return secondOutput.map { (firstOutput.value, $0) }
        }
    }

    /// Returns a parser matching both `first` and `second`, producing the output of the first
    /// - parameter first: a parser producing `O`
    /// - parameter second: a parser producing `P`

    public static func first<I, O, P>(of first: Parser<I, P>, and second: Parser<I, O>) -> Parser<
        I, P
    > {
        Parser {
            let firstOutput = try first.body($0)
            let secondOutput = try second.body(firstOutput.remainder)

            return secondOutput.map { _ in firstOutput.value }
        }
    }

    /// Returns a parser matching both `first` and `second`, producing the output of the second
    /// - parameter first: a parser producing `O`
    /// - parameter second: a parser producing `P`

    public static func second<I, O, P>(of first: Parser<I, O>, and second: Parser<I, P>) -> Parser<
        I, P
    > {
        Parser {
            let firstOutput = try first.body($0)
            let secondOutput = try second.body(firstOutput.remainder)

            return secondOutput
        }
    }

    /// Returns a parser which parses zero or one `parser`
    /// - Parameters:
    ///   - parser: an item parser

    public static func zeroOrOne<I, O>(_ parser: Parser<I, O>) -> Parser<I, O?> {
        Parser {
            do {
                let output = try parser.body($0)
                return ParserOutput(value: output.value, remainder: output.remainder)
            } catch {
                return ParserOutput(value: nil, remainder: $0)
            }
        }
    }

    /// Returns a parser which parses zero or one `parser`.
    /// This is a static combinator version of the `.optional()` instance method, allowing for a more functional composition style.
    /// - Parameters:
    ///   - parser: an item parser
    public static func optional<I, O>(_ parser: Parser<I, O>) -> Parser<I, O?> {
        zeroOrOne(parser)
    }

    /// Returns a parser which parses one or more contiguous instances of `parser`.
    public static func oneOrMore<I, O>(_ parser: Parser<I, O>) -> Parser<I, [O]> {
        list(of: parser, count: 1 ... Int.max)
    }

    /// Returns a parser which parses zero or more contiguous instances of `parser`.
    public static func zeroOrMore<I, O>(_ parser: Parser<I, O>) -> Parser<I, [O]> {
        list(of: parser, count: 0 ... Int.max)
    }

    /// Returns a parser which parses one or more `parser`, separated by `separator`.
    public static func oneOrMore<I, O, P>(
        _ parser: Parser<I, O>, separatedBy separator: Parser<I, P>
    ) -> Parser<I, [O]> {
        list(of: parser, separatedBy: separator, count: 1 ... Int.max)
    }

    /// Returns a parser which parses zero or more `parser`, separated by `separator`.
    public static func zeroOrMore<I, O, P>(
        _ parser: Parser<I, O>, separatedBy separator: Parser<I, P>
    ) -> Parser<I, [O]> {
        list(of: parser, separatedBy: separator, count: 0 ... Int.max)
    }

    /// Returns a parser which reduces a list of `elements`, separated by `operators`, using the functions associated each operator.
    public static func reduce<I, O>(left elements: Parser<I, O>, operators: Parser<I, (O, O) -> O>)
        -> Parser<I, O>
    {
        lists(of: elements, separatedBy: operators, count: 1 ... Int.max) |> {
            (values, ops) in

            var value = values[0]
            for (next, op) in zip(values.dropFirst(), ops) {
                value = op(value, next)
            }

            return value
        }
    }

    /// Returns a parser which reduces a list of `elements`, separated by `operators`, using the functions associated each operator.
    public static func reduce<I, O>(right elements: Parser<I, O>, operators: Parser<I, (O, O) -> O>)
        -> Parser<I, O>
    {
        lists(of: elements, separatedBy: operators, count: 1 ... Int.max) |> {
            (values, ops) in
            var value = values.last!
            for (next, op) in zip(values.reversed().dropFirst(), ops.reversed()) {
                value = op(value, next)
            }

            return value
        }
    }

    /// Returns a parser which reduces a list of `elements`, separated by `operators`, using the function `combine`.
    public static func reduce<I, O, P>(
        left elements: Parser<I, O>, operators: Parser<I, P>, combine: @escaping (O, P, O) -> O
    ) -> Parser<I, O> {
        lists(of: elements, separatedBy: operators, count: 1 ... Int.max) |> {
            (values, ops) in

            var value = values[0]
            for (next, op) in zip(values.dropFirst(), ops) {
                value = combine(value, op, next)
            }

            return value
        }
    }

    /// Returns a parser which reduces a list of `elements`, separated by `operators`, using the function `combine`.
    public static func reduce<I, O, P>(
        right elements: Parser<I, O>, operators: Parser<I, P>, combine: @escaping (O, P, O) -> O
    ) -> Parser<I, O> {
        lists(of: elements, separatedBy: operators, count: 1 ... Int.max) |> {
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
        Parser {
            var elements: [O] = []
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
        Parser {
            input in
            var lastError: Error?
            for parser in parsers {
                do {
                    return try parser.body(input)
                } catch {
                    lastError = error
                }
            }

            throw lastError ?? ParseError(position: input)
        }
    }

    // MARK: - List Overloads

    public static func list<I, O>(of parser: Parser<I, O>, count: ClosedRange<Int> = 1 ... Int.max)
        -> Parser<I, [O]>
    {
        lists(of: parser, count: count) |> { $0.0 }
    }

    public static func list<I, O, P>(
        of parser: Parser<I, O>, separatedBy separator: Parser<I, P>,
        count: ClosedRange<Int> = 1 ... Int.max
    ) -> Parser<I, [O]> {
        lists(of: parser, separatedBy: separator, count: count) |> { $0.0 }
    }

    public static func lists<I, O>(of parser: Parser<I, O>, count: ClosedRange<Int>) -> Parser<
        I, ([O], [Any])
    > {
        Parser { input in
            var elements: [O] = []
            var remainder = input

            while elements.count < count.upperBound {
                guard let output = try? parser.atomic().body(remainder) else { break }
                elements.append(output.value)
                remainder = output.remainder
            }

            if count.contains(elements.count) {
                return ParserOutput(value: (elements, []), remainder: remainder)
            } else {
                _ = try parser.body(remainder)  // Rerun to throw rich error
                fatalError("Should have thrown")
            }
        }
    }

    public static func lists<I, O, P>(
        of parser: Parser<I, O>, separatedBy separator: Parser<I, P>, count: ClosedRange<Int>
    ) -> Parser<I, ([O], [P])> {
        Parser { input in
            var elements: [O] = []
            var separators: [P] = []
            var remainder = input

            // Attempt to parse the first element.
            if let firstOutput = try? parser.atomic().body(remainder) {
                elements.append(firstOutput.value)
                remainder = firstOutput.remainder
            } else {
                if count.contains(0) {
                    return ParserOutput(value: ([], []), remainder: input)
                } else {
                    _ = try parser.body(input)  // Re-run to throw the rich error
                    fatalError("Should have thrown")
                }
            }

            // Loop, parsing `separator` followed by `item`.
            while elements.count < count.upperBound {
                let loopStartRemainder = remainder

                // Try to parse a separator. If this fails, the list ends cleanly.
                guard let separatorOutput = try? separator.atomic().body(loopStartRemainder) else {
                    break
                }

                // If a separator was found, an item MUST follow.
                // A failure here is a true syntax error and the error must be propagated.
                let elementOutput = try parser.body(separatorOutput.remainder)
                separators.append(separatorOutput.value)
                elements.append(elementOutput.value)
                remainder = elementOutput.remainder
            }

            guard count.contains(elements.count) else {
                throw ParseError(
                    position: remainder,
                    contextStack: ["expected at least \(count.lowerBound) items"])
            }
            return ParserOutput(value: (elements, separators), remainder: remainder)
        }
    }

    public static func lists<I, O, P>(
        of parser: Parser<I, O>, separatedBy separator: Parser<I, P>,
        prefix: Parser<I, Void> = Parse.nothing(), suffix: Parser<I, Void> = Parse.nothing(),
        count: ClosedRange<Int>
    ) -> Parser<I, ([O], [P])> {
        let coreList = lists(of: parser, separatedBy: separator, count: count)
        return (prefix *> coreList <* suffix)
    }
}

public protocol CharacterContainer {
    func contains(_ character: Character) -> Bool
}

extension String: CharacterContainer {
    // Conformance is automatic as String already implements contains(_:)
}

extension Character: CharacterContainer {
    public func contains(_ character: Character) -> Bool {
        self == character
    }
}

extension ClosedRange: CharacterContainer where Bound == Character {
    // Conformance is automatic as ClosedRange already implements contains(_:)
}

extension CharacterSet: CharacterContainer {
    public func contains(_ character: Character) -> Bool {
        // A character is in the set if all its unicode scalars are in the set.
        character.unicodeScalars.allSatisfy(self.contains)
    }
}

extension Parse {
    /// Returns  a parser which produces a prefix containing only characters in`matching`
    /// - Parameter matching: ranges of characters to match
    public static func characters(in matching: CharacterContainer...) -> Parser<String, String> {
        Parser {
            func anyMatch(_ character: Character) -> Bool {
                matching.contains { $0.contains(character) }
            }

            guard let output = $0.take(while: anyMatch), output.value.count > 0 else {
                throw ParseError(position: $0)
            }
            return output
        }
    }
}

extension Parser {

    /// Shorthand for `Parse.zeroOrOne(self)`

    public func optional() -> Parser<Input, Output?> {
        Parse.zeroOrOne(self)
    }

    /// Returns a parser which produces the receiver's match on success, or `value` on failure.
    /// - Parameter value: a value to produce if the receiver fails to match

    public func orElse(_ value: Output) -> Parser<Input, Output> {
        Parse.zeroOrOne(self) |> { $0 ?? value }
    }

    /// Returns a parser that produces the receiver's match when surrounded by `trim`
    ///
    /// ````
    /// let ws = Parse.whitespace().optional()
    /// let plus = Parse.string("+").between(ws)
    /// ````
    public func between<P>(_ trim: Parser<Input, P>) -> Parser<Input, Output> {
        Parse.first(of: Parse.second(of: trim, and: self), and: trim)
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

    public func between<P, Q>(_ prefix: Parser<Input, P>, _ suffix: Parser<Input, Q>) -> Parser<
        Input, Output
    > {
        Parse.first(of: Parse.second(of: prefix, and: self), and: suffix)
    }

    /// Returns a new parser that first runs the receiver, and if successful,
    /// applies a validation check to its output. If the `isValid` closure
    /// returns `true`, the parser succeeds with the original output. If the
    /// closure returns `false`, the parser fails with a `ParseError`.
    ///
    /// This is useful for enforcing semantic rules on a structurally valid parse.
    ///
    /// - Parameter isValid: A closure that takes the parser's output and returns `true` if it is valid.
    /// - Returns: A new parser that incorporates the validation logic.
    public func validate(_ isValid: @escaping (Output) -> Bool) -> Parser<Input, Output> {
        Parser { input in
            // First, run the original parser. If this throws, the error propagates naturally.
            let originalOutput = try self.body(input)

            // If the original parser succeeded, apply the validation check to its value.
            guard isValid(originalOutput.value) else {
                // The value is invalid, so force a failure.
                throw ParseError(position: input)
            }
            // The value is valid, so return the original success output.
            return originalOutput
        }
    }
}
