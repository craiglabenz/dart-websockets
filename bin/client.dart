import 'dart:io';
import 'package:args/args.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const url = 'ws://localhost:8080';

/// Usage:
///   # To send a message
///   dart bin/client.dart -c <NAME> -m <MSG>
///
///   # To listen to messages on a channel
///   dart bin/client.dart -c <NAME>
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('channel', abbr: 'c', mandatory: true)
    ..addOption('message', abbr: 'm');
  final results = parser.parse(arguments);

  final channel = WebSocketChannel.connect(
    Uri.parse(url),
  );

  if (results['message'] != null) {
    final msg = '${results["channel"]} :: ${results["message"]}';
    stdout.writeln("[sending] $msg");
    await channel.sink.add(msg);
    channel.sink.close();
  } else {
    stdout.writeln('Listening on $url/${results["channel"]}');
    channel.sink.add('__CONNECT__ :: ${results["channel"]}');
    channel.stream.listen(print);
  }
}
