
Code Style Conventions For Erlang
=================================

* Use 4 spaces alignment. Never use tabs.

* Use the next frecuently used variables:
  T - tail of a list;
  F - local function;
  MState - Module state variable must have always this name.

* API functions should be as small as possible. Move all implementation code
into separate hidden functions.

* Do not introduce lines longer than 120 characters.

* Main service module must implement gen_server.

* Use the next naming convention:
  CONSTANT_EXAMPLE - constances are written in uppercase characters separated by underscores;
  any_function() - use lowercase charecters separated by underscores  for function names;
  SomeVariable - UpperCamelCase for variables in a complex code;
  N - single letter variables for super simple or obvious code;

* For C-code use FreeBSD code style:
  http://www.freebsd.org/cgi/man.cgi?query=style&sektion=9

