import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:attendly/api.dart';
import 'package:attendly/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void phoneSize(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tapSubmit(WidgetTester tester, String text) async {
  final button = find.widgetWithText(FilledButton, text);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'registration validates email and confirmation before requesting OTP',
    (tester) async {
      phoneSize(tester);
      final bodies = <Map<String, dynamic>>[];
      final api = Api(
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({'challengeId': 'signup-1', 'deliveryMode': 'smtp'}),
            200,
          );
        }),
      )..restored = true;
      await tester.pumpWidget(AttendlyApp(api: api));
      await tester.tap(find.byKey(const ValueKey('register-tab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('Họ và tên')),
        'Nguyễn Minh An',
      );
      await tester.enterText(find.byKey(const ValueKey('Email')), 'email-sai');
      await tester.enterText(
        find.byKey(const ValueKey('Tên đăng nhập')),
        'student_new',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password')),
        'Password123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm-password')),
        'Password124',
      );
      await tapSubmit(tester, 'Tạo tài khoản');
      expect(find.text('Địa chỉ email chưa hợp lệ'), findsOneWidget);
      expect(find.text('Mật khẩu xác nhận chưa khớp'), findsOneWidget);
      expect(bodies, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('Email')),
        'student@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm-password')),
        'Password123',
      );
      await tapSubmit(tester, 'Tạo tài khoản');
      expect(bodies.single, {
        'name': 'Nguyễn Minh An',
        'email': 'student@example.test',
        'username': 'student_new',
        'password': 'Password123',
      });
      expect(find.text('Kiểm tra hộp thư'), findsOneWidget);
      expect(find.text('student@example.test'), findsOneWidget);
      expect(api.user, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets(
    'small screen supports password visibility and keyboard scrolling',
    (tester) async {
      phoneSize(tester, width: 360, height: 740);
      final api = Api(client: MockClient((_) async => http.Response('{}', 200)))
        ..restored = true;
      await tester.pumpWidget(AttendlyApp(api: api));
      await tester.enterText(
        find.byKey(const ValueKey('Tên đăng nhập')),
        'teacher001',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password')),
        'Password123',
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('password')),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        isTrue,
      );
      await tester.ensureVisible(find.byTooltip('Hiện mật khẩu'));
      await tester.tap(find.byTooltip('Hiện mật khẩu'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('password')),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        isFalse,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Đăng nhập'),
      );
      expect(
        find.widgetWithText(FilledButton, 'Đăng nhập').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets(
    'switching forms hides the password and clears old validation errors',
    (tester) async {
      phoneSize(tester);
      final api = Api(client: MockClient((_) async => http.Response('{}', 200)))
        ..restored = true;
      await tester.pumpWidget(AttendlyApp(api: api));
      await tapSubmit(tester, 'Đăng nhập');
      expect(find.text('Vui lòng nhập tên đăng nhập'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('register-tab')));
      await tester.tap(find.byKey(const ValueKey('register-tab')));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập tên đăng nhập'), findsNothing);
      expect(find.byKey(const ValueKey('confirm-password')), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('password')),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets('capture login registration and OTP phone previews', (
    tester,
  ) async {
    phoneSize(tester, width: 430, height: 932);
    await tester.runAsync(() async {
      final config = jsonDecode(
        await File('.dart_tool/package_config.json').readAsString(),
      ) as Map;
      final flutter = (config['packages'] as List).firstWhere(
        (p) => p['name'] == 'flutter',
      );
      final sdk = Directory.fromUri(Uri.parse(flutter['rootUri']))
          .parent
          .parent;
      final fonts = '${sdk.path}/bin/cache/artifacts/material_fonts';
      final roboto = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium', 'Bold', 'Black']) {
        roboto.addFont(
          File('$fonts/Roboto-$weight.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      }
      await roboto.load();
      await (FontLoader('MaterialIcons')..addFont(
            File('$fonts/MaterialIcons-Regular.otf')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
    });
    for (final mode in ['login', 'register', 'otp']) {
      final api = Api(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'challengeId': 'preview-otp', 'deliveryMode': 'smtp'}),
            200,
          ),
        ),
      )..restored = true;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: AttendlyApp(api: api),
        ),
      );
      await tester.pumpAndSettle();
      if (mode == 'register') {
        await tester.tap(find.byKey(const ValueKey('register-tab')));
        await tester.pumpAndSettle();
      } else if (mode == 'otp') {
        await tester.enterText(
          find.byKey(const ValueKey('Tên đăng nhập')),
          'student_demo',
        );
        await tester.enterText(
          find.byKey(const ValueKey('password')),
          'DemoPassword123',
        );
        await tapSubmit(tester, 'Đăng nhập');
      }
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final output = File('../docs/previews/auth-$mode.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    }
  }, skip: !const bool.fromEnvironment('CAPTURE_AUTH_PREVIEWS'));
}
