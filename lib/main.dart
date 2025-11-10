// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PC-80B BLE ECG',
    theme: ThemeData.dark(),
    home: const EcgHomePage(),
  );
}

class EcgHomePage extends StatefulWidget {
  const EcgHomePage({super.key});
  @override
  State<EcgHomePage> createState() => _EcgHomePageState();
}

class _EcgHomePageState extends State<EcgHomePage> {
  final flutterReactiveBle = FlutterReactiveBle();
  final _scanStream = StreamController<DiscoveredDevice>.broadcast();
  final _log = <String>[];
  late final Uuid serviceUuid;
  late final Uuid charReadUuid;
  late final Uuid charWriteUuid;

  DiscoveredDevice? _selectedDevice;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifySub;

  // streaming parser buffer
  final List<int> _buffer = [];

  // UI fields
  int? heartRate;
  String status = 'idle';
  List<int> latestSamples = [];

  @override
  void initState() {
    super.initState();
    serviceUuid = Uuid.parse("0000FFF0-0000-1000-8000-00805f9b34fb");
    charReadUuid = Uuid.parse("0000FFF1-0000-1000-8000-00805f9b34fb");
    charWriteUuid = Uuid.parse("0000FFF2-0000-1000-8000-00805f9b34fb");
  }

  @override
  void dispose() {
    _scanStream.close();
    _connection?.cancel();
    _notifySub?.cancel();
    super.dispose();
  }

  void _appendLog(String s) {
    setState(() {
      _log.insert(0, "${DateTime.now().toIso8601String()} $s");
      if (_log.length > 200) _log.removeLast();
    });
  }

  Future<void> scanForDevices() async {
    _appendLog('Start scanning for PC80B...');
    setState(() => status = 'scanning');
    flutterReactiveBle
        .scanForDevices(
          withServices: [serviceUuid],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (device) {
            // pick devices that look like PC80B (advertised name may contain PC80B)
            if ((device.name?.contains('PC80B') ?? false) ||
                (device.name?.contains('PC-80B') ?? false) ||
                device.serviceUuids.contains(serviceUuid)) {
              _appendLog('Found device: ${device.name} ${device.id}');
              _scanStream.add(device);
            }
          },
          onError: (e) {
            _appendLog('Scan error: $e');
            setState(() => status = 'idle');
          },
        );
  }

  Future<void> connectTo(DiscoveredDevice device) async {
    _appendLog('Connecting to ${device.name} ${device.id}');
    setState(() {
      status = 'connecting';
      _selectedDevice = device;
    });

    _connection?.cancel();
    _connection = flutterReactiveBle
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 8),
        )
        .listen(
          (event) async {
            _appendLog('Connection state: ${event.connectionState}');
            if (event.connectionState == DeviceConnectionState.connected) {
              setState(() => status = 'connected');
              // subscribe to notifications
              _subscribeNotifications();
              // send query version packet to handshake
              _sendQueryVersion();
            } else if (event.connectionState ==
                DeviceConnectionState.disconnected) {
              _appendLog('Disconnected.');
              setState(() {
                status = 'disconnected';
                _selectedDevice = null;
              });
            }
          },
          onError: (e) {
            _appendLog('Connection error: $e');
            setState(() => status = 'idle');
          },
        );
  }

  // === Packet helpers ===

  /// Build packet: Head(0xA5) Token Length Data CRC
  Uint8List buildPacket(int token, List<int> data) {
    final len = data.length;
    final buf = <int>[];
    buf.add(0xA5);
    buf.add(token & 0xFF);
    buf.add(len & 0xFF);
    buf.addAll(data);
    final crc = computeCrc(buf); // CRC over Head..end of data
    buf.add(crc);
    return Uint8List.fromList(buf);
  }

  /// Default CRC: simple sum & 0xFF. If your device uses CRC-8 polynomial,
  /// replace computeCrc with the CRC-8 (poly=0x07) routine.
  int computeCrc(List<int> bytes) {
    // sum & 0xFF
    int s = 0;
    for (final b in bytes) s = (s + (b & 0xFF)) & 0xFF;
    return s;
  }

  bool validateCrc(List<int> packetBytes) {
    if (packetBytes.length < 4)
      return false; // must include head token len crc minimally
    final crcReceived = packetBytes.last;
    final payload = packetBytes.sublist(0, packetBytes.length - 1);
    final c = computeCrc(payload);
    return (c & 0xFF) == (crcReceived & 0xFF);
  }

  // === Send handshake/query ===

  void _sendQueryVersion() async {
    if (_selectedDevice == null) return;
    final q = buildPacket(0x11, [
      0x00,
      0x00,
      0x00,
    ]); // Host query packet sample (3 reserved bytes)
    await flutterReactiveBle.writeCharacteristicWithResponse(
      QualifiedCharacteristic(
        characteristicId: charWriteUuid,
        serviceId: serviceUuid,
        deviceId: _selectedDevice!.id,
      ),
      value: q,
    );
    _appendLog('Sent version query (0x11).');
  }

  void _sendConfigRealTime() async {
    // Device Model 0x80, Filter+Type: 0x00 = real-time, Device ID 12 bytes (all zeros if unknown)
    final deviceId = List<int>.filled(12, 0x00);
    final payload =
        <int>[0x80, 0x00] +
        deviceId; // length 14? protocol says 0x0E length (14)
    final packet = buildPacket(0x55, payload);
    await flutterReactiveBle.writeCharacteristicWithResponse(
      QualifiedCharacteristic(
        characteristicId: charWriteUuid,
        serviceId: serviceUuid,
        deviceId: _selectedDevice!.id,
      ),
      value: packet,
    );
    _appendLog('Sent config (0x55) real-time request.');
  }

  // === Subscribe to incoming notifications ===

  void _subscribeNotifications() {
    if (_selectedDevice == null) return;
    _notifySub?.cancel();
    final char = QualifiedCharacteristic(
      characteristicId: charReadUuid,
      serviceId: serviceUuid,
      deviceId: _selectedDevice!.id,
    );
    _notifySub = flutterReactiveBle
        .subscribeToCharacteristic(char)
        .listen(
          (data) {
            // data is List<int>
            _appendLog('raw received ${data.length} bytes');
            _feedBytes(data);
          },
          onError: (e) {
            _appendLog('Notification error: $e');
          },
        );
  }

  // Feed the streaming bytes into parser buffer and attempt to parse packets
  void _feedBytes(List<int> bytes) {
    _buffer.addAll(bytes);
    _parseBuffer();
  }

  void _parseBuffer() {
    // Loop trying to extract full packets
    while (true) {
      if (_buffer.length < 4) return; // need at least head, token, len, crc
      // find head 0xA5
      int headIndex = _buffer.indexOf(0xA5);
      if (headIndex == -1) {
        _buffer.clear();
        return;
      }
      if (headIndex > 0) {
        // drop bytes before head
        _buffer.removeRange(0, headIndex);
      }
      if (_buffer.length < 4) return;
      final token = _buffer[1];
      final len = _buffer[2];
      final totalLen = 3 + len + 1; // head+token+len + data(len) + crc(1)
      if (_buffer.length < totalLen) return; // wait for more bytes
      final packet = _buffer.sublist(0, totalLen);
      // remove packet from buffer
      _buffer.removeRange(0, totalLen);

      // validate CRC
      if (!validateCrc(packet)) {
        _appendLog(
          'CRC failed for token 0x${token.toRadixString(16)}. Dropping packet.',
        );
        continue;
      }

      // parse by token
      try {
        _handlePacket(Uint8List.fromList(packet));
      } catch (e) {
        _appendLog('Packet parse error: $e');
      }
    }
  }

  void _handlePacket(Uint8List packet) {
    final token = packet[1];
    final len = packet[2];
    final data = packet.sublist(3, 3 + len);
    switch (token) {
      case 0xFF:
        // heartbeat
        _appendLog('Heartbeat received.');
        break;
      case 0x11:
        // version reply
        final ver = data
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        _appendLog('Version packet: $ver');
        break;
      case 0x55:
        // configuration from device
        _appendLog('Config packet from device: ${data.length} bytes');
        // parse device model, filter/trans type, device id(12)
        if (data.length >= 14) {
          final devModel = data[0];
          final filterAndType = data[1];
          final devId = data.sublist(2, 14);
          final json = {
            'token': '0x55',
            'deviceModel': devModel,
            'filterAndType': filterAndType,
            'deviceId': base64Encode(devId),
          };
          _appendLog('Config JSON: ${jsonEncode(json)}');
        }
        break;
      case 0xDD:
        // real-time tracking packet (used during tracking mode)
        _parseTracking(data);
        break;
      case 0xAA:
        // data frame (non-real-time / data dump or real-time frames depending on session)
        _parseDataFrame(data);
        break;
      default:
        _appendLog('Unhandled token 0x${token.toRadixString(16)} len $len');
    }
  }

  void _parseTracking(Uint8List data) {
    // Format per protocol: SegNo(1), Info(2), MeasurementStatus(1), ECGdesc(2), ECG data (0..)
    if (data.length < 6) {
      _appendLog('Tracking packet too short: ${data.length}');
      return;
    }
    int segNo = data[0];
    int infoLow = data[1];
    int infoHigh = data[2];
    int info = (infoHigh << 8) | infoLow;
    int measStatus = data[3];
    int ecgDescLow = data[4];
    int ecgDescHigh = data[5];
    int ecgDesc = (ecgDescHigh << 8) | ecgDescLow;
    final ecgBytes = data.sublist(6);
    // If ecgDesc indicates structure-1 => 25 sampling points, each 2 bytes little endian
    List<int> samples = [];
    if (ecgBytes.length >= 50) {
      for (int i = 0; i + 1 < ecgBytes.length && samples.length < 25; i += 2) {
        int v = (ecgBytes[i + 1] << 8) | ecgBytes[i];
        // lower 12 bits valid per doc
        v &= 0x0FFF;
        samples.add(v);
      }
    }
    // Some tracking packets contain analysis result (structure-2) with time/HR/result
    Map<String, dynamic> parsed = {
      'token': '0xDD',
      'segNo': segNo,
      'info': info,
      'measStatus': measStatus,
      'ecgDesc': ecgDesc,
      'samplesCount': samples.length,
      'samplesBase64': base64Encode(
        Uint8List.fromList(
          samples.expand((s) {
            // pack each sample as 2 bytes little endian for storage
            final lo = s & 0xFF;
            final hi = (s >> 8) & 0xFF;
            return [lo, hi];
          }).toList(),
        ),
      ),
    };
    // If HR is embedded in analysis result later, we will parse that too
    _appendLog('Tracking JSON: ${jsonEncode(parsed)}');
    setState(() {
      latestSamples = samples;
    });
  }

  void _parseDataFrame(Uint8List data) {
    // Data frame begins with frame sequence number, then data block (SCP or real-time packet per session)
    if (data.isEmpty) return;
    final seq = data[0];
    final payload = data.sublist(1);
    // If this session is real-time streaming as defined in 4.2.2, the packet was token 0x55 with 0x36 length;
    // but some devices may send 0xAA for data frames. We'll attempt to detect 25*2+3 pattern.
    if (payload.length >= 25 * 2 + 3) {
      // interpret as waves: first 25*2 bytes = 25 samples
      List<int> samples = [];
      for (int i = 0; i + 1 < payload.length && samples.length < 25; i += 2) {
        int v = (payload[i + 1] << 8) | payload[i];
        v &= 0x0FFF;
        samples.add(v);
      }
      // last 3 bytes might be HR (1), lead status (1), battery (1 or 2)
      int hr = (payload.length > 25 * 2) ? payload[25 * 2] : 0;
      int leadStatus = (payload.length > 25 * 2 + 1) ? payload[25 * 2 + 1] : 0;
      int battery = (payload.length > 25 * 2 + 2) ? payload[25 * 2 + 2] : 0;
      final json = {
        'token': '0xAA',
        'seq': seq,
        'hr': hr,
        'leadStatus': leadStatus,
        'battery': battery,
        'samples': samples,
      };
      _appendLog('Realtime samples JSON: ${jsonEncode(json)}');
      setState(() {
        heartRate = hr;
        latestSamples = samples;
      });
    } else {
      // treat as chunk of SCP file / binary; base64 it
      final json = {
        'token': '0xAA',
        'seq': seq,
        'payloadBase64': base64Encode(payload),
      };
      _appendLog('Data chunk JSON: ${jsonEncode(json)}');
    }
  }

  // UI & controls

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PC-80B BLE ECG')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: scanForDevices,
                  icon: const Icon(Icons.search),
                  label: const Text('Scan BLE'),
                ),
                ElevatedButton.icon(
                  onPressed: _selectedDevice == null
                      ? null
                      : () => connectTo(_selectedDevice!),
                  icon: const Icon(Icons.bluetooth_connected),
                  label: const Text('Connect Selected'),
                ),
                ElevatedButton.icon(
                  onPressed: _selectedDevice == null
                      ? null
                      : _sendConfigRealTime,
                  icon: const Icon(Icons.settings_remote),
                  label: const Text('Request Real-Time'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      const Text('Discovered devices:'),
                      Expanded(
                        child: StreamBuilder<DiscoveredDevice>(
                          stream: _scanStream.stream,
                          builder: (context, snap) {
                            final list = <DiscoveredDevice>[];
                            if (snap.hasData) list.add(snap.data!);
                            return ListView(
                              children: list
                                  .map(
                                    (d) => ListTile(
                                      title: Text(
                                        d.name.isEmpty ? d.id : d.name,
                                      ),
                                      subtitle: Text(d.id),
                                      onTap: () =>
                                          setState(() => _selectedDevice = d),
                                      selected: _selectedDevice?.id == d.id,
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Text('Status: $status HR: ${heartRate ?? '--'}'),
                      if (latestSamples.isNotEmpty)
                        SizedBox(
                          height: 120,
                          child: CustomPaint(
                            painter: WavePainter(latestSamples),
                            size: const Size(double.infinity, 120),
                          ),
                        ),
                      const Divider(),
                      const Text('Log:'),
                      Expanded(
                        child: ListView.builder(
                          reverse: true,
                          itemCount: _log.length,
                          itemBuilder: (c, i) => Text(
                            _log[i],
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  final List<int> samples;
  WavePainter(this.samples);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    if (samples.isEmpty) return;
    final double w = size.width;
    final double h = size.height;
    final int n = samples.length;
    final double step = w / (n - 1);
    final maxVal = samples.reduce((a, b) => a > b ? a : b);
    final minVal = samples.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal).toDouble();
    final path = Path();
    for (int i = 0; i < n; i++) {
      final x = step * i;
      final normalized = range == 0 ? 0.5 : (samples[i] - minVal) / range;
      final y = h - normalized * h;
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) =>
      oldDelegate.samples != samples;
}
