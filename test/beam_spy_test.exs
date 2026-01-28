defmodule BeamSpyTest do
  use ExUnit.Case

  describe "version/0" do
    test "returns version string" do
      assert is_binary(BeamSpy.version())
      assert BeamSpy.version() =~ ~r/^\d+\.\d+\.\d+/
    end
  end
end
