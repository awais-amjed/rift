import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/notification_service.dart';

/// A call's notice on Windows is posted by Rift itself, not the plugin, so it
/// can be taken down again; it still has to read like every other Rift toast.
void main() {
  test('a title and a body, and no sound of its own', () {
    final xml = NotificationService.windowsToastXml(
      title: 'Tester B is calling',
      body: 'Direct call · Win Test',
    );

    expect(
      xml,
      '<toast useButtonStyle="true"><visual><binding template="ToastGeneric">'
      '<text>Tester B is calling</text><text>Direct call · Win Test</text>'
      '</binding></visual><audio silent="true"/></toast>',
    );
  });

  test('a press carries no payload, so it only brings the window forward', () {
    final xml = NotificationService.windowsToastXml(
      title: 'Missed call',
      body: 'From A',
    );

    expect(xml, isNot(contains('launch')));
  });

  test('a name is text, never markup', () {
    final xml = NotificationService.windowsToastXml(
      title: 'A & <B> "C" \'D\' is calling',
      body: '</text><audio src="x"/>',
    );

    expect(
      xml,
      contains(
        '<text>A &amp; &lt;B&gt; &quot;C&quot; &apos;D&apos; is calling</text>',
      ),
    );
    expect(
      xml,
      contains('<text>&lt;/text&gt;&lt;audio src=&quot;x&quot;/&gt;</text>'),
    );
    expect('<audio'.allMatches(xml), hasLength(1));
  });
}
