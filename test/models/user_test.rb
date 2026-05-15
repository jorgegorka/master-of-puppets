require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "has_secure_password sets digest" do
    u = User.create!(email: "a@b.com", password: "supersecret123")
    assert u.authenticate("supersecret123")
    refute u.authenticate("wrong")
  end

  test "email is required and unique" do
    User.create!(email: "dup@b.com", password: "supersecret123")
    dup = User.new(email: "dup@b.com", password: "supersecret123")
    refute dup.save
    assert_includes dup.errors[:email], "has already been taken"
  end
end
