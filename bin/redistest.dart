import 'package:args/args.dart';
import 'package:redis/redis.dart';

/// Simple file demonstration of working Redis PubSub.
/// Launch a Redis Docker container (using the linked
/// docker-compose.yml file), and run the two following
/// commands in two separate terminals. The message from
/// your second terminal will appear in the first.
///
/// Usage:
///   # To listen to messages on a channel
///   dart bin/redistest.dart -c <NAME>
///
///   # To send a message
///   dart bin/redistest.dart -c <NAME> -m <MSG>
void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('channel', abbr: 'c', mandatory: true)
    ..addOption('message', abbr: 'm');

  final results = parser.parse(args);

  final conn = RedisConnection();
  final command = await conn.connect('localhost', 6379);

  if (results['message'] == null) {
    final pubSub = PubSub(command);
    pubSub.getStream().listen((obj) => print(obj));
    pubSub.subscribe([results['channel']]);
  } else {
    await command.send_object(
      ['PUBLISH', results['channel'], results['message']],
    );
    await conn.close();
  }
}
