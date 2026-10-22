import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'device_services.dart';
import 'ui.dart';

LatLng? mapPoint(dynamic latitude, dynamic longitude) {
  final lat = num.tryParse('$latitude')?.toDouble();
  final lon = num.tryParse('$longitude')?.toDouble();
  if (lat == null ||
      lon == null ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat < -90 ||
      lat > 90 ||
      lon < -180 ||
      lon > 180) {
    return null;
  }
  return LatLng(lat, lon);
}

class GpsLocationResult {
  final Position position;
  final double radiusMeters;
  const GpsLocationResult(this.position, this.radiusMeters);
  LatLng get point => LatLng(position.latitude, position.longitude);
}

class MapLocation {
  final LatLng point;
  final double accuracy;
  final String label;
  const MapLocation(this.point, this.accuracy, this.label);
}

class LocationMapPage extends StatefulWidget {
  final String title;
  final LatLng? target;
  final double radiusMeters;
  final bool captureClassLocation, allowDeviceLocation;
  final MapLocation? recordedLocation;
  final Future<Position> Function()? locationLoader;
  // Tests can supply an in-memory tile provider without network requests.
  final TileProvider? tileProvider;
  const LocationMapPage({
    this.title = 'Bản đồ vị trí',
    this.target,
    this.radiusMeters = 100,
    this.captureClassLocation = false,
    this.allowDeviceLocation = true,
    this.recordedLocation,
    this.locationLoader,
    this.tileProvider,
    super.key,
  });
  @override
  State<LocationMapPage> createState() => _LocationMapPageState();
}

class _LocationMapPageState extends State<LocationMapPage>
    with WidgetsBindingObserver {
  final controller = MapController();
  late LatLng? target = widget.target;
  late double radius = widget.radiusMeters.isFinite
      ? widget.radiusMeters.clamp(10, 500).toDouble()
      : 100;
  late MapLocation? location = widget.recordedLocation;
  bool locating = false, tileError = false;
  int tileAttempt = 0;
  String? error;
  Position? currentPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.allowDeviceLocation && widget.recordedLocation == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) locate();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.allowDeviceLocation &&
        widget.recordedLocation == null &&
        !locating) {
      locate();
    }
  }

  bool get canConfirm =>
      !locating &&
      currentPosition != null &&
      DeviceServices.locationProblem(currentPosition!) == null;

  void confirmGps() {
    final position = currentPosition;
    if (position == null) return;
    final problem = DeviceServices.locationProblem(position);
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    Navigator.pop(context, GpsLocationResult(position, radius));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  Future<void> locate() async {
    if (locating) return;
    setState(() {
      locating = true;
      error = null;
      currentPosition = null;
      location = null;
    });
    try {
      final position =
          await (widget.locationLoader ?? DeviceServices.location)();
      if (!mounted) return;
      final point = mapPoint(position.latitude, position.longitude);
      if (point == null ||
          !position.accuracy.isFinite ||
          position.accuracy <= 0) {
        throw Exception('GPS chưa trả về vị trí hợp lệ. Hãy thử lại.');
      }
      setState(() {
        location = MapLocation(point, position.accuracy, 'Vị trí GPS của tôi');
        currentPosition = position;
        error = DeviceServices.locationProblem(position);
        if (widget.captureClassLocation) target = point;
      });
      if (target != null && !widget.captureClassLocation) {
        controller.fitCamera(cameraFit(target!, point));
      } else {
        controller.move(point, 17);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void tileFailed() {
    if (tileError || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !tileError) setState(() => tileError = true);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  CameraFit cameraFit(LatLng first, LatLng second) => CameraFit.bounds(
    bounds: LatLngBounds.fromPoints([first, second]),
    padding: const EdgeInsets.fromLTRB(55, 100, 55, 55),
    maxZoom: 17,
  );

  Widget marker(LatLng point, String label, IconData icon, Color color) =>
      MarkerLayer(
        markers: [
          Marker(
            point: point,
            width: 40,
            height: 40,
            alignment: icon == Icons.location_on
                ? Alignment.topCenter
                : Alignment.center,
            rotate: true,
            child: Tooltip(
              message: label,
              child: Icon(
                icon,
                color: color,
                size: 40,
                shadows: const [Shadow(color: Colors.white, blurRadius: 5)],
              ),
            ),
          ),
        ],
      );

  String get distanceMessage {
    final sample = location!;
    final distance = Geolocator.distanceBetween(
      target!.latitude,
      target!.longitude,
      sample.point.latitude,
      sample.point.longitude,
    );
    final description = sample.accuracy > 50
        ? 'GPS chưa đủ chính xác để điểm danh'
        : distance + sample.accuracy <= radius
        ? 'Trong vùng điểm danh'
        : distance - sample.accuracy > radius
        ? 'Ngoài vùng điểm danh'
        : 'Gần ranh giới vùng điểm danh; hãy lấy lại GPS';
    return 'Cách lớp ${distance.toStringAsFixed(0)} m · $description';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: controller,
                  options: MapOptions(
                    initialCenter:
                        target ?? location?.point ?? const LatLng(16.05, 108.2),
                    initialZoom: target != null || location != null ? 16 : 5,
                    initialCameraFit: target != null && location != null
                        ? cameraFit(target!, location!.point)
                        : null,
                    minZoom: 3,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      key: ValueKey(tileAttempt),
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'vn.edu.attendly.attendly',
                      tileProvider: widget.tileProvider,
                      panBuffer: 0,
                      maxNativeZoom: 19,
                      errorTileCallback: (_, _, _) => tileFailed(),
                    ),
                    if (target != null) ...[
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: target!,
                            radius: radius,
                            useRadiusInMeter: true,
                            color: teal.withValues(alpha: .14),
                            borderColor: teal,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                      marker(
                        target!,
                        'Vị trí lớp học',
                        Icons.location_on,
                        teal,
                      ),
                    ],
                    if (location != null) ...[
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: location!.point,
                            radius: location!.accuracy,
                            useRadiusInMeter: true,
                            color: Colors.blue.withValues(alpha: .12),
                            borderColor: Colors.blue.withValues(alpha: .5),
                            borderStrokeWidth: 1,
                          ),
                        ],
                      ),
                      marker(
                        location!.point,
                        location!.label,
                        Icons.my_location,
                        Colors.blue,
                      ),
                    ],
                    SimpleAttributionWidget(
                      source: const Text(
                        'OpenStreetMap contributors',
                        style: TextStyle(fontSize: 11),
                      ),
                      onTap: () async {
                        try {
                          final opened = await launchUrl(
                            Uri.parse(
                              'https://www.openstreetmap.org/copyright',
                            ),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!opened && context.mounted) {
                            showError(
                              context,
                              'Không mở được liên kết bản quyền.',
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            showError(
                              context,
                              'Không mở được liên kết bản quyền.',
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        locating
                            ? 'Đang xác định vị trí GPS từ điện thoại…'
                            : widget.captureClassLocation
                            ? 'Tọa độ lớp được lấy từ GPS của điện thoại. Di chuyển bản đồ chỉ để xem.'
                            : widget.recordedLocation != null
                            ? 'Vị trí đã ghi nhận lúc điểm danh; không phải GPS hiện tại.'
                            : location == null
                            ? 'Chưa xác định được vị trí GPS. Hãy kiểm tra quyền vị trí.'
                            : 'Ghim xanh: lớp học · Chấm xanh dương: GPS điện thoại',
                        style: const TextStyle(color: navy),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 36,
                  child: Column(
                    children: [
                      if (target != null)
                        FloatingActionButton.small(
                          heroTag: 'class-location',
                          tooltip: 'Về vị trí lớp',
                          onPressed: () => controller.move(target!, 16),
                          child: const Icon(Icons.school_outlined),
                        ),
                      if (widget.allowDeviceLocation)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: FloatingActionButton.small(
                            heroTag: 'my-location',
                            tooltip: 'Cập nhật GPS',
                            onPressed: locating ? null : locate,
                            child: locating
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.my_location),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (tileError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Chưa tải được bản đồ. Kiểm tra Internet.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      tileError = false;
                      tileAttempt++;
                    }),
                    child: const Text('Tải lại'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locating)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(),
                  ),
                if (error != null) ...[
                  Text(error!, style: const TextStyle(color: Colors.red)),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: locating ? null : locate,
                        child: const Text('Thử lại GPS'),
                      ),
                      TextButton(
                        onPressed: () async {
                          await Geolocator.openLocationSettings();
                        },
                        child: const Text('Cài đặt vị trí'),
                      ),
                      TextButton(
                        onPressed: () async {
                          await Geolocator.openAppSettings();
                        },
                        child: const Text('Quyền ứng dụng'),
                      ),
                    ],
                  ),
                ],
                if (target != null)
                  Text(
                    'Vị trí lớp: ${target!.latitude.toStringAsFixed(6)}, ${target!.longitude.toStringAsFixed(6)}',
                  ),
                if (location != null) ...[
                  Text(
                    '${location!.label}: ${location!.point.latitude.toStringAsFixed(6)}, ${location!.point.longitude.toStringAsFixed(6)}',
                  ),
                  Text(
                    'Độ chính xác GPS: ±${location!.accuracy.toStringAsFixed(0)} m',
                  ),
                  if (target != null && !widget.captureClassLocation)
                    Text(
                      distanceMessage,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: teal,
                      ),
                    ),
                ] else if (widget.allowDeviceLocation)
                  Text(
                    locating
                        ? 'Đang chờ tín hiệu GPS…'
                        : 'Bật GPS và nhấn Cập nhật GPS để thử lại.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                if (widget.captureClassLocation) ...[
                  Text('Bán kính điểm danh: ${radius.round()} m'),
                  Slider(
                    value: radius,
                    min: 10,
                    max: 500,
                    divisions: 49,
                    label: '${radius.round()} m',
                    onChanged: (value) => setState(() => radius = value),
                  ),
                  FilledButton.icon(
                    onPressed: canConfirm ? confirmGps : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Xác nhận vị trí GPS'),
                  ),
                ] else ...[
                  if (target != null)
                    Text('Bán kính điểm danh: ${radius.round()} m'),
                  if (widget.recordedLocation == null)
                    const Text(
                      'Vị trí chỉ hiển thị trên máy; khi điểm danh, app sẽ lấy lại GPS.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
