// lib/main.dart
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:math' as math;

void main() => runApp(const MyApp());
// BLE UUIDs
final SERVICE_UUID = Uuid.parse("0000FFF0-0000-1000-8000-00805f9b34fb");
final CHAR_READ = Uuid.parse("0000FFF1-0000-1000-8000-00805f9b34fb");
final CHAR_WRITE = Uuid.parse("0000FFF2-0000-1000-8000-00805f9b34fb");
// ----- CRC8-CCITT Implementation -----
const List<int> _crc8Table = [
  0x00,
  0x5e,
  0xbc,
  0xe2,
  0x61,
  0x3f,
  0xdd,
  0x83,
  0xc2,
  0x9c,
  0x7e,
  0x20,
  0xa3,
  0xfd,
  0x1f,
  0x41,
  0x9d,
  0xc3,
  0x21,
  0x7f,
  0xfc,
  0xa2,
  0x40,
  0x1e,
  0x5f,
  0x01,
  0xe3,
  0xbd,
  0x3e,
  0x60,
  0x82,
  0xdc,
  0x23,
  0x7d,
  0x9f,
  0xc1,
  0x42,
  0x1c,
  0xfe,
  0xa0,
  0xe1,
  0xbf,
  0x5d,
  0x03,
  0x80,
  0xde,
  0x3c,
  0x62,
  0xbe,
  0xe0,
  0x02,
  0x5c,
  0xdf,
  0x81,
  0x63,
  0x3d,
  0x7c,
  0x22,
  0xc0,
  0x9e,
  0x1d,
  0x43,
  0xa1,
  0xff,
  0x46,
  0x18,
  0xfa,
  0xa4,
  0x27,
  0x79,
  0x9b,
  0xc5,
  0x84,
  0xda,
  0x38,
  0x66,
  0xe5,
  0xbb,
  0x59,
  0x07,
  0xdb,
  0x85,
  0x67,
  0x39,
  0xba,
  0xe4,
  0x06,
  0x58,
  0x19,
  0x47,
  0xa5,
  0xfb,
  0x78,
  0x26,
  0xc4,
  0x9a,
  0x65,
  0x3b,
  0xd9,
  0x87,
  0x04,
  0x5a,
  0xb8,
  0xe6,
  0xa7,
  0xf9,
  0x1b,
  0x45,
  0xc6,
  0x98,
  0x7a,
  0x24,
  0xf8,
  0xa6,
  0x44,
  0x1a,
  0x99,
  0xc7,
  0x25,
  0x7b,
  0x3a,
  0x64,
  0x86,
  0xd8,
  0x5b,
  0x05,
  0xe7,
  0xb9,
  0x8c,
  0xd2,
  0x30,
  0x6e,
  0xed,
  0xb3,
  0x51,
  0x0f,
  0x4e,
  0x10,
  0xf2,
  0xac,
  0x2f,
  0x71,
  0x93,
  0xcd,
  0x11,
  0x4f,
  0xad,
  0xf3,
  0x70,
  0x2e,
  0xcc,
  0x92,
  0xd3,
  0x8d,
  0x6f,
  0x31,
  0xb2,
  0xec,
  0x0e,
  0x50,
  0xaf,
  0xf1,
  0x13,
  0x4d,
  0xce,
  0x90,
  0x72,
  0x2c,
  0x6d,
  0x33,
  0xd1,
  0x8f,
  0x0c,
  0x52,
  0xb0,
  0xee,
  0x32,
  0x6c,
  0x8e,
  0xd0,
  0x53,
  0x0d,
  0xef,
  0xb1,
  0xf0,
  0xae,
  0x4c,
  0x12,
  0x91,
  0xcf,
  0x2d,
  0x73,
  0xca,
  0x94,
  0x76,
  0x28,
  0xab,
  0xf5,
  0x17,
  0x49,
  0x08,
  0x56,
  0xb4,
  0xea,
  0x69,
  0x37,
  0xd5,
  0x8b,
  0x57,
  0x09,
  0xeb,
  0xb5,
  0x36,
  0x68,
  0x8a,
  0xd4,
  0x95,
  0xcb,
  0x29,
  0x77,
  0xf4,
  0xaa,
  0x48,
  0x16,
  0xe9,
  0xb7,
  0x55,
  0x0b,
  0x88,
  0xd6,
  0x34,
  0x6a,
  0x2b,
  0x75,
  0x97,
  0xc9,
  0x4a,
  0x14,
  0xf6,
  0xa8,
  0x74,
  0x2a,
  0xc8,
  0x96,
  0x15,
  0x4b,
  0xa9,
  0xf7,
  0xb6,
  0xe8,
  0x0a,
  0x54,
  0xd7,
  0x89,
  0x6b,
  0x35,
];
int crc8Ccitt(List<int> bytes) {
  int crc = 0x00;
  for (final b in bytes) {
    crc = _crc8Table[(crc ^ (b & 0xFF)) & 0xFF];
  }
  return crc & 0xFF;
}

Uint8List buildPacket(int token, List<int> data) {
  final buf = <int>[0xA5, token & 0xFF, data.length & 0xFF];
  buf.addAll(data);
  buf.add(crc8Ccitt(buf));
  return Uint8List.fromList(buf);
}

bool validatePacket(List<int> packet) {
  if (packet.length < 4) return false;
  final payload = packet.sublist(0, packet.length - 1);
  final crc = packet.last & 0xFF;
  return crc8Ccitt(payload) == crc;
}

// ----- App -----
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PC-80B ECG',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0B10),
        primaryColor: Colors.greenAccent,
      ),
      home: const EcgHomePage(),
    );
  }
}

class EcgHomePage extends StatefulWidget {
  const EcgHomePage({super.key});
  @override
  State<EcgHomePage> createState() => _EcgHomePageState();
}

enum DeviceState {
  idle,
  scanning,
  connecting,
  handshaking,
  ready,
  measuring,
  completed,
  disconnected,
  error,
}

class _EcgHomePageState extends State<EcgHomePage> {
  final _ble = FlutterReactiveBle();
  final List<String> _logV = [];
  final List<int> _recvBuffer = [];
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _heartbeatTimer;
  DiscoveredDevice? _selectedDevice;
  DeviceState _state = DeviceState.idle;
  // ECG data
  final ListQueue<double> _ecgBuffer = ListQueue();
  final int _samplingHz = 150;
  final double _secondsToShow = 5.0;
  late final int _bufferCapacity;
  // Metrics
  int? _heartRate;
  bool _leadOff = false;
  double _batteryMv = 0.0;
  String _measureStage = 'idle';
  // ADC calibration (per protocol: 12-bit ADC, adjust for actual mV)
  double _adcToMv = 0.005; // 1 ADC count ≈ 0.005 mV (default; hidden from UI)
  double _ampMultiplier = 1.0; // Runtime amplitude from device (x0.5/x1/x2/x4)
  // Full recording
  final List<double> _collectedSamples = [];
  int _lastSeqNo = -1;
  @override
  void initState() {
    super.initState();
    _bufferCapacity = (_samplingHz * _secondsToShow).toInt();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  void _cleanup() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _notifySub?.cancel();
    _heartbeatTimer?.cancel();
  }

  void _log(String msg) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    setState(() {
      _logV.insert(0, '[$timestamp] $msg');
      if (_logV.length > 200) _logV.removeLast();
    });
    debugPrint(msg);
  }

  // ----- Scanning -----
  Future<void> _startScan() async {
    _log('🔍 Starting scan...');
    setState(() {
      _state = DeviceState.scanning;
      _selectedDevice = null;
    });
    _scanSub?.cancel();
    _scanSub = _ble
        .scanForDevices(
          withServices: [SERVICE_UUID],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (device) {
            if (_selectedDevice == null &&
                (device.name.contains('PC80B') ||
                    device.serviceUuids.contains(SERVICE_UUID))) {
              _log('📱 Found: ${device.name} (${device.id})');
              setState(() => _selectedDevice = device);
              _scanSub?.cancel();
            }
          },
          onError: (e) {
            _log('❌ Scan error: $e');
            setState(() => _state = DeviceState.error);
          },
        );
  }

  // ----- Connection -----
  Future<void> _connect() async {
    if (_selectedDevice == null) return;
    _log('🔗 Connecting to ${_selectedDevice!.name}...');
    setState(() => _state = DeviceState.connecting);
    _connSub?.cancel();
    _connSub = _ble
        .connectToDevice(id: _selectedDevice!.id)
        .listen(
          (update) {
            _log('Connection state: ${update.connectionState}');
            if (update.connectionState == DeviceConnectionState.connected) {
              _onConnected();
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              _onDisconnected();
            }
          },
          onError: (e) {
            _log('❌ Connection error: $e');
            setState(() => _state = DeviceState.error);
          },
        );
  }

  void _onConnected() {
    _log('✅ Connected!');
    setState(() => _state = DeviceState.handshaking);
    _subscribeNotifications();
    _startHandshake();
  }

  void _onDisconnected() {
    _log('🔌 Disconnected');
    _cleanup();
    setState(() {
      _state = DeviceState.disconnected;
      _selectedDevice = null;
    });
  }

  // ----- Notifications -----
  void _subscribeNotifications() {
    if (_selectedDevice == null) return;
    _notifySub?.cancel();
    final char = QualifiedCharacteristic(
      deviceId: _selectedDevice!.id,
      serviceId: SERVICE_UUID,
      characteristicId: CHAR_READ,
    );
    _notifySub = _ble.subscribeToCharacteristic(char).listen((data) {
      _recvBuffer.addAll(data);
      _parsePackets();
    }, onError: (e) => _log('❌ Notify error: $e'));
  }

  // ----- Handshake Flow -----
  Future<void> _startHandshake() async {
    // Step 1: Send version query (0x11)
    await Future.delayed(const Duration(milliseconds: 200));
    await _write(buildPacket(0x11, [0x00, 0x00, 0x00]));
    _log('📤 Sent version query (0x11)');
    // Step 2: Start heartbeat (per protocol: 1 packet/second)
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state != DeviceState.disconnected && _state != DeviceState.idle) {
        _write(buildPacket(0xFF, [0x00]));
      }
    });
  }

  // ----- Packet Parsing -----
  void _parsePackets() {
    while (true) {
      if (_recvBuffer.length < 4) return;
      final headIdx = _recvBuffer.indexOf(0xA5);
      if (headIdx == -1) {
        _recvBuffer.clear();
        return;
      }
      if (headIdx > 0) {
        _recvBuffer.removeRange(0, headIdx);
      }
      if (_recvBuffer.length < 4) return;
      final token = _recvBuffer[1];
      final len = _recvBuffer[2];
      final total = 3 + len + 1;
      if (_recvBuffer.length < total) return;
      final packet = _recvBuffer.sublist(0, total);
      _recvBuffer.removeRange(0, total);
      _log(
        'Raw packet: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
      if (!validatePacket(packet)) {
        _log('❌ CRC fail for token 0x${token.toRadixString(16)}');
        continue;
      }
      _handlePacket(Uint8List.fromList(packet));
    }
  }

  void _handlePacket(Uint8List packet) {
    final token = packet[1];
    final len = packet[2];
    final data = packet.sublist(3, 3 + len);
    switch (token) {
      case 0xFF:
        _handleHeartbeat(data);
        break;
      case 0x11:
        _handleVersionReply(data);
        break;
      case 0x33:
        _handleTimeSyncRequest(data);
        break;
      case 0x55:
        _handleConfig(data);
        break;
      case 0xAA:
        _handleDataFrame(data);
        break;
      case 0xDD:
        _handleTracking(data);
        break;
      default:
        _log('Unknown token: 0x${token.toRadixString(16)}');
    }
  }

  // ----- Packet Handlers -----
  void _handleHeartbeat(List<int> data) {
    if (data.isNotEmpty) {
      final batLevel = data[0] & 0x0F;
      _log('💓 Heartbeat OK (battery level: $batLevel)');
    }
  }

  void _handleVersionReply(List<int> data) {
    _log(
      '📋 Version: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
    );
    setState(() => _state = DeviceState.ready);
    _log('✅ Device ready!');
  }

  Future<void> _handleTimeSyncRequest(List<int> data) async {
    _log('🕒 Time sync request from device');
    final now = DateTime.now();
    final sec = now.second;
    final min = now.minute;
    final hour = now.hour;
    final date = now.day;
    final month = now.month;
    final year = now.year;
    final yearLo = year & 0xFF;
    final yearHi = year >> 8;
    final weekday =
        now.weekday; // 1=Monday to 7=Sunday; adjust if needed (doc: 0-7)
    final timeData = [sec, min, hour, date, month, yearLo, yearHi, weekday];
    await _write(buildPacket(0x33, timeData));
    _log('📤 Sent time sync response');
  }

  Future<void> _handleConfig(List<int> data) async {
    if (data.length >= 14) {
      final model = data[0];
      final filterType = data[1];
      _log(
        '⚙️ Config: model=0x${model.toRadixString(16)}, filter=0x${filterType.toRadixString(16)}',
      );
      await _write(buildPacket(0x55, [0x00]));
      _log('📤 Sent config ACK (0x55)');
    }
  }

  void _handleTracking(List<int> data) {
    if (data.length < 6) return;
    final segNo = data[0];
    final measStatus = data[3];
    final info = (data[5] << 8) | data[4];
    _measureStage = _decodeMeasureStatus(measStatus);
    _leadOff = (info & 0x8000) != 0;
    final ampBits = (info >> 12) & 0x7;
    _ampMultiplier = _getAmpMultiplier(ampBits);
    final dataStruct = (info >> 8) & 0x07;
    if (dataStruct == 1 && data.length >= 56) {
      // 25 samples (structure-1)
      final ecgBytes = data.sublist(6);
      for (int i = 0; i + 1 < ecgBytes.length && i < 50; i += 2) {
        int val = (ecgBytes[i + 1] << 8) | ecgBytes[i];
        val &= 0x0FFF;
        final mv = val * _adcToMv * _ampMultiplier;
        _pushSample(mv);
      }
      _log('📊 Tracking seg:$segNo stage:$_measureStage samples:25');
    } else if (dataStruct == 2 && data.length >= 15) {
      // Analysis result (structure-2)
      final hr = data[13];
      final resultCode = data[14];
      _heartRate = hr;
      final analysisText = _getAnalysisText(resultCode);
      _log('📈 Analysis: HR=$hr, result=$resultCode ($analysisText)');
      _onMeasurementComplete(hr, resultCode, analysisText);
    }
    setState(() {});
  }

  void _handleDataFrame(List<int> data) {
    if (data.isEmpty) return;
    final seq = data[0];
    final payload = data.sublist(1);
    // Real-time data (structure per protocol 4.2.2)
    if (payload.length >= 53) {
      // 25 samples (50 bytes) + HR (1) + leadBattery (2)
      final hr = payload[50];
      final leadBatLo = payload[51];
      final leadBatHi = payload[52];
      final info = (leadBatHi << 8) | leadBatLo;
      _leadOff = (info & 0x8000) != 0;
      final ampBits = (info >> 12) & 0x7;
      _ampMultiplier = _getAmpMultiplier(ampBits);
      _batteryMv = (info & 0x0FFF).toDouble();
      // Process samples with multiplier
      for (int i = 0; i < 25; i++) {
        final lo = payload[i * 2];
        final hi = payload[i * 2 + 1];
        int val = (hi << 8) | lo;
        val &= 0x0FFF;
        final mv = val * _adcToMv * _ampMultiplier;
        _pushSample(mv);
      }
      _heartRate = hr;
      // Send ACK
      _write(buildPacket(0xAA, [seq, 0x00]));
      if (_lastSeqNo != seq) {
        _log('📡 Real-time seq:$seq HR:$hr battery:${_batteryMv.toInt()}mV');
        _lastSeqNo = seq;
      }
      setState(() {});
    }
  }

  double _getAmpMultiplier(int ampBits) {
    switch (ampBits) {
      case 0x0:
        return 0.5; // x1/2
      case 0x1:
        return 1.0; // x1
      case 0x2:
        return 2.0; // x2
      case 0x4:
        return 4.0; // x4
      default:
        return 1.0; // fallback
    }
  }

  // ----- Sample Management -----
  void _pushSample(double mv) {
    if (mv.isNaN || mv.isInfinite) return;
    if (mv.abs() < 0.02) return; // basic noise filter
    // Add to collected buffer (full recording)
    _collectedSamples.add(mv);
    // Maintain live display buffer
    if (_ecgBuffer.length >= _bufferCapacity) {
      _ecgBuffer.removeFirst();
    }
    _ecgBuffer.add(mv);
  }

  // ----- Measurement Control -----
  // NOTE: Removed user-triggered start measurement button.
  // The device will drive measurement and send structure-2 result packets
  // which will call _onMeasurementComplete(...).
  void _onMeasurementComplete(int? hr, int resultCode, String analysisText) {
    setState(() {
      _state = DeviceState.completed;
      _heartRate = hr;
    });
    // Show full-width dialog with scrollable waveform inside
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final screenW = MediaQuery.of(context).size.width;
        final dialogWidth = screenW;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final scrollController = ScrollController();
            double sliderValue = 0.0;
            final totalWidth = _calcScrollableWidth();
            final visibleWidth =
                screenW - 24.0; // Approx, accounting for padding
            final maxSlider = (totalWidth - visibleWidth).clamp(
              0.0,
              double.infinity,
            );

            // Listener to sync slider with manual scroll
            scrollController.addListener(() {
              setDialogState(() {
                sliderValue = scrollController.offset.clamp(0.0, maxSlider);
              });
            });

            return Dialog(
              insetPadding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              child: Container(
                width: dialogWidth,
                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 40),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0B10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Text(
                            '📊 Measurement Complete',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            color: Colors.white70,
                            onPressed: () {
                              Navigator.of(context).pop();
                              setState(() => _state = DeviceState.ready);
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Heart Rate: ${hr ?? '--'} bpm',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Result: ${_getAnalysisText(resultCode)}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('Samples: ${_collectedSamples.length}'),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    // Scrollable waveform area
                    SizedBox(
                      height: 220,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            color: Colors.black,
                            child: SingleChildScrollView(
                              controller: scrollController,
                              scrollDirection: Axis.horizontal,
                              child: CustomPaint(
                                size: Size(totalWidth, 220),
                                painter: ScrollableEcgPainter(
                                  List<double>.from(_collectedSamples),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Slider for controlling the scroll
                    if (maxSlider >
                        0) // Only show if waveform is wider than visible area
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Slider(
                          value: sliderValue,
                          min: 0.0,
                          max: maxSlider,
                          onChanged: (newValue) {
                            setDialogState(() {
                              sliderValue = newValue;
                            });
                            scrollController.jumpTo(newValue);
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    // actions
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              setState(() => _state = DeviceState.ready);
                            },
                            child: const Text('OK'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                              setState(() => _state = DeviceState.ready);
                            },
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  double _calcScrollableWidth() {
    // px per sample for horizontal scroll; adjust for density and readability
    const pxPerSample = 2.0; // small value makes waveform wider; tune as needed
    final w = (_collectedSamples.length * pxPerSample).clamp(300.0, 50000.0);
    return w;
  }

  // ----- Helper Methods -----
  String _decodeMeasureStatus(int b) {
    final stage = b & 0x0F;
    const stages = [
      'detecting',
      'preparing',
      'measuring',
      'analysing',
      'reporting',
      'tracking_end',
    ];
    return stage < stages.length ? stages[stage] : 'stage_$stage';
  }

  String _getAnalysisText(int code) {
    const mapping = {
      0: 'No irregular rhythm found',
      1: 'Suspected a little fast beat',
      2: 'Suspected fast beat',
      3: 'Suspected short run of fast beat',
      4: 'Suspected a little slow beat',
      5: 'Suspected slow beat',
      6: 'Suspected short beat interval',
      7: 'Suspected irregular beat interval',
      8: 'Suspected fast beat with short beat interval',
      9: 'Suspected slow beat with short beat interval',
      10: 'Suspected slow beat with irregular beat interval',
      11: 'Waveform baseline wander',
      12: 'Suspected fast beat with baseline wander',
      13: 'Suspected slow beat with baseline wander',
      14: 'Suspected short beat interval with baseline wander',
      15: 'Suspected irregular beat interval with baseline wander',
      16: 'Poor Signal, please try again',
    };
    return mapping[code] ?? 'Result $code';
  }

  Future<void> _write(Uint8List bytes) async {
    if (_selectedDevice == null) return;
    try {
      await _ble.writeCharacteristicWithResponse(
        QualifiedCharacteristic(
          deviceId: _selectedDevice!.id,
          serviceId: SERVICE_UUID,
          characteristicId: CHAR_WRITE,
        ),
        value: bytes.toList(),
      );
    } catch (e) {
      _log('❌ Write error: $e');
    }
  }

  Future<void> _disconnect() async {
    if (_selectedDevice == null) return;
    _log('🔌 Disconnecting...');
    try {
      _notifySub?.cancel();
      await _connSub
          ?.cancel(); // cancels the connectToDevice subscription => disconnect
      _scanSub?.cancel();
    } catch (e) {
      _log('❌ Disconnect error: $e');
    } finally {
      _cleanup();
      setState(() {
        _state = DeviceState.disconnected;
        _selectedDevice = null;
      });
    }
  }

  // ----- UI -----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PC-80B ECG Monitor'),
        backgroundColor: Colors.black87,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildControlPanel(),
            _buildWaveformCard(),
            _buildMetricsCard(),
            _buildLogPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Card(
      margin: const EdgeInsets.all(8),
      color: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('Scan'),
                    onPressed: _state == DeviceState.idle ? _startScan : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.bluetooth),
                    label: const Text('Connect'),
                    onPressed:
                        _selectedDevice != null &&
                            (_state == DeviceState.scanning ||
                                _state == DeviceState.disconnected)
                        ? _connect
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                // Measure button removed per request (device triggers measurement)
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: const Text(
                      'Measurement triggered from ECG device',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildStatusChip(_state.name, _getStateColor(_state)),
                const SizedBox(width: 8),
                if (_selectedDevice != null)
                  Expanded(
                    child: Text(
                      _selectedDevice!.name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(width: 8),
                if (_selectedDevice != null)
                  IconButton(
                    tooltip: 'Disconnect',
                    onPressed: _disconnect,
                    icon: const Icon(Icons.cancel, color: Colors.redAccent),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStateColor(DeviceState state) {
    switch (state) {
      case DeviceState.ready:
      case DeviceState.completed:
        return Colors.green;
      case DeviceState.measuring:
        return Colors.blue;
      case DeviceState.error:
      case DeviceState.disconnected:
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Widget _buildWaveformCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.black,
      child: Container(
        height: 240,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ECG Waveform ${_leadOff ? "⚠️ LEAD OFF" : ""}',
              style: TextStyle(
                color: _leadOff ? Colors.red : Colors.white70,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: CustomPaint(
                painter: LiveEcgPainter(_ecgBuffer.toList()),
                child: Container(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsCard() {
    return Card(
      margin: const EdgeInsets.all(8),
      color: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetric('HR', '${_heartRate ?? '--'} bpm', Colors.red),
                _buildMetric(
                  'Battery',
                  '${_batteryMv.toInt()} mV',
                  Colors.blue,
                ),
                _buildMetric('Stage', _measureStage, Colors.orange),
              ],
            ),
            // Removed ADC slider per request; using default _adcToMv
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String title, String value, Color color) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildLogPanel() {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.all(8),
        color: Colors.black,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: Colors.black87,
              child: Row(
                children: [
                  const Text(
                    'Logs',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Clear logs',
                    onPressed: () => setState(() => _logV.clear()),
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _logV.isEmpty
                  ? const Center(
                      child: Text(
                        'No logs yet',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      reverse: false,
                      itemCount: _logV.length,
                      itemBuilder: (context, idx) {
                        final line = _logV[idx];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 6,
                          ),
                          child: Text(
                            line,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----- Live ECG Painter (used during measuring) -----
// Smooth-ish visual for live rendering; limited horizontal width (fits widget)
class LiveEcgPainter extends CustomPainter {
  final List<double> samples;
  LiveEcgPainter(this.samples);
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF050507);
    canvas.drawRect(Offset.zero & size, bg);
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.12)
      ..strokeWidth = 0.5;
    const double mmPerCell = 10;
    for (double x = 0; x <= size.width; x += mmPerCell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += mmPerCell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    // baseline
    final baseline = Paint()..color = Colors.white24;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      baseline,
    );
    if (samples.isEmpty) return;
    double minMv = samples.reduce(math.min);
    double maxMv = samples.reduce(math.max);
    double range = (maxMv - minMv);
    if (range < 0.5) {
      minMv = -1.5;
      maxMv = 1.5;
      range = 3.0;
    } else {
      final margin = range * 0.2;
      minMv -= margin;
      maxMv += margin;
      range = maxMv - minMv;
    }
    final sampleCount = samples.length;
    final dx = sampleCount > 1 ? size.width / (sampleCount - 1) : size.width;
    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final x = i * dx;
      final norm = (samples[i] - minMv) / range;
      final y = size.height - (norm * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.greenAccent;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant LiveEcgPainter oldDelegate) =>
      !listEquals(oldDelegate.samples, samples);
}

// ----- Scrollable ECG Painter (simple polyline) -----
// Used inside the result dialog for the full recording; scrollable horizontally.
// class ScrollableEcgPainter extends CustomPainter {
//   final List<double> samples;
//   ScrollableEcgPainter(this.samples);
//   @override
//   void paint(Canvas canvas, Size size) {
//     final bg = Paint()..color = Colors.black;
//     canvas.drawRect(Offset.zero & size, bg);
//     // baseline center
//     final baselinePaint = Paint()..color = Colors.white12;
//     canvas.drawLine(
//       Offset(0, size.height / 2),
//       Offset(size.width, size.height / 2),
//       baselinePaint,
//     );
//     if (samples.isEmpty) return;
//     double minMv = samples.reduce(math.min);
//     double maxMv = samples.reduce(math.max);
//     double range = (maxMv - minMv);
//     if (range < 0.5) {
//       minMv = -1.5;
//       maxMv = 1.5;
//       range = 3.0;
//     } else {
//       final margin = range * 0.2;
//       minMv -= margin;
//       maxMv += margin;
//       range = maxMv - minMv;
//     }
//     // Use px-per-sample proportional to width
//     final pxPerSample = size.width / (samples.length > 0 ? samples.length : 1);
//     final path = Path();
//     for (int i = 0; i < samples.length; i++) {
//       final x = i * pxPerSample;
//       final norm = (samples[i] - minMv) / range;
//       final y = size.height - (norm * size.height);
//       if (i == 0) {
//         path.moveTo(x, y);
//       } else {
//         path.lineTo(x, y);
//       }
//     }
//     final paint = Paint()
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 1.6
//       ..color = Colors.greenAccent;
//     canvas.drawPath(path, paint);
//   }

//   @override
//   bool shouldRepaint(covariant ScrollableEcgPainter oldDelegate) =>
//       !listEquals(oldDelegate.samples, samples);
// }

class ScrollableEcgPainter extends CustomPainter {
  final List<double> samples;
  final double pxPerSample;
  ScrollableEcgPainter(this.samples, {this.pxPerSample = 2.0});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.black;
    canvas.drawRect(Offset.zero & size, bg);

    final baselinePaint = Paint()..color = Colors.white12;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      baselinePaint,
    );

    if (samples.isEmpty) return;

    double minMv = samples.reduce(math.min);
    double maxMv = samples.reduce(math.max);
    double range = maxMv - minMv;
    if (range < 0.5) {
      minMv = -1.5;
      maxMv = 1.5;
      range = 3.0;
    }

    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final x = i * pxPerSample;
      final norm = (samples[i] - minMv) / range;
      final y = size.height - (norm * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.greenAccent;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ScrollableEcgPainter oldDelegate) =>
      oldDelegate.samples != samples;
}

// Helper: deep listEquals (for shouldRepaint)
bool listEquals(List<double>? a, List<double>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-9) return false;
  }
  return true;
}
