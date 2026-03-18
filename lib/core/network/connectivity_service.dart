import 'package:connectivity_plus/connectivity_plus.dart';

enum ConnectivityStatus { online, offline }

class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<ConnectivityStatus> get statusStream {
    return _connectivity.onConnectivityChanged.map(_mapResults);
  }

  Future<ConnectivityStatus> get currentStatus async {
    final results = await _connectivity.checkConnectivity();
    return _mapResults(results);
  }

  ConnectivityStatus _mapResults(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.none) || results.isEmpty) {
      return ConnectivityStatus.offline;
    }
    return ConnectivityStatus.online;
  }
}
