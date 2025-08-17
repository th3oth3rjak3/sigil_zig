# Sigil Language Summary

## Overview

Sigil is a modern, dynamically-typed programming language with optional static typing, designed for clarity, expressiveness, and performance. It combines familiar and clean syntax with powerful features like first-class functions, classes, unions, and a flexible type system. Sigil compiles to a stack-based bytecode executed by a custom virtual machine with automatic memory management.

---

## Core Language Features

### 1. Syntax

- Functions are defined with block bodies:

      fun add(a, b) {
          a + b
      }

- Control structures use clear keywords and blocks:

      if (condition) {
          // true branch
      } else if (otherCondition) {
          // else if branch
      } else {
          // else branch
      }

- Looping is done with the traditional `while` and `for` loop keywords:

      while (true) { /* Infinite */ }
      for (i = 0; i < 10; i = i + 1) {
          // do something 10 times.
      }

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

      class Person {
          fun new(name, age) {
              this.name = name;
              this.age = age;
          }

          fun sayHi() {
              return "Hello, I'm " + this.name + " and I'm " + this.age + " years old!"
          }
      }

      // usage:
      john = Person("John", 25);
      print(john.sayHi());

- Methods use the `fun` keyword.

---

### 4. Functions

- First-class, can be assigned to variables, passed as arguments, and returned.
- Functions return `none` when a return value is not provided. Otherwise, the `return` keyword is used to return a value.

---

### 5. Type System

- **Optional static typing:** Types can be annotated in the following manner:

      fun add(a: Number, b: Number): Number {
          return a + b;
      }

- Typechecker validates annotations at compile time; if errors exist, compilation fails.
- Code without annotations is dynamically typed, with runtime type checks.
- Future plans include generics and gradual typing support.

---

### 6. Virtual Machine

- Executes a **stack-based bytecode** designed for efficiency and clarity.
- Stack holds Value types now, with future plans to move to **NaN-boxed 64-bit values** enabling compact and fast value representation.
- Instruction set designed for arithmetic, control flow, function calls, and object operations.

---

### 7. Memory Management

- Uses a **mark-and-sweep stop-the-world garbage collector** implemented within the runtime.
- All objects allocated on a managed heap tracked by the GC.
- Roots include stack frames, global variables.

---

## Development Tools & Build System

- Written in Zig for portability and low-level control.

---

## Future Directions

- Expand the type system with generics and interfaces.
- Improve the GC with incremental or generational strategies.
- Enhance tooling with a REPL, debugger, and IDE support.
- Possibly add concurrency primitives and async support.

---

*This document will evolve as Sigil progresses.*
