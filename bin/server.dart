import 'dart:io';
import 'package:redis/redis.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Stores each WebSocket subscribed to given channels. Used to distribute messages
// received from Redis.
final socketMap = <String, List<WebSocketChannel>>{};

// Stores a pointer from each WebSocket to its subscribed channel. Used to remove
// pointers to a given WebSocket once the client disconnects.
final reverseSocketMap = <WebSocketChannel, Set<String>>{};

// All currently subscribed channels. Used to maintain Redis subscriptions and to
// prevent duplicate subscriptions if more than one incoming websocket wants info
// about a specific channel.
final subscribedChannels = <String>{};

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
  // Create a PubSub connection for subscribing to channels
  final conn = RedisConnection();
  final pubSub = PubSub(await conn.connect('127.0.0.1', 6379));
  setUpRedisPubSub(pubSub);

  // Create a second Redis connection for sending messages to channels
  final redisConn = RedisConnection();
  final redisCommand = await redisConn.connect('127.0.0.1', 6379);

  final handler = webSocketHandler((WebSocketChannel webSocket) async {
    webSocket.stream.listen((dynamic message) {
      if (message is! String) {
        stderr.writeln("Unexpected message type: ${message.runtimeType}");
        return;
      }
      onMessage(
        message: message,
        webSocket: webSocket,
        pubSub: pubSub,
        redisCommand: redisCommand,
      );
    }).onDone(() {
      if (reverseSocketMap.containsKey(webSocket)) {
        stdout.writeln('[DISCONNECT]');
        final Set<String> channels = reverseSocketMap[webSocket]!;

        // Cleanup!
        for (final String channel in channels) {
          // Remove the socket from the channel name's list
          socketMap[channel]!.remove(webSocket);

          // And if that channel name now has no more sockets...
          if (socketMap[channel]!.isEmpty) {
            stdout.writeln('[REMOVING] $channel');

            // Deep cleaning
            socketMap.remove(channel);
            subscribedChannels.remove(channel);
            pubSub.unsubscribe([channel]);
          }
        }
      }
    });
  });

  // Boilerplate from shelf
  final server = Pipeline().addMiddleware(logRequests()).addHandler(handler);

  // Boilerplate from shelf
  shelf_io.serve(server, 'localhost', 8080).then((server) {
    stdout.writeln('Serving at ws://${server.address.host}:${server.port}');
  });
}

Future<void> onMessage({
  required String message,
  required WebSocketChannel webSocket,
  required PubSub pubSub,
  required Command redisCommand,
}) async {
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

  // Incoming message is the special signal to subscribe this connection to
  // that channel topic.
  if (channel == '__CONNECT__') {
    // Prepare to register our new websocket with its channel nane in both the
    // look-ups
    if (!socketMap.containsKey(value)) {
      socketMap[value] = <WebSocketChannel>[];
    }
    if (!reverseSocketMap.containsKey(webSocket)) {
      reverseSocketMap[webSocket] = <String>{};
    }

    socketMap[value]!.add(webSocket);
    reverseSocketMap[webSocket]!.add(value);

    // If this channel is new for this process, save the channel name and subscribe.
    if (!subscribedChannels.contains(value)) {
      subscribedChannels.add(value);
      pubSub.psubscribe([value]);
    }
  } else {
    stdout.writeln('[PUBLISHING] $channel $value');
    await redisCommand.send_object(["PUBLISH", channel, value]);
  }
}

/// One-time set up to establish a stream to any/all PubSub messages we receive.
void setUpRedisPubSub(PubSub pubSub) async {
  // Redis boilerplate.
  final stream = pubSub.getStream().handleError(
        (err) => stderr.writeln('[ERROR] $err'),
      );
  stream.listen((dynamic message) {
    // Messages are one of the following structures:
    //
    // 1. ["pmessage", <CHANNEL_NAME>, <CHANNEL_NAME>, <PAYLOAD>}]
    //    TODO: Why channel name twice?
    // 2. ["unsubscribe", <CHANNEL_NAME>, ?]
    //    TODO: What is the significance of the final argument, which seems
    //    to be an integer?

    if (message is! List) {
      stderr.writeln('Unexpected subscription type: ${message.runtimeType}');
    }

    if (message[1] == 'unsubscribe') {
      stderr.writeln('TODO: handle unsubscriptions');
      return;
    }

    stdout.writeln('[SUBSCRIPTION] $message');
    // Loop over all connected websockets to this server for this channel.
    if (socketMap.containsKey(message[2])) {
      for (final webSocket in socketMap[message[2]]!) {
        webSocket.sink.add(message.last);
      }
    }
  })
    ..onError((err) {
      stdout.writeln('[ERROR] $err');
    })
    ..onDone(() => stdout.writeln('Done listening to Redis'));
}
