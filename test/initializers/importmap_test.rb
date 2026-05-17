require "test_helper"

# Phase 5 H5: lock the contract that every CDN-hosted ESM pin carries an
# explicit Subresource Integrity hash. If a future pin is added to a remote
# host without `integrity:`, this test fails — forcing the author to either
# compute a sha384 or justify the omission.
class ImportmapIntegrityTest < ActiveSupport::TestCase
  CDN_PINS = %w[chart.js @kurkle/color].freeze

  test "external CDN pins carry an integrity hash" do
    packages = Rails.application.importmap.packages

    CDN_PINS.each do |name|
      package = packages[name]
      assert package, "expected #{name} to be pinned in config/importmap.rb"
      assert package.integrity.is_a?(String),
             "expected literal integrity string on #{name}, got #{package.integrity.inspect}"
      assert package.integrity.start_with?("sha384-"),
             "expected sha384 integrity on #{name}, got #{package.integrity.inspect}"
    end
  end

  test "CSP allowlists ga.jspm.io for script-src only" do
    policy = Rails.application.config.content_security_policy

    assert_includes policy.script_src, "https://ga.jspm.io",
                    "ga.jspm.io must be in script-src so chart.js can load"
    assert_not_includes Array(policy.connect_src), "https://ga.jspm.io",
                        "ga.jspm.io must NOT be in connect-src (static ESM uses script-src)"
  end
end
