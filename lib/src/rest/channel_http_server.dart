import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_message.dart';
import 'deployment_api.dart';
// Only the socket, by name: this file speaks dart:io's HttpRequest, and the framework has a port
// of its own under that name. Importing the whole library would shadow one with the other, and
// what the analyzer then reports is a missing getter rather than a collision.
import 'package:ansiwise_core/ansiwise_core.dart' show ChannelServerSocket, ChannelSocket;

/// Serves the REST surface over one channel, and returns when the channel closes.
///
/// This is the one place in the package that knows the API is reached over HTTP at all. Everything
/// above it takes an [ApiRequest] and answers with an [ApiResponse]; this turns one into the other
/// and writes the bytes.
///
/// Nothing listens. `HttpServer.listenOn` is given a [ChannelServerSocket] holding the session's own
/// standard input and output, so there is no port to open, nothing to authenticate a second time,
/// and no process left when the session ends. NOTHING HERE READS A CREDENTIAL, and it is the
/// composition that says so rather than a flag: sshd is the whole authentication of a session, and
/// a surface that demanded one here could not be reached on a machine that has none yet — which is
/// every machine at its first installation.
final class ChannelHttpServer {
  /// Serves [api] over the bytes of [incoming] and [outgoing].
  const ChannelHttpServer(this.api, {required this.incoming, required this.outgoing});

  /// What answers the requests.
  final DeploymentApi api;

  /// The channel's standard input.
  final Stream<List<int>> incoming;

  /// The channel's standard output.
  final StreamSink<List<int>> outgoing;

  /// Answers requests until the channel closes, and returns once every answer still in flight has
  /// been written.
  Future<void> serve() async {
    final HttpServer server = HttpServer.listenOn(
      ChannelServerSocket(ChannelSocket(incoming: incoming, outgoing: outgoing)),
    );
    await _answerAll(server, api.call);
  }
}

/// Answers every request of [server] until its stream of requests ends, and returns once the
/// answers still in flight have been written.
///
/// CONCURRENTLY, and that is load-bearing. A run being watched is one response held open for as
/// long as the run takes — an hour, for a deployment — and a loop that answered one request to the
/// end before reading the next would let that single watcher stop every other caller on the
/// channel, including the `GET /runs/{id}` a manager asks to find a run again after its own
/// restart. So each request is dispatched and the next one read; what orders the answers is how
/// long each takes, and nothing here needs them ordered.
Future<void> _answerAll(HttpServer server, _Answering answering_) async {
  final Set<Future<void>> pending = <Future<void>>{};
  final Completer<void> noMoreRequests = Completer<void>();
  server.listen(
    (HttpRequest request) {
      late final Future<void> answering;
      answering = _answer(answering_, request).whenComplete(() => pending.remove(answering));
      pending.add(answering);
    },
    // A connection that breaks or talks nonsense reports here, and it is that connection's end,
    // not the server's: ending the loop for it would take the surface away from every other
    // caller on the machine for one peer's failure.
    onError: (Object _) {},
    onDone: noMoreRequests.complete,
  );
  await noMoreRequests.future;
  await Future.wait(pending);
}

/// Answers one request, and never throws.
///
/// Never, because the future this returns is not awaited by the dispatch above — an error escaping
/// here would be an unhandled asynchronous error, which ends the process. Two different things are
/// swallowed into that guarantee: an endpoint that throws is answered `500` where the headers have
/// not gone out yet, and a response whose caller vanished mid-write is simply abandoned — its
/// failed write already told the only party that could have cared. Neither disturbs any other
/// response: each request's answer holds no state but its own.
Future<void> _answer(_Answering answering, HttpRequest request) async {
  try {
    final ApiResponse answer = await answering(
      ApiRequest(request.method, request.uri, body: await utf8.decoder.bind(request).join()),
    );

    switch (answer) {
      case Answered(:final int status, :final Object payload):
        request.response
          ..statusCode = status
          ..headers.contentType = ContentType.json;
        request.response.write(jsonEncode(payload));

      case Refused(:final int status, :final String reason):
        request.response
          ..statusCode = status
          ..headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, Object?>{'refused': reason}));

      case Streaming(:final Stream<Object> items):
        // One JSON object per line, flushed as it arrives. `transfer-encoding: chunked` comes out
        // of dart:io by itself once the length is unknown, so a run being watched reaches the
        // client as it happens rather than when it ends — which for a deployment is an hour later.
        //
        // `bufferOutput` is off because `flush` alone does not do what it says here: dart:io holds
        // small writes in an internal buffer that a flush provably leaves a line behind in, so a
        // watcher would see each event only when the next one pushed it out — or at the end, which
        // is the one time it no longer matters. The flush below still earns its keep as
        // backpressure: it completes when the socket accepted the bytes, so a slow reader slows
        // the reading of its own run's events instead of growing an unbounded buffer here.
        request.response
          ..bufferOutput = false
          ..statusCode = 200
          ..headers.contentType = ContentType('application', 'x-ndjson', charset: 'utf-8');

        // How a vanished caller is noticed. A write to a dead socket does not throw here: dart:io
        // swallows it and reports the failure once, through `done` — so a loop that only wrote
        // would follow a run's events into a dead socket for the rest of the run. `done` is
        // watched instead, and the following ends the moment the response is over, whichever way
        // it ended.
        final Completer<void> over = Completer<void>();
        void ended([Object? _, Object? _]) {
          if (!over.isCompleted) {
            over.complete();
          }
        }

        unawaited(request.response.done.then(ended, onError: ended));

        final Completer<void> drained = Completer<void>();
        late final StreamSubscription<Object> following;
        following = items.listen(
          (Object item) {
            request.response.writeln(jsonEncode(item));
            // Backpressure, not delivery: the pause holds the next event back until the socket
            // accepted this one, so a slow reader slows the reading of its own run's events
            // instead of growing an unbounded buffer here. A flush that fails is not the ending —
            // `done` above is — so its error is dropped rather than left unhandled.
            following.pause(request.response.flush().then((void _) {}, onError: (Object _) {}));
          },
          onError: drained.completeError,
          onDone: drained.complete,
        );
        try {
          await Future.any(<Future<void>>[drained.future, over.future]);
        } finally {
          await following.cancel();
        }
    }

    await request.response.close();
  } on Object catch (_) {
    try {
      // Meaningful only while nothing has been written: a caller whose endpoint threw is told the
      // machine failed, not handed an empty 200. Once the headers are out this line throws, and
      // the close below still runs.
      request.response.statusCode = 500;
    } on Object catch (_) {}
    try {
      await request.response.close();
    } on Object catch (_) {}
  }
}

/// What answers one request.
typedef _Answering = Future<ApiResponse> Function(ApiRequest request);
