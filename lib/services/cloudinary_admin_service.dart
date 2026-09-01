import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cloudinary_upload_service.dart' show kCloudinaryCloudName;

/// **IMPORTANT: HARDCODED CLOUDINARY ADMIN SECRETS**
/// Since we don't have Cloud Functions, we are embedding the API Key
/// and Secret here. This is ONLY safe because this service is completely 
/// restricted to the Super Admin app which is never distributed to the public.
/// 
/// Replace these placeholders with your actual keys from the 
/// Cloudinary Dashboard -> Settings -> Access Keys.
const String kCloudinaryApiKey = 'YOUR_API_KEY_HERE';
const String kCloudinaryApiSecret = 'YOUR_API_SECRET_HERE';

class CloudinaryUsageInfo {
  final int storageUsedBytes;
  final int storageLimitBytes;
  final double storageUsedPercent;
  
  final int bandwidthUsedBytes;
  final int bandwidthLimitBytes;
  final double bandwidthUsedPercent;

  final int requestsUsed;
  final int requestsLimit;
  
  final int resourcesUsed;
  final int resourcesLimit;

  final int derivativesUsed;
  final int derivativesLimit;

  CloudinaryUsageInfo({
    required this.storageUsedBytes,
    required this.storageLimitBytes,
    required this.storageUsedPercent,
    required this.bandwidthUsedBytes,
    required this.bandwidthLimitBytes,
    required this.bandwidthUsedPercent,
    required this.requestsUsed,
    required this.requestsLimit,
    required this.resourcesUsed,
    required this.resourcesLimit,
    required this.derivativesUsed,
    required this.derivativesLimit,
  });

  factory CloudinaryUsageInfo.fromJson(Map<String, dynamic> json) {
    return CloudinaryUsageInfo(
      storageUsedBytes: (json['storage']?['usage'] as num?)?.toInt() ?? 0,
      storageLimitBytes: (json['storage']?['limit'] as num?)?.toInt() ?? 26843545600, // 25 GB default
      storageUsedPercent: (json['storage']?['used_percent'] as num?)?.toDouble() ?? 0.0,
      bandwidthUsedBytes: (json['bandwidth']?['usage'] as num?)?.toInt() ?? 0,
      bandwidthLimitBytes: (json['bandwidth']?['limit'] as num?)?.toInt() ?? 26843545600,
      bandwidthUsedPercent: (json['bandwidth']?['used_percent'] as num?)?.toDouble() ?? 0.0,
      requestsUsed: (json['requests']?['usage'] as num?)?.toInt() ?? 0,
      requestsLimit: (json['requests']?['limit'] as num?)?.toInt() ?? 0,
      resourcesUsed: (json['resources']?['usage'] as num?)?.toInt() ?? 0,
      resourcesLimit: (json['resources']?['limit'] as num?)?.toInt() ?? 0,
      derivativesUsed: (json['derivatives']?['usage'] as num?)?.toInt() ?? 0,
      derivativesLimit: (json['derivatives']?['limit'] as num?)?.toInt() ?? 0,
    );
  }
}

class CloudinaryResource {
  final String publicId;
  final String format;
  final int bytes;
  final String secureUrl;
  final DateTime createdAt;

  CloudinaryResource({
    required this.publicId,
    required this.format,
    required this.bytes,
    required this.secureUrl,
    required this.createdAt,
  });

  factory CloudinaryResource.fromJson(Map<String, dynamic> json) {
    return CloudinaryResource(
      publicId: json['public_id'] as String? ?? '',
      format: json['format'] as String? ?? '',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      secureUrl: json['secure_url'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class CloudinaryAdminService {
  factory CloudinaryAdminService() => _instance;
  CloudinaryAdminService._internal();
  static final CloudinaryAdminService _instance = CloudinaryAdminService._internal();

  bool get isConfigured => 
      kCloudinaryApiKey != 'YOUR_API_KEY_HERE' && 
      kCloudinaryApiSecret != 'YOUR_API_SECRET_HERE';

  Map<String, String> get _authHeaders {
    final credentials = '$kCloudinaryApiKey:$kCloudinaryApiSecret';
    final base64Credentials = base64Encode(utf8.encode(credentials));
    return {
      'Authorization': 'Basic $base64Credentials',
      'Content-Type': 'application/json',
    };
  }

  /// Fetches storage and bandwidth usage from the Cloudinary Admin API.
  Future<CloudinaryUsageInfo?> getUsage() async {
    if (!isConfigured) return null;

    final url = Uri.parse('https://api.cloudinary.com/v1_1/$kCloudinaryCloudName/usage');
    try {
      final response = await http.get(url, headers: _authHeaders);
      if (response.statusCode == 200) {
        // jsonDecode returns `dynamic`; fromJson wants Map<String, dynamic>.
        // Cast explicitly rather than relying on an implicit dynamic
        // downcast, which the analyzer rejects as an error.
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CloudinaryUsageInfo.fromJson(data);
      } else {
        debugPrint('❌ Cloudinary usage failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Cloudinary usage error: $e');
      return null;
    }
  }

  /// Fetches all uploaded resources (images). Handles pagination up to 500 per call.
  Future<List<CloudinaryResource>> getResources({String? nextCursor}) async {
    if (!isConfigured) return [];

    var urlString = 'https://api.cloudinary.com/v1_1/$kCloudinaryCloudName/resources/image?max_results=500';
    if (nextCursor != null && nextCursor.isNotEmpty) {
      urlString += '&next_cursor=$nextCursor';
    }

    try {
      final response = await http.get(Uri.parse(urlString), headers: _authHeaders);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final resources = (data['resources'] as List?)
                ?.map((e) => CloudinaryResource.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [];
        // NOTE: If data['next_cursor'] exists, we can fetch more. 
        // For this simple dashboard, we return the first 500 (most recent).
        return resources;
      } else {
        debugPrint('❌ Cloudinary getResources failed: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('❌ Cloudinary getResources error: $e');
      return [];
    }
  }

  /// Deletes multiple images using their public IDs.
  Future<bool> deleteResources(List<String> publicIds) async {
    if (!isConfigured || publicIds.isEmpty) return false;

    // Cloudinary bulk delete endpoint accepts a DELETE request (or POST with method override)
    // with 'public_ids' array in JSON body.
    final url = Uri.parse('https://api.cloudinary.com/v1_1/$kCloudinaryCloudName/resources/image/upload');
    
    try {
      final request = http.Request('DELETE', url);
      request.headers.addAll(_authHeaders);
      request.body = jsonEncode({'public_ids': publicIds});

      final response = await http.Client().send(request);
      final respBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        return true;
      } else {
        debugPrint('❌ Cloudinary delete failed: ${response.statusCode} - $respBody');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Cloudinary delete error: $e');
      return false;
    }
  }
}
