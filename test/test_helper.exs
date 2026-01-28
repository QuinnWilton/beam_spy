# Disable colors in tests for consistent output
System.put_env("NO_COLOR", "1")

# Compile support files
Code.compile_file("test/support/beam_builder.ex")
Code.compile_file("test/support/test_helpers.ex")

# Build test fixtures if needed
BeamSpy.Test.Helpers.ensure_fixtures()

ExUnit.start()
