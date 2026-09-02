# frozen_string_literal: true

module SLA
  class Error < StandardError; end

  # Raised when the Devin API answers with a non-2xx status.
  class DevinAPIError < Error
    attr_reader :status, :body

    def initialize(status:, body:)
      @status = status
      @body = body
      super("Devin API returned #{status}: #{body.inspect}")
    end
  end
end
