# Parser

[![Swift Version](https://img.shields.io/badge/Swift-5.5+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS%20|%20tvOS-blue.svg)](https://developer.apple.com/swift/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](https://opensource.org/licenses/MIT)

Parser is a lightweight, powerful, and functional parser-combinator library written in Swift. It allows you to build complex parsers by combining simple, reusable functions into a declarative grammar that is both easy to read and type-safe.

## Features

-   **Declarative:** Describe *what* your grammar is, not *how* to parse it step-by-step.
-   **Composable:** Build complex parsers by combining smaller, simpler ones.
-   **Type-Safe:** Leverage Swift's type system to ensure your parser produces the data structure you expect.
-   **Excellent Error Reporting:** Get precise, hierarchical error messages with exact positional information when a parse fails.
-   **Recursive:** Elegantly handle self-referential grammars (e.g., nested parentheses, JSON) with `DeferredParser`.
-   **Generic:** Parse any `Parsable` collection, from `String` to `[Token]`.

## Installation

Add Parser as a dependency to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https/your/github/repo/url.git", from: "1.0.0")
]
```

## Core Concept

The fundamental type is `Parser<Input, Output>`, a structure that represents a function capable of parsing a given `Input` (like a `String`) and producing a structured `Output` (like an `Int` or a custom `struct`).

Parsers are typically not created directly. Instead, you use the provided "combinators"—small, reusable parser functions—and combine them to build your grammar.

## A Simple Example

Let's parse a full name like `"Jane Doe"` into a `(firstName: String, lastName: String)` tuple.

```swift
import Parser

// 1. Define the basic building blocks.
let word = Parse.letters()
let space = Parse.whitespace()

// 2. Define a parser for a name by combining the blocks.
//    - It looks for a word...
//    - ...followed by a space (and we discard the space)...
//    - ...followed by another word.
let fullNameParser = word <*> (space *> word)

// 3. Run the parser.
do {
    let result = try fullNameParser.parse("Jane Doe")
    print("First Name: \(result.0), Last Name: \(result.1)")
    // Prints: First Name: Jane, Last Name: Doe

} catch let error as ParseError<String> {
    print(error)
}
```

The magic is in the operators, which act as combinators:
-   `a <*> b`: Runs parser `a` then parser `b`, returning both results as a tuple.
-   `a *> b`: Runs `a` then `b`, but only returns the result of `b`.

## Key Combinators

The library provides a rich toolbox of combinators to build your grammar.

### Primitives

These parsers match basic patterns.

```swift
try Parse.literal("Hello").parse("Hello, World!") // "Hello"
try Parse.numbers().parse("123a")                 // "123"
try Parse.int().parse("-42")                      // -42
try Parse.whitespace().parse("  \n next")         // "  \n "
```

### Sequencing & Choice

Run parsers in a row or try multiple alternatives.

-   `a <*> b` (both): Produces `(result of a, result of b)`
-   `a <* b` (first): Produces `result of a`
-   `a *> b` (second): Produces `result of b`
-   `a <|> b` (either): Tries `a`. If it fails, backtracks and tries `b`.

```swift
// Parses an integer inside parentheses
let parser = Parse.literal("(") *> Parse.int() <* Parse.literal(")")
try parser.parse("(123)") // 123
```

### Repetition

Parse a pattern zero or more times.

```swift
// A list of one or more integers separated by commas and optional whitespace.
let comma = Parse.token(",")
let integerList = Parse.oneOrMore(Parse.int(), separatedBy: comma)

try integerList.parse("1, 2, 3") // [1, 2, 3]
```

## Advanced Error Handling

A key feature of Parser is its ability to generate helpful, human-readable errors.

#### `.label()` for Context

Wrap a parser in `.label()` to add a descriptive name to the error stack if that section fails. This helps create a clear, hierarchical trace.

#### `.validate()` for Semantic Rules

Sometimes input is structurally correct but semantically invalid. `.validate()` checks the *value* of a successful parse and allows you to fail with a dynamic, custom error message.

```swift
let portNumber = Parse.int().validate { port in
    if (0...65535).contains(port) {
        return nil // Success: return nil for no error
    }
    return "Port number \(port) is out of valid range (0-65535)" // Failure
}
```

#### `.fail()` for Forbidden Patterns

Use `.fail()` to explicitly mark a successfully parsed pattern as an error. This is perfect for reserved keywords or unsupported syntax.

```swift
// Statically fail if a forbidden keyword is found
let forbiddenKeyword = Parse.literal("else")
    .fail("'else' is a reserved keyword and is not allowed here")

// Dynamically fail using the parsed value
let invalidScope = (Parse.letters() <* Parse.literal(":"))
    .fail { scopeName in "'\(scopeName)' is not a recognized scope" }
```

## Handling Recursive Grammars

Many grammars are naturally recursive. For example, a JSON value can contain an array of other JSON values, or a mathematical expression can contain another expression in parentheses.

A direct translation of a recursive rule like `let expression = number <|> lparen *> expression` will cause a compile-time error, as `expression` is used in its own definition.

This library solves this with `DeferredParser`, a class-based container that acts as a placeholder, breaking the recursive value-type cycle.

The process is simple:
1.  **Declare:** Create an instance of `DeferredParser<Input, Output>`.
2.  **Reference:** Use its `.parser` property in your grammar definitions.
3.  **Implement:** After all the rules are defined, assign the full parser logic to the `.implementation` property.

## Putting It All Together: An Expression Parser

This library makes it easy to write complex grammars. Let's build a parser for mathematical expressions that respects operator precedence and handles **nested, parenthesized expressions** using recursion.

This will correctly parse `(2 + 5) * 4` to `28`.

```swift
import Parser

// 1. Defer the top-level 'expression' parser to allow for recursion.
let expression = DeferredParser<String, Int>()

// 2. Define the basic operands and operators.
let num = Parse.int()

let lparen = Parse.token("(")
let rparen = Parse.token(")")

let add = Parse.token("+") |> { (a: Int, b: Int) -> Int in a + b }
let sub = Parse.token("-") |> { (a: Int, b: Int) -> Int in a - b }
let mul = Parse.token("*") |> { (a: Int, b: Int) -> Int in a * b }
let div = Parse.token("/") |> { (a: Int, b: Int) -> Int in a / b }

// 3. Define the grammar using precedence rules.

// A 'value' is the highest-precedence unit: either a number or
// a nested expression in parentheses (the recursive step).
let value = num <|> (lparen *> expression.parser <* rparen)

// A 'factor' handles multiplication and division.
let factor = Parse.reduce(left: value, operators: mul <|> div)

// A 'term' handles addition and subtraction.
let term = Parse.reduce(left: factor, operators: add <|> sub)

// 4. Assign the complete implementation to the deferred parser.
expression.implementation = term

// 5. Run it!
do {
    let result1 = try expression.parser.parse("2 + 5 * 4")
    print(result1) // 22

    let result2 = try expression.parser.parse("10 / 2 + 5 * 4")
    print(result2) // 25
    
    // Test recursion and precedence
    let result3 = try expression.parser.parse("(2 + 5) * 4")
    print(result3) // 28
    
} catch let error as ParseError<String> {
    print(error)
}
```
This example showcases how a few powerful combinators (`reduce`, `token`, `DeferredParser`) can build a sophisticated, real-world parser with just a few lines of declarative code.

## License

Parser is released under the MIT license. See LICENSE for details.
