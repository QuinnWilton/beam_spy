# Changelog

All notable changes to this project are documented in this file.

## 0.2.0 — 2026-09-11

### Added

- `BeamSpy.Operand`, `BeamSpy.Instruction`, `BeamSpy.BeamType`: a typed
  operand model for disassembly (registers, labels, literals, call
  targets, typed registers, alloc lists, map pairs, with `{:raw, _}` as a
  loud last resort), instruction normalization of the `test`/`bif`/
  `gc_bif` container forms to real genop names, and the OTP 25+ Type
  chunk decoded through the compiler's own `beam_types`. Each
  disassembled function now carries `typed_instructions`; the string
  rendering moved verbatim to `BeamSpy.Render` and is byte-identical.
- `BeamSpy.DebugInfo`: reads OTP 28's `DbgB` chunk (emitted by the
  `beam_debug_info` compiler option) — per `debug_line`, the frame size
  and every live source variable with the register it occupies or the
  constant it folded to. `by_line/1` keys entries by source line via the
  Line chunk. The static equivalent of `code:get_debug_info/1`.
- `BeamSpy.literals/1` (the `LitT` pool as `{index, term}` pairs) and
  `BeamSpy.docs/1` (the EEP-48 `Docs` chunk, normalized).
- `BeamFile.load/1` accepts raw beam data (IFF or gzip) and paths with
  any extension; every reader goes through it.
- `docs/beam-isa.md`: a reference for the BEAM instruction set, register
  and memory models, encoding, transformation rules, and JIT/interpreter
  differences.

### Fixed

- `Source.parse_line_table/1` decodes the Line chunk correctly: references
  are 1-based (0 is "no location") and file-switch items are not line
  entries. Previously reference 0 resolved to a fabricated line, the last
  reference of every module was missing, and modules with a leading file
  switch were shifted by one. An oracle test pins the table against the
  compiler's own `:to_asm` line markers.
- No more `Burrito.Util.Args.get_arguments/0 is undefined` warning in
  downstream compiles; a non-Burrito release falls back to the supervisor.
- `BeamFile.read_chunks/2` handles `:beam_lib`'s `{:invalid_chunk, _, _}`
  instead of raising `CaseClauseError`.

### Dependencies

- Requires `ctf ~> 0.1.1` for the untagged-unsigned length decoding that
  real `beam_asm` output uses in `DbgB` operands.

## 0.1.0

Initial release.
