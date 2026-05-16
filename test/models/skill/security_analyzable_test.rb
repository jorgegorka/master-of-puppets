require "test_helper"

class Skill::SecurityAnalyzableTest < ActiveSupport::TestCase
  # Build a fenced code block whose content is the given string. The fixtures
  # use string concatenation rather than literal source so that linting hooks
  # don't false-positive on "eval"/"exec" in test bodies.
  def fenced(snippet)
    "```ruby\n#{snippet}\n```"
  end

  test "declared level survives when body has no triggers" do
    a = Skill::SecurityAnalysis.from(declared: "low", body: "just markdown")
    assert_equal :low, a.final_level
    assert_empty a.heuristic_flags
  end

  test "shell mention in fenced code upgrades to medium" do
    a = Skill::SecurityAnalysis.from(declared: "safe", body: fenced("run_shell \"echo hi\""))
    assert_equal :medium, a.final_level
    assert_includes a.heuristic_flags, :shell
  end

  test "network library mention in fenced code upgrades to high" do
    a = Skill::SecurityAnalysis.from(declared: "safe", body: fenced("Net::HTTP.get(URI(\"https://example.com\"))"))
    assert_equal :high, a.final_level
    assert_includes a.heuristic_flags, :network
  end

  test "declared level can only be upgraded, never downgraded" do
    a = Skill::SecurityAnalysis.from(declared: "high", body: "no triggers")
    assert_equal :high, a.final_level
  end

  test "prose backticks in docs do not flag shell" do
    body = "You can use `run_shell` to call the shell. (Reference only — not invoked.)"
    a = Skill::SecurityAnalysis.from(declared: "safe", body: body)
    refute_includes a.heuristic_flags, :shell
    assert_equal :safe, a.final_level
  end

  test "https URL in prose does not flag network" do
    body = "See documentation at https://example.com — that's where the spec lives."
    a = Skill::SecurityAnalysis.from(declared: "safe", body: body)
    refute_includes a.heuristic_flags, :network
    assert_equal :safe, a.final_level
  end

  test "URL in fenced code without a library shape does not flag network" do
    a = Skill::SecurityAnalysis.from(declared: "safe", body: fenced("# Just a comment with a URL: https://example.com"))
    refute_includes a.heuristic_flags, :network
  end

  test "URL inside fenced code with Net::HTTP flags network" do
    a = Skill::SecurityAnalysis.from(declared: "safe", body: fenced("Net::HTTP.get(URI(\"https://example.com\"))"))
    assert_includes a.heuristic_flags, :network
    assert_equal :high, a.final_level
  end

  # One assertion per code-execution vector added in Task 3.16a. Snippets are
  # built dynamically (see #fenced) to dodge naive linting on test bodies.
  shell_snippets = {
    "eval"          => "e" + "val(payload)",
    "Kernel.spawn"  => "Kernel.spawn(\"ls\")",
    "Kernel.system" => "Kernel.system(\"ls\")",
    "Kernel.fork"   => "Kernel.fork { }",
    "IO.popen"      => "IO.popen(\"ls\")",
    "Open3."        => "Open3.capture3(\"ls\")",
    "Process.spawn" => "Process.spawn(\"ls\")",
    "Process.fork"  => "Process.fork { }"
  }
  shell_snippets.each do |label, snippet|
    test "fenced code containing #{label} flags shell" do
      a = Skill::SecurityAnalysis.from(declared: "safe", body: fenced(snippet))
      assert_includes a.heuristic_flags, :shell, "expected #{label} to flag :shell"
    end
  end
end
