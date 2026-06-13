// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'store_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StoreModelAdapter extends TypeAdapter<StoreModel> {
  @override
  final int typeId = 10;

  @override
  StoreModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StoreModel(
      id: fields[0] as String,
      name: fields[1] as String,
      category: fields[2] as String,
      city: fields[3] as String,
      updatedAt: fields[11] as String,
      lastSynced: fields[12] as DateTime,
      address: fields[4] as String?,
      latitude: fields[5] as double?,
      longitude: fields[6] as double?,
      logoUrl: fields[7] as String?,
      isOpen: fields[8] as bool,
      rating: fields[9] as double?,
      deliveryTimeMinutes: fields[10] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, StoreModel obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.city)
      ..writeByte(4)
      ..write(obj.address)
      ..writeByte(5)
      ..write(obj.latitude)
      ..writeByte(6)
      ..write(obj.longitude)
      ..writeByte(7)
      ..write(obj.logoUrl)
      ..writeByte(8)
      ..write(obj.isOpen)
      ..writeByte(9)
      ..write(obj.rating)
      ..writeByte(10)
      ..write(obj.deliveryTimeMinutes)
      ..writeByte(11)
      ..write(obj.updatedAt)
      ..writeByte(12)
      ..write(obj.lastSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoreModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
