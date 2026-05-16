require "test_helper"

class Skill::SecurityAnalyzableTest < ActiveSupport::TestCase
  test "declared level survives when body has no triggers" do
    a = Skill::SecurityAnalysis.from(declared: "low", body: "just markdown")
    assert_equal :low, a.final_level
    assert_empty a.heuristic_flags
  end

  test "shell mention upgrades to medium" do
    a = Skill::SecurityAnalysis.from(declared: "safe", body: "use `run_shell` for tar")
    assert_equal :medium, a.final_level
    assert_includes a.heuristic_flags, :shell
  end

  test "network call upgrades to high" do
    a = Skill::SecurityAnalysis.from(declared: "safe", body: "GET https://example.com")
    assert_equal :high, a.final_level
    assert_includes a.heuristic_flags, :network
  end

  test "declared level can only be upgraded, never downgraded" do
    a = Skill::SecurityAnalysis.from(declared: "high", body: "no triggers")
    assert_equal :high, a.final_level
  end
end
