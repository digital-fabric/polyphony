run Proc.new { |env|
    ['200', {'Content-Type' => 'text/html'}, [
      env.select { |k, v| k =~ /^[A-Z]/}.inspect
    ]]
}
