import '../constants/api_constants.dart';
import '../models/map_data_model.dart';
import 'api_service.dart';

class MapService {
  final ApiService _api;

  MapService(this._api);

  Future<TeknisiMapData> getMapData() async {
    final response = await _api.get(ApiConstants.teknisiMapData);
    if (response is Map<String, dynamic>) {
      return TeknisiMapData.fromJson(response);
    }
    if (response is Map) {
      return TeknisiMapData.fromJson(
        response.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    throw ApiException('Data peta tidak valid.');
  }
}
