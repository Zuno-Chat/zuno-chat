import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';

void main() {
  final l10n = englishLocalizations;

  group('unopened shares', () {
    test('one file', () {
      expect(
        l10n.chatUnopenedShares(1),
        'One shared file could not be opened. Share it again.',
      );
    });

    test('several files', () {
      expect(
        l10n.chatUnopenedShares(3),
        '3 shared files could not be opened. Share them again.',
      );
    });
  });

  group('identity change', () {
    test('one person is named', () {
      expect(
        l10n.chatIdentityChanged(1, 'ann'),
        "ann's security details changed",
      );
    });

    test('several people are counted', () {
      expect(
        l10n.chatIdentityChanged(3, 'ann'),
        "3 people's security details changed",
      );
    });

    test('the room info tile keeps its curly apostrophe for several', () {
      expect(
        l10n.roomInfoGroupIdentityChanged(1, 'ann'),
        "ann's security details changed",
      );
      expect(
        l10n.roomInfoGroupIdentityChanged(3, 'ann'),
        '3 people’s security details changed',
      );
      expect(
        l10n.roomInfoPersonIdentityChanged('ann'),
        "ann's security details changed",
      );
    });
  });

  group('delete title', () {
    test('one message', () {
      expect(l10n.chatDeleteTitle(1), 'Delete message?');
    });

    test('several items', () {
      expect(l10n.chatDeleteTitle(4), 'Delete 4 items?');
    });
  });

  group('failed gallery', () {
    test('one item', () {
      expect(l10n.chatGalleryNotSent(1), 'Not sent. Tap to try again.');
    });

    test('several items', () {
      expect(l10n.chatGalleryNotSent(2), 'Not sent. Tap an item to try again.');
    });
  });

  group('gallery actions', () {
    test('count in brackets', () {
      expect(l10n.chatShareAll(3), 'Share all (3)');
      expect(l10n.chatSaveAll(3), 'Save all (3)');
      expect(l10n.chatDeleteAllCount(3), 'Delete all (3)');
    });
  });

  group('more sign-ins', () {
    test('one more', () {
      expect(l10n.roomsMoreSignIns(1), '+1 more new sign-in');
    });

    test('several more', () {
      expect(l10n.roomsMoreSignIns(2), '+2 more new sign-ins');
    });
  });

  group('room info counts', () {
    test('members title', () {
      expect(l10n.roomInfoMembersCount(1), 'Members (1)');
      expect(l10n.roomInfoMembersCount(1200), 'Members (1,200)');
    });

    test('confirmed of total', () {
      expect(l10n.roomInfoConfirmedCount(1, 3), '1 of 3 confirmed');
      expect(l10n.roomInfoConfirmedCount(2, 5), '2 of 5 confirmed');
    });
  });
}
