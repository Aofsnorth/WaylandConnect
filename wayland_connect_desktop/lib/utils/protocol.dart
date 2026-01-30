import 'dart:typed_data';
import 'package:msgpack_dart/msgpack_dart.dart';

class ProtocolHandler {
  final BytesBuilder _buffer = BytesBuilder();
  int _neededBytes = -1; // -1 means we need length (4 bytes)

  List<dynamic> process(Uint8List data) {
    _buffer.add(data);
    List<dynamic> packets = [];

    while (true) {
      if (_neededBytes == -1) {
        if (_buffer.length >= 4) {
          final bytes = _buffer.toBytes();
          final lenData = ByteData.sublistView(bytes, 0, 4);
          _neededBytes = lenData.getUint32(0, Endian.big); // Big Endian for Rust
        } else {
          break;
        }
      }

      if (_neededBytes != -1) {
        if (_buffer.length >= 4 + _neededBytes) {
           final bytes = _buffer.toBytes();
           final payload = Uint8List.sublistView(bytes, 4, 4 + _neededBytes);
           
           try {
             final decoded = deserialize(payload);
             packets.add(decoded);
           } catch (e) {
             // Decode error
           }
           
           final remaining = Uint8List.sublistView(bytes, 4 + _neededBytes);
           _buffer.clear();
           _buffer.add(remaining);
           _neededBytes = -1;
        } else {
          break;
        }
      }
    }
    return packets;
  }

  static Uint8List encodePacket(dynamic data) {
    final payload = serialize(data);
    final builder = BytesBuilder();
    
    final lenBuf = ByteData(4);
    lenBuf.setUint32(0, payload.length, Endian.big); // Big Endian for Rust
    
    builder.add(lenBuf.buffer.asUint8List());
    builder.add(payload);
    
    return builder.toBytes();
  }
}
