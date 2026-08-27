import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/presentation/screens/flight/whiteboard_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('remembers the last whiteboard canvas independently per note', () async {
    expect(await WhiteboardPrefs.loadLastCanvas(10), isNull);

    await WhiteboardPrefs.saveLastCanvas(10, 101);
    await WhiteboardPrefs.saveLastCanvas(20, 202);

    expect(await WhiteboardPrefs.loadLastCanvas(10), 101);
    expect(await WhiteboardPrefs.loadLastCanvas(20), 202);
    expect(await WhiteboardPrefs.loadLastCanvas(30), isNull);
  });
}
