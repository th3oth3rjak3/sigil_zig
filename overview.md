# Sigil Language Summary

## Overview

Sigil is a modern, dynamically-typed programming language with optional static typing, designed for clarity, expressiveness, and performance. It combines familiar and clean syntax with powerful features like first-class functions, classes, unions, and a flexible type system. Sigil compiles to a register-based bytecode executed by a custom virtual machine with automatic memory management.

---

## Core Language Features

### 1. Syntax

- Functions can be defined with either expression or block bodies:

      let add = fn(a, b) => a + b

      fn add(a, b) {
          a + b
      }

- Control structures use clear keywords and blocks:

      if condition {
          // true branch
      } else if otherCondition {
          // else if branch
      } else {
          // else branch
      }

- Looping uses a single `loop` keyword supporting different styles:

      loop { /* infinite */ }
      loop i in 1..=10 { print(i) }
      loop i < 10 { print(i) }

---

### 2. Data Types

- **Numbers:** Single numeric type underlying all numbers (like `f64` floating-point).
- **Strings, Booleans, None:** Built-in primitive types.
- **Classes:** Support instance fields, methods, static methods, and single inheritance.
- **Unions:** First-class union types to express sum types with tagged variants.

---

### 3. Classes and Inheritance

- Classes are declared with optional constructor parameters and a body initializing instance fields.
- Single inheritance is supported with a `:` syntax:

      let Person = class(name, age) : Animal {
          this.name = name
          this.age = age
          super.legCount = 2  // call or assign to base constructor members
          this.sayHi = fn() { ... }
          static let greet = fn(name) => "Hi, " + name
      }

- Methods use the `this` keyword; static methods use `static let`.

---

### 4. Functions

- First-class, can be assigned to variables, passed as arguments, and returned.
- All functions return the last expression’s value by default (no explicit `return` needed).

---

### 5. Type System

- **Optional static typing:** Types can be annotated in a TypeScript-like manner:

      let add = fn(a: Number, b: Number): Number => a + b

- Typechecker validates annotations at compile time; if errors exist, compilation fails.
- Code without annotations is dynamically typed, with runtime type checks.
- Future plans include generics and gradual typing support.

---

### 6. Virtual Machine

- Executes a **register-based bytecode** designed for efficiency and clarity.
- Registers hold **NaN-boxed 64-bit values** enabling compact and fast value representation.
- Instruction set designed for arithmetic, control flow, function calls, and object operations.

---

### 7. Memory Management

- Uses a **mark-and-sweep stop-the-world garbage collector** implemented within the runtime.
- All objects allocated on a managed heap tracked by the GC.
- Roots include stack frames, global variables, and registers.

---

## Development Tools & Build System

- Written primarily in C for portability and low-level control.
- Uses **CMake** for build configuration and compilation.
- Supports VSCode and CLion for development, with integration for IntelliSense and debugging.

---

## Future Directions

- Expand the type system with generics and interfaces.
- Improve the GC with incremental or generational strategies.
- Enhance tooling with a REPL, debugger, and IDE support.
- Possibly add concurrency primitives and async support.

---

*This document will evolve as Sigil progresses.*
