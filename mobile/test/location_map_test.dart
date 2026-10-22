import 'dart:async';
import 'dart:convert';

import 'package:attendly/api.dart';
import 'package:attendly/device_services.dart';
import 'package:attendly/location_map_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class MemoryTiles extends TileProvider {
  final image = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
    ),
  );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      image;
}

class UnusedTile extends Fake implements TileImage {}

Position fix({
  double accuracy = 8,
  DateTime? timestamp,
  double latitude = 10.762622,
}) => Position(
  latitude: latitude,
  longitude: 106.660172,
  timestamp: timestamp ?? DateTime.now(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Future<void> mount(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}

Future<void> disposeMap(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const SizedBox());
}

void main() {
  test(
    'coordinates and GPS quality reject invalid, stale and inaccurate fixes',
    () {
      final now = DateTime.now();
      expect(mapPoint('0', '0'), const LatLng(0, 0));
      expect(mapPoint('NaN', 106), isNull);
      expect(mapPoint(91, 106), isNull);
      expect(
        DeviceServices.locationProblem(fix(timestamp: now), now: now),
        isNull,
      );
      for (final sample in [
        fix(accuracy: 0),
        fix(accuracy: double.nan),
        fix(accuracy: 100),
        fix(latitude: 91),
        fix(latitude: double.nan),
        fix(timestamp: now.subtract(const Duration(seconds: 61))),
        fix(timestamp: now.add(const Duration(seconds: 11))),
      ]) {
        expect(DeviceServices.locationProblem(sample, now: now), isNotNull);
      }
    },
  );

  testWidgets(
    'class location is automatically acquired; map taps cannot choose it',
    (tester) async {
      GpsLocationResult? result;
      var calls = 0;
      final pending = Completer<Position>();
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<GpsLocationResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LocationMapPage(
                      captureClassLocation: true,
                      target: const LatLng(10, 106),
                      tileProvider: MemoryTiles(),
                      locationLoader: () {
                        calls++;
                        return pending.future;
                      },
                    ),
                  ),
                );
              },
              child: const Text('Mở GPS'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở GPS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls, 1);
      expect(
        find.text('Đang xác định vị trí GPS từ điện thoại…'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap,
        isNull,
      );
      final position = fix();
      pending.complete(position);
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getCenter(find.byType(FlutterMap)) + const Offset(70, 0),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Vị trí lớp: 10.762622, 106.660172'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận vị trí GPS'));
      await tester.pumpAndSettle();
      expect(result!.position, same(position));
      expect(result!.radiusMeters, greaterThan(100));
      expect(result!.radiusMeters, lessThanOrEqualTo(500));
      await disposeMap(tester);
    },
  );

  testWidgets(
    'cancelling GPS capture returns no replacement for the class location',
    (tester) async {
      GpsLocationResult? result;
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<GpsLocationResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LocationMapPage(
                      captureClassLocation: true,
                      tileProvider: MemoryTiles(),
                      locationLoader: () async => fix(),
                    ),
                  ),
                );
              },
              child: const Text('Mở GPS'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở GPS'));
      await tester.pumpAndSettle();
      expect(find.text('Vị trí lớp: 10.762622, 106.660172'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(result, isNull);
      await disposeMap(tester);
    },
  );

  testWidgets(
    'GPS failure blocks confirmation and can be retried without manual entry',
    (tester) async {
      var attempts = 0;
      await mount(
        tester,
        LocationMapPage(
          captureClassLocation: true,
          target: const LatLng(10, 106),
          tileProvider: MemoryTiles(),
          locationLoader: () async {
            if (++attempts == 1) throw ApiException('Cần quyền vị trí');
            return fix();
          },
        ),
      );
      expect(find.text('Cần quyền vị trí'), findsOneWidget);
      expect(find.text('Cài đặt vị trí'), findsOneWidget);
      expect(find.text('Quyền ứng dụng'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Thử lại GPS'));
      await tester.pumpAndSettle();
      expect(find.text('Cần quyền vị trí'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(find.text('Vị trí lớp: 10.762622, 106.660172'), findsOneWidget);
      await disposeMap(tester);
    },
  );

  testWidgets('stale and inaccurate fixes cannot confirm a class position', (
    tester,
  ) async {
    var attempts = 0;
    await mount(
      tester,
      LocationMapPage(
        captureClassLocation: true,
        tileProvider: MemoryTiles(),
        locationLoader: () async {
          attempts++;
          if (attempts == 1) return fix(accuracy: 100);
          if (attempts == 2) {
            return fix(
              timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
            );
          }
          return fix();
        },
      ),
    );
    expect(find.textContaining('GPS đang sai số'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Cập nhật GPS'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kết quả GPS đã cũ'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Cập nhật GPS'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await disposeMap(tester);
  });

  testWidgets('a failed refresh cannot reuse the previous successful fix', (
    tester,
  ) async {
    var calls = 0;
    await mount(
      tester,
      LocationMapPage(
        captureClassLocation: true,
        tileProvider: MemoryTiles(),
        locationLoader: () async {
          if (++calls > 1) throw ApiException('Không có tín hiệu GPS');
          return fix();
        },
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.byTooltip('Cập nhật GPS'));
    await tester.pumpAndSettle();
    expect(find.text('Không có tín hiệu GPS'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await disposeMap(tester);
  });

  testWidgets(
    'student map gets GPS automatically while keeping the class center fixed',
    (tester) async {
      var calls = 0;
      await mount(
        tester,
        LocationMapPage(
          target: const LatLng(10.762622, 106.660172),
          tileProvider: MemoryTiles(),
          locationLoader: () async {
            calls++;
            return fix();
          },
        ),
      );
      expect(calls, 1);
      expect(find.textContaining('Trong vùng điểm danh'), findsOneWidget);
      expect(
        tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap,
        isNull,
      );
      expect(find.byType(FilledButton), findsNothing);
      await disposeMap(tester);
    },
  );

  testWidgets('returning from settings automatically refreshes GPS', (
    tester,
  ) async {
    var calls = 0;
    await mount(
      tester,
      LocationMapPage(
        captureClassLocation: true,
        tileProvider: MemoryTiles(),
        locationLoader: () async {
          calls++;
          return fix(latitude: calls == 1 ? 10.762622 : 10.77);
        },
      ),
    );
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Vị trí lớp: 10.770000, 106.660172'), findsOneWidget);
    await disposeMap(tester);
  });

  testWidgets('historical report never requests or substitutes current GPS', (
    tester,
  ) async {
    var calls = 0;
    await mount(
      tester,
      LocationMapPage(
        target: const LatLng(10.762622, 106.660172),
        tileProvider: MemoryTiles(),
        allowDeviceLocation: false,
        locationLoader: () async {
          calls++;
          return fix();
        },
        recordedLocation: const MapLocation(
          LatLng(10.77, 106.67),
          8,
          'Điểm danh 21/10/2026',
        ),
      ),
    );
    expect(calls, 0);
    expect(find.byTooltip('Cập nhật GPS'), findsNothing);
    expect(
      find.textContaining('Điểm danh 21/10/2026: 10.770000'),
      findsOneWidget,
    );
    expect(find.textContaining('Ngoài vùng điểm danh'), findsOneWidget);
    await disposeMap(tester);
  });

  testWidgets(
    'tile retry retains the GPS position and never enables map selection',
    (tester) async {
      await mount(
        tester,
        LocationMapPage(
          captureClassLocation: true,
          tileProvider: MemoryTiles(),
          locationLoader: () async => fix(),
        ),
      );
      final tiles = tester.widget<TileLayer>(find.byType(TileLayer));
      tiles.errorTileCallback!(
        UnusedTile(),
        Exception('offline'),
        StackTrace.current,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa tải được bản đồ'), findsOneWidget);
      await tester.tap(find.text('Tải lại'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa tải được bản đồ'), findsNothing);
      expect(find.text('Vị trí lớp: 10.762622, 106.660172'), findsOneWidget);
      expect(
        tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap,
        isNull,
      );
      await disposeMap(tester);
    },
  );
}
