---
layout: page
title: Polyphony::Net
parent: API Reference
permalink: /api-reference/polyphony-net/
---
# Polyphony::Net

The `Polyphony::Net` provides convenience methods for working with sockets. The
module unifies secure and non-secure socket APIs.

## Class Methods

### #tcp_connect(host, port, opts = {}) → socket

Connects to a TCP server.

### #tcp_listen(host = nil, port = nil, opts = {}) → socket

Opens a server socket for listening to incoming connections.
