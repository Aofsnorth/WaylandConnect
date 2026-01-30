import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:msgpack_dart/msgpack_dart.dart';

class ProtocolHandler {
  Uint8List _buffer = Uint8List(0);
  int _neededBytes = -1; // -1 means we need length (4 bytes)

  // Returns a list of decoded packets (Maps or simple types)
  List<dynamic> process(Uint8List data) {
    // Append new data to existing buffer
    final newBuffer = Uint8List(_buffer.length + data.length);
    newBuffer.setAll(0, _buffer);
    newBuffer.setAll(_buffer.length, data);
    _buffer = newBuffer;
    
    List<dynamic> packets = [];

    while (true) {
      if (_neededBytes == -1) {
        if (_buffer.length >= 4) {
          final lenData = ByteData.sublistView(_buffer, 0, 4);
          _neededBytes = lenData.getUint32(0, Endian.big);
        } else {
          break; // Need more data for length
        }
      }

      // Check payload
      if (_neededBytes != -1) {
        if (_buffer.length >= 4 + _neededBytes) {
           final payload = Uint8List.sublistView(_buffer, 4, 4 + _neededBytes);
           
           try {
             packets.add(deserialize(payload));
           } catch (e) {
             debugPrint("Packet decode error: $e");
           }
           
           // Efficiently truncate the buffer
           final remainingLength = _buffer.length - (4 + _neededBytes);
           if (remainingLength > 0) {
             final remaining = Uint8List(remainingLength);
             remaining.setAll(0, Uint8List.sublistView(_buffer, 4 + _neededBytes));
             _buffer = remaining;
           } else {
             _buffer = Uint8List(0);
           }
           _neededBytes = -1; // Reset state
        } else {
          break; // Need more data for payload
        }
      }
    }
    
    return packets;
  }

  static Uint8List encodePacket(dynamic data) {
    final payload = serialize(data);
    final builder = BytesBuilder(copy: false);
    
    final lenBuf = ByteData(4);
    lenBuf.setUint32(0, payload.length, Endian.big);
    
    builder.add(lenBuf.buffer.asUint8List());
    builder.add(payload);
    
    return builder.toBytes();
  }
}
