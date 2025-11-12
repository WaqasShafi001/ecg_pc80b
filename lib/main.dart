// lib/main.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
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
  final List<String> _loggV = [];
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
  // Protocol specifies 5mm/mV display scale. Typical ECG: 1mV = ~200 ADC counts
  double _adcToMv = 0.005; // 1 ADC count ≈ 0.005 mV (adjust empirically)

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

  void _cleanup() async {
    _scanSub?.cancel();
    _connSub?.cancel();
    _notifySub?.cancel();
    _heartbeatTimer?.cancel();
    // Optionally attempt a disconnect if device is selected
    if (_selectedDevice != null) {
      try {
        // _ble.disconnectDevice(id: _selectedDevice!.id);
        await _ble.deinitialize();
      } catch (_) {}
    }
  }

  void _logg(String msg) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    setState(() {
      _loggV.insert(0, '[$timestamp] $msg');
      if (_loggV.length > 200) _loggV.removeLast();
    });
    debugPrint(msg);
  }

  // ----- Scanning -----
  Future<void> _startScan() async {
    _logg('🔍 Starting scan...');
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
              _logg('📱 Found: ${device.name} (${device.id})');
              setState(() => _selectedDevice = device);
              _scanSub?.cancel();
            }
          },
          onError: (e) {
            _logg('❌ Scan error: $e');
            setState(() => _state = DeviceState.error);
          },
        );
  }

  // ----- Connection -----
  Future<void> _connect() async {
    if (_selectedDevice == null) return;

    _logg('🔗 Connecting to ${_selectedDevice!.name}...');
    setState(() => _state = DeviceState.connecting);

    _connSub?.cancel();
    _connSub = _ble
        .connectToDevice(
          id: _selectedDevice!.id,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (update) {
            _logg('Connection state: ${update.connectionState}');

            if (update.connectionState == DeviceConnectionState.connected) {
              _onConnected();
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              _onDisconnected();
            }
          },
          onError: (e) {
            _logg('❌ Connection error: $e');
            setState(() => _state = DeviceState.error);
          },
        );
  }

  void _onConnected() {
    _logg('✅ Connected!');
    setState(() => _state = DeviceState.handshaking);
    _subscribeNotifications();
    _startHandshake();
  }

  void _onDisconnected() {
    _logg('🔌 Disconnected');
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
    }, onError: (e) => _logg('❌ Notify error: $e'));
  }

  // ----- Handshake Flow -----
  Future<void> _startHandshake() async {
    // Step 1: Send version query (0x11)
    await Future.delayed(const Duration(milliseconds: 200));
    await _write(buildPacket(0x11, [0x00, 0x00, 0x00]));
    _logg('📤 Sent version query (0x11)');

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

      if (!validatePacket(packet)) {
        _logg('❌ CRC fail for token 0x${token.toRadixString(16)}');
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
        _handleHandshake33(data);
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
        _logg('Unknown token: 0x${token.toRadixString(16)}');
    }
  }

  // ----- Packet Handlers -----
  void _handleHeartbeat(List<int> data) {
    // Device responded to heartbeat - connection alive
    if (data.isNotEmpty) {
      final batLevel = data[0] & 0x0F;
      _logg('💓 Heartbeat OK (battery level: $batLevel)');
    }
  }

  void _handleVersionReply(List<int> data) {
    _logg(
      '📋 Version: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
    );

    // After version, move to ready state
    setState(() => _state = DeviceState.ready);
    _logg('✅ Device ready!');
  }

  Future<void> _handleHandshake33(List<int> data) async {
    _logg('🤝 Handshake (0x33) from device');

    // Respond with ACK
    await _write(buildPacket(0x33, [0x00]));
    _logg('📤 Sent handshake ACK (0x33)');
  }

  Future<void> _handleConfig(List<int> data) async {
    if (data.length >= 14) {
      final model = data[0];
      final filterType = data[1];
      _logg(
        '⚙️ Config: model=0x${model.toRadixString(16)}, filter=0x${filterType.toRadixString(16)}',
      );

      // Send ACK
      await _write(buildPacket(0x55, [0x00]));
      _logg('📤 Sent config ACK (0x55)');
    }
  }

  void _handleTracking(List<int> data) {
    if (data.length < 6) return;

    final segNo = data[0];
    final measStatus = data[3];
    final ecgDesc = (data[5] << 8) | data[4];

    _measureStage = _decodeMeasureStatus(measStatus);
    _leadOff = (ecgDesc & 0x8000) != 0;
    final dataStruct = (ecgDesc >> 8) & 0x07;

    if (dataStruct == 1 && data.length >= 56) {
      // 25 samples (structure-1)
      final ecgBytes = data.sublist(6);
      for (int i = 0; i + 1 < ecgBytes.length && i < 50; i += 2) {
        int val = (ecgBytes[i + 1] << 8) | ecgBytes[i];
        val &= 0x0FFF;
        final mv = val * _adcToMv;
        _pushSample(mv);
      }
      _logg('📊 Tracking seg:$segNo stage:$_measureStage samples:25');
    } else if (dataStruct == 2 && data.length >= 15) {
      // Analysis result (structure-2)
      final year = (data[7] << 8) | data[6];
      final hr = data[13];
      final resultCode = data[14];

      _heartRate = hr;
      final analysisText = _getAnalysisText(resultCode);

      _logg('📈 Analysis: HR=$hr, result=$resultCode ($analysisText)');
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
      for (int i = 0; i < 25; i++) {
        final lo = payload[i * 2];
        final hi = payload[i * 2 + 1];
        int val = (hi << 8) | lo;
        val &= 0x0FFF;
        final mv = val * _adcToMv;
        _pushSample(mv);
      }

      final hr = payload[50];
      final leadBatLo = payload[51];
      final leadBatHi = payload[52];
      final leadBat = (leadBatHi << 8) | leadBatLo;

      _heartRate = hr;
      _leadOff = (leadBat & 0x8000) != 0;
      _batteryMv = (leadBat & 0x0FFF).toDouble();

      // Send ACK
      _write(buildPacket(0xAA, [seq, 0x00]));

      if (_lastSeqNo != seq) {
        _logg('📡 Real-time seq:$seq HR:$hr battery:${_batteryMv.toInt()}mV');
        _lastSeqNo = seq;
      }

      setState(() {});
    }
  }

  // ----- Sample Management -----
  void _pushSample(double mv) {
    // Guard - skip obviously invalid noise
    if (mv.isNaN || mv.isInfinite) return;

    // small threshold to remove tiny noise
    if (mv.abs() < 0.02) return;

    _collectedSamples.add(mv);

    // Add to display buffer
    if (_ecgBuffer.length >= _bufferCapacity) {
      _ecgBuffer.removeFirst();
    }
    _ecgBuffer.add(mv);
  }

  // ----- Measurement Control -----
  Future<void> _startMeasurement() async {
    _logg('▶️ Starting measurement...');

    setState(() {
      _state = DeviceState.measuring;
      _ecgBuffer.clear();
      _collectedSamples.clear();
      _heartRate = null;
      _measureStage = 'preparing';
    });

    // Request real-time transmission (per protocol section 4.2.1)
    final deviceId = List<int>.filled(12, 0x00);
    final payload = [0x80, 0x00, ...deviceId]; // Model 0x80, Type 0x00
    await _write(buildPacket(0x55, payload));
    _logg('📤 Requested real-time mode (0x55)');
  }

  void _onMeasurementComplete(int? hr, int resultCode, String analysisText) {
    setState(() {
      _state = DeviceState.completed;
      _heartRate = hr;
    });

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('📊 Measurement Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Heart Rate: ${hr ?? '--'} bpm',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Result: $analysisText'),
            const SizedBox(height: 12),
            Text('Samples: ${_collectedSamples.length}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _state = DeviceState.ready);
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
        value: bytes,
      );
    } catch (e) {
      _logg('❌ Write error: $e');
    }
  }

  Future<void> _disconnect() async {
    if (_selectedDevice == null) return;
    _logg('🔌 Disconnecting...');
    try {
      // cancel streams & ask BLE to disconnect
      _scanSub?.cancel();
      _notifySub?.cancel();
      _connSub?.cancel();
      // await _ble.disconnectDevice(id: _selectedDevice!.id);
      await _ble.deinitialize();
    } catch (e) {
      _logg('❌ Disconnect error: $e');
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
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Measure'),
                    onPressed: _state == DeviceState.ready
                        ? _startMeasurement
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
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
        color: color.withOpacity(0.2),
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
                painter: EcgPainter(_ecgBuffer.toList()),
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
            const SizedBox(height: 8),
            // ADC scale control
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ADC Scale (µV / count)',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              min: 1.0, // 1 µV
                              max: 20.0, // 20 µV
                              divisions: 19,
                              value: (_adcToMv * 1000).clamp(1.0, 20.0),
                              label:
                                  '${(_adcToMv * 1000).toStringAsFixed(1)} µV',
                              onChanged: (v) {
                                setState(() {
                                  _adcToMv = v / 1000.0;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Current',
                                style: TextStyle(fontSize: 10),
                              ),
                              Text(
                                '${(_adcToMv * 1000).toStringAsFixed(1)} µV',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
                    onPressed: () {
                      setState(() => _loggV.clear());
                    },
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loggV.isEmpty
                  ? const Center(
                      child: Text(
                        'No logs yet',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      reverse: false,
                      itemCount: _loggV.length,
                      itemBuilder: (context, idx) {
                        final line = _loggV[idx];
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

// ----- ECG Painter -----
class EcgPainter extends CustomPainter {
  final List<double> samples;
  EcgPainter(this.samples);

  @override
  void paint(Canvas canvas, Size size) {
    // background
    final bgPaint = Paint()..color = const Color(0xFF050507);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // grid
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.12)
      ..strokeWidth = 0.5;

    const double mmPerCell = 10; // visually, not real mm -> adjust
    for (double x = 0; x <= size.width; x += mmPerCell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += mmPerCell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // thicker central horizontal baseline
    final baselinePaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      baselinePaint,
    );

    if (samples.isEmpty) return;

    // compute vertical scale: fit most of waveform to view
    double minMv = samples.reduce(math.min);
    double maxMv = samples.reduce(math.max);

    // enforce a sensible range to avoid flat-line zooms
    double range = (maxMv - minMv);
    if (range < 0.5) {
      // if data small, center around 0 and use ±1.5 mV
      minMv = -1.5;
      maxMv = 1.5;
      range = 3.0;
    } else {
      // add margin
      final margin = range * 0.2;
      minMv -= margin;
      maxMv += margin;
      range = maxMv - minMv;
    }

    // horizontal scaling: display up to width with current number of samples
    final sampleCount = samples.length;
    final dx = sampleCount > 1 ? size.width / (sampleCount - 1) : size.width;

    // path
    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final x = i * dx;
      // map mv to y (invert because canvas y grows downward)
      final norm = (samples[i] - minMv) / range;
      final y = size.height - (norm * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        // smooth using quadratic Bezier
        final prevX = (i - 1) * dx;
        final prevY =
            size.height - ((samples[i - 1] - minMv) / range * size.height);
        final cpx = (prevX + x) / 2;
        final cpy = (prevY + y) / 2;
        path.quadraticBezierTo(prevX, prevY, cpx, cpy);
      }
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..shader = null
      ..color = Colors.greenAccent;

    canvas.drawPath(path, linePaint);

    // optional: draw latest value marker
    final lastX = (samples.length - 1) * dx;
    final lastY = size.height - ((samples.last - minMv) / range * size.height);
    final dotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(lastX, lastY), 3.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant EcgPainter oldDelegate) {
    return !listEquals(oldDelegate.samples, samples);
  }
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
