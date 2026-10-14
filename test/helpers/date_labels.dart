import 'package:zuno/core/format/date_labels.dart';
import 'package:zuno/core/l10n/l10n.dart';

DateLabels testDateLabels({bool use24Hour = true}) =>
    DateLabels(englishLocalizations, locale: 'en_US', use24Hour: use24Hour);
