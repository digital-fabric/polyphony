require 'yard'

# shamelessly copied from https://github.com/troessner/reek/blob/master/docs/yard_plugin.rb

# Template helper to modify processing of links in HTML generated from our
# markdown files.
module LocalLinkHelper
  # Rewrites links to (assumed local) markdown files so they're processed as
  # {file: } directives.
  def resolve_links(text)
    text = text.gsub(%r{<a href="(docs/[^"]*.md)">([^<]*)</a>}, '{file:/\1 \2}')
               .gsub(%r{<img src="(assets/[^"]*)">}, '{rdoc-image:/\1}')
    super text
  end
end

YARD::Templates::Template.extra_includes << LocalLinkHelper
