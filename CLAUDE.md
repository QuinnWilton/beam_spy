# CLAUDE.md

This project inherits all shared conventions from the top-level CLAUDE.md.

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

## Project-Specific UX

- Smart defaults: auto-detect terminal capabilities, automatic paging
- Respect `NO_COLOR` environment variable

## Elixir Version

- Use Elixir ~> 1.15 as specified in `mix.exs`

## Testing

### Integration Tests

- Place integration tests in `test/integration/` for end-to-end CLI tests
- Use tags (`:real_world`, `:slow`) to categorize and filter tests
- Test against real stdlib modules (Enum, :lists, etc.) for regression testing

### Test Fixtures

- Pre-compiled .beam files in `test/fixtures/beam/`

## Commit Message Style

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

## Quick Reference

Additional commands beyond those in the root:

```bash
mix test --only unit    # Run only unit tests
mix test --exclude slow # Skip slow tests
mix escript.build       # Build the CLI binary
./beam_spy info Enum    # Run the CLI
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
