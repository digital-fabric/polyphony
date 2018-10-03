// For the sake of comparing performance, here's a node.js-based HTTP server
// doing roughly the same thing as http_server. Preliminary benchmarking shows
// the ruby version has a throughput (req/s) of about 2/3 of the JS version.

const http = require('http');

const MSG = 'Hello World';

const server = http.createServer((req, res) => {
  // let requestCopy = {
  //   method: req.method,
  //   request_url: req.url,
  //   headers: req.headers
  // };
  
  // res.writeHead(200, { 'Content-Type': 'application/json' });
  // res.end(JSON.stringify(requestCopy));

  res.writeHead(200);
  res.end(MSG)
});

server.listen(1235);
console.log('Listening on port 1235');
