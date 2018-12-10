# frozen_string_literal: true

export_default :Request

class Request
  
end


# export :prepare

# require 'uri'

# # the request object passed to handlers is a hash containing the following:
# #
# # {
# #   method:       :GET,
# #   request_url:  '/?q=time',
# #   path:         '/',
# #   query:        { q: 'time' },
# #   headers:      { ... },
# #   upgrade:      'echo',
# #   cookies:      { ... },
# #   body:         'blahblah', # or:
# #   body_form_data: { ... },
# # }

# # Prepares a request hash, parsing url, headers, body
# # @param request [Hash]
# # @return [void]
# def prepare(request)
#   parse_request_url(request)
#   parse_headers(request)
#   parse_body(request)
# end

# S_EMPTY     = ''
# S_AMPERSAND = '&'
# S_EQUAL     = '='

# # Parses path, query from request_url
# # @param request [Hash]
# # @return [void]
# def parse_request_url(request)
#   u = URI.parse(request[:request_url] || S_EMPTY)
#   request[:path] = u.path

#   return unless (q = u.query)
#   request[:query] = q.split(S_AMPERSAND).each_with_object({}) do |kv, h|
#     k, v = kv.split(S_EQUAL)
#     h[k.to_sym] = URI.decode_www_form_component(v)
#   end
# end

# # Parses cookies, upgrade headers
# # @param request [Hash]
# # @return [void]
# def parse_headers(request); end

# # Parses request body
# # @param request [Hash]
# # @return [void]
# def parse_body(request); end
