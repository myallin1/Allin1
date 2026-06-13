// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reward_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RewardModelAdapter extends TypeAdapter<RewardModel> {
  @override
  final int typeId = 11;

  @override
  RewardModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RewardModel(
      id: fields[0] as String,
      title: fields[1] as String,
      subtitle: fields[2] as String,
      emoji: fields[3] as String,
      coins: fields[4] as int,
      channel: fields[5] as String,
      updatedAt: fields[11] as String,
      lastSynced: fields[12] as DateTime,
      taskUrl: fields[6] as String?,
      internalAction: fields[7] as String?,
      isHot: fields[8] as bool,
      status: fields[9] as String,
      expiresAt: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, RewardModel obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.subtitle)
      ..writeByte(3)
      ..write(obj.emoji)
      ..writeByte(4)
      ..write(obj.coins)
      ..writeByte(5)
      ..write(obj.channel)
      ..writeByte(6)
      ..write(obj.taskUrl)
      ..writeByte(7)
      ..write(obj.internalAction)
      ..writeByte(8)
      ..write(obj.isHot)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.expiresAt)
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
      other is RewardModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
