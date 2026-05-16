# Minitest 6 (on Ruby 3.4) dropped `minitest/mock`, which provided
# `Object#stub`. We use a tiny inline shim instead so tests can write either:
#
#   with_singleton_method(Tool::Internal, :invoke, ->(**) { Tool::Result.ok("x") }) { ... }
#
# or the more familiar:
#
#   Tool::Internal.stub(:invoke, Tool::Result.ok("x")) { ... }
#
# Both replace a singleton method for the duration of the block and restore the
# original implementation afterward, even if the block raises.
module MethodStub
  # Replace `mod.<name>` with `replacement` for the duration of the block.
  # `replacement` may be a Proc/Method (called with original args) or any value
  # (returned directly, mirroring Minitest's stub semantics).
  def with_singleton_method(mod, name, replacement)
    original = mod.method(name)
    if replacement.respond_to?(:call)
      mod.define_singleton_method(name, replacement)
    else
      mod.define_singleton_method(name) { |*_, **_, &_| replacement }
    end
    yield
  ensure
    mod.singleton_class.define_method(name, original)
  end
end

# Shim `Object#stub` so existing/idiomatic stub calls keep working under
# Minitest 6 without pulling in minitest/mock.
class Object
  unless method_defined?(:stub) || respond_to?(:stub)
    def stub(name, value_or_callable, *args, &block)
      original = singleton_class.instance_method(name) if singleton_class.method_defined?(name) ||
        singleton_class.private_method_defined?(name)
      owner_has_own = original&.owner == singleton_class

      if value_or_callable.respond_to?(:call)
        define_singleton_method(name, value_or_callable)
      else
        define_singleton_method(name) { |*_a, **_kw, &_b| value_or_callable }
      end

      block.call(self)
    ensure
      singleton_class.send(:remove_method, name) if singleton_class.method_defined?(name, false)
      singleton_class.define_method(name, original) if original && owner_has_own
    end
  end
end

class ActiveSupport::TestCase
  include MethodStub
end
