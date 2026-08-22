/// The REST surface of a deployment: what it is asked, what it answers, and how it is served.
///
/// Neither the messages nor the endpoints know about a socket, a pipe or `dart:io`. That is what
/// makes every endpoint testable by calling it with a request and looking at what came back, and it
/// is what lets the same surface be served over an SSH channel today and over something else later
/// without a line of the endpoints changing.
///
/// The surface has two doors and each of them is a PROGRAM of the executable that serves it. The
/// resident door stands on an address and demands a service token; the session door speaks over the
/// pipes of an SSH session sshd has already authenticated. What starts either of them — the word,
/// the options, and the command a unit file has to carry — is stated in
/// `src/rest/resident_service.dart`, because that interface belongs to the surface rather than to
/// whichever entry point carries it.
///
/// This file exists because three different callers reach the same set of types: the serving
/// executable, the installer that renders the unit file it is started from, and the suites under
/// `test/rest/`. Without it each of them names ten files.
library;

export 'src/rest/api_message.dart';
export 'src/rest/channel_http_server.dart';
export 'src/rest/resident_service.dart';
export 'src/rest/service_token.dart';
export 'src/rest/service_token_file.dart';
export 'src/rest/service_token_gate.dart';
export 'src/rest/deployment_api.dart';
export 'src/rest/endpoints/events_endpoint.dart';
export 'src/rest/endpoints/programs_endpoint.dart';
export 'src/rest/endpoints/runs_endpoint.dart';
