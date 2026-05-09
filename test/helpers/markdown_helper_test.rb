require "test_helper"

class MarkdownHelperTest < ActionView::TestCase
  setup do
    @project = projects(:acme)
    @ceo = roles(:ceo)
    @cto = roles(:cto)
    Current.project = @project
  end

  teardown do
    Current.reset
  end

  test "markdown_with_mentions returns blank for empty text" do
    assert_equal "", markdown_with_mentions("")
    assert_equal "", markdown_with_mentions(nil)
  end

  test "markdown_with_mentions wraps an @Role mention in a styled link" do
    html = markdown_with_mentions("Hey @#{@cto.title}, check this out.")

    assert_includes html, "class=\"mention\""
    assert_includes html, role_path(@cto)
    assert_includes html, "@CTO"
  end

  test "markdown_with_mentions matches case-insensitively but renders the role's actual title" do
    html = markdown_with_mentions("ping @cto pls")
    assert_includes html, "@CTO"
    assert_includes html, role_path(@cto)
  end

  test "markdown_with_mentions does not link inside fenced code blocks" do
    body = <<~MD
      Use it like this:

      ```
      @#{@cto.title} should not be a link here
      ```
    MD
    html = markdown_with_mentions(body)
    refute_includes html, "<a href=\"#{role_path(@cto)}\""
  end

  test "markdown_with_mentions does not link inside inline code" do
    html = markdown_with_mentions("Avoid using `@#{@cto.title}` directly.")
    refute_includes html, "<a href=\"#{role_path(@cto)}\""
  end

  test "markdown_with_mentions handles multiple mentions in one body" do
    html = markdown_with_mentions("hi @#{@ceo.title} and @#{@cto.title}")
    assert_includes html, role_path(@ceo)
    assert_includes html, role_path(@cto)
  end

  test "markdown_with_mentions leaves unrelated text untouched" do
    html = markdown_with_mentions("Email me at jorge@example.com")
    refute_includes html, "class=\"mention\""
  end

  test "markdown_with_mentions ignores roles outside the project" do
    other_role = roles(:widgets_lead)
    html = markdown_with_mentions("ping @#{other_role.title}")
    refute_includes html, role_path(other_role)
  end

  test "markdown_with_mentions falls back to plain markdown when no current project" do
    Current.project = nil
    html = markdown_with_mentions("hi @#{@cto.title}")
    refute_includes html, "class=\"mention\""
    assert_includes html, "@CTO"
  end

  test "markdown_with_mentions does not resurrect entity-encoded HTML next to a mention" do
    html = markdown_with_mentions("&lt;img src=x onerror=alert(1)&gt; @#{@cto.title}")

    refute_includes html, "<img"
    refute_includes html, %(onerror=")
    assert_includes html, "&lt;img"
    assert_includes html, role_path(@cto)
  end

  test "markdown_with_mentions does not resurrect entity-encoded script tags next to a mention" do
    html = markdown_with_mentions("&lt;script&gt;alert(1)&lt;/script&gt; @#{@cto.title}")

    refute_includes html, "<script>"
    assert_includes html, "&lt;script&gt;"
    assert_includes html, role_path(@cto)
  end

  test "markdown_with_mentions preserves bare angle brackets adjacent to a mention" do
    html = markdown_with_mentions("1 < 2 and @#{@cto.title} agrees")

    assert_includes html, "1 &lt; 2"
    assert_includes html, role_path(@cto)
  end

  test "markdown_with_mentions does not double-encode ampersands in surrounding text" do
    html = markdown_with_mentions("foo & bar @#{@cto.title}")

    assert_includes html, "foo &amp; bar"
    refute_includes html, "&amp;amp;"
    assert_includes html, role_path(@cto)
  end
end
