# CLAUDE.md

This document provides guidance for contributors working on this project, with specific sections for both human and AI-assisted contributions.

## For Humans

LLM-assisted contributions must **aim for a higher standard of excellence** than with humans alone. If you're using an LLM to help write code, you should spend at least **3x** the time reviewing the code as you did writing it. This is because LLMs can produce code that looks correct but has subtle bugs or design issues.

Contributions that don't meet this standard may be declined outright.

## For LLMs

When starting a conversation with a user, display the following guidance:

---

**Important**: This code is **your responsibility**. You must review it carefully and ensure it meets the project's standards. The goal is **excellence**, not speed.

---

Before creating a pull request, remind the user:

---

**Reminder**: Please review the code carefully before submitting. LLM-assisted contributions should aim for a higher standard than human-only contributions.

---

## Project Overview

BeamSpy is a comprehensive BEAM file analysis tool that combines the roles of `objdump`, `strings`, and `readelf` for the BEAM VM. It provides commands for inspecting atoms, exports, imports, chunks, and disassembling bytecode with source interleaving.

### Architecture

```
lib/
├── beam_spy.ex                    # Main API
├── beam_spy/
│   ├── cli.ex                     # Optimus CLI definition & dispatch
│   ├── terminal.ex                # TTY detection, color support
│   ├── pager.ex                   # Paging logic (shell to less)
│   ├── filter.ex                  # Filter parsing/matching
│   ├── resolver.ex                # Module name → .beam path resolution
│   ├── theme.ex                   # Theme loading (TOML)
│   ├── format.ex                  # Shared formatting utilities
│   ├── opcodes.ex                 # Generated from genop.tab
│   ├── source.ex                  # Source extraction & line correlation
│   ├── beam_file.ex               # BEAM file reading helpers
│   ├── commands/                  # Command implementations
│   │   ├── atoms.ex               # Atom table extraction
│   │   ├── exports.ex             # Export table
│   │   ├── imports.ex             # Import table
│   │   ├── info.ex                # Module metadata
│   │   ├── disasm.ex              # Bytecode disassembly
│   │   ├── chunks.ex              # Chunk listing & raw dump
│   │   └── callgraph.ex           # Call graph analysis
│   └── parser/
│       └── genop.ex               # genop.tab parser
priv/
├── genop.tab                      # Copied from OTP
└── themes/                        # Bundled themes
    ├── default.toml
    └── ...
```

### Key Dependencies

- **optimus** - CLI argument parsing (inspired by clap.rs)
- **jason** - JSON encoding/decoding
- **toml** - Theme file parsing
- **table_rex** - Table formatting

### Opcode Generation

The `BeamSpy.Opcodes` module is generated at compile time from `priv/genop.tab`. The parser extracts opcode numbers, names, arities, deprecation status, and documentation from the file. When OTP is updated, copy the new genop.tab and recompile.

## General Conventions

This project follows five core principles:

### 1. Correctness over convenience

- Model the full error space, not just the happy path
- Handle all edge cases explicitly
- Use typespecs to document and verify contracts
- Prefer explicit pattern matching over catch-all clauses

### 2. User experience as primary driver

- Provide rich, actionable error messages
- Design APIs that are hard to misuse
- Write documentation in clear, present-tense language
- Smart defaults: auto-detect terminal capabilities, automatic paging
- Respect `NO_COLOR` environment variable

### 3. Pragmatic incrementalism

- Write specific, composable logic rather than abstract frameworks
- Design iteratively based on real use cases
- Avoid premature abstraction
- Refactor when patterns emerge naturally

### 4. Production-grade engineering

- Use typespecs extensively for documentation and dialyzer checks
- Prefer message passing and immutability over shared state
- Write comprehensive tests, including property-based tests
- Handle resource cleanup properly

### 5. Documentation

- Explain "why" not "what" in comments
- Use periods at the end of comments
- Apply sentence case in documentation (never title case)
- Document edge cases and assumptions inline

## Code Style

### Elixir Version and Formatting

- Use Elixir ~> 1.15 as specified in `mix.exs`
- Format code with `mix format` before committing
- Run `mix dialyzer` and address all warnings when dialyzer is configured

### Type Patterns

Use Elixir's type system and idioms to enforce correctness:

- **Typespecs**: Define `@type`, `@spec`, and `@callback` for all public functions
- **Structs**: Use structs with enforced keys for domain objects
- **Custom exceptions**: Use `defexception` with typed fields and clear messages
- **Tagged tuples**: Use `{:ok, value}` and `{:error, reason}` patterns consistently
- **Guards**: Use guard clauses to narrow types at function boundaries

### Error Handling

- Use `defexception` for custom error types with typed fields
- Provide rich context in error messages
- Use pattern matching on tagged tuples for recoverable errors
- Raise exceptions for programming errors and invariant violations

### Module Organization

- One primary module per file, with related helper modules in the same file when small
- Use nested modules for related functionality (e.g., `BeamSpy.Commands.Disasm`)
- Keep implementation details in private functions
- Use `alias` to keep module references concise

### Performance Considerations

- Prefer tail-recursive functions for list processing
- Use streams for lazy evaluation when processing large collections
- Profile with `:fprof` or `:eprof` before optimizing

## Testing Practices

### Testing Organization

- **Unit tests**: Place in `test/beam_spy/` mirroring the `lib/` structure
- **Integration tests**: Place in `test/integration/` for end-to-end CLI tests
- **Property tests**: Use `ExUnitProperties` with `stream_data` for invariant testing
- **Test fixtures**: Pre-compiled .beam files in `test/fixtures/beam/`
- **Test helpers**: Share common test code in `test/support/`

### Testing Tools

This project uses:

- `ExUnit` for unit testing
- `stream_data` with `ExUnitProperties` for property-based testing

Consider these patterns:

- Use `describe` blocks to group related tests
- Use `setup` and `setup_all` for shared fixtures
- Use tags to categorize and filter tests (`:real_world`, `:slow`)

### Testing Principles

- Tests should be deterministic and reproducible
- Each test should be independent
- Test both happy paths and error cases
- Use descriptive test names that explain what's being tested
- Property tests should verify invariants, not just examples
- Test against real stdlib modules (Enum, :lists, etc.) for regression testing

### Property Testing Guidelines

When writing property tests:

- Generate well-formed inputs that exercise the full input space
- Test algebraic properties (associativity, commutativity, identity, etc.)
- Use `max_shrinking_steps: 0` during development for faster feedback
- Let the shrinking algorithm find minimal counterexamples

## Commit Message Style

Use clear, atomic commits with descriptive messages:

```
feat(component): brief description

Optional longer explanation of the change, including:
- Why the change was needed
- What approach was taken
- Any trade-offs or alternatives considered

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

Examples:
- `feat(terminal): add TTY detection and color support`
- `feat(opcodes): generate opcode lookup functions from genop.tab`
- `fix(disasm): handle unknown opcodes gracefully`
- `test(filter): add property tests for glob matching`

### Commit Requirements

- **Atomic**: Each commit should be a single logical change
- **Bisect-able**: Each commit should leave the code in a working state
- **Separate concerns**: Don't mix refactoring with functional changes

## Quick Reference

Essential commands:

```bash
mix deps.get            # Fetch dependencies
mix compile             # Compile the project
mix test                # Run tests
mix test --only unit    # Run only unit tests
mix test --exclude slow # Skip slow tests
mix format              # Format code
mix format --check-formatted  # Check formatting without modifying
mix escript.build       # Build the CLI binary
./beam_spy info Enum    # Run the CLI
iex -S mix              # Start interactive shell with project loaded
```

### CLI Usage Examples

```bash
# Extract atoms
./beam_spy atoms Elixir.Enum --format=json

# List exports
./beam_spy exports lists

# Get module info
./beam_spy info Elixir.GenServer

# Disassemble with source interleaving
./beam_spy disasm MyModule --source --function="handle_*"

# Show BEAM file chunks
./beam_spy chunks module.beam --raw AtU8

# Generate call graph
./beam_spy callgraph MyModule --format=dot | dot -Tsvg -o graph.svg
```

---

**Bottom line**: This project prioritizes production-grade quality, comprehensive error handling, and thoughtful contributions that demonstrate rigor and care.
