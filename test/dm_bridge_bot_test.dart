// Test to verify that bridge bots are hidden in DM room display names.
//
// This test demonstrates the difference between fixed and unfixed
// matrix-dart-sdk behaviour for `getLocalizedDisplayname()` in DM rooms
// that contain functional members (bridge bots).
//
// With the fix (beezly/matrix-dart-sdk @ fix/dm-hero-filtering):
//   - The `io.element.functional_members` state event is respected
//   - Bridge bots are filtered from the hero list when computing the DM name
//   - Result: "John Doe" (only the real human)
//
// Without the fix (vanilla matrix-dart-sdk):
//   - Functional members are NOT filtered in getLocalizedDisplayname()
//   - Bridge bots appear in the DM name
//   - Result: "Signal Bridge Bot, John Doe" or similar

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  group('DM Bridge Bot Filtering', () {
    late Client client;
    late Room room;

    const roomId = '!dmroom:example.com';
    const ownUserId = '@alice:fakeserver.notexisting';
    const johnUserId = '@john:example.com';
    const botUserId = '@signal-bot:example.com';

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);

      // Set up m.direct account data so the room is treated as a DM with John
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          johnUserId: [roomId],
        },
      );

      // Create the room with heroes including both the bot and John
      room = Room(
        id: roomId,
        client: client,
        summary: RoomSummary.fromJson({
          'm.heroes': [botUserId, johnUserId],
          'm.joined_member_count': 3,
          'm.invited_member_count': 0,
        }),
      );

      // Add the room to the client
      client.rooms.add(room);

      // Add member event for the bot
      room.setState(
        Event(
          type: 'm.room.member',
          content: {
            'membership': 'join',
            'displayname': 'Signal Bridge Bot',
          },
          room: room,
          stateKey: botUserId,
          senderId: botUserId,
          eventId: '\$bot_member:example.com',
          originServerTs: DateTime.now(),
        ),
      );

      // Add member event for John
      room.setState(
        Event(
          type: 'm.room.member',
          content: {
            'membership': 'join',
            'displayname': 'John Doe',
          },
          room: room,
          stateKey: johnUserId,
          senderId: johnUserId,
          eventId: '\$john_member:example.com',
          originServerTs: DateTime.now(),
        ),
      );

      // Add member event for ourselves
      room.setState(
        Event(
          type: 'm.room.member',
          content: {
            'membership': 'join',
            'displayname': 'Alice',
          },
          room: room,
          stateKey: ownUserId,
          senderId: ownUserId,
          eventId: '\$own_member:example.com',
          originServerTs: DateTime.now(),
        ),
      );
    });

    tearDown(() async {
      await client.dispose();
    });

    test(
        'WITH functional_members state event: bot is filtered, name is "John Doe"',
        () {
      // Add the io.element.functional_members state event marking the bot
      room.setState(
        Event(
          type: 'io.element.functional_members',
          content: {
            'service_members': [botUserId],
          },
          room: room,
          stateKey: '',
          senderId: ownUserId,
          eventId: '\$func_members:example.com',
          originServerTs: DateTime.now(),
        ),
      );

      // Verify the room is treated as a DM
      expect(room.isDirectChat, isTrue,
          reason: 'Room should be treated as a DM');

      // Verify functional members are correctly read
      expect(room.functionalMembers, contains(botUserId),
          reason: 'Bot should be in functionalMembers');

      // With the fix, the bot should be filtered out
      final displayName = room.getLocalizedDisplayname();
      expect(
        displayName,
        equals('John Doe'),
        reason:
            'With functional_members set, bot should be filtered and only John Doe shown',
      );
    });

    test(
        'WITHOUT functional_members state event: bot appears in name (unfixed behaviour)',
        () {
      // Do NOT add io.element.functional_members — simulates unfixed SDK behaviour
      // (or vanilla SDK where functional members aren't filtered)

      // Verify the room is treated as a DM
      expect(room.isDirectChat, isTrue,
          reason: 'Room should be treated as a DM');

      // Verify no functional members
      expect(room.functionalMembers, isEmpty,
          reason: 'No functional members state event set');

      // Without the fix (no functional_members event), the bot appears in the name
      final displayName = room.getLocalizedDisplayname();

      // The bot IS in the heroes list and has no functional_members to filter it,
      // so it should appear in the display name
      expect(
        displayName,
        contains('Signal Bridge Bot'),
        reason:
            'Without functional_members event, the bot should appear in the display name '
            '(demonstrating the unfixed/broken behaviour)',
      );

      // John should also appear since he is a real participant
      expect(
        displayName,
        contains('John Doe'),
        reason: 'John Doe should also appear in the display name',
      );
    });

    test('functionalMembers getter returns correct list', () {
      room.setState(
        Event(
          type: 'io.element.functional_members',
          content: {
            'service_members': [botUserId],
          },
          room: room,
          stateKey: '',
          senderId: ownUserId,
          eventId: '\$func_members2:example.com',
          originServerTs: DateTime.now(),
        ),
      );

      expect(room.functionalMembers, equals([botUserId]));
    });

    test('directChatMatrixID is set correctly', () {
      expect(room.directChatMatrixID, equals(johnUserId));
    });
  });
}
