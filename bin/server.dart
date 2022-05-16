import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final socketMap = <String, List<WebSocketChannel>>{};

/// Allows registration of sockets to channels, and submission of messages
/// to channels.
///
/// The format of each message is "<CHANNEL> :: <MESSAGE>". The special channel,
/// "__CONNECT__", is not a real channel, but instead is used to connect to the
/// channel name specified in the message.
///
/// Examples:
///
///   // Connect to channel XYZ
///   "__CONNECT__ :: XYZ"
///
///   // Send message "Hello world!" to channel "XYZ"
///   "XYZ :: Hello world!"
///
Future<void> main(List<String> arguments) async {
  var handler = webSocketHandler((WebSocketChannel webSocket) async {
    webSocket.stream.listen((message) {
      if (message is! String) {
        stderr.writeln("Unexpected message type: ${message.runtimeType}");
        return;
      }
      stdout.writeln('[RECEIVED] $message');
      final tokens =
          message.split('::').map((String token) => token.trim()).toList();

      if (tokens.length != 2) {
        stderr.writeln(
          "Unexpected message format. Expected '<CHANNEL> :: <MESSAGE>'",
        );
        return;
      }

      final channel = tokens[0];
      final value = tokens[1];

      if (channel == 'CONNECT') {
        if (!socketMap.containsKey(value)) {
          socketMap[value] = <WebSocketChannel>[];
        }
        socketMap[value].add(webSocket);
      } else {
        if (!socketMap.containsKey(channel)) {
          return;
        }
        for (final subscribedChannel in socketMap[channel]) {
          subscribedChannel.sink.add(value);
        }
      }
    });
  });

  final server = Pipeline().addMiddleware(logRequests()).addHandler(handler);

  shelf_io.serve(server, 'localhost', 8080).then((server) {
    print('Serving at ws://${server.address.host}:${server.port}');
  });
}
