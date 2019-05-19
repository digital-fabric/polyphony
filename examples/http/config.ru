run Proc.new { |env|
    ['200', {'Content-Type' => 'text/html'}, ['A barebones rack app.']]
}
