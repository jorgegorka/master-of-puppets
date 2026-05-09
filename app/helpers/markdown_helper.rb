module MarkdownHelper
  MARKDOWN_OPTIONS = {
    parse: { smart: true },
    render: { hardbreaks: false, github_pre_lang: true, unsafe: false },
    extension: {
      strikethrough: true,
      table: true,
      tasklist: true,
      autolink: true,
      tagfilter: true
    }
  }.freeze

  def markdown(text)
    return "" if text.blank?

    html = Commonmarker.to_html(text.to_s, options: MARKDOWN_OPTIONS)
    tag.div(html.html_safe, class: "prose")
  end

  def markdown_with_mentions(text)
    return "" if text.blank?

    html = Commonmarker.to_html(text.to_s, options: MARKDOWN_OPTIONS)
    if Current.project && text.to_s.include?("@")
      html = link_role_mentions(html, Current.project)
    end
    tag.div(html.html_safe, class: "prose")
  end

  private

  def link_role_mentions(html, project)
    index = mention_role_index(project)
    return html if index[:pattern].nil?

    fragment = Nokogiri::HTML::DocumentFragment.parse(html)
    fragment.traverse do |node|
      next unless node.text?
      next unless node.content.include?("@")
      next if node.ancestors.any? { |a| %w[a code pre].include?(a.name) }
      next unless node.content.match?(index[:pattern])

      node.replace(build_mention_nodes(node.content, index, node.document))
    end
    fragment.to_html
  end

  # Builds nodes directly instead of round-tripping a string through
  # Nokogiri.parse — re-parsing decoded text content turns entity-encoded
  # markup into live HTML and reintroduces XSS.
  def build_mention_nodes(text, index, document)
    parts = text.split(index[:pattern], -1)
    new_nodes = parts.each_with_index.map do |part, i|
      if i.odd?
        role = index[:by_title][part.downcase]
        if role
          anchor = Nokogiri::XML::Node.new("a", document)
          anchor["href"] = role_path(role)
          anchor["class"] = "mention"
          anchor.content = "@#{role.title}"
          anchor
        else
          Nokogiri::XML::Text.new("@#{part}", document)
        end
      else
        Nokogiri::XML::Text.new(part, document) unless part.empty?
      end
    end.compact

    Nokogiri::XML::NodeSet.new(document, new_nodes)
  end

  def mention_role_index(project)
    @_mention_role_index ||= {}
    @_mention_role_index[project.id] ||= begin
      roles = project.roles.active.to_a
      # Match longest titles first so "@CTO Bob" wins over "@CTO".
      sorted = roles.sort_by { |r| -r.title.length }
      pattern = sorted.empty? ? nil : /@(#{sorted.map { |r| Regexp.escape(r.title) }.join("|")})/i
      {
        by_title: roles.index_by { |r| r.title.downcase },
        pattern: pattern
      }
    end
  end
end
