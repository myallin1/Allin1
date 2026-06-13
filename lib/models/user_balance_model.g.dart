// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_balance_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserBalanceModelAdapter extends TypeAdapter<UserBalanceModel> {
  @override
  final int typeId = 12;

  @override
  UserBalanceModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserBalanceModel(
      userId: fields[0] as String,
      updatedAt: fields[6] as String,
      lastSynced: fields[7] as DateTime,
      pendingCoins: fields[1] as int,
      verifiedCoins: fields[2] as int,
      walletRupees: fields[3] as double,
      lifetimeCoins: fields[4] as int,
      completedTaskCount: fields[5] as int,
    );
  }

  @override
  void write(BinaryWriter writer, UserBalanceModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.userId)
      ..writeByte(1)
      ..write(obj.pendingCoins)
      ..writeByte(2)
      ..write(obj.verifiedCoins)
      ..writeByte(3)
      ..write(obj.walletRupees)
      ..writeByte(4)
      ..write(obj.lifetimeCoins)
      ..writeByte(5)
      ..write(obj.completedTaskCount)
      ..writeByte(6)
      ..write(obj.updatedAt)
      ..writeByte(7)
      ..write(obj.lastSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserBalanceModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
