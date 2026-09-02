# frozen_string_literal: true

require 'yaml'

require_relative 'errors'

module SLA
  # The first fenced ```yaml block in a markdown document, parsed.
  module YAMLBlock
    FENCE = /^```yaml[ \t]*\r?\n(.*?)\r?\n```[ \t]*$/m

    # Returns the parsed block, or nil when the document has none.
    def self.first(markdown)
      match = FENCE.match(markdown.to_s)
      return nil unless match

      YAML.safe_load(match[1])
    rescue Psych::Exception => e
      raise Error, "invalid yaml block: #{e.message}"
    end
  end
end
