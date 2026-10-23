import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_showdown_client/core/protocol/client_commands.dart';

void main() {
  test('serializes authentication with an unchanged assertion tail', () {
    final command = TrnCommand(
      username: 'Alice Smith',
      assertion: 'alice,2,123,host;signature+/=',
    );
    expect(
      command.serialize(),
      '|/trn Alice Smith,0,alice,2,123,host;signature+/=',
    );
    expect(command.username, 'Alice Smith');
    expect(command.assertion, 'alice,2,123,host;signature+/=');
    expect(command.toString(), isNot(contains(command.assertion)));
  });

  test('serializes global joins and room-scoped leaves', () {
    for (final roomId in [
      'lobby',
      'battle-gen9randombattle-123',
      'groupchat-alice-test',
    ]) {
      final join = JoinRoomCommand(roomId: roomId);
      final leave = LeaveRoomCommand(roomId: roomId);
      expect(join.serialize(), '|/join $roomId');
      expect(leave.serialize(), '$roomId|/leave');
      expect(join.roomId, roomId);
      expect(leave.roomId, roomId);
    }
  });

  test('all commands share one serialization interface', () {
    final commands = <ClientCommand>[
      TrnCommand(username: 'Alice', assertion: 'token'),
      JoinRoomCommand(roomId: 'lobby'),
      LeaveRoomCommand(roomId: 'lobby'),
    ];
    expect(commands.map((command) => command.serialize()), [
      '|/trn Alice,0,token',
      '|/join lobby',
      'lobby|/leave',
    ]);
    for (final command in commands) {
      expect(command.serialize(), command.serialize());
      expect(command.serialize().split('|'), hasLength(2));
      expect(command.serialize(), isNot(contains('\n')));
    }
  });

  test('rejects control characters and separators in every input field', () {
    final unsafe = [
      for (var code = 0; code <= 31; code++) String.fromCharCode(code),
      for (var code = 127; code <= 159; code++) String.fromCharCode(code),
      '\u2028',
      '\u2029',
      '|',
      '\r\n/leave',
      '\n|/join lobby',
    ];
    for (final separator in unsafe) {
      final value = 'a${separator}b';
      expect(
        () => TrnCommand(username: value, assertion: 'token'),
        throwsArgumentError,
      );
      expect(
        () => TrnCommand(username: 'Alice', assertion: value),
        throwsArgumentError,
      );
      expect(() => JoinRoomCommand(roomId: value), throwsArgumentError);
      expect(() => LeaveRoomCommand(roomId: value), throwsArgumentError);
    }
  });

  test(
    'rejects empty fields and surrounding whitespace without normalization',
    () {
      for (final value in ['', ' ', ' alice', 'alice ', '\u00a0alice']) {
        expect(
          () => TrnCommand(username: value, assertion: 'token'),
          throwsArgumentError,
        );
        expect(
          () => TrnCommand(username: 'Alice', assertion: value),
          throwsArgumentError,
        );
        expect(() => JoinRoomCommand(roomId: value), throwsArgumentError);
        expect(() => LeaveRoomCommand(roomId: value), throwsArgumentError);
      }
    },
  );

  test(
    'rejects comma in username but does not implement account name policy',
    () {
      expect(
        () => TrnCommand(username: 'Alice,1', assertion: 'token'),
        throwsArgumentError,
      );
      expect(
        TrnCommand(username: 'Алиса Smith', assertion: 'token').serialize(),
        '|/trn Алиса Smith,0,token',
      );
    },
  );

  test('requires canonical room IDs, not titles, URLs or room lists', () {
    for (final roomId in [
      'Lobby',
      'two rooms',
      'lobby,staff',
      '/join',
      '>lobby',
      'https://example.com/lobby',
      'комната',
      'room_name',
    ]) {
      expect(() => JoinRoomCommand(roomId: roomId), throwsArgumentError);
      expect(() => LeaveRoomCommand(roomId: roomId), throwsArgumentError);
    }
  });

  test('validation errors do not expose sensitive input', () {
    const secret = 'private-secret\n/leave';
    try {
      TrnCommand(username: 'Alice', assertion: secret);
      fail('Expected rejection');
    } on ArgumentError catch (error) {
      expect(error.invalidValue, isNull);
      expect(error.toString(), isNot(contains('private-secret')));
      expect(error.toString(), contains('assertion'));
    }
  });
}
