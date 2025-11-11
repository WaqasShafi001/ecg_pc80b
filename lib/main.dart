// lib/main.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

void main() => runApp(const MyApp());

Uuid SERVICE_UUID = Uuid.parse("0000FFF0-0000-1000-8000-00805f9b34fb");
Uuid CHAR_READ = Uuid.parse("0000FFF1-0000-1000-8000-00805f9b34fb");
Uuid CHAR_WRITE = Uuid.parse("0000FFF2-0000-1000-8000-00805f9b34fb");

// ----- CRC8-CCITT table from protocol Appendix A -----
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

// ----- Helper utilities -----
Uint8List buildPacket(int token, List<int> data) {
  final buf = <int>[];
  buf.add(0xA5);
  buf.add(token & 0xFF);
  buf.add(data.length & 0xFF);
  buf.addAll(data);
  final c = crc8Ccitt(buf);
  buf.add(c);
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

class _EcgHomePageState extends State<EcgHomePage> {
  final _ble = FlutterReactiveBle();
  final _scanController = StreamController<DiscoveredDevice>.broadcast();
  final List<String> _log = [];
  final List<int> _recvBuffer = [];
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  DiscoveredDevice? _selected;
  String status = 'idle';

  // ECG rolling buffer (samples in ADC counts)
  final ListQueue<double> ecgBuffer = ListQueue(); // store as millivolts
  final int samplingHz = 150;
  final double secondsToShow = 5.0;
  late final int bufferCapacity;

  // current metrics
  int? heartRate;
  bool leadOff = false;
  double batteryMv = 0.0;
  String measureState = 'idle';

  // conversion (tweak this to calibrate -> mV)
  double adcToMv = 0.1; // initial guess: 1 count => 0.1 mV. Adjust as needed.

  @override
  void initState() {
    super.initState();
    bufferCapacity = (samplingHz * secondsToShow).toInt(); // e.g., 750
  }

  @override
  void dispose() {
    _scanController.close();
    _connSub?.cancel();
    _notifySub?.cancel();
    super.dispose();
  }

  void _appendLog(String text) {
    final t = "${DateTime.now().toIso8601String()} $text";
    setState(() {
      _log.insert(0, t);
      if (_log.length > 300) _log.removeLast();
    });
    // also print JSON / human-readable to console for debug
    // ignore: avoid_print
    print(t);
  }

  Future<void> scanForDevices() async {
    _appendLog('Scan start...');
    setState(() {
      status = 'scanning';
      _selected = null;
    });
    final seen = <String>{};

    _ble
        .scanForDevices(
          withServices: [SERVICE_UUID],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (device) {
            if (seen.contains(device.id)) return;
            seen.add(device.id);
            if ((device.name?.isNotEmpty ?? false) ||
                device.serviceUuids.contains(SERVICE_UUID)) {
              _appendLog('Found ${device.name} (${device.id})');

              if (_selected == null || _selected!.id != device.id) {
                setState(() {
                  _selected = device;
                });
              }
              _scanController.add(device);
            }
          },
          onError: (e) {
            _appendLog('Scan error: $e');
            setState(() => status = 'idle');
          },
        );
  }

  Future<void> connectTo(DiscoveredDevice dev) async {
    _appendLog('Connecting to ${dev.name}');
    setState(() {
      status = 'connecting';
      _selected = dev;
    });
    _connSub?.cancel();
    _connSub = _ble
        .connectToDevice(
          id: dev.id,
          connectionTimeout: const Duration(seconds: 8),
        )
        .listen(
          (update) {
            _appendLog('ConnState: ${update.connectionState}');
            if (update.connectionState == DeviceConnectionState.connected) {
              setState(() => status = 'connected');
              _subscribeNotifications();
              // send version query per protocol
              final q = buildPacket(0x11, [0x00, 0x00, 0x00]);
              _writeWithResponse(q);
              // send heartbeat timer optionally
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              _appendLog('Disconnected');
              _notifySub?.cancel();
              setState(() {
                status = 'disconnected';
                _selected = null;
              });
            }
          },
          onError: (e) {
            _appendLog('Connection error: $e');
            setState(() => status = 'idle');
          },
        );
  }

  Future<void> _writeWithResponse(Uint8List bytes) async {
    if (_selected == null) return;
    try {
      await _ble.writeCharacteristicWithResponse(
        QualifiedCharacteristic(
          deviceId: _selected!.id,
          serviceId: SERVICE_UUID,
          characteristicId: CHAR_WRITE,
        ),
        value: bytes,
      );
    } catch (e) {
      _appendLog('Write error: $e');
    }
  }

  void _subscribeNotifications() {
    if (_selected == null) return;
    _notifySub?.cancel();
    final char = QualifiedCharacteristic(
      deviceId: _selected!.id,
      serviceId: SERVICE_UUID,
      characteristicId: CHAR_READ,
    );
    _notifySub = _ble.subscribeToCharacteristic(char).listen((data) {
      _appendLog('raw ${data.length} bytes');
      _feedBytes(data);
    }, onError: (e) => _appendLog('Notify error: $e'));
  }

  // feed bytes into buffer and try to parse packets
  void _feedBytes(List<int> bytes) {
    _recvBuffer.addAll(bytes);
    _tryParseBuffer();
  }

  void _tryParseBuffer() {
    while (true) {
      if (_recvBuffer.length < 4) return;
      final headIndex = _recvBuffer.indexOf(0xA5);
      if (headIndex == -1) {
        _recvBuffer.clear();
        return;
      }
      if (headIndex > 0) {
        _recvBuffer.removeRange(0, headIndex);
        if (_recvBuffer.length < 4) return;
      }
      if (_recvBuffer.length < 4) return;
      final token = _recvBuffer[1];
      final len = _recvBuffer[2];
      final total = 3 + len + 1;
      if (_recvBuffer.length < total) return; // wait
      final packet = _recvBuffer.sublist(0, total);
      _recvBuffer.removeRange(0, total);
      if (!validatePacket(packet)) {
        _appendLog('CRC fail token 0x${token.toRadixString(16)} dropping');
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
      case 0x55:
        _handleConfig(data); // either request from device or ack response
        break;
      case 0xDD:
        _handleTracking(data);
        break;
      case 0xAA:
        _handleDataFrame(data);
        break;
      default:
        _appendLog('Unknown token 0x${token.toRadixString(16)} len $len');
    }
  }

  void _handleHeartbeat(List<int> data) {
    // data[0] incidental info: battery level in low nibble
    if (data.isNotEmpty) {
      final info = data[0];
      final batLevel = info & 0x0F;
      // map 0..3 to levels — not exact voltage. We'll show level
      setState(() {
        batteryMv =
            0.0; // unknown exact mV from this byte; real battery mV comes in data frames
      });
      _appendLog('Heartbeat: level $batLevel');
    } else {
      _appendLog('Heartbeat (no incidental info)');
    }
  }

  void _handleVersionReply(List<int> data) {
    // device responds with version bytes (BCD etc.)
    _appendLog(
      'Version reply: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
    );
  }

  void _handleConfig(List<int> data) {
    // config packet: DeviceModel(1), Filter+Type(1), DeviceID(12)
    if (data.length >= 14) {
      final model = data[0];
      final filterType = data[1];
      final deviceId = data.sublist(2, 14);
      final json = {
        'token': '0x55',
        'deviceModel': model,
        'filterType': filterType,
        'deviceId': deviceId
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
      };
      _appendLog('Config: ${jsonEncode(json)}');
      // send ACK to device to confirm config received
      final ack = buildPacket(0x55, [0x00]); // ACK=0x00
      _writeWithResponse(ack);
    } else if (data.length == 1) {
      // Host response when host responds to device config
      final code = data[0];
      _appendLog('Config response from host code=$code');
    }
  }

  void _handleTracking(Uint8List data) {
    // SegNo(1), Info(2 little endian), MeasurementStatus(1), ECGdesc(2), ECG data...
    if (data.length < 6) {
      _appendLog('Tracking too short ${data.length}');
      return;
    }
    final segNo = data[0];
    final info = (data[2] << 8) | data[1];
    final measStatus = data[3];
    final ecgDesc = (data[5] << 8) | data[4];
    measureState = _decodeMeasureStatus(measStatus);
    // ecgDesc bits: bit15 lead off, bits10-8 data structure
    final leadOffFlag = ((ecgDesc & 0x8000) != 0);
    final dataStruct = (ecgDesc >> 8) & 0x07; // bits10-8
    leadOff = leadOffFlag;
    // Ecg data follows
    final ecgBytes = data.sublist(6);
    if (dataStruct == 1 && ecgBytes.length >= 50) {
      // 25 samples (2 bytes each)
      final samples = <double>[];
      for (int i = 0; i + 1 < ecgBytes.length && samples.length < 25; i += 2) {
        int v = (ecgBytes[i + 1] << 8) | ecgBytes[i];
        v &= 0x0FFF; // lower 12 bits valid
        final mv = v * adcToMv;
        samples.add(mv);
        _pushSample(mv);
      }
      _appendLog(
        'Tracking seg:$segNo struct1 samples:${samples.length} state:$measureState',
      );
      // print JSON
      final json = {
        'token': '0xDD',
        'seg': segNo,
        'state': measureState,
        'samples': samples,
      };
      // ignore: avoid_print
      print(jsonEncode(json));
    } else if (dataStruct == 2 && ecgBytes.length >= 9) {
      // analysis result: year month day hour minute second HR result
      final year = ((ecgBytes[0] << 8) | ecgBytes[1]);
      final month = ecgBytes[2];
      final day = ecgBytes[3];
      final hour = ecgBytes[4];
      final minute = ecgBytes[5];
      final second = ecgBytes[6];
      final hr = ecgBytes[7];
      final resultCode = ecgBytes[8];
      heartRate = hr;
      _appendLog(
        'Analysis: $year-$month-$day $hour:$minute:$second HR:$hr result:$resultCode ${_analysisText(resultCode)}',
      );
      final json = {
        'token': '0xDD',
        'analysis': {
          'datetime': '$year-$month-$day $hour:$minute:$second',
          'hr': hr,
          'result': resultCode,
        },
      };
      // ignore: avoid_print
      print(jsonEncode(json));
    } else {
      _appendLog('Tracking struct:$dataStruct bytes:${ecgBytes.length}');
    }
    setState(() {});
  }

  void _handleDataFrame(Uint8List data) {
    // Data frame: seq(1) followed by payload
    if (data.isEmpty) return;
    final seq = data[0];
    final payload = data.sublist(1);
    // For real-time upload (protocol 4.2.2), the device sends 25 points (25*2 bytes) + HR(1) + lead&battery(2) total length 25*2+3 = 53
    if (payload.length >= (25 * 2 + 3)) {
      final samples = <double>[];
      for (int i = 0; i < 25; i++) {
        final lo = payload[i * 2];
        final hi = payload[i * 2 + 1];
        int val = (hi << 8) | lo;
        val &= 0x0FFF;
        final mv = val * adcToMv;
        samples.add(mv);
        _pushSample(mv);
      }
      // trailing bytes
      final hr = payload[25 * 2];
      final leadBatteryLow = payload[25 * 2 + 1];
      final leadBatteryHigh = payload[25 * 2 + 2];
      final leadBattery =
          (leadBatteryHigh << 8) |
          leadBatteryLow; // little endian note in doc: high after low
      final leadFlag = ((leadBattery & 0x8000) != 0);
      final batteryVal =
          (leadBattery &
          0x0FFF); // bits 11..0 represent battery (unit: mV per doc)
      // Build readable metrics
      heartRate = hr;
      leadOff = leadFlag;
      // batteryVal unit per doc is mV (they said unit MV but it is mV likely). We'll treat as mV.
      batteryMv = batteryVal.toDouble();
      // ACK back to device for real-time packet (Host should respond with ACK)
      final ackPacket = buildPacket(0xAA, [seq, 0x00]); // seq + ACK(0x00)
      _writeWithResponse(ackPacket);
      final json = {
        'token': '0xAA',
        'seq': seq,
        'hr': hr,
        'leadOff': leadOff,
        'battery_mV': batteryMv,
        'samples_mV': samples,
      };
      _appendLog(
        'Realtime seq:$seq HR:$hr battery:${batteryMv.toStringAsFixed(0)}mV lead:${leadOff ? "OFF" : "ON"}',
      );
      // large sample JSON to console
      // ignore: avoid_print
      print(jsonEncode(json));
      setState(() {});
    } else {
      // Possibly non-real-time data chunk (SCP) — we base64 it and log
      final json = {
        'token': '0xAA',
        'seq': seq,
        'payloadBase64': base64Encode(payload),
      };
      _appendLog('Data chunk seq:$seq size:${payload.length}');
      // ignore: avoid_print
      print(jsonEncode(json));
    }
  }

  void _pushSample(double mv) {
    // push into rolling buffer, keep capacity
    if (ecgBuffer.length >= bufferCapacity) {
      ecgBuffer.removeFirst();
    }
    ecgBuffer.add(mv);
  }

  String _decodeMeasureStatus(int b) {
    // bit7..6 channel, bit5..4 measure mode, bit3..0 stage
    final stage = b & 0x0F;
    switch (stage) {
      case 0:
        return 'detecting';
      case 1:
        return 'preparing';
      case 2:
        return 'measuring';
      case 3:
        return 'analysing';
      case 4:
        return 'reporting';
      case 5:
        return 'tracking_end';
      default:
        return 'stage_$stage';
    }
  }

  String _analysisText(int code) {
    // Appendix B mapping
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

  // UI actions
  void requestRealTime() {
    // Send config: Device Model 0x80, TransmissionType 0x00, Device ID 12 zeros (or you can read deviceId earlier)
    final deviceId = List<int>.filled(12, 0x00);
    final payload = <int>[0x80, 0x00] + deviceId;
    final packet = buildPacket(0x55, payload);
    _writeWithResponse(packet);
    _appendLog('Requested real-time (0x55) sent.');
  }

  // Build UI
  @override
  Widget build(BuildContext context) {
    final samples = ecgBuffer.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('PC-80B - Live ECG')),
      body: SafeArea(
        child: Column(
          children: [
            // top controls & metrics
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('Scan'),
                    onPressed: scanForDevices,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.bluetooth_connected),
                    label: const Text('Connect'),
                    onPressed: _selected == null
                        ? null
                        : () => connectTo(_selected!),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.stream),
                    label: const Text('Request Real-Time'),
                    onPressed: _selected == null ? null : requestRealTime,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status: $status',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Measure: $measureState',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'HR: ${heartRate ?? "--"} bpm',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.greenAccent,
                        ),
                      ),
                      Text(
                        'Battery: ${batteryMv > 0 ? "${batteryMv.toStringAsFixed(0)} mV" : "--"}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        leadOff ? "Touch electrodes to start" : "Signal OK",
                        style: TextStyle(
                          color: leadOff
                              ? Colors.redAccent
                              : Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // waveform
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: const Color(0xFF081010),
              child: SizedBox(
                height: 220,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CustomPaint(
                    painter: EcgPainter(samples),
                    child: Container(),
                  ),
                ),
              ),
            ),

            // controls: scale adjust
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  const Text('ADC→mV scale:'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: adcToMv,
                      min: 0.01,
                      max: 1.0,
                      divisions: 99,
                      label: adcToMv.toStringAsFixed(2),
                      onChanged: (v) => setState(() => adcToMv = v),
                    ),
                  ),
                  Text(adcToMv.toStringAsFixed(2)),
                ],
              ),
            ),

            const Divider(),

            // logs
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Log (latest):',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ListView.builder(
                          reverse: true,
                          itemCount: _log.length,
                          itemBuilder: (c, i) => Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              _log[i],
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Painter: draws waveform in green, smooth polyline
class EcgPainter extends CustomPainter {
  final List<double> samplesMv;
  EcgPainter(this.samplesMv);
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF061010);
    canvas.drawRect(Offset.zero & size, bg);

    if (samplesMv.isEmpty) return;

    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    // scale samples to fit vertical space
    final maxVal = samplesMv.reduce((a, b) => a > b ? a : b);
    final minVal = samplesMv.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);
    final n = samplesMv.length;
    final stepX = size.width / (n - 1).clamp(1, double.infinity);
    final path = Path();
    for (int i = 0; i < n; i++) {
      final x = i * stepX;
      final normalized = (samplesMv[i] - minVal) / range;
      final y = size.height - normalized * size.height;
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);

    // draw midline
    final midPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      midPaint,
    );
  }

  @override
  bool shouldRepaint(covariant EcgPainter oldDelegate) =>
      oldDelegate.samplesMv != samplesMv;
}
